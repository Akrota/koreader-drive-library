-- Drive-Bibliothek: Google Drive als Cloud-Bibliothek. Buecher auslagern (erst pruefen, dann loeschen)
-- und bei Bedarf wieder herunterladen. Die .sdr (Lesestand, eigene Angaben) geht mit nach Drive und bleibt
-- als Sicherheitskopie im Plugin-Ordner; in der Bibliothek bleibt nichts zurueck, leere Ordner verschwinden.
local Api = require("gdl_api")
local DataStorage = require("datastorage")
local Sdr = require("gdl_sdr")
local Browser = require("gdl_browser")
local ConfirmBox = require("ui/widget/confirmbox")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Job = require("gdl_job")
local PathChooser = require("ui/widget/pathchooser")
local T = require("gdl_i18n")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local DriveLibrary = WidgetContainer:extend{
    name = "drivelibrary",
    is_doc_only = false,
}

local BOOK_EXT = { cbz = true, cbr = true, cb7 = true, cbt = true, epub = true, kepub = true, pdf = true, mobi = true, azw = true, azw3 = true, djvu = true, fb2 = true }
local SETTINGS_KEY = "drivelibrary"
local DEFAULT_FOLDER = "KOReader Library"

local function settings()
    return G_reader_settings:readSetting(SETTINGS_KEY, {})
end

local function ext_of(path)
    return (path:match("%.([^./]+)$") or ""):lower()
end

function DriveLibrary:isBook(name)
    if name:sub(1, 2) == "._" then return false end
    return BOOK_EXT[ext_of(name)] == true
end

function DriveLibrary:rootDir()
    local dir = settings().root_dir or G_reader_settings:readSetting("home_dir") or "/mnt/onboard/books"
    return (dir:gsub("/+$", ""))
end

function DriveLibrary:folderName()
    return settings().folder_name or DEFAULT_FOLDER
end

--- Pfad relativ zur Bibliothek. @return { "comics", "Akira" }, "Band.cbz" oder nil
function DriveLibrary:relParts(path)
    local root = self:rootDir() .. "/"
    if path:sub(1, #root) ~= root then return nil end
    local parts = {}
    for p in path:sub(#root + 1):gmatch("[^/]+") do parts[#parts + 1] = p end
    local name = table.remove(parts)
    return parts, name
end

function DriveLibrary:errorText(key)
    if key == "no_credentials" then return T("no_credentials", Api.credentialsDir()) end
    return Job.errorText(key)
end

--- Im Werkzeuge-Menue weit oben einreihen: direkt nach Story Recall, Guitar Tab Reader und Comic Display
--- (die stellen sich selbst an den Anfang), sonst ganz oben.
function DriveLibrary.placeInToolsMenu()
    local TOP = { story_recall = true, guitar_tab_reader = true, comicdisplay = true }
    for _, mod in ipairs({ "ui/elements/reader_menu_order", "ui/elements/filemanager_menu_order" }) do
        local ok, order = pcall(require, mod)
        local tools = ok and type(order) == "table" and order.tools
        if type(tools) == "table" then
            for i = #tools, 1, -1 do if tools[i] == "drivelibrary" then table.remove(tools, i) end end
            local pos = 1
            for i, key in ipairs(tools) do if TOP[key] then pos = i + 1 end end
            table.insert(tools, pos, "drivelibrary")
        end
    end
end

function DriveLibrary:init()
    DriveLibrary.placeInToolsMenu()
    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterActions()
    if self.ui.addFileDialogButtons then
        self.ui:addFileDialogButtons("drivelibrary", function(file, is_file)
            local fits = is_file and self:isBook(file) and self:relParts(file) ~= nil
            local folder = not is_file and self:relParts((file:gsub("/+$", "")) .. "/x") ~= nil
            if not (fits or folder) then return end
            return { {
                text = is_file and T("button_offload") or T("button_offload_dir"),
                callback = function()
                    local FileManager = require("apps/filemanager/filemanager")
                    local fm = FileManager.instance
                    if fm and fm.file_dialog then UIManager:close(fm.file_dialog) end
                    if is_file then
                        self:confirmOffload({ file })
                    else
                        self:confirmOffload(self:booksIn(file))
                    end
                end,
            } }
        end)
    end
end

function DriveLibrary:onDispatcherRegisterActions()
    Dispatcher:registerAction("drivelibrary_open", { category = "none", event = "DriveLibraryOpen", title = T("menu_title") .. ": " .. T("open_cloud"), general = true })
    Dispatcher:registerAction("drivelibrary_offload_selected", { category = "none", event = "DriveLibraryOffloadSelected", title = T("menu_title") .. ": " .. T("offload_selected"), filemanager = true })
end

function DriveLibrary:onDriveLibraryOpen()
    self:openCloud()
    return true
end

function DriveLibrary:onDriveLibraryOffloadSelected()
    self:offloadSelected()
    return true
end

-- Ausgewaehlte Dateien aus KOReaders/ZenOS' Auswahl-Modus
function DriveLibrary:selectedBooks()
    local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
    local fm = ok and FileManager.instance
    local list = {}
    if fm and fm.selected_files then
        for file in pairs(fm.selected_files) do
            if self:isBook(file) then list[#list + 1] = file end
        end
    end
    table.sort(list)
    return list
end

function DriveLibrary:offloadSelected()
    local list = self:selectedBooks()
    if #list == 0 then
        UIManager:show(InfoMessage:new{ text = T("no_books") })
        return
    end
    self:confirmOffload(list)
end

--- Alle Buecher in einem Ordner, auch in Unterordnern
function DriveLibrary:booksIn(dir)
    local list = {}
    local function scan(d)
        for name in lfs.dir(d) do
            if name ~= "." and name ~= ".." and name:sub(1, 1) ~= "." then
                local p = d .. "/" .. name
                local mode = lfs.attributes(p, "mode")
                if mode == "directory" then
                    if not name:match("%.sdr$") then scan(p) end
                elseif mode == "file" and self:isBook(name) then
                    list[#list + 1] = p
                end
            end
        end
    end
    scan((dir:gsub("/+$", "")))
    table.sort(list)
    return list
end

function DriveLibrary:openFile()
    local ok, ReaderUI = pcall(require, "apps/reader/readerui")
    local ui = ok and ReaderUI.instance
    return ui and ui.document and ui.document.file or nil
end

function DriveLibrary:checkCredentials()
    local c, err = Api.credentials()
    if c then return true end
    UIManager:show(InfoMessage:new{ text = self:errorText(err) })
    return false
end

--- Auftrag zum Auslagern, mit Lesedaten (.sdr) und Ort der Sicherheitskopie
function DriveLibrary:offloadTask(file, parts, name, root_name)
    return {
        kind = "offload", file = file, rel = parts, name = name, root_name = root_name or self:folderName(),
        sdr = Sdr.localDir(file),
        sdr_archive = Sdr.archivePath(DataStorage:getDataDir(), parts, name),
        root = self:rootDir(),
    }
end

function DriveLibrary:confirmOffload(files)
    if #files == 0 then
        UIManager:show(InfoMessage:new{ text = T("no_books") })
        return
    end
    if not self:checkCredentials() then return end
    local tasks = {}
    local open_file = self:openFile()
    for _, file in ipairs(files) do
        local parts, name = self:relParts(file)
        if not parts then
            UIManager:show(InfoMessage:new{ text = T("local_only_root", file) })
            return
        end
        if file == open_file then
            UIManager:show(InfoMessage:new{ text = T("in_reader_open") })
            return
        end
        tasks[#tasks + 1] = self:offloadTask(file, parts, name)
    end
    local text = #tasks == 1 and T("offload_q_one", tasks[1].name) or T("offload_q_many", #tasks)
    self.offload_box = ConfirmBox:new{
        text = text,
        ok_text = T("offload"),
        ok_callback = function() self:startJobs(tasks) end,
    }
    self.offload_box.tasks = tasks
    UIManager:show(self.offload_box)
end

function DriveLibrary:startJobs(tasks)
    if not self:checkCredentials() then return end
    local NetworkMgr = require("ui/network/manager")
    NetworkMgr:runWhenOnline(function()
        if Job.add(tasks) then
            UIManager:show(InfoMessage:new{ text = T("started"), timeout = 3 })
        else
            UIManager:show(InfoMessage:new{ text = T("queued"), timeout = 2 })
        end
    end)
end

function DriveLibrary:openBook(path)
    if Browser.current and Browser.current.menu then
        UIManager:close(Browser.current.menu)
        Browser.current = nil
    end
    require("apps/reader/readerui"):showReader(path)
end

function DriveLibrary:openCloud()
    if not self:checkCredentials() then return end
    local NetworkMgr = require("ui/network/manager")
    NetworkMgr:runWhenOnline(function()
        local name = self:folderName()
        local root, err = Api.ensureFolder("root", name, true)
        if not root then
            UIManager:show(InfoMessage:new{ text = self:errorText(err) })
            return
        end
        Browser.show(self, root, name)
    end)
end

function DriveLibrary:checkLogin()
    if not self:checkCredentials() then return end
    local NetworkMgr = require("ui/network/manager")
    NetworkMgr:runWhenOnline(function()
        local name = self:folderName()
        local root, err = Api.ensureFolder("root", name, true)
        local files
        if root then files, err = Api.list(root) end
        if not files then
            UIManager:show(InfoMessage:new{ text = self:errorText(err) })
            return
        end
        UIManager:show(InfoMessage:new{ text = T("login_ok", name, #files) })
    end)
end

-- ── Nach dem Auftrag ─────────────────────────────────────────────────────────────────────────────
local function refresh_file_manager()
    local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
    local fm = ok and FileManager.instance
    if fm and fm.file_chooser then
        if fm.file_chooser._zen_clear_item_table_cache then pcall(fm.file_chooser._zen_clear_item_table_cache, fm.file_chooser) end
        fm.file_chooser:refreshPath()
    end
end

--- Datei nach bestandener Pruefung entfernen. Die .sdr bleibt absichtlich liegen.
-- @return true, wenn die Datei weg ist
function DriveLibrary.removeBookFile(file)
    local ok_r, ReaderUI = pcall(require, "apps/reader/readerui")
    local ui = ok_r and ReaderUI.instance
    if ui and ui.document and ui.document.file == file then return false end
    if not os.remove(file) then return false end
    local ok_l, BookList = pcall(require, "ui/widget/booklist")
    if ok_l and BookList.resetBookInfoCache then pcall(BookList.resetBookInfoCache, file) end
    local ok_b, BIM = pcall(require, "bookinfomanager")
    if ok_b and BIM and BIM.deleteBookInfo then pcall(BIM.deleteBookInfo, BIM, file) end
    local ok_h, ReadHistory = pcall(require, "readhistory")
    if ok_h then pcall(ReadHistory.fileDeleted, ReadHistory, file) end
    logger.info("DriveLibrary: offloaded", file)
    return true
end

local function free_space_text()
    local ok, util = pcall(require, "util")
    local plugin_root = settings().root_dir or G_reader_settings:readSetting("home_dir")
    if not ok or not util.diskUsage or not plugin_root then return nil end
    local ok2, usage = pcall(util.diskUsage, plugin_root)
    if ok2 and usage and usage.available and usage.available > 0 then
        return T("done_space", Browser.sizeText(usage.available))
    end
end

local function notify(text)
    local ok, Notification = pcall(require, "ui/widget/notification")
    if ok and Notification and Notification.notify then
        pcall(Notification.notify, Notification, text)
    else
        UIManager:show(InfoMessage:new{ text = text, timeout = 3 })
    end
end
DriveLibrary.notify = notify

local function show_summary(r)
    refresh_file_manager()
    Browser.refreshCurrent()
    -- Hintergrund-Auftraege beim Lesen: nur ein kurzer Hinweis, kein Fenster
    if r.quiet then
        if #r.fail > 0 then
            notify(T("note_failed", #r.fail))
            for _, l in ipairs(r.fail) do logger.warn("DriveLibrary:", l) end
        elseif r.prefetched then
            local all = r.prefetched_all or { r.prefetched }
            if #all > 1 then
                notify(T("note_prefetched_n", #all, (all[1]:gsub("%.[^.]+$", ""))))
            else
                notify(T("note_prefetched", (all[1]:gsub("%.[^.]+$", ""))))
            end
        elseif r.offloaded > 0 then
            notify(T("note_offloaded", r.offloaded))
        end
        return
    end
    -- Einzelner Download zum Oeffnen: direkt fragen
    if #r.fail == 0 and not r.cancelled and r.offloaded == 0 and r.last_download and r.last_download.open_after then
        local task = r.last_download
        UIManager:show(ConfirmBox:new{
            text = T("open_now", task.name),
            ok_text = T("open"),
            cancel_text = T("later"),
            ok_callback = function()
                if Browser.current and Browser.current.menu then
                    UIManager:close(Browser.current.menu)
                    Browser.current = nil
                end
                require("apps/reader/readerui"):showReader(task.dest)
            end,
        })
        return
    end
    local lines = { T("done_title") }
    if r.offloaded > 0 then lines[#lines + 1] = T("done_offload", r.offloaded) end
    if r.downloaded > 0 then lines[#lines + 1] = T("done_download", r.downloaded) end
    if #r.fail > 0 then lines[#lines + 1] = T("done_failed", #r.fail) end
    if r.cancelled then lines[#lines + 1] = T("done_cancelled") end
    for _, l in ipairs(r.fail) do lines[#lines + 1] = "• " .. l end
    local free = free_space_text()
    if free then lines[#lines + 1] = free end
    UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n") })
end

local function refresh_open_menu()
    for _, mod in ipairs({ "apps/reader/readerui", "apps/filemanager/filemanager" }) do
        local ok, UI = pcall(require, mod)
        local ui = ok and UI.instance
        local container = ui and ui.menu and ui.menu.menu_container
        local menu = container and container[1]
        if menu and type(menu.item_table) == "table" and menu.updateItems and UIManager:isWidgetShown(container) then
            for _, item in ipairs(menu.item_table) do
                if type(item) == "table" and item.gdl_status then
                    menu:updateItems()
                    return
                end
            end
        end
    end
end

Job.on_change = refresh_open_menu
Job.on_finish = show_summary
Job.on_offloaded = function(task, result)
    if not DriveLibrary.removeBookFile(task.file) then return false end
    -- Lesedaten: nur wenn sie in Drive geprueft sind, in die Sicherheitskopie verschieben
    if result and result.sdr and task.sdr and Sdr.isDir(task.sdr) then
        if Sdr.copyDir(task.sdr, task.sdr_archive, true) then
            Sdr.remove(task.sdr)
        else
            logger.warn("DriveLibrary: sdr archive copy failed, keeping", task.sdr)
        end
    elseif task.sdr and Sdr.isDir(task.sdr) and not Sdr.hasFiles(task.sdr) then
        Sdr.remove(task.sdr) -- leerer .sdr-Ordner
    end
    -- Markierung "ausgelagert", auch ohne Lesedaten (leerer Ordner in der Sicherheitskopie):
    -- so weiss das Vorladen ohne Netz, dass es diesen Band gibt
    if task.sdr_archive and not Sdr.isDir(task.sdr_archive) then require("util").makePath(task.sdr_archive) end
    if task.root then Sdr.removeEmptyParents(task.file:match("^(.*)/[^/]+$"), task.root) end
    return true
end

local function online()
    if DriveLibrary.force_online ~= nil then return DriveLibrary.force_online end -- nur fuer Tests
    local ok, NetworkMgr = pcall(require, "ui/network/manager")
    if not ok then return false end
    local ok2, connected = pcall(NetworkMgr.isConnected, NetworkMgr)
    return ok2 and connected and true or false
end
DriveLibrary.online = online

--- Flugmodus an? (Flugmodus-Plugin von KOReader/ZenOS, falls installiert)
local function airplane()
    local api = package.loaded["utils/flight_utilities"]
    local get = api and (api.getFlightStatus or api.getStatus)
    if type(get) == "function" then
        local ok, on = pcall(get, api)
        if ok and on == true then return true end
    end
    return G_reader_settings:isTrue("airplanemode")
end

--- WLAN still einschalten (ohne Fenster) und dann fn ausfuehren. Im Flugmodus nichts tun.
local function with_wifi(fn)
    if online() then return fn() end
    if DriveLibrary.force_online ~= nil or airplane() then return end
    local ok, NetworkMgr = pcall(require, "ui/network/manager")
    if not ok then return end
    pcall(NetworkMgr.enableWifi, NetworkMgr, function()
        if online() then fn() end
    end, false)
end
DriveLibrary.with_wifi = with_wifi

local function book_exts()
    local list = {}
    for e in pairs(BOOK_EXT) do list[#list + 1] = e end
    return list
end

-- ── Beim Lesen ───────────────────────────────────────────────────────────────────────────────────
--- Naechsten Band vorladen: einmal pro Buch, sobald 85 % gelesen sind (nur mit WLAN, still im Hintergrund).
DriveLibrary.PREFETCH_AT = 0.85
DriveLibrary.PREFETCH_RETRY = 120
DriveLibrary.PREFETCH_TRIES = 3
-- Vorladen fehlgeschlagen (kein WLAN zustande gekommen, Auftrag nicht gestartet, Netzfehler):
-- spaeter noch einmal, hoechstens PREFETCH_TRIES Versuche pro Buch
Job.on_next_failed = function(task) DriveLibrary.prefetch_pending = task.file end

function DriveLibrary:onPageUpdate(pageno)
    if not settings().prefetch_next then return end
    local doc = self.ui and self.ui.document
    if not doc or not doc.file or type(pageno) ~= "number" then return end
    if self.prefetch_done then
        if DriveLibrary.prefetch_pending ~= doc.file or (self.prefetch_tries or 0) >= DriveLibrary.PREFETCH_TRIES
                or os.time() < (self.prefetch_retry or 0) or Job.isRunning() then return end
        self.prefetch_done = false
    end
    local ok, total = pcall(doc.getPageCount, doc)
    if not ok or not total or total < 2 or pageno / total < DriveLibrary.PREFETCH_AT then return end
    local parts, name = self:relParts(doc.file)
    if not parts or not self:isBook(name) or not Api.credentials() then self.prefetch_done = true return end
    -- Erst ohne Netz schauen: liegt der naechste Band schon auf dem Geraet, ist nichts zu tun
    local count = settings().prefetch_count == 2 and 2 or 1
    if self:nextIsLocal(doc.file, parts, name, count) then self.prefetch_done = true return end
    self.prefetch_done = true
    self.prefetch_tries = (self.prefetch_tries or 0) + 1
    self.prefetch_retry = os.time() + DriveLibrary.PREFETCH_RETRY
    DriveLibrary.prefetch_pending = doc.file -- bleibt stehen, falls das WLAN nicht zustande kommt
    local task = {
        kind = "next", quiet = true, file = doc.file, rel = parts, name = name, root_name = self:folderName(),
        dir = doc.file:match("^(.*)/[^/]+$"), exts = book_exts(), count = count,
    }
    with_wifi(function()
        DriveLibrary.prefetch_pending = nil
        Job.add({ task })
    end)
end

--- Naechster Band laut Ordner auf dem Geraet: Buecher dort plus ausgelagerte (Sicherheitskopien der .sdr),
--- natuerlich sortiert. @return true, wenn der direkt folgende Band schon auf dem Geraet liegt
function DriveLibrary:nextIsLocal(file, parts, name, count)
    count = count or 1
    local dir = file:match("^(.*)/[^/]+$")
    local function stem(n) return (n:gsub("%.[^.]+$", "")) end
    local function key(n) return (n:lower():gsub("%d+", function(d) return string.rep("0", 12 - #d) .. d end)) end
    local entries = {}
    for f in lfs.dir(dir) do
        if f:sub(1, 1) ~= "." and self:isBook(f) and lfs.attributes(dir .. "/" .. f, "mode") == "file" then
            entries[stem(f)] = "local"
        end
    end
    local arch = Sdr.archivePath(DataStorage:getDataDir(), parts, "x.cbz"):match("^(.*)/[^/]+$")
    if arch and lfs.attributes(arch, "mode") == "directory" then
        for f in lfs.dir(arch) do
            local st = f:match("^(.*)%.sdr$")
            if st and not entries[st] then entries[st] = "cloud" end
        end
    end
    local list = {}
    for st in pairs(entries) do list[#list + 1] = st end
    table.sort(list, function(a, b) return key(a) < key(b) end)
    for i, st in ipairs(list) do
        if st == stem(name) then
            -- nur sicher, wenn alle gewuenschten Folgebaende bekannt und auf dem Geraet sind
            for k = 1, count do
                if entries[list[i + k] or ""] ~= "local" then return false end
            end
            return true
        end
    end
    return false
end

-- Nach dem Lesen: automatisch auslagern, Lesestand sichern oder fragen (je nach Einstellung)
function DriveLibrary:onCloseDocument()
    local s = settings()
    if not (s.ask_after_finish or s.auto_offload or s.sync_sdr) then return end
    local doc = self.ui and self.ui.document
    local file = doc and doc.file
    if not file or not self.ui.doc_settings then return end
    local summary = self.ui.doc_settings:readSetting("summary")
    local complete = type(summary) == "table" and summary.status == "complete"
    local parts, name = self:relParts(file)
    if not parts or not self:isBook(name) or not Api.credentials() then return end
    local root_name = self:folderName()
    local plugin = self
    -- Erst nach dem Schliessen und kurz warten: KOReader speichert den Lesestand beim Schliessen
    if complete and s.auto_offload then
        UIManager:scheduleIn(3, function()
            local task = plugin:offloadTask(file, parts, name, root_name)
            task.quiet = true
            with_wifi(function() Job.add({ task }) end)
        end)
        return
    end
    if s.sync_sdr and not (complete and s.ask_after_finish) then
        UIManager:scheduleIn(3, function()
            with_wifi(function()
                Job.add({ { kind = "syncsdr", quiet = true, file = file, rel = parts, name = name, root_name = root_name,
                    sdr = Sdr.localDir(file) } })
            end)
        end)
    end
    if not (complete and s.ask_after_finish) then return end
    UIManager:scheduleIn(0.5, function()
        UIManager:show(ConfirmBox:new{
            text = T("offload_ask_finished", name),
            ok_text = T("offload"),
            ok_callback = function()
                plugin:startJobs({ plugin:offloadTask(file, parts, name, root_name) })
            end,
        })
    end)
end

-- ── Menue ────────────────────────────────────────────────────────────────────────────────────────
function DriveLibrary:addToMainMenu(menu_items)
    menu_items.drivelibrary = {
        text = T("menu_title"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text_func = function() return Job.statusText() end,
                gdl_status = true,
                keep_menu_open = true,
                enabled_func = function() return Job.isRunning() end,
                callback = function() self:confirmCancel() end,
                separator = true,
            },
            { text = T("open_cloud"), callback = function() self:openCloud() end },
            {
                text_func = function()
                    local n = #self:selectedBooks()
                    return n > 0 and T("offload_selected_n", n) or T("offload_selected")
                end,
                enabled_func = function() return #self:selectedBooks() > 0 end,
                callback = function() self:offloadSelected() end,
                separator = true,
            },
            {
                text = T("settings"),
                sub_item_table = {
                    {
                        text_func = function() return T("set_root", self:rootDir()) end,
                        keep_menu_open = true,
                        callback = function()
                            UIManager:show(PathChooser:new{
                                select_directory = true,
                                select_file = false,
                                path = self:rootDir(),
                                onConfirm = function(dir) settings().root_dir = dir end,
                            })
                        end,
                    },
                    {
                        text_func = function() return T("set_folder", self:folderName()) end,
                        keep_menu_open = true,
                        callback = function() self:editFolderName() end,
                    },
                    {
                        text = T("set_ask"),
                        help_text = T("set_ask_help"),
                        checked_func = function() return settings().ask_after_finish == true end,
                        enabled_func = function() return not settings().auto_offload end,
                        callback = function() settings().ask_after_finish = not settings().ask_after_finish end,
                    },
                    {
                        text = T("set_auto_offload"),
                        help_text = T("set_auto_offload_help"),
                        checked_func = function() return settings().auto_offload == true end,
                        callback = function() settings().auto_offload = not settings().auto_offload end,
                    },
                    {
                        text = T("set_prefetch"),
                        help_text = T("set_prefetch_help"),
                        checked_func = function() return settings().prefetch_next == true end,
                        sub_item_table = {
                            {
                                text = T("prefetch_off"),
                                radio = true,
                                checked_func = function() return not settings().prefetch_next end,
                                callback = function() settings().prefetch_next = nil end,
                            },
                            {
                                text = T("prefetch_one"),
                                radio = true,
                                checked_func = function() return settings().prefetch_next == true and settings().prefetch_count ~= 2 end,
                                callback = function() settings().prefetch_next = true; settings().prefetch_count = 1 end,
                            },
                            {
                                text = T("prefetch_two"),
                                radio = true,
                                checked_func = function() return settings().prefetch_next == true and settings().prefetch_count == 2 end,
                                callback = function() settings().prefetch_next = true; settings().prefetch_count = 2 end,
                            },
                        },
                    },
                    {
                        text = T("set_sync_sdr"),
                        help_text = T("set_sync_sdr_help"),
                        checked_func = function() return settings().sync_sdr == true end,
                        callback = function() settings().sync_sdr = not settings().sync_sdr end,
                    },
                    {
                        text = T("check_login"),
                        keep_menu_open = true,
                        callback = function() self:checkLogin() end,
                    },
                },
                separator = true,
            },
            {
                text = T("about"),
                keep_menu_open = true,
                callback = function() UIManager:show(InfoMessage:new{ text = T("about_text") }) end,
            },
        },
    }
end

function DriveLibrary:editFolderName()
    local dialog
    dialog = InputDialog:new{
        title = T("set_folder_title"),
        input = self:folderName(),
        buttons = { {
            { text = T("abort"), id = "close", callback = function() UIManager:close(dialog) end },
            {
                text = "OK",
                is_enter_default = true,
                callback = function()
                    local v = dialog:getInputText():gsub("^%s+", ""):gsub("%s+$", "")
                    if v ~= "" then settings().folder_name = v end
                    UIManager:close(dialog)
                end,
            },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function DriveLibrary:confirmCancel()
    if not Job.isRunning() then return end
    UIManager:show(ConfirmBox:new{
        text = T("cancel_q", Job.currentName()),
        ok_text = T("abort"),
        cancel_text = T("continue"),
        ok_callback = function() Job.cancel() end,
    })
end

return DriveLibrary
