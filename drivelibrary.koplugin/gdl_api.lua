-- Drive-Bibliothek: Anbindung an die Google-Drive-API.
-- Laeuft im Hauptprogramm (Listen) und im Unterprozess (Laden, Hochladen).
-- Grosse Dateien gehen nie komplett in den Speicher: Herunterladen schreibt direkt in die Datei,
-- Hochladen laeuft in Stuecken. Zugangsdaten und Tokens werden nie geloggt.
local DataStorage = require("datastorage")
local http = require("socket.http")
local https = require("ssl.https")
local json = require("json")
local lfs = require("libs/libkoreader-lfs")
local ltn12 = require("ltn12")
local md5 = require("ffi/sha2").md5
local socket = require("socket")
local socketutil = require("socketutil")
local socket_url = require("socket.url")
local util = require("util")

local Api = {
    token_url = "https://oauth2.googleapis.com/token",
    api_url = "https://www.googleapis.com/drive/v3",
    upload_url = "https://www.googleapis.com/upload/drive/v3",
    ca_file = "data/ca-bundle.crt",
    chunk_size = 2 * 1024 * 1024, -- Vielfaches von 256 KB (Drive); klein gehalten fuer wenig Arbeitsspeicher
    retry_wait = 2,
}

local FOLDER_MIME = "application/vnd.google-apps.folder"
Api.FOLDER_MIME = FOLDER_MIME

local token, token_expires
local creds

function Api.credentialsDir()
    return DataStorage:getDataDir() .. "/drivelibrary"
end

function Api.resetSession()
    token, token_expires, creds = nil, nil, nil
end

local function read_all(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

--- Zugangsdaten lesen. @return table oder nil, Fehlerschluessel
function Api.credentials()
    if creds then return creds end
    local dir = Api.credentialsDir()
    local raw = read_all(dir .. "/client_id.json")
    local refresh = read_all(dir .. "/refresh_token.txt")
    if not raw or not refresh then return nil, "no_credentials" end
    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= "table" then return nil, "bad_credentials" end
    local c = data.web or data.installed or data
    refresh = refresh:gsub("%s+", "")
    if type(c.client_id) ~= "string" or type(c.client_secret) ~= "string" or refresh == "" then
        return nil, "bad_credentials"
    end
    creds = { client_id = c.client_id, client_secret = c.client_secret, refresh_token = refresh }
    return creds
end

-- Eine Anfrage. Bei https immer mit Zertifikatspruefung.
-- @return code, headers  oder nil, Fehlertext
local function raw_request(req)
    local params = {
        url = req.url, method = req.method or "GET", headers = req.headers or {},
        source = req.source, sink = req.sink, redirect = false,
    }
    local mod = http
    if req.url:sub(1, 6) == "https:" then
        mod = https
        params.verify = "peer"
        params.cafile = Api.ca_file
    end
    local ok, a, code, headers = pcall(mod.request, params)
    if not ok then return nil, tostring(a) end
    if a == nil then return nil, tostring(code) end
    return code, headers
end

local function form_encode(t)
    local parts = {}
    for k, v in pairs(t) do parts[#parts + 1] = k .. "=" .. socket_url.escape(v) end
    return table.concat(parts, "&")
end

--- Gueltigen Zugang holen (bis kurz vor Ablauf zwischengespeichert). @return token oder nil, Fehlerschluessel
function Api.accessToken(force)
    if token and not force and os.time() < (token_expires or 0) - 60 then return token end
    local c, err = Api.credentials()
    if not c then return nil, err end
    local body = form_encode{
        client_id = c.client_id, client_secret = c.client_secret,
        refresh_token = c.refresh_token, grant_type = "refresh_token",
    }
    local out = {}
    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local code = raw_request{
        url = Api.token_url, method = "POST",
        headers = { ["Content-Type"] = "application/x-www-form-urlencoded", ["Content-Length"] = tostring(#body) },
        source = ltn12.source.string(body), sink = ltn12.sink.table(out),
    }
    socketutil:reset_timeout()
    if not code then return nil, "network" end
    local ok, data = pcall(json.decode, table.concat(out))
    if code == 200 and ok and type(data) == "table" and data.access_token then
        token = data.access_token
        token_expires = os.time() + (tonumber(data.expires_in) or 3600)
        return token
    end
    if ok and type(data) == "table" and (data.error == "invalid_grant" or data.error == "invalid_client" or data.error == "unauthorized_client") then
        return nil, "token_invalid"
    end
    return nil, "token_failed"
end

-- JSON-Anfrage mit Zugang. Wiederholt bei abgelaufenem Zugang, Ueberlastung und Serverfehlern.
local function api_json(method, url, body)
    local encoded = body and json.encode(body) or nil
    local tries = 0
    while true do
        tries = tries + 1
        local tok, terr = Api.accessToken()
        if not tok then return nil, terr end
        local out = {}
        local headers = { ["Authorization"] = "Bearer " .. tok, ["Accept"] = "application/json" }
        if encoded then
            headers["Content-Type"] = "application/json; charset=UTF-8"
            headers["Content-Length"] = tostring(#encoded)
        end
        socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
        local code, resp = raw_request{
            url = url, method = method, headers = headers,
            source = encoded and ltn12.source.string(encoded) or nil, sink = ltn12.sink.table(out),
        }
        socketutil:reset_timeout()
        if code == 401 and tries <= 2 then
            token = nil
        elseif (not code or code == 403 or code == 429 or (type(code) == "number" and code >= 500)) and tries <= 3 then
            socket.sleep(Api.retry_wait * tries)
        elseif not code then
            return nil, "network"
        else
            local ok, data = pcall(json.decode, table.concat(out))
            if code >= 200 and code < 300 and ok then return data, nil, resp end
            local reason = ok and type(data) == "table" and type(data.error) == "table" and data.error.errors
                and data.error.errors[1] and data.error.errors[1].reason
            if reason == "storageQuotaExceeded" then return nil, "quota" end
            if code == 404 then return nil, "not_found" end
            return nil, "http_" .. tostring(code)
        end
    end
end

local function q_string(s)
    return "'" .. s:gsub("\\", "\\\\"):gsub("'", "\\'") .. "'"
end

local FIELDS = "id,name,mimeType,size,md5Checksum,modifiedTime"

--- Alle Eintraege eines Drive-Ordners (auch ueber mehrere Antwortseiten). @return Liste oder nil, Fehler
function Api.list(folder_id)
    local q = socket_url.escape(q_string(folder_id) .. " in parents and trashed = false")
    local fields = socket_url.escape("nextPageToken,files(" .. FIELDS .. ")")
    local files, page = {}, nil
    repeat
        local url = Api.api_url .. "/files?pageSize=1000&q=" .. q .. "&fields=" .. fields
        if page then url = url .. "&pageToken=" .. socket_url.escape(page) end
        local data, err = api_json("GET", url)
        if not data then return nil, err end
        for _, f in ipairs(data.files or {}) do files[#files + 1] = f end
        page = data.nextPageToken
    until not page or page == json.null
    return files
end

--- Eintrag mit diesem Namen in einem Ordner. @return Eintrag, nil (nicht gefunden) oder nil, Fehler
function Api.findChild(parent_id, name)
    local q = socket_url.escape("name = " .. q_string(name) .. " and " .. q_string(parent_id) .. " in parents and trashed = false")
    local url = Api.api_url .. "/files?pageSize=10&q=" .. q .. "&fields=" .. socket_url.escape("files(" .. FIELDS .. ")")
    local data, err = api_json("GET", url)
    if not data then return nil, err end
    return data.files and data.files[1] or nil
end

function Api.createFolder(parent_id, name)
    local data, err = api_json("POST", Api.api_url .. "/files?fields=" .. socket_url.escape(FIELDS),
        { name = name, mimeType = FOLDER_MIME, parents = { parent_id } })
    if not data then return nil, err end
    return data
end

--- Unterordner holen, auf Wunsch anlegen. @return Ordner-ID oder nil, Fehler
function Api.ensureFolder(parent_id, name, create)
    local found, err = Api.findChild(parent_id, name)
    if err then return nil, err end
    if found then
        if found.mimeType ~= FOLDER_MIME then return nil, "not_a_folder" end
        return found.id
    end
    if not create then return nil, "not_found" end
    local made, cerr = Api.createFolder(parent_id, name)
    if not made then return nil, cerr end
    return made.id
end

--- Ordner der Reihe nach durchgehen ({"comics", "Akira"}). @return Ordner-ID oder nil, Fehler
function Api.walk(root_id, parts, create)
    local id = root_id
    for _, part in ipairs(parts) do
        local nid, err = Api.ensureFolder(id, part, create)
        if not nid then return nil, err end
        id = nid
    end
    return id
end

--- MD5 einer Datei in Stuecken. Drive liefert fuer jede Datei dieselbe Pruefsumme.
function Api.md5File(path, progress)
    local f = io.open(path, "rb")
    if not f then return nil end
    local update = md5()
    local total = lfs.attributes(path, "size") or 0
    local done = 0
    while true do
        local chunk = f:read(1024 * 1024)
        if not chunk then break end
        update(chunk)
        done = done + #chunk
        if progress and progress(done, total) == false then
            f:close()
            return nil, "cancelled"
        end
    end
    f:close()
    return update()
end

--- Datei herunterladen und pruefen. Am Ziel erscheint sie erst nach bestandener Pruefung.
-- @param file Drive-Eintrag mit id, size, md5Checksum
-- @return true oder nil, Fehlerschluessel
function Api.download(file, dest, progress)
    local tok, terr = Api.accessToken()
    if not tok then return nil, terr end
    local dir = dest:match("^(.*)/[^/]+$")
    if dir then util.makePath(dir) end
    local part = dest .. ".part"
    local handle, ioerr = io.open(part, "wb")
    if not handle then return nil, "write:" .. tostring(ioerr) end
    local total = tonumber(file.size)
    local received = 0
    local cancelled = false
    local file_sink = ltn12.sink.file(handle)
    local sink = function(chunk, err)
        if chunk then
            received = received + #chunk
            if progress and progress(received, total) == false then
                cancelled = true
                return nil, "cancelled"
            end
        end
        return file_sink(chunk, err)
    end
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, -1)
    local url = Api.api_url .. "/files/" .. socket_url.escape(file.id) .. "?alt=media"
    local code = raw_request{ url = url, headers = { ["Authorization"] = "Bearer " .. tok }, sink = sink }
    socketutil:reset_timeout()
    pcall(function() io.close(handle) end)
    local function fail(key)
        os.remove(part)
        return nil, key
    end
    if cancelled then return fail("cancelled") end
    if code == 401 then token = nil; return fail("http_401") end
    if code == 403 then return fail("http_403") end
    if code == 404 then return fail("not_found") end
    if code ~= 200 then return fail(type(code) == "number" and ("http_" .. code) or "network") end
    if total and lfs.attributes(part, "size") ~= total then return fail("size_mismatch") end
    if file.md5Checksum then
        local sum = Api.md5File(part, progress and function(d, t) return progress(d, t, "check") end or nil)
        if sum ~= file.md5Checksum then return fail("md5_mismatch") end
    end
    if lfs.attributes(dest, "mode") then os.remove(part); return nil, "exists" end
    local ok, rerr = os.rename(part, dest)
    if not ok then return fail("write:" .. tostring(rerr)) end
    return true
end

-- Wie weit ist die Sitzung gekommen? @return naechstes Byte oder "done", Eintrag oder nil, Fehler
local function session_status(session, total)
    local out = {}
    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local code, headers = raw_request{
        url = session, method = "PUT",
        headers = { ["Content-Range"] = "bytes */" .. total, ["Content-Length"] = "0" },
        source = ltn12.source.string(""), sink = ltn12.sink.table(out),
    }
    socketutil:reset_timeout()
    if code == 308 then
        local range = headers and headers.range
        local last = range and range:match("bytes=0%-(%d+)")
        return last and (tonumber(last) + 1) or 0
    end
    if code == 200 or code == 201 then
        local ok, data = pcall(json.decode, table.concat(out))
        if ok then return "done", data end
    end
    return nil, code and ("http_" .. tostring(code)) or "network"
end

--- Datei in Stuecken hochladen. Bricht die Verbindung ab, geht es an der letzten Stelle weiter.
-- @param file_id gesetzt: Inhalt einer vorhandenen Drive-Datei ersetzen (fuer .sdr-Dateien)
-- @return Drive-Eintrag oder nil, Fehlerschluessel
function Api.upload(path, parent_id, name, progress, file_id)
    local total = lfs.attributes(path, "size")
    if not total then return nil, "read" end
    local tok, terr = Api.accessToken()
    if not tok then return nil, terr end
    local meta = file_id and "{}" or json.encode{ name = name, parents = { parent_id } }
    local url = Api.upload_url .. "/files" .. (file_id and ("/" .. socket_url.escape(file_id)) or "")
        .. "?uploadType=resumable&fields=" .. socket_url.escape(FIELDS)
    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local code, headers = raw_request{
        url = url, method = file_id and "PATCH" or "POST",
        headers = {
            ["Authorization"] = "Bearer " .. tok,
            ["Content-Type"] = "application/json; charset=UTF-8",
            ["Content-Length"] = tostring(#meta),
            ["X-Upload-Content-Type"] = "application/octet-stream",
            ["X-Upload-Content-Length"] = tostring(total),
        },
        source = ltn12.source.string(meta), sink = ltn12.sink.null(),
    }
    socketutil:reset_timeout()
    if not code then return nil, "network" end
    if code == 403 then return nil, "quota_or_forbidden" end
    local session = code == 200 and headers and headers.location
    if not session then return nil, "http_" .. tostring(code) end

    local f = io.open(path, "rb")
    if not f then return nil, "read" end
    local function finish(a, b)
        f:close()
        return a, b
    end
    local offset, failures = 0, 0
    while true do
        if progress and progress(offset, total) == false then return finish(nil, "cancelled") end
        f:seek("set", offset)
        local chunk = total > 0 and f:read(Api.chunk_size) or ""
        local stop = offset + #chunk - 1
        local out = {}
        socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, -1)
        local c, h = raw_request{
            url = session, method = "PUT",
            headers = {
                ["Content-Length"] = tostring(#chunk),
                ["Content-Range"] = total > 0 and string.format("bytes %d-%d/%d", offset, stop, total) or "bytes */0",
            },
            source = ltn12.source.string(chunk), sink = ltn12.sink.table(out),
        }
        socketutil:reset_timeout()
        chunk = nil -- luacheck: ignore
        if c == 200 or c == 201 then
            local ok, data = pcall(json.decode, table.concat(out))
            if ok and type(data) == "table" and data.id then return finish(data) end
            return finish(nil, "bad_response")
        elseif c == 308 then
            local last = h and h.range and h.range:match("bytes=0%-(%d+)")
            offset = last and (tonumber(last) + 1) or 0
            failures = 0
        else
            failures = failures + 1
            if failures > 5 then return finish(nil, c and ("http_" .. tostring(c)) or "network") end
            if c == 403 then return finish(nil, "quota_or_forbidden") end
            socket.sleep(Api.retry_wait * failures)
            local next_byte, entry = session_status(session, total)
            if next_byte == "done" then return finish(entry) end
            if type(next_byte) == "number" then offset = next_byte end
        end
    end
end

--- Ordner (z. B. .sdr) nach Drive spiegeln: fehlende Dateien hochladen, geaenderte ersetzen, jede pruefen.
-- In Drive ueberzaehlige Dateien bleiben. @return true oder nil, Fehlerschluessel
function Api.uploadDir(local_dir, parent_id, name)
    local folder, ferr = Api.ensureFolder(parent_id, name, true)
    if not folder then return nil, ferr end
    local existing, lerr = Api.list(folder)
    if not existing then return nil, lerr end
    local by_name = {}
    for _, f in ipairs(existing) do
        if not by_name[f.name] then by_name[f.name] = f end
    end
    for e in lfs.dir(local_dir) do
        if e ~= "." and e ~= ".." then
            local p = local_dir .. "/" .. e
            local mode = lfs.attributes(p, "mode")
            if mode == "directory" then
                local ok, err = Api.uploadDir(p, folder, e)
                if not ok then return nil, err end
            elseif mode == "file" then
                local sum = Api.md5File(p)
                if not sum then return nil, "read" end
                local size = lfs.attributes(p, "size")
                local have = by_name[e]
                if have and have.mimeType == FOLDER_MIME then return nil, "not_a_file" end
                if not (have and have.md5Checksum == sum and tonumber(have.size) == size) then
                    local up, uerr = Api.upload(p, folder, e, nil, have and have.id)
                    if not up then return nil, uerr end
                    local stored, cerr = Api.findChild(folder, e)
                    if cerr then return nil, cerr end
                    if not stored or stored.md5Checksum ~= sum or tonumber(stored.size) ~= size then
                        return nil, "md5_mismatch"
                    end
                end
            end
        end
    end
    return true
end

--- Drive-Ordner komplett herunterladen. Das Ziel entsteht erst, wenn alles geprueft ist.
-- @return true oder nil, Fehlerschluessel
function Api.downloadDir(folder_id, dest)
    if lfs.attributes(dest, "mode") then return nil, "exists" end
    local tmp = dest .. ".part"
    local ffiutil = require("ffi/util")
    if lfs.attributes(tmp, "mode") == "directory" then ffiutil.purgeDir(tmp) end
    local function fetch(id, dir)
        util.makePath(dir)
        local files, err = Api.list(id)
        if not files then return nil, err end
        for _, f in ipairs(files) do
            if f.name ~= "." and f.name ~= ".." and not f.name:find("/", 1, true) then
                if f.mimeType == FOLDER_MIME then
                    local ok, ferr = fetch(f.id, dir .. "/" .. f.name)
                    if not ok then return nil, ferr end
                elseif f.md5Checksum then -- nur echte Dateien (keine Google-Dokumente)
                    local ok, derr = Api.download(f, dir .. "/" .. f.name)
                    if not ok then return nil, derr end
                end
            end
        end
        return true
    end
    local ok, err = fetch(folder_id, tmp)
    if not ok then
        ffiutil.purgeDir(tmp)
        return nil, err
    end
    if not os.rename(tmp, dest) then
        ffiutil.purgeDir(tmp)
        return nil, "write"
    end
    return true
end

return Api
