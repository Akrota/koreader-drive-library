-- Drive-Bibliothek: eigener kleiner Prozess fuer einen Auftrag (hochladen, pruefen, herunterladen).
-- Wird von gdl_job.lua mit KOReaders luajit im KOReader-Ordner gestartet:
--   ./luajit <plugin>/gdl_worker.lua <plugin-ordner> <auftrag.json> <ergebnis.json> <fortschritt.txt> <koreader-pid>
-- Braucht nur ein paar MB Arbeitsspeicher und ist unabhaengig vom grossen KOReader-Prozess.
local plugin_dir, task_file, result_file, progress_file, parent_pid = ...
package.path = plugin_dir .. "/?.lua;common/?.lua;frontend/?.lua;" .. package.path
package.cpath = "common/?.so;libs/?.so;" .. package.cpath
require("setupkoenv")
-- socketutil (Netz) laedt sonst KOReaders ganzes Geraetemodul samt Bildschirm (>100 MB). Es braucht nur
-- den Geraetenamen fuer die Kennung der Anfragen; ein schlanker Ersatz haelt diesen Prozess bei ein paar MB.
package.loaded["device"] = { model = "Kobo" }

local json -- erst nach setupkoenv verfuegbar
local function write_result(result)
    local ok_j, encoded = pcall(json.encode, result)
    local f = io.open(result_file .. ".tmp", "w")
    if not f then return end
    f:write(ok_j and encoded or '{"err":"unknown:encode"}')
    f:close()
    os.rename(result_file .. ".tmp", result_file)
end

local ok, err = pcall(function()
    json = require("json")
    G_defaults = require("luadefaults"):open()
    local DataStorage = require("datastorage")
    -- Nur lesen (z. B. wo KOReader die .sdr ablegt); der Prozess speichert nie Einstellungen
    G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.reader.lua")

    local f = assert(io.open(task_file, "r"))
    local task = json.decode(f:read("*a"))
    f:close()

    local Api = require("gdl_api")
    for k, v in pairs(task.api or {}) do Api[k] = v end -- Adressen/Groessen wie im Hauptprogramm (Tests)
    local Tasks = require("gdl_tasks")

    local last = -1
    local function progress(stage, done, total)
        -- KOReader beendet? Dann abbrechen.
        if parent_pid then
            local h = io.open("/proc/" .. parent_pid .. "/stat", "r")
            if not h then return false end
            h:close()
        end
        local now = os.time()
        if now ~= last then
            last = now
            local p = io.open(progress_file .. ".new", "w")
            if p then
                p:write(string.format("%s %d %d", stage, done or 0, total or 0))
                p:close()
                os.rename(progress_file .. ".new", progress_file)
            end
        end
        return true
    end

    local run = ({ offload = Tasks.runOffload, next = Tasks.runNext, syncsdr = Tasks.runSyncSdr })[task.kind] or Tasks.runDownload
    local ok_r, result = pcall(run, task, progress)
    if not ok_r then result = { err = "unknown:" .. tostring(result) } end
    write_result(result)
end)
if not ok then
    if not json then pcall(function() json = require("json") end) end
    if json then write_result({ err = "unknown:" .. tostring(err) }) end
end
os.exit(0)
