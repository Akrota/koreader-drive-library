-- Drive-Bibliothek: die eigentliche Arbeit (hochladen, pruefen, herunterladen). Ohne Oberflaeche:
-- laeuft im eigenen kleinen Prozess (gdl_worker.lua), nicht als Abzweig von KOReader. Ein Abzweig
-- teilt anfangs den Speicher mit KOReader und kopiert ihn beim Arbeiten nach und nach, was beim
-- Lesen grosser Comics den Arbeitsspeicher sprengen kann (Absturz am 10.11.2026).
local Api = require("gdl_api")
local Sdr = require("gdl_sdr")
local DataStorage = require("datastorage")

local Job = {}
--- Hochladen falls noetig und pruefen. Loescht selbst nichts.
-- @return { ok = true, uploaded = bool } oder { err = Schluessel }
function Job.runOffload(task, progress)
    local stage_progress = function(stage)
        return function(done, total) return progress(stage, done, total) end
    end
    local sum, serr = Api.md5File(task.file, stage_progress("check"))
    if not sum then return { err = serr or "read" } end
    local size = require("libs/libkoreader-lfs").attributes(task.file, "size")
    local root, rerr = Api.ensureFolder("root", task.root_name, true)
    if not root then return { err = rerr } end
    local parent, perr = Api.walk(root, task.rel, true)
    if not parent then return { err = perr } end
    local existing, ferr = Api.findChild(parent, task.name)
    if ferr then return { err = ferr } end
    local uploaded = false
    if existing then
        if existing.md5Checksum ~= sum or tonumber(existing.size) ~= size then
            return { err = "differs" }
        end
    else
        local up, uerr = Api.upload(task.file, parent, task.name, stage_progress("up"))
        if not up then return { err = uerr } end
        -- Nachfragen statt der Antwort zu vertrauen: So zaehlt, was wirklich in Drive liegt.
        local stored, cerr = Api.findChild(parent, task.name)
        if cerr then return { err = cerr } end
        if not stored or stored.md5Checksum ~= sum or tonumber(stored.size) ~= size then
            return { err = "md5_mismatch" }
        end
        uploaded = true
    end
    -- Lesedaten: der Stand auf dem Geraet ersetzt den in Drive. Klappt das nicht, wird nichts geloescht.
    local sdr_done = false
    if task.sdr and Sdr.hasFiles(task.sdr) then
        local ok, serr = Api.uploadDir(task.sdr, parent, Sdr.driveName(task.name))
        if not ok then
            require("logger").warn("DriveLibrary: sdr upload failed", tostring(serr))
            return { err = "sdr_failed" }
        end
        sdr_done = true
    end
    return { ok = true, uploaded = uploaded, sdr = sdr_done }
end

--- Herunterladen und pruefen.
function Job.runDownload(task, progress)
    local ok, err = Api.download(task.entry, task.dest, function(done, total, stage)
        return progress(stage or "down", done, total)
    end)
    if not ok then return { err = err } end
    return { ok = true, sdr = Job.restoreSdr(task) }
end

--- Lesedaten zum heruntergeladenen Buch: zuerst aus der Sicherheitskopie, sonst aus Drive.
--- Eine vorhandene .sdr bleibt immer, wie sie ist. Fehler hier lassen den Download gelten.
-- @return "local", "archive", "drive", "none" oder "failed"
function Job.restoreSdr(task)
    local dest = Sdr.localDir(task.dest)
    if Sdr.isDir(dest) then return "local" end
    if task.sdr_archive and Sdr.isDir(task.sdr_archive) and not Sdr.hasFiles(task.sdr_archive) then
        Sdr.remove(task.sdr_archive) -- nur die Markierung "ausgelagert", Lesedaten ggf. aus Drive
    end
    if task.sdr_archive and Sdr.isDir(task.sdr_archive) then
        if Sdr.copyDir(task.sdr_archive, dest) then
            Sdr.remove(task.sdr_archive)
            return "archive"
        end
        return "failed"
    end
    if not task.parent_id then return "none" end
    local folder, ferr = Api.findChild(task.parent_id, Sdr.driveName(task.name))
    if ferr then return "failed" end
    if not folder or folder.mimeType ~= Api.FOLDER_MIME then return "none" end
    local ok = Api.downloadDir(folder.id, dest)
    return ok and "drive" or "failed"
end

local function natural_key(n)
    return (n:lower():gsub("%d+", function(d) return string.rep("0", 12 - #d) .. d end))
end

--- Naechsten Band im selben Drive-Ordner laden (nach dem aktuellen Dateinamen, natuerlich sortiert).
-- Liegt er schon auf dem Geraet, passiert nichts. @return { ok, downloaded = Name } / { ok, none } / { err }
function Job.runNext(task, progress)
    local root, rerr = Api.ensureFolder("root", task.root_name)
    if not root then return { err = rerr } end
    local parent, perr = Api.walk(root, task.rel)
    if not parent then return { err = perr } end
    local files, lerr = Api.list(parent)
    if not files then return { err = lerr } end
    local exts = {}
    for _, e in ipairs(task.exts or {}) do exts[e] = true end
    local books = {}
    for _, f in ipairs(files) do
        local ext = (f.name:match("%.([^./]+)$") or ""):lower()
        if f.mimeType ~= Api.FOLDER_MIME and exts[ext] and f.name:sub(1, 1) ~= "." then books[#books + 1] = f end
    end
    table.sort(books, function(a, b) return natural_key(a.name) < natural_key(b.name) end)
    local idx
    for i, f in ipairs(books) do
        if f.name == task.name then idx = i break end
    end
    if not idx then return { ok = true, none = true } end
    local count = math.max(1, math.min(tonumber(task.count) or 1, 5))
    local got = {}
    for i = idx + 1, math.min(idx + count, #books) do -- gibt es weniger Folgebaende, eben weniger
        local nxt = books[i]
        local dest = task.dir .. "/" .. nxt.name
        if not require("libs/libkoreader-lfs").attributes(dest, "mode") then
            local ok, err = Api.download(nxt, dest, function(done, total, stage) return progress(stage or "down", done, total) end)
            if not ok then
                if #got > 0 then return { ok = true, downloaded = got[1], downloaded_all = got, partial_err = err } end
                return { err = err }
            end
            Job.restoreSdr({ dest = dest, name = nxt.name, parent_id = parent,
                sdr_archive = Sdr.archivePath(DataStorage:getDataDir(), task.rel, nxt.name) })
            got[#got + 1] = nxt.name
        end
    end
    if #got == 0 then return { ok = true, none = true } end
    return { ok = true, downloaded = got[1], downloaded_all = got }
end

--- Lesestand (.sdr) eines Buchs nach Drive spiegeln, wenn das Buch dort liegt. Loescht nichts.
function Job.runSyncSdr(task)
    if not (task.sdr and Sdr.hasFiles(task.sdr)) then return { ok = true, skipped = true } end
    local root, rerr = Api.ensureFolder("root", task.root_name)
    if not root then return { err = rerr } end
    local parent = Api.walk(root, task.rel)
    if not parent then return { ok = true, skipped = true } end
    local book, ferr = Api.findChild(parent, task.name)
    if ferr then return { err = ferr } end
    if not book then return { ok = true, skipped = true } end
    local ok, err = Api.uploadDir(task.sdr, parent, Sdr.driveName(task.name))
    if not ok then return { err = err } end
    return { ok = true, synced = true }
end


return Job
