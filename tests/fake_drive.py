"""Nachgebautes Google Drive fuer die Tests (nur localhost, nur im Speicher).
Steuerung: GET /__mode?corrupt_upload=1&corrupt_download=1&fail_chunk=1&slow=0.2&reset=1
Abfrage:   GET /__state -> JSON mit Zaehlern
"""
import hashlib, json, re, sys, time, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PAGE = 3  # kleine Antwortseiten, damit die Seiten-Logik wirklich laeuft
state = {}

def reset():
    state.clear()
    state.update(files={}, next=1, sessions={}, uploads=0, token_calls=0, page_requests=0, fail_chunk=0,
                 corrupt_upload=False, corrupt_download=False, slow=0.0, expired_once=False, tok=1)
reset()

def new_id():
    state["next"] += 1
    return "id%d" % state["next"]

def entry(f):
    d = {"id": f["id"], "name": f["name"], "mimeType": f["mimeType"], "modifiedTime": "2026-11-07T00:00:00Z"}
    if f.get("data") is not None:
        d["size"] = str(len(f["data"]))
        d["md5Checksum"] = hashlib.md5(f["data"]).hexdigest()
    return d

def add(name, parent, data=None, mime="application/octet-stream"):
    f = {"id": new_id(), "name": name, "parent": parent, "mimeType": mime, "data": data}
    state["files"][f["id"]] = f
    return f

def unq(s):
    return s.replace("\\'", "'").replace("\\\\", "\\")

class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a): pass

    def send(self, code, body=b"", headers=None, ctype="application/json"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n else b""

    def authed(self):
        if self.headers.get("Authorization") == "Bearer tok%d" % state["tok"]:
            return True
        self.send(401, {"error": {"code": 401}})
        return False

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        qs = urllib.parse.parse_qs(u.query)
        if u.path == "/__mode":
            if "reset" in qs: reset()
            for k in ("corrupt_upload", "corrupt_download"):
                if k in qs: state[k] = qs[k][0] == "1"
            if "fail_chunk" in qs: state["fail_chunk"] = int(qs["fail_chunk"][0])
            if "slow" in qs: state["slow"] = float(qs["slow"][0])
            if "expire" in qs: state["tok"] += 1
            return self.send(200, {"ok": True})
        if u.path == "/__state":
            return self.send(200, {k: state[k] for k in ("uploads", "token_calls", "page_requests")})
        if not self.authed(): return
        m = re.match(r"^/drive/v3/files/([^/]+)$", u.path)
        if m and qs.get("alt") == ["media"]:
            f = state["files"].get(urllib.parse.unquote(m.group(1)))
            if not f: return self.send(404, {"error": {"code": 404}})
            data = f["data"]
            if state["corrupt_download"]:
                data = data[:-1] + bytes([(data[-1] + 1) % 256])
            self.send_response(200)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            step = max(1, len(data) // 20)
            for i in range(0, len(data), step):
                if state["slow"]: time.sleep(state["slow"])
                self.wfile.write(data[i:i + step])
            return
        if u.path == "/drive/v3/files":
            q = qs.get("q", [""])[0]
            parent = re.search(r"'((?:[^'\\]|\\.)*)' in parents", q)
            name = re.search(r"name = '((?:[^'\\]|\\.)*)'", q)
            items = [f for f in state["files"].values()
                     if f["parent"] == (parent.group(1) if parent else None)
                     and (not name or f["name"] == unq(name.group(1)))]
            start = int(qs.get("pageToken", ["0"])[0])
            state["page_requests"] += 1
            page = items[start:start + PAGE]
            out = {"files": [entry(f) for f in page]}
            if start + PAGE < len(items):
                out["nextPageToken"] = str(start + PAGE)
            return self.send(200, out)
        self.send(404, {"error": {"code": 404}})

    def do_POST(self):
        u = urllib.parse.urlparse(self.path)
        if u.path == "/token":
            form = urllib.parse.parse_qs(self.body().decode())
            state["token_calls"] += 1
            if form.get("refresh_token") != ["good-refresh"]:
                return self.send(400, {"error": "invalid_grant"})
            return self.send(200, {"access_token": "tok%d" % state["tok"], "expires_in": 3600})
        if not self.authed():
            self.body(); return
        if u.path == "/drive/v3/files":
            meta = json.loads(self.body())
            f = add(meta["name"], meta["parents"][0], None, meta.get("mimeType"))
            return self.send(200, entry(f))
        if u.path == "/upload/drive/v3/files":
            meta = json.loads(self.body())
            sid = "s%d" % state["next"]; state["next"] += 1
            state["sessions"][sid] = {"meta": meta, "buf": b"", "total": int(self.headers["X-Upload-Content-Length"]), "chunks": 0}
            state["uploads"] += 1
            host = self.headers["Host"]
            return self.send(200, b"", {"Location": "http://%s/upload/session/%s" % (host, sid)})
        self.send(404, {})

    def do_PATCH(self):
        u = urllib.parse.urlparse(self.path)
        if not self.authed():
            self.body(); return
        m = re.match(r"^/upload/drive/v3/files/([^/]+)$", u.path)
        if not m or urllib.parse.unquote(m.group(1)) not in state["files"]:
            self.body(); return self.send(404, {})
        self.body()
        sid = "s%d" % state["next"]; state["next"] += 1
        state["sessions"][sid] = {"meta": {"update": urllib.parse.unquote(m.group(1))}, "buf": b"",
                                  "total": int(self.headers["X-Upload-Content-Length"]), "chunks": 0}
        state["uploads"] += 1
        state["updates"] = state.get("updates", 0) + 1
        return self.send(200, b"", {"Location": "http://%s/upload/session/%s" % (self.headers["Host"], sid)})

    def do_PUT(self):
        m = re.match(r"^/upload/session/(\w+)$", self.path)
        data = self.body()
        if not m or m.group(1) not in state["sessions"]:
            return self.send(404, {})
        s = state["sessions"][m.group(1)]
        cr = self.headers.get("Content-Range", "")
        range_hdr = {"Range": "bytes=0-%d" % (len(s["buf"]) - 1)} if s["buf"] else {}
        if cr.startswith("bytes */") and not (cr == "bytes */0" and s["total"] == 0):
            return self.send(308, b"", range_hdr)
        s["chunks"] += 1
        if state["slow"]: time.sleep(state["slow"])
        if state["fail_chunk"] and s["chunks"] == state["fail_chunk"]:
            state["fail_chunk"] = 0
            return self.send(503, {"error": {"code": 503}})
        mm = re.match(r"bytes (\d+)-(\d+)/(\d+)", cr)
        if mm and int(mm.group(1)) == len(s["buf"]):
            s["buf"] += data
        if len(s["buf"]) >= s["total"]:
            buf = s["buf"]
            if state["corrupt_upload"]:
                buf = buf[:-1] + bytes([(buf[-1] + 1) % 256])
            if "update" in s["meta"]:
                f = state["files"][s["meta"]["update"]]
                f["data"] = buf
            else:
                f = add(s["meta"]["name"], s["meta"]["parents"][0], buf)
            return self.send(200, entry(f))
        return self.send(308, b"", {"Range": "bytes=0-%d" % (len(s["buf"]) - 1)})

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
