-- Drive-Bibliothek: Auftraege im Hintergrund. Jede Datei laeuft in einem eigenen kleinen Prozess
-- (gdl_worker.lua, KOReaders luajit), KOReader bleibt bedienbar und sein Arbeitsspeicher unberuehrt.
-- Fortschritt und Ergebnis kommen ueber kleine Dateien im Cache-Ordner.
-- Geloescht wird nur im Hauptprogramm und nur, wenn der Auftrag die Pruefung bestaetigt hat.
local DataStorage = require("datastorage")
local T = require("gdl_i18n")
local UIManager = require("ui/uimanager")
local json = require("json")
local logger = require("logger")

local Job = {
    queue = {},
    index = 0,
    total = 0,
    child = nil,
    progress = nil,  -- { stage, done, total }
    results = nil,
    on_change = nil,
    on_finish = nil,
    on_offloaded = nil, -- function(task) -> true, wenn die Datei geloescht wurde
}

local POLL = 1
Job.START_RETRY = 3
-- Eigener Unterordner: KOReader merkt sich beim Start alle Dateien direkt in cache/ und stuerzt beim
-- Schliessen eines Buchs ab, wenn eine davon inzwischen geloescht ist (doccache.lua, 11.11.2026).
local WORK_DIR = DataStorage:getDataDir() .. "/cache/drivelibrary"
local PROGRESS_FILE = WORK_DIR .. "/progress.txt"

local function changed()
    if Job.on_change then pcall(Job.on_change) end
end

-- ── Wach bleiben ─────────────────────────────────────────────────────────────────────────────────
local awake, suspend_paused = false, false

local function keepAwake(on)
    if on == awake then return end
    awake = on
    local ok, PluginShare = pcall(require, "pluginshare")
    if on then
        UIManager:preventStandby()
        if ok and not PluginShare.pause_auto_suspend then
            PluginShare.pause_auto_suspend = true
            suspend_paused = true
        end
    else
        UIManager:allowStandby()
        if ok and suspend_paused then PluginShare.pause_auto_suspend = false end
        suspend_paused = false
    end
end

-- ── Aufgaben: siehe gdl_tasks.lua (laufen im eigenen Prozess gdl_worker.lua) ──────────────────────
local Tasks = require("gdl_tasks")
Job.runOffload, Job.runDownload, Job.restoreSdr, Job.runNext, Job.runSyncSdr =
    Tasks.runOffload, Tasks.runDownload, Tasks.restoreSdr, Tasks.runNext, Tasks.runSyncSdr

local function write_progress(stage, done, total)
    local f = io.open(PROGRESS_FILE .. ".new", "w")
    if f then
        f:write(string.format("%s %d %d", stage, done or 0, total or 0))
        f:close()
        os.rename(PROGRESS_FILE .. ".new", PROGRESS_FILE)
    end
end

local function read_progress()
    local f = io.open(PROGRESS_FILE, "r")
    if not f then return end
    local stage, done, total = f:read("*a"):match("^(%a+) (%d+) (%d+)")
    f:close()
    if stage then Job.progress = { stage = stage, done = tonumber(done), total = tonumber(total) } end
end

local PLUGIN_DIR = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "plugins/drivelibrary.koplugin"
local TASK_FILE = WORK_DIR .. "/task.json"
local RESULT_FILE = WORK_DIR .. "/result.json"

local function my_pid()
    local f = io.open("/proc/self/stat", "r")
    if not f then return nil end
    local pid = f:read("*a"):match("^(%d+)")
    f:close()
    return pid
end

local function alive(pid)
    local f = pid and io.open("/proc/" .. pid .. "/stat", "r")
    if not f then return false end
    local st = f:read("*a")
    f:close()
    return not st:match("^%d+ %b() Z") -- Zombie zaehlt als beendet
end

local function sh_quote(s) return "'" .. tostring(s):gsub("'", [['\'']]) .. "'" end

--- Auftrag als eigenen kleinen Prozess starten (nicht als Abzweig von KOReader, siehe gdl_tasks.lua)
local function start_child(task)
    os.remove(PROGRESS_FILE)
    os.remove(RESULT_FILE)
    require("util").makePath(WORK_DIR)
    local Api = require("gdl_api")
    task.api = { token_url = Api.token_url, api_url = Api.api_url, upload_url = Api.upload_url,
        chunk_size = Api.chunk_size, retry_wait = Api.retry_wait, ca_file = Api.ca_file }
    local f = io.open(TASK_FILE, "w")
    if not f then return false end
    f:write(json.encode(task))
    f:close()
    local cmd = string.format("./luajit %s %s %s %s %s %s >/dev/null 2>&1 & echo $!",
        sh_quote(PLUGIN_DIR .. "/gdl_worker.lua"), sh_quote(PLUGIN_DIR), sh_quote(TASK_FILE),
        sh_quote(RESULT_FILE), sh_quote(PROGRESS_FILE), sh_quote(my_pid() or ""))
    local h, perr = io.popen(cmd, "r")
    local pid = h and h:read("*l")
    if h then h:close() end
    if not pid or not pid:match("^%d+$") then
        logger.warn("DriveLibrary: worker start failed", h and ("output=" .. tostring(pid)) or ("popen: " .. tostring(perr)))
        return false
    end
    Job.child = { pid = pid, task = task, started = os.time() }
    Job.progress = nil
    return true
end

local function read_result()
    local f = io.open(RESULT_FILE, "r")
    if not f then return nil end
    local raw = f:read("*a")
    f:close()
    local ok, result = pcall(json.decode, raw or "")
    return ok and type(result) == "table" and result or { err = "crash" }
end

local function task_name(task)
    return task.name
end

-- Fehlerschluessel in lesbaren Text
function Job.errorText(key)
    key = tostring(key or "crash")
    if key:match("^unknown:") or key:match("^http_") or key:match("^write:") then return T("unknown", key) end
    local text = T(key)
    if text == key then return T("unknown", key) end
    return text
end

local function record(task, result)
    local r = Job.results
    if result.ok then
        if task.kind == "offload" then
            if Job.on_offloaded and Job.on_offloaded(task, result) then
                r.offloaded = r.offloaded + 1
            else
                r.fail[#r.fail + 1] = task_name(task) .. ": " .. T("in_reader_open")
            end
        elseif task.kind == "next" then
            if result.downloaded then
                local all = result.downloaded_all or { result.downloaded }
                r.downloaded = r.downloaded + #all
                r.prefetched = result.downloaded
                r.prefetched_all = all
            end
        elseif task.kind == "syncsdr" then
            if result.synced then r.synced = (r.synced or 0) + 1 end
        else
            r.downloaded = r.downloaded + 1
            r.last_download = task
        end
    elseif result.err == "exists" and task.kind == "download" then
        r.last_download = task
    else
        r.fail[#r.fail + 1] = task_name(task) .. ": " .. Job.errorText(result.err)
        if task.kind == "next" and Job.on_next_failed then pcall(Job.on_next_failed, task) end
    end
end

local poll

local function finish()
    if Job.poll_task then UIManager:unschedule(Job.poll_task) end
    Job.poll_task, Job.child, Job.progress = nil, nil, nil
    os.remove(PROGRESS_FILE)
    keepAwake(false)
    local results = Job.results
    Job.results = nil
    Job.queue = {}
    changed()
    if Job.on_finish then Job.on_finish(results) end
end

local function next_task()
    while #Job.queue > 0 do
        local task = table.remove(Job.queue, 1)
        Job.index = Job.index + 1
        changed()
        if start_child(task) then
            Job.poll_task = poll
            UIManager:scheduleIn(POLL, poll)
            return
        end
        -- Ein zweiter Versuch nach kurzer Pause (Kobo 13.11.2026: Start schlug einmal direkt nach dem
        -- Einschalten des WLANs fehl, wenig freier Speicher)
        if not task.start_retried then
            task.start_retried = true
            table.insert(Job.queue, 1, task)
            Job.index = Job.index - 1
            Job.poll_task = next_task
            UIManager:scheduleIn(Job.START_RETRY, next_task)
            return
        end
        record(task, { err = "start_failed" })
    end
    finish()
end

poll = function()
    Job.poll_task = nil
    local child = Job.child
    if not child then return end
    read_progress()
    local result = read_result()
    if not result and not alive(child.pid) then
        result = read_result() -- koennte gerade fertig geworden sein
        if not result then
            logger.warn("DriveLibrary: job ended without result", task_name(child.task))
            if child.task.dest then os.remove(child.task.dest .. ".part") end
            result = { err = "crash" }
        end
    end
    if result then
        os.remove(RESULT_FILE)
        Job.child = nil
        record(child.task, result)
        next_task()
        return
    end
    changed()
    Job.poll_task = poll
    UIManager:scheduleIn(POLL, poll)
end

-- ── Oeffentlich ──────────────────────────────────────────────────────────────────────────────────
function Job.isRunning()
    return Job.results ~= nil
end

local function task_key(task)
    return task.kind .. ":" .. (task.file or task.dest)
end

--- Auftraege starten. Laeuft schon etwas, kommen sie hinten an die Warteschlange.
-- @return true bei neuem Lauf, false wenn angehaengt
function Job.add(tasks)
    local seen = {}
    if Job.child then seen[task_key(Job.child.task)] = true end
    for _, t in ipairs(Job.queue) do seen[task_key(t)] = true end
    local added = 0
    for _, t in ipairs(tasks) do
        local k = task_key(t)
        if not seen[k] then
            seen[k] = true
            Job.queue[#Job.queue + 1] = t
            added = added + 1
        end
    end
    local quiet = true
    for _, t in ipairs(tasks) do if not t.quiet then quiet = false end end
    if Job.isRunning() then
        Job.total = Job.total + added
        if not quiet then Job.results.quiet = false end
        changed()
        return false
    end
    -- quiet: Hintergrund-Auftraege beim Lesen (Vorladen, automatisch auslagern, Lesestand sichern),
    -- danach nur ein kurzer Hinweis statt eines Fensters
    Job.results = { offloaded = 0, downloaded = 0, fail = {}, cancelled = false, quiet = quiet }
    Job.index, Job.total = 0, #Job.queue
    keepAwake(true)
    next_task()
    return true
end

function Job.cancel()
    if not Job.isRunning() then return end
    local child = Job.child
    if child then
        os.execute("kill " .. child.pid .. " 2>/dev/null")
        os.remove(RESULT_FILE)
        if child.task.dest then os.remove(child.task.dest .. ".part") end
    end
    Job.results.cancelled = true
    finish()
end

function Job.statusText()
    if not Job.isRunning() then return T("status_idle") end
    local p = Job.progress
    if p and p.total and p.total > 0 then
        local pct = math.floor(p.done * 100 / p.total)
        local key = p.stage == "up" and "status_up" or p.stage == "check" and "status_check" or "status_down"
        return T(key, Job.index, Job.total, pct)
    end
    return T("status_wait", Job.index, Job.total)
end

function Job.currentName()
    return Job.child and task_name(Job.child.task) or ""
end

return Job
