-- Drive-Bibliothek: Cloud-Ansicht. Zeigt einen Ordner aus Google Drive und bei jedem Buch, ob es auch auf
-- dem Geraet liegt. Antippen oeffnet es oder laedt es herunter.
local Api = require("gdl_api")
local DataStorage = require("datastorage")
local Sdr = require("gdl_sdr")
local ButtonDialog = require("ui/widget/buttondialog")
local DocSettings = require("docsettings")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local T = require("gdl_i18n")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local Screen = require("device").screen

local Browser = {}

function Browser.sizeText(bytes)
    bytes = tonumber(bytes)
    if not bytes then return "" end
    if bytes >= 1024 * 1024 * 1024 then return string.format("%.1f GB", bytes / (1024 * 1024 * 1024)) end
    return string.format("%d MB", math.max(1, math.floor(bytes / (1024 * 1024) + 0.5)))
end

local function read_settings(file)
    if not file or lfs.attributes(file, "mode") ~= "file" then return nil end
    local ok, s = pcall(DocSettings.openSettingsFile, file)
    return ok and s or nil
end

-- Eigener Titel und Lesestand: aus der .sdr neben dem Buch, sonst aus der Sicherheitskopie des Plugins
function Browser.localInfo(path, archive)
    local info = {}
    if archive and Sdr.isDir(archive) and not Sdr.isDir(Sdr.localDir(path)) then
        local custom = read_settings(archive .. "/custom_metadata.lua")
        local props = custom and custom:readSetting("custom_props")
        if type(props) == "table" and type(props.title) == "string" and props.title ~= "" then info.title = props.title end
        local ext = (path:match("%.([^./]+)$") or ""):lower()
        local meta = read_settings(archive .. "/metadata." .. ext .. ".lua")
        local summary = meta and meta:readSetting("summary")
        if type(summary) == "table" then info.status = summary.status end
        return info
    end
    local ok_c, cmf = pcall(DocSettings.findCustomMetadataFile, DocSettings, path)
    if ok_c and cmf then
        local ok, s = pcall(DocSettings.openSettingsFile, cmf)
        local custom = ok and s:readSetting("custom_props")
        if type(custom) == "table" and type(custom.title) == "string" and custom.title ~= "" then
            info.title = custom.title
        end
    end
    local ok_h, sidecar = pcall(DocSettings.findSidecarFile, DocSettings, path)
    if ok_h and sidecar then
        local ok, ds = pcall(DocSettings.open, DocSettings, path)
        local summary = ok and ds:readSetting("summary")
        if type(summary) == "table" then info.status = summary.status end
    end
    return info
end

local function natural_key(s)
    return (s:lower():gsub("%d+", function(d) return string.rep("0", 12 - #d) .. d end))
end

--- Eintraege fuer die Anzeige aufbereiten: nur Ordner und Buecher, Ordner zuerst, natuerlich sortiert.
function Browser.buildEntries(files, local_dir, is_book, archive_for)
    local folders, books = {}, {}
    for _, f in ipairs(files) do
        if f.mimeType == Api.FOLDER_MIME then
            -- .sdr-Ordner (z. B. aus einer hochgeladenen Sicherung) und versteckte Ordner nicht zeigen
            if not f.name:match("%.sdr$") and f.name:sub(1, 1) ~= "." then
                folders[#folders + 1] = f
            end
        elseif is_book(f.name) then
            local path = local_dir .. "/" .. f.name
            f.local_path = path
            f.on_device = lfs.attributes(path, "mode") == "file"
            local info = Browser.localInfo(path, archive_for and archive_for(f.name))
            f.display = info.title or f.name:gsub("%.[^.]+$", "")
            f.read = info.status == "complete"
            books[#books + 1] = f
        end
    end
    local by = function(a, b) return natural_key(a.name) < natural_key(b.name) end
    table.sort(folders, by)
    table.sort(books, by)
    return folders, books
end

--- @param plugin das Plugin (root_dir, Auftraege, oeffnen)
function Browser.show(plugin, root_id, root_name)
    local browser = {
        plugin = plugin,
        stack = { { id = root_id, name = root_name, parts = {} } },
        selecting = false,
        selected = {},   -- Drive-ID -> Auftrag, bleibt beim Ordnerwechsel
        sel_order = {},  -- Reihenfolge des Anhakens = Reihenfolge beim Laden
    }
    setmetatable(browser, { __index = Browser })
    browser.menu = Menu:new{
        title = root_name,
        item_table = {},
        is_borderless = true,
        is_popout = false,
        covers_fullscreen = true,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        title_bar_fm_style = true,
        -- Haekchen oben links: Auswahl-Modus (mehrere Buecher anhaken, dann zusammen laden)
        title_bar_left_icon = "check",
        onLeftButtonTap = function()
            browser:onSelectButton()
        end,
        -- Antippen fuehrt nur die Aktion aus. KOReaders Menu wuerde danach close_callback aufrufen und die
        -- Cloud-Ansicht bei jedem Ordner oder Buch schliessen.
        onMenuSelect = function(_menu, item)
            if item.callback then item.callback() end
            return true
        end,
        onMenuHold = function(_menu, item)
            browser:onHold(item)
            return true
        end,
        onReturn = function()
            browser:goBack()
        end,
        close_callback = function()
            UIManager:close(browser.menu)
            Browser.current = nil
        end,
    }
    browser.menu.paths = {}
    Browser.current = browser
    UIManager:show(browser.menu)
    browser:load()
    return browser
end

function Browser:top()
    return self.stack[#self.stack]
end

function Browser:localDir()
    local dir = self.plugin:rootDir()
    for _, part in ipairs(self:top().parts) do dir = dir .. "/" .. part end
    return dir
end

function Browser:load()
    local level = self:top()
    local msg = InfoMessage:new{ text = T("loading") }
    UIManager:show(msg)
    UIManager:forceRePaint()
    local files, err = Api.list(level.id)
    UIManager:close(msg)
    if not files then
        UIManager:show(InfoMessage:new{ text = self.plugin:errorText(err) })
        files = {}
    end
    level.files = files
    self:render()
end

function Browser:render()
    local level = self:top()
    local folders, books = Browser.buildEntries(level.files or {}, self:localDir(), function(n) return self.plugin:isBook(n) end,
        function(n) return Sdr.archivePath(DataStorage:getDataDir(), level.parts, n) end)
    level.folders, level.books = folders, books
    local items = {}
    local missing = 0
    for _, b in ipairs(books) do if not b.on_device then missing = missing + 1 end end
    if self.selecting then
        local n = #self.sel_order
        items[#items + 1] = {
            text = n > 0 and T("sel_load", n) or T("sel_hint"),
            bold = n > 0,
            callback = function() self:onSelectButton() end,
        }
    elseif missing > 1 then
        items[#items + 1] = {
            text = T("download_all", missing),
            bold = true,
            callback = function() self:downloadAll() end,
        }
    end
    for _, f in ipairs(folders) do
        items[#items + 1] = {
            text = f.name,
            mandatory = "▸",
            entry = f,
            callback = function() self:enter(f) end,
        }
    end
    for i, b in ipairs(books) do
        local size = Browser.sizeText(b.size)
        local key = b.on_device and (b.read and "state_read" or "state_local") or (b.read and "state_cloud_read" or "state_cloud")
        local text = b.display
        if self.selecting and not b.on_device then
            text = (self.selected[b.id] and "☑ " or "☐ ") .. text
        end
        items[#items + 1] = {
            text = text,
            mandatory = T(key, size),
            entry = b,
            book_index = i,
            callback = function()
                if self.selecting then self:toggle(b, i) else self:tapBook(b) end
            end,
        }
    end
    if #items == 0 then
        items[1] = { text = T("empty"), dim = true, callback = function() end }
    end
    self.menu.paths = {}
    for i = 2, #self.stack do self.menu.paths[i - 1] = self.stack[i] end
    local title = level.name
    -- Beim Anhaken auf derselben Seite bleiben
    local keep = self.keep_page and self.menu.page and self.menu.perpage
        and ((self.menu.page - 1) * self.menu.perpage + 1) or nil
    self.keep_page = nil
    local subtitle = self.selecting and T("sel_subtitle", #self.sel_order) or ""
    self.menu:switchItemTable(title, items, keep, nil, subtitle)
end

-- Auswahl-Modus -----------------------------------------------------------------------------------

function Browser:setSelected(book, on)
    if book.on_device then return end
    if on and not self.selected[book.id] then
        self.selected[book.id] = self:taskFor(book)
        self.sel_order[#self.sel_order + 1] = book.id
    elseif not on and self.selected[book.id] then
        self.selected[book.id] = nil
        for i, id in ipairs(self.sel_order) do
            if id == book.id then table.remove(self.sel_order, i) break end
        end
    end
end

function Browser:toggle(book, index)
    if book.on_device then return end
    local on = not self.selected[book.id]
    self:setSelected(book, on)
    self.last_pick = on and { folder = self:top().id, index = index } or nil
    self.keep_page = true
    self:render()
end

--- Lang druecken im Auswahl-Modus: alles vom zuletzt angehakten bis hier anhaken.
function Browser:selectRange(index)
    local level = self:top()
    local from = (self.last_pick and self.last_pick.folder == level.id) and self.last_pick.index or index
    local a, b = math.min(from, index), math.max(from, index)
    for i = a, b do
        local book = level.books[i]
        if book then self:setSelected(book, true) end
    end
    self.last_pick = { folder = level.id, index = index }
    self.keep_page = true
    self:render()
end

function Browser:clearSelection()
    self.selecting = false
    self.selected, self.sel_order, self.last_pick = {}, {}, nil
end

--- Haekchen oben links (und oberster Eintrag im Auswahl-Modus)
function Browser:onSelectButton()
    if not self.selecting then
        self.selecting = true
        self:render()
        return
    end
    local n = #self.sel_order
    if n == 0 then
        self:clearSelection()
        self:render()
        return
    end
    local dialog
    dialog = ButtonDialog:new{
        title = T("sel_confirm", n),
        buttons = {
            { { text = T("sel_go", n), callback = function()
                UIManager:close(dialog)
                self:downloadSelected()
            end } },
            { { text = T("sel_more"), callback = function() UIManager:close(dialog) end } },
            { { text = T("sel_cancel"), callback = function()
                UIManager:close(dialog)
                self:clearSelection()
                self:render()
            end } },
        },
    }
    UIManager:show(dialog)
end

function Browser:downloadSelected()
    local tasks = {}
    for _, id in ipairs(self.sel_order) do tasks[#tasks + 1] = self.selected[id] end
    self:clearSelection()
    self:render()
    if #tasks > 0 then self.plugin:startJobs(tasks) end
end

function Browser:enter(folder)
    local level = self:top()
    local parts = {}
    for i, p in ipairs(level.parts) do parts[i] = p end
    parts[#parts + 1] = folder.name
    self.stack[#self.stack + 1] = { id = folder.id, name = folder.name, parts = parts }
    self:load()
end

function Browser:goBack()
    if #self.stack > 1 then
        self.stack[#self.stack] = nil
        self:render()
    end
end

function Browser:taskFor(book, open_after)
    return {
        kind = "download", name = book.name, dest = book.local_path, open_after = open_after,
        parent_id = self:top().id,
        sdr_archive = Sdr.archivePath(DataStorage:getDataDir(), self:top().parts, book.name),
        entry = { id = book.id, name = book.name, size = book.size, md5Checksum = book.md5Checksum },
    }
end

function Browser:tapBook(book)
    if book.on_device then
        self.plugin:openBook(book.local_path)
    else
        self.plugin:startJobs({ self:taskFor(book, true) })
    end
end

function Browser:downloadAll()
    local tasks = {}
    for _, b in ipairs(self:top().books or {}) do
        if not b.on_device then tasks[#tasks + 1] = self:taskFor(b) end
    end
    if #tasks > 0 then self.plugin:startJobs(tasks) end
end

function Browser:onHold(item)
    local entry = item.entry
    if not entry then return end
    if self.selecting and item.book_index then
        self:selectRange(item.book_index)
        return
    end
    local dialog
    local buttons = {}
    local function add(text, fn)
        buttons[#buttons + 1] = { { text = text, callback = function()
            UIManager:close(dialog)
            fn()
        end } }
    end
    if entry.mimeType == Api.FOLDER_MIME then
        add(T("open"), function() self:enter(entry) end)
    elseif entry.on_device then
        add(T("hold_open"), function() self.plugin:openBook(entry.local_path) end)
        add(T("hold_offload"), function() self.plugin:confirmOffload({ entry.local_path }) end)
    else
        add(T("hold_download"), function() self.plugin:startJobs({ self:taskFor(entry, true) }) end)
    end
    dialog = ButtonDialog:new{ title = entry.display or entry.name, buttons = buttons }
    UIManager:show(dialog)
end

--- Nach einem Auftrag: Anzeige erneuern, ohne neu aus dem Netz zu laden.
function Browser.refreshCurrent()
    local b = Browser.current
    if b and b.menu and UIManager:isWidgetShown(b.menu) then b:render() end
end

return Browser
