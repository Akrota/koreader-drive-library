-- Tests fuer die Drive-Bibliothek gegen den nachgebauten Server (fake_drive.py).
local Api = require("gdl_api")
local Job = require("gdl_job")
local util = require("util")
local Browser = require("gdl_browser")
local DocSettings = require("docsettings")
local UIManager = require("ui/uimanager")
local http = require("socket.http")
local json = require("json")
local lfs = require("libs/libkoreader-lfs")
local DataStorage = require("datastorage")
local Sdr = require("gdl_sdr")

local BASE = "http://127.0.0.1:8765"
local LIB = "/work/gdltest/lib"
local f = io.open("/work/gdltest/result.txt", "w")
local passed, failed = 0, 0
local function log(...) local p = {} for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end f:write(table.concat(p, " "), "\n"); f:flush() end
local function check(name, ok, extra)
    if ok then passed = passed + 1 else failed = failed + 1 end
    log(ok and "PASS" or "FAIL", name, (not ok and extra) and ("[" .. tostring(extra) .. "]") or "")
end
local function exists(p) return lfs.attributes(p, "mode") ~= nil end
local function write(p, data)
    local dir = p:match("^(.*)/[^/]+$")
    os.execute("mkdir -p '" .. dir .. "'")
    local h = io.open(p, "wb"); h:write(data); h:close()
end
local function read(p) local h = io.open(p, "rb"); if not h then return nil end local s = h:read("*a"); h:close(); return s end
local function mode(q) return http.request(BASE .. "/__mode?" .. q) end
local function server_state() return json.decode((http.request(BASE .. "/__state"))) end

Api.token_url = BASE .. "/token"
Api.api_url = BASE .. "/drive/v3"
Api.upload_url = BASE .. "/upload/drive/v3"
Api.chunk_size = 256 * 1024
Api.retry_wait = 0

local CRED = Api.credentialsDir()
local function set_creds(refresh)
    os.execute("mkdir -p '" .. CRED .. "'")
    write(CRED .. "/client_id.json", json.encode{ web = { client_id = "cid", client_secret = "sec" } })
    write(CRED .. "/refresh_token.txt", refresh .. "\n")
    Api.resetSession()
end

local plugin
local FAKE
local steps, last_result = {}, nil
Job.on_finish_orig = Job.on_finish
Job.on_finish = function(r) last_result = r end

local function run_steps()
    local i = 0
    local function nextstep()
        if Job.isRunning() then UIManager:scheduleIn(0.2, nextstep); return end
        i = i + 1
        local s = steps[i]
        if not s then
            log(string.format("ERGEBNIS: %d bestanden, %d fehlgeschlagen", passed, failed))
            f:close()
            UIManager:quit()
            return
        end
        local ok, err = xpcall(s, debug.traceback)
        if not ok then check("Schritt " .. i .. " ohne Absturz", false, err) end
        UIManager:scheduleIn(0.3, nextstep)
    end
    nextstep()
end

local function offload(path)
    local parts, name = plugin:relParts(path)
    last_result = nil
    Job.add({ plugin:offloadTask(path, parts, name, "Kobo Bibliothek") })
end

local BIG = string.rep("ABCDEFGH", 128 * 1024) .. "ende" -- gut 1 MB, mehrere Stuecke
local ARCH -- Sicherheitskopie der .sdr von Akira Band 1
local AKIRA_DIR
local function akira_download()
    local remote = Api.findChild(AKIRA_DIR, "Band 1.cbz")
    last_result = nil
    Job.add({ { kind = "download", name = remote.name, dest = LIB .. "/comics/Akira/Band 1.cbz",
        parent_id = AKIRA_DIR, sdr_archive = ARCH,
        entry = { id = remote.id, size = remote.size, md5Checksum = remote.md5Checksum, name = remote.name } } })
end

steps = {
    function()
        local FileManager = require("apps/filemanager/filemanager")
        plugin = FileManager.instance.drivelibrary
        check("Plugin im Dateimanager geladen", plugin ~= nil)
        G_reader_settings:saveSetting("drivelibrary", { root_dir = LIB })
        check("Bibliothek aus den Einstellungen", plugin:rootDir() == LIB, plugin:rootDir())
        check("Standard-Ordner in Drive", plugin:folderName() == "Kobo Bibliothek")

        os.execute("rm -rf '" .. CRED .. "'")
        Api.resetSession()
        local c, err = Api.credentials()
        check("Ohne Dateien: klare Meldung", c == nil and err == "no_credentials" and plugin:errorText(err):find(CRED, 1, true) ~= nil)
        set_creds("bad-refresh")
        local t, terr = Api.accessToken()
        check("Abgelaufene Anmeldung erkannt", t == nil and terr == "token_invalid", terr)
        check("Meldung dazu verstaendlich", plugin:errorText(terr):find("Anmeldung", 1, true) or plugin:errorText(terr):find("sign", 1, true))
        write(CRED .. "/client_id.json", "kaputt{")
        Api.resetSession()
        local c2, e2 = Api.credentials()
        check("Kaputte client_id.json: kein Absturz", c2 == nil and e2 == "bad_credentials")
        set_creds("good-refresh")
        check("Anmeldung funktioniert", Api.accessToken() == "tok1")
        local calls = server_state().token_calls
        Api.accessToken()
        check("Zugang wird zwischengespeichert", server_state().token_calls == calls)
        mode("expire=1")
        local root = Api.ensureFolder("root", "Kobo Bibliothek", true)
        check("Abgelaufener Zugang wird automatisch erneuert", root ~= nil)
        check("Ordner nur einmal angelegt", Api.ensureFolder("root", "Kobo Bibliothek", true) == root)
        check("Fehlender Ordner ohne Anlegen", select(2, Api.ensureFolder(root, "gibtsnicht", false)) == "not_found")
        for i = 1, 8 do Api.createFolder(root, "Ordner " .. i) end
        local list = Api.list(root)
        check("Liste ueber mehrere Antwortseiten vollstaendig", list and #list == 8, list and #list)
    end,

    -- Auslagern: neu hochladen
    function()
        write(LIB .. "/comics/Akira/Band 1.cbz", BIG)
        write(LIB .. "/comics/Akira/Band 1.sdr/custom_metadata.lua", 'return { ["custom_props"] = { ["title"] = "Akira 01" }, ["doc_props"] = {} }')
        write(LIB .. "/comics/Akira/Band 1.sdr/metadata.cbz.lua", 'return { ["last_page"] = 5, ["summary"] = { ["status"] = "complete" } }')
        ARCH = Sdr.archivePath(DataStorage:getDataDir(), { "comics", "Akira" }, "Band 1.cbz")
        os.execute("rm -rf '" .. Sdr.archiveRoot(DataStorage:getDataDir()) .. "'")
        offload(LIB .. "/comics/Akira/Band 1.cbz")
    end,
    function()
        check("Auslagern ohne Fehler", last_result and #last_result.fail == 0 and last_result.offloaded == 1, last_result and last_result.fail[1])
        check("Datei vom Geraet entfernt", not exists(LIB .. "/comics/Akira/Band 1.cbz"))
        check(".sdr nicht mehr in der Bibliothek", not exists(LIB .. "/comics/Akira/Band 1.sdr"))
        check("Leere Ordner entfernt", not exists(LIB .. "/comics/Akira") and not exists(LIB .. "/comics") and exists(LIB))
        check("Sicherheitskopie der .sdr", read(ARCH .. "/metadata.cbz.lua") and read(ARCH .. "/custom_metadata.lua"))
        local root = Api.ensureFolder("root", "Kobo Bibliothek")
        local dir = Api.walk(root, { "comics", "Akira" })
        check("Ordner in Drive wie auf dem Geraet", dir ~= nil)
        local remote = dir and Api.findChild(dir, "Band 1.cbz")
        check("Datei liegt vollstaendig in Drive", remote and tonumber(remote.size) == #BIG)
        local sdr_dir = dir and Api.findChild(dir, "Band 1.sdr")
        local sdr_files = sdr_dir and Api.list(sdr_dir.id) or {}
        check(".sdr liegt in Drive (2 Dateien)", #sdr_files == 2, #sdr_files)
        check("Buch und .sdr je einmal hochgeladen", server_state().uploads == 3, server_state().uploads)
        AKIRA_DIR = dir

        -- Wieder herunterladen: Inhalt und Lesestand (aus der Sicherheitskopie)
        last_result = nil
        Job.add({ { kind = "download", name = remote.name, dest = LIB .. "/comics/Akira/Band 1.cbz", open_after = true,
            parent_id = dir, sdr_archive = ARCH,
            entry = { id = remote.id, size = remote.size, md5Checksum = remote.md5Checksum, name = remote.name } } })
    end,
    function()
        check("Herunterladen ohne Fehler", last_result and #last_result.fail == 0 and last_result.downloaded == 1, last_result and last_result.fail[1])
        check("Inhalt identisch", read(LIB .. "/comics/Akira/Band 1.cbz") == BIG)
        check("Keine .part-Reste", not exists(LIB .. "/comics/Akira/Band 1.cbz.part"))
        check("Oeffnen wird angeboten", last_result and last_result.last_download and last_result.last_download.open_after)
        local ds = DocSettings:open(LIB .. "/comics/Akira/Band 1.cbz")
        check("Lesestand wieder da", ds:readSetting("last_page") == 5)
        check("Status wieder da", (ds:readSetting("summary") or {}).status == "complete")
        check("Sicherheitskopie nach dem Zurueckholen weg", not exists(ARCH))

        -- Liegt schon in Drive und ist gleich: kein zweiter Upload
        last_result = nil
        offload(LIB .. "/comics/Akira/Band 1.cbz")
    end,
    function()
        check("Schon in Drive: kein zweiter Upload", server_state().uploads == 3, server_state().uploads)
        check("Schon in Drive: trotzdem entfernt", last_result and last_result.offloaded == 1 and not exists(LIB .. "/comics/Akira/Band 1.cbz"))

        -- Andere Datei gleichen Namens in Drive: NICHT loeschen
        write(LIB .. "/comics/Akira/Band 1.cbz", "andere Datei")
        last_result = nil
        offload(LIB .. "/comics/Akira/Band 1.cbz")
    end,
    function()
        check("Anderer Inhalt: Fehler gemeldet", last_result and #last_result.fail == 1 and last_result.fail[1]:find("Band 1", 1, true), last_result and last_result.fail[1])
        check("Anderer Inhalt: NICHT geloescht", read(LIB .. "/comics/Akira/Band 1.cbz") == "andere Datei")
        check("Anderer Inhalt: Drive unveraendert", server_state().uploads == 3)
        os.remove(LIB .. "/comics/Akira/Band 1.cbz")
        akira_download()
    end,
    function()
        -- Geaenderter Lesestand ersetzt den in Drive
        check(".sdr wieder aus der Sicherheitskopie", read(LIB .. "/comics/Akira/Band 1.sdr/metadata.cbz.lua") ~= nil)
        write(LIB .. "/comics/Akira/Band 1.sdr/metadata.cbz.lua", 'return { ["last_page"] = 9, ["summary"] = { ["status"] = "complete" } }')
        offload(LIB .. "/comics/Akira/Band 1.cbz")
    end,
    function()
        check("Geaenderte .sdr: ausgelagert", last_result and last_result.offloaded == 1, last_result and last_result.fail[1])
        check("Geaenderte .sdr: nur diese Datei neu", server_state().uploads == 4, server_state().uploads)
        check("Sicherheitskopie hat den neuen Stand", (read(ARCH .. "/metadata.cbz.lua") or ""):find("= 9", 1, true))
        os.execute("rm -rf '" .. ARCH .. "'")
        akira_download()
    end,
    function()
        local ds = DocSettings:open(LIB .. "/comics/Akira/Band 1.cbz")
        check("Ohne Sicherheitskopie: .sdr aus Drive", ds:readSetting("last_page") == 9, ds:readSetting("last_page"))
        check("Eigener Titel aus Drive", (read(LIB .. "/comics/Akira/Band 1.sdr/custom_metadata.lua") or ""):find("Akira 01", 1, true))
        check("Keine .part-Ordner", not exists(LIB .. "/comics/Akira/Band 1.sdr.part"))
        -- Vorhandene .sdr wird nie ersetzt
        os.remove(LIB .. "/comics/Akira/Band 1.cbz")
        os.execute("mkdir -p '" .. ARCH .. "'")
        write(ARCH .. "/metadata.cbz.lua", 'return { ["last_page"] = 1 }')
        akira_download()
    end,
    function()
        check("Vorhandene .sdr nicht ersetzt", (read(LIB .. "/comics/Akira/Band 1.sdr/metadata.cbz.lua") or ""):find("= 9", 1, true))
        os.execute("rm -rf '" .. ARCH .. "'")
        -- .sdr kommt beschaedigt in Drive an: Buch und .sdr bleiben
        write(LIB .. "/comics/Akira/Band 1.sdr/metadata.cbz.lua", 'return { ["last_page"] = 11, ["summary"] = { ["status"] = "complete" } }')
        mode("corrupt_upload=1")
        offload(LIB .. "/comics/Akira/Band 1.cbz")
    end,
    function()
        mode("corrupt_upload=0")
        check(".sdr-Fehler: gemeldet", last_result and #last_result.fail == 1 and last_result.offloaded == 0, last_result and last_result.offloaded)
        check(".sdr-Fehler: Buch bleibt", read(LIB .. "/comics/Akira/Band 1.cbz") == BIG)
        check(".sdr-Fehler: Lesedaten bleiben", (read(LIB .. "/comics/Akira/Band 1.sdr/metadata.cbz.lua") or ""):find("= 11", 1, true))
        check(".sdr-Fehler: verstaendliche Meldung", last_result and last_result.fail[1]:find(".sdr", 1, true), last_result and last_result.fail[1])

        -- Beschaedigt in Drive angekommen: NICHT loeschen
        mode("corrupt_upload=1")
        write(LIB .. "/comics/Kaputt.cbz", BIG)
        last_result = nil
        offload(LIB .. "/comics/Kaputt.cbz")
    end,
    function()
        mode("corrupt_upload=0")
        check("Beschaedigter Upload: Fehler gemeldet", last_result and #last_result.fail == 1, last_result and last_result.offloaded)
        check("Beschaedigter Upload: NICHT geloescht", read(LIB .. "/comics/Kaputt.cbz") == BIG)

        -- Verbindungsfehler mitten im Hochladen: geht weiter
        mode("fail_chunk=2")
        write(LIB .. "/comics/Abbruch.cbz", BIG)
        last_result = nil
        offload(LIB .. "/comics/Abbruch.cbz")
    end,
    function()
        check("Serverfehler mittendrin: macht weiter", last_result and last_result.offloaded == 1 and #last_result.fail == 0, last_result and last_result.fail[1])
        local root = Api.ensureFolder("root", "Kobo Bibliothek")
        local dir = Api.walk(root, { "comics" })
        local remote = Api.findChild(dir, "Abbruch.cbz")
        check("Danach vollstaendig in Drive", remote and tonumber(remote.size) == #BIG)

        -- Beschaedigter Download: nichts am Ziel
        mode("corrupt_download=1")
        last_result = nil
        Job.add({ { kind = "download", name = remote.name, dest = LIB .. "/comics/Abbruch.cbz",
            entry = { id = remote.id, size = remote.size, md5Checksum = remote.md5Checksum, name = remote.name } } })
    end,
    function()
        mode("corrupt_download=0")
        check("Beschaedigter Download: Fehler gemeldet", last_result and #last_result.fail == 1)
        check("Beschaedigter Download: nichts am Ziel", not exists(LIB .. "/comics/Abbruch.cbz"))
        check("Beschaedigter Download: keine Reste", not exists(LIB .. "/comics/Abbruch.cbz.part"))

        -- Vorhandene Datei wird nie ueberschrieben
        write(LIB .. "/comics/Abbruch.cbz", "lokal")
        local root = Api.ensureFolder("root", "Kobo Bibliothek")
        local remote = Api.findChild(Api.walk(root, { "comics" }), "Abbruch.cbz")
        last_result = nil
        Job.add({ { kind = "download", name = remote.name, dest = LIB .. "/comics/Abbruch.cbz",
            entry = { id = remote.id, size = remote.size, md5Checksum = remote.md5Checksum, name = remote.name } } })
    end,
    function()
        check("Vorhandene Datei nicht ueberschrieben", read(LIB .. "/comics/Abbruch.cbz") == "lokal")
        os.remove(LIB .. "/comics/Abbruch.cbz")

        -- Sonderzeichen im Namen
        write(LIB .. "/comics/Domu - A Child's Dream.cbz", "domu")
        last_result = nil
        offload(LIB .. "/comics/Domu - A Child's Dream.cbz")
    end,
    function()
        check("Name mit Apostroph hochgeladen", last_result and last_result.offloaded == 1, last_result and last_result.fail[1])
        local root = Api.ensureFolder("root", "Kobo Bibliothek")
        check("Name mit Apostroph wiedergefunden", Api.findChild(Api.walk(root, { "comics" }), "Domu - A Child's Dream.cbz") ~= nil)

        -- Abbrechen beim Hochladen
        mode("slow=0.3")
        write(LIB .. "/comics/Abbrechen.cbz", BIG)
        last_result = nil
        offload(LIB .. "/comics/Abbrechen.cbz")
        UIManager:scheduleIn(1.5, function()
            check("Status zeigt Fortschritt", Job.isRunning() and Job.statusText():find("/", 1, true) ~= nil, Job.statusText())
            Job.cancel()
        end)
    end,
    function()
        mode("slow=0")
        check("Abbrechen: gemeldet", last_result and last_result.cancelled)
        check("Abbrechen: Datei bleibt", read(LIB .. "/comics/Abbrechen.cbz") == BIG)
        check("Abbrechen: wach-bleiben aufgehoben", require("pluginshare").pause_auto_suspend ~= true)

        -- Auftrag fuer ein gerade offenes Buch loescht nicht
        local main = package.loaded["main"]
        local remove = plugin.removeBookFile
        check("Loesch-Funktion vorhanden", type(remove) == "function")
        check("Fehlende Datei: Loeschen meldet Fehler", remove(LIB .. "/gibtsnicht.cbz") == false)
    end,

    -- Cloud-Ansicht
    function()
        write(LIB .. "/comics/Serie/Band 2.cbz", "zwei")
        local root = Api.ensureFolder("root", "Kobo Bibliothek")
        local dir = Api.walk(root, { "comics", "Serie" }, true)
        for _, n in ipairs({ "Band 10.cbz", "Band 2.cbz", "Band 1.cbz" }) do
            if n ~= "Band 2.cbz" then
                write(LIB .. "/tmp_" .. n, n)
                Api.upload(LIB .. "/tmp_" .. n, dir, n)
                os.remove(LIB .. "/tmp_" .. n)
            else
                Api.upload(LIB .. "/comics/Serie/Band 2.cbz", dir, n)
            end
        end
        Api.createFolder(dir, "Unterordner")
        Api.createFolder(dir, "Band 1.sdr")
        Api.createFolder(dir, ".versteckt")
        local files = Api.list(dir)
        local folders, books = Browser.buildEntries(files, LIB .. "/comics/Serie", function(n) return plugin:isBook(n) end)
        check("Cloud-Ansicht: Ordner erkannt", #folders == 1 and folders[1].name == "Unterordner")
        check("Cloud-Ansicht: Zahlen richtig sortiert", books[1].name == "Band 1.cbz" and books[2].name == "Band 2.cbz" and books[3].name == "Band 10.cbz",
            books[1] and books[1].name)
        check("Cloud-Ansicht: auf dem Geraet erkannt", books[2].on_device == true and books[1].on_device == false)
        check("Groesse lesbar", Browser.sizeText(1536 * 1024 * 1024) == "1.5 GB" and Browser.sizeText(5 * 1024 * 1024) == "5 MB")
        check("Mac-Reste keine Buecher", not plugin:isBook("._Band.cbz") and plugin:isBook("Band.CBZ") and not plugin:isBook("x.txt"))
        local parts, name = plugin:relParts(LIB .. "/comics/Akira/Band 1.cbz")
        check("Pfad zerlegt", parts and parts[1] == "comics" and parts[2] == "Akira" and name == "Band 1.cbz")
        check("Ausserhalb der Bibliothek abgelehnt", plugin:relParts("/mnt/anderswo/x.cbz") == nil)
        local listed = plugin:booksIn(LIB .. "/comics/Serie")
        check("Ordner auslagern findet die Buecher", #listed == 1, #listed)

        local info = Browser.localInfo(LIB .. "/comics/Akira/Band 1.cbz")
        check("Cloud-Ansicht: eigener Titel aus der .sdr", info.title == "Akira 01", info.title)
        check("Cloud-Ansicht: gelesen aus der .sdr", info.status == "complete", info.status)
        -- Ausgelagert: Titel und gelesen aus der Sicherheitskopie
        local arch = Sdr.archivePath(DataStorage:getDataDir(), { "comics", "Serie" }, "Band 1.cbz")
        os.execute("mkdir -p '" .. arch .. "'")
        write(arch .. "/custom_metadata.lua", 'return { ["custom_props"] = { ["title"] = "Serie 01" } }')
        write(arch .. "/metadata.cbz.lua", 'return { ["summary"] = { ["status"] = "complete" } }')
        local _, books2 = Browser.buildEntries(files, LIB .. "/comics/Serie", function(n) return plugin:isBook(n) end,
            function(n) return Sdr.archivePath(DataStorage:getDataDir(), { "comics", "Serie" }, n) end)
        check("Cloud-Ansicht: Titel aus der Sicherheitskopie", books2[1].display == "Serie 01", books2[1].display)
        check("Cloud-Ansicht: gelesen aus der Sicherheitskopie", books2[1].read == true)
    end,
    function()
        local root = Api.ensureFolder("root", "Kobo Bibliothek")
        local b = Browser.show(plugin, root, "Kobo Bibliothek")
        check("Cloud-Ansicht geoeffnet", b.menu and UIManager:isWidgetShown(b.menu))
        local item
        for _, it in ipairs(b.menu.item_table) do if it.text == "comics" then item = it end end
        check("Ordner angezeigt", item ~= nil)
        b.menu:onMenuSelect(item)
        check("Cloud-Ansicht bleibt nach Antippen offen", UIManager:isWidgetShown(b.menu))
        check("In Unterordner gewechselt", #b.stack == 2 and b:localDir() == LIB .. "/comics", b:localDir())
        local serie
        for _, it in ipairs(b.menu.item_table) do if it.text == "Serie" then serie = it end end
        b.menu:onMenuSelect(serie)
        check("Lokaler Ordner folgt der Cloud", b:localDir() == LIB .. "/comics/Serie")
        check("Anzahl fehlender Baende angeboten", (b.menu.item_table[1].text or ""):find("2", 1, true) ~= nil, b.menu.item_table[1].text)
        check("Zurueck-Pfeil verfuegbar", #b.menu.paths == 2)
        -- Auswahl-Modus
        local function item_of(name)
            for _, it in ipairs(b.menu.item_table) do if it.entry and it.entry.name == name then return it end end
        end
        b.menu:onLeftButtonTap()
        check("Auswahl: Modus an", b.selecting == true)
        check("Auswahl: Hinweis oben", (b.menu.item_table[1].text or ""):find("antippen", 1, true) ~= nil, b.menu.item_table[1].text)
        b.menu:onMenuSelect(item_of("Band 10.cbz"))
        check("Auswahl: Antippen hakt an statt zu laden", #b.sel_order == 1 and not Job.child and #Job.queue == 0)
        check("Auswahl: Haekchen sichtbar", item_of("Band 10.cbz").text:sub(1, 3) == "☑", item_of("Band 10.cbz").text)
        b.menu:onMenuSelect(item_of("Band 2.cbz"))
        check("Auswahl: Buch auf dem Geraet nicht anhakbar", #b.sel_order == 1)
        b.menu:onMenuSelect(item_of("Band 10.cbz"))
        check("Auswahl: zweites Antippen hakt ab", #b.sel_order == 0)
        b.menu:onMenuSelect(item_of("Band 1.cbz"))
        b:onHold(item_of("Band 10.cbz"))
        check("Auswahl: lang druecken hakt bis dort an", #b.sel_order == 2, #b.sel_order)
        check("Auswahl: Anzeige oben", (b.menu.item_table[1].text or ""):find("(2)", 1, true) ~= nil, b.menu.item_table[1].text)
        check("Auswahl: Ansicht bleibt offen", UIManager:isWidgetShown(b.menu))
        -- Laden: Auftraege in Reihenfolge, ohne Oeffnen-Frage pro Buch
        local got
        local orig = plugin.startJobs
        plugin.startJobs = function(_, tasks) got = tasks end
        b:downloadSelected()
        plugin.startJobs = orig
        check("Auswahl: zwei Auftraege", got and #got == 2)
        check("Auswahl: Reihenfolge wie angehakt", got and got[1].name == "Band 1.cbz" and got[2].name == "Band 10.cbz")
        check("Auswahl: Ziel im lokalen Ordner", got and got[1].dest == LIB .. "/comics/Serie/Band 1.cbz", got and got[1].dest)
        check("Auswahl: kein Oeffnen pro Buch", got and not got[1].open_after and not got[2].open_after)
        check("Auswahl: danach zurueckgesetzt", not b.selecting and #b.sel_order == 0)
        -- Auswahl bleibt beim Ordnerwechsel; fuer das Bildschirmfoto eine Auswahl stehen lassen
        b.menu:onLeftButtonTap()
        b.menu:onMenuSelect(item_of("Band 1.cbz"))
        b:goBack()
        b.menu:onMenuSelect((function()
            for _, it in ipairs(b.menu.item_table) do if it.text == "Serie" then return it end end
        end)())
        check("Auswahl: bleibt beim Ordnerwechsel", #b.sel_order == 1 and item_of("Band 1.cbz").text:sub(1, 3) == "☑")
        -- Menue-Position im Werkzeuge-Menue
        local tools = require("ui/elements/filemanager_menu_order").tools
        local pos_d, pos_top = util.arrayContains(tools, "drivelibrary"), 0
        for i, k in ipairs(tools) do
            if k == "story_recall" or k == "guitar_tab_reader" or k == "comicdisplay" then pos_top = i end
        end
        check("Menue: weit oben in Werkzeuge", pos_d and pos_d == pos_top + 1, tostring(pos_d) .. " nach " .. pos_top)
        UIManager:setDirty(nil, "full")
    end,
    function()
        -- Bildschirmfoto der Cloud-Ansicht (Ordner Serie), Zeit zum Zeichnen lassen
        UIManager:forceRePaint()
        os.execute("DISPLAY=:99 kor shot gdl_cloud >/dev/null 2>&1")
        local b = Browser.current
        b.menu:onReturn()
        check("Zurueck funktioniert", #b.stack == 2)
        UIManager:close(b.menu)
        Browser.current = nil
    end,
    function()
        -- Menue und Anfragen vor dem Loeschen
        local items = {}
        plugin:addToMainMenu(items)
        local sub = items.drivelibrary.sub_item_table
        check("Menue vorhanden", #sub >= 5)
        check("Letzter Eintrag ist die Anleitung", sub[#sub].text == "Wie funktioniert das?" or sub[#sub].text == "How does it work?", sub[#sub].text)
        check("Statuszeile oben", sub[1].gdl_status == true and sub[1].enabled_func() == false)
        check("Auswahl-Eintrag ohne Auswahl aus", sub[3].enabled_func() == false)

        local FileManager = require("apps/filemanager/filemanager")
        local fm = FileManager.instance
        fm.selected_files = { [LIB .. "/comics/Kaputt.cbz"] = true, [LIB .. "/comics/x.txt"] = true }
        check("Auswahl: nur Buecher", #plugin:selectedBooks() == 1)
        check("Auswahl-Eintrag jetzt aktiv", sub[3].enabled_func() == true and sub[3].text_func():find("1", 1, true) ~= nil)
        plugin:offloadSelected()
        local box = plugin.offload_box
        check("Vor dem Loeschen wird gefragt", box ~= nil and box.tasks and #box.tasks == 1)
        UIManager:close(box)
        fm.selected_files = nil
        check("Kaputt.cbz weiter da (nur gefragt)", exists(LIB .. "/comics/Kaputt.cbz"))

        local ReaderUI = require("apps/reader/readerui")
        local saved = ReaderUI.instance
        ReaderUI.instance = { document = { file = LIB .. "/comics/Kaputt.cbz" } }
        check("Offenes Buch wird nicht geloescht", plugin.removeBookFile(LIB .. "/comics/Kaputt.cbz") == false and exists(LIB .. "/comics/Kaputt.cbz"))
        plugin.offload_box = nil
        plugin:confirmOffload({ LIB .. "/comics/Kaputt.cbz" })
        check("Offenes Buch: keine Rueckfrage zum Loeschen", plugin.offload_box == nil)
        ReaderUI.instance = saved

        check("Fehlertext ohne Zugangsdaten", not plugin:errorText("network"):find("good-refresh", 1, true))
        local log_text = read("/work/koreader.log") or ""
        check("Keine Zugangsdaten im Log", #log_text > 0 and not log_text:find("good-refresh", 1, true) and not log_text:find("Bearer", 1, true) and not log_text:find("tok1", 1, true))
    end,

    -- 0.4: naechsten Band vorladen (ab 85 %, still)
    function()
        local s = G_reader_settings:readSetting("drivelibrary")
        s.prefetch_next = true
        getmetatable(plugin).force_online = true
        FAKE = setmetatable({ ui = { document = { file = LIB .. "/comics/Serie/Band 2.cbz", getPageCount = function() return 100 end } } }, { __index = plugin })
        last_result = nil
        FAKE:onPageUpdate(50)
        check("Vorladen: bei 50 % noch nichts", not Job.isRunning() and last_result == nil)
        FAKE:onPageUpdate(90)
        check("Vorladen: ab 85 % gestartet", Job.isRunning() or last_result ~= nil)
    end,
    function()
        check("Vorladen: leiser Auftrag", last_result and last_result.quiet == true)
        check("Vorladen: naechster Band nach natuerlicher Sortierung (2 -> 10)", last_result and last_result.prefetched == "Band 10.cbz", last_result and last_result.prefetched)
        check("Vorladen: Datei da", exists(LIB .. "/comics/Serie/Band 10.cbz") and not exists(LIB .. "/comics/Serie/Band 10.cbz.part"))
        last_result = nil
        FAKE:onPageUpdate(95)
        check("Vorladen: nur einmal pro Buch", not Job.isRunning() and last_result == nil)
        -- Naechster Band liegt schon da: ohne Netz erkannt, kein Auftrag
        getmetatable(plugin).force_online = false
        local again = setmetatable({ ui = { document = { file = LIB .. "/comics/Serie/Band 2.cbz", getPageCount = function() return 100 end } } }, { __index = plugin })
        check("Vorladen: naechster Band lokal erkannt", plugin:nextIsLocal(LIB .. "/comics/Serie/Band 2.cbz", { "comics", "Serie" }, "Band 2.cbz") == true)
        again:onPageUpdate(90)
        check("Vorladen: lokal vorhanden -> kein Auftrag, kein Netz", not Job.isRunning() and last_result == nil and again.prefetch_done == true and again.prefetch_retry == nil)
        check("Vorladen: letzter Band hat lokal keinen Nachfolger", plugin:nextIsLocal(LIB .. "/comics/Serie/Band 10.cbz", { "comics", "Serie" }, "Band 10.cbz") == false)
        getmetatable(plugin).force_online = true
        -- letzter Band: kein Nachfolger
        local last = setmetatable({ ui = { document = { file = LIB .. "/comics/Serie/Band 10.cbz", getPageCount = function() return 10 end } } }, { __index = plugin })
        last:onPageUpdate(10)
    end,
    function()
        check("Vorladen: letzter Band ohne Nachfolger, kein Fehler", last_result and #last_result.fail == 0 and not last_result.prefetched)
        -- 0.5.2: WLAN kommt nicht zustande -> nach 2 Minuten neuer Versuch, hoechstens 3 pro Buch
        getmetatable(plugin).force_online = false
        local r = setmetatable({ ui = { document = { file = LIB .. "/comics/Serie/Band 10.cbz", getPageCount = function() return 10 end } } }, { __index = plugin })
        r:onPageUpdate(10)
        local t1 = r.prefetch_tries
        r:onPageUpdate(10)
        local t2 = r.prefetch_tries
        r.prefetch_retry = 0; r:onPageUpdate(10)
        local t3 = r.prefetch_tries
        r.prefetch_retry = 0; r:onPageUpdate(10)
        r.prefetch_retry = 0; r:onPageUpdate(10)
        check("Vorladen: ohne WLAN spaeter neuer Versuch, hoechstens 3", t1 == 1 and t2 == 1 and t3 == 2 and r.prefetch_tries == 3,
            tostring(t1) .. "/" .. tostring(t2) .. "/" .. tostring(t3) .. "/" .. tostring(r.prefetch_tries))
        check("Vorladen: dabei kein Auftrag", not Job.isRunning())
        getmetatable(plugin).prefetch_pending = nil
        getmetatable(plugin).force_online = true
        -- Lesestand sichern (ohne Loeschen)
        write(LIB .. "/comics/Serie/Band 2.sdr/metadata.cbz.lua", 'return { ["last_page"] = 7 }')
        last_result = nil
        Job.add({ { kind = "syncsdr", quiet = true, file = LIB .. "/comics/Serie/Band 2.cbz", rel = { "comics", "Serie" },
            name = "Band 2.cbz", root_name = "Kobo Bibliothek", sdr = LIB .. "/comics/Serie/Band 2.sdr" } })
    end,
    function()
        local root = Api.ensureFolder("root", "Kobo Bibliothek")
        local dir = Api.walk(root, { "comics", "Serie" })
        local sdr = Api.findChild(dir, "Band 2.sdr")
        local files = sdr and Api.list(sdr.id) or {}
        check("Lesestand gesichert: .sdr in Drive", #files == 1 and files[1].name == "metadata.cbz.lua", #files)
        check("Lesestand gesichert: Buch und .sdr bleiben auf dem Geraet", exists(LIB .. "/comics/Serie/Band 2.cbz") and exists(LIB .. "/comics/Serie/Band 2.sdr"))
        -- Automatisch auslagern nach dem Schliessen (gelesen)
        local s = G_reader_settings:readSetting("drivelibrary")
        s.auto_offload = true
        local closing = setmetatable({ ui = { document = { file = LIB .. "/comics/Serie/Band 10.cbz" },
            doc_settings = { readSetting = function(_, k) if k == "summary" then return { status = "complete" } end end } } }, { __index = plugin })
        last_result = nil
        closing:onCloseDocument()
        check("Auto-Auslagern: nicht sofort (erst nach dem Schliessen)", exists(LIB .. "/comics/Serie/Band 10.cbz") and not Job.isRunning())
        os.execute("sleep 4")
    end,
    function()
        check("Auto-Auslagern: leise ausgelagert", last_result and last_result.quiet == true and last_result.offloaded == 1, last_result and last_result.offloaded)
        check("Auto-Auslagern: Datei vom Geraet", not exists(LIB .. "/comics/Serie/Band 10.cbz"))
        -- Nicht gelesen: bleibt
        write(LIB .. "/comics/Serie/Band 11.cbz", "elf")
        local open = setmetatable({ ui = { document = { file = LIB .. "/comics/Serie/Band 11.cbz" },
            doc_settings = { readSetting = function() return { status = "reading" } end } } }, { __index = plugin })
        last_result = nil
        open:onCloseDocument()
        os.execute("sleep 4")
    end,
    function()
        check("Auto-Auslagern: ungelesenes Buch bleibt", exists(LIB .. "/comics/Serie/Band 11.cbz") and (last_result == nil or last_result.offloaded == 0))
        local s = G_reader_settings:readSetting("drivelibrary")
        s.auto_offload, s.prefetch_next = nil, nil
        os.remove(LIB .. "/comics/Serie/Band 11.cbz") -- nur lokal, nicht in Drive
        check("Markierung: ausgelagerter Band ohne Lesedaten bekannt", lfs.attributes(Sdr.archivePath(DataStorage:getDataDir(), { "comics", "Serie" }, "Band 10.cbz"), "mode") == "directory")
        -- 2 Baende vorladen: von Band 1 aus folgen Band 2 (liegt da) und Band 10 (ausgelagert)
        s.prefetch_next, s.prefetch_count = true, 2
        check("2 Baende: nicht alles lokal -> Drive fragen", plugin:nextIsLocal(LIB .. "/comics/Serie/Band 1.cbz", { "comics", "Serie" }, "Band 1.cbz", 2) == false)
        local two = setmetatable({ ui = { document = { file = LIB .. "/comics/Serie/Band 1.cbz", getPageCount = function() return 100 end } } }, { __index = plugin })
        last_result = nil
        two:onPageUpdate(90)
    end,
    function()
        check("2 Baende: vorhandener uebersprungen, fehlender geladen", last_result and last_result.prefetched_all
            and #last_result.prefetched_all == 1 and last_result.prefetched_all[1] == "Band 10.cbz", last_result and last_result.prefetched_all and #last_result.prefetched_all)
        check("2 Baende: Band 10 wieder da", exists(LIB .. "/comics/Serie/Band 10.cbz"))
        check("2 Baende: Markierung nach dem Laden weg, keine leere .sdr", lfs.attributes(Sdr.archivePath(DataStorage:getDataDir(), { "comics", "Serie" }, "Band 10.cbz"), "mode") == nil)
        -- Ende der Reihe: hinter Band 10 nichts mehr, trotzdem kein Fehler
        local tail = setmetatable({ ui = { document = { file = LIB .. "/comics/Serie/Band 10.cbz", getPageCount = function() return 10 end } } }, { __index = plugin })
        last_result = nil
        tail:onPageUpdate(10)
    end,
    function()
        check("2 Baende am Reihenende: kein Fehler, nichts geladen", last_result and #last_result.fail == 0 and not last_result.prefetched)
        -- Keine Hilfsdateien direkt in cache/ (KOReaders Seiten-Zwischenspeicher stuerzt sonst beim Schliessen ab)
        local stray = {}
        for f in lfs.dir(DataStorage:getDataDir() .. "/cache") do
            if f:find("drivelibrary", 1, true) and lfs.attributes(DataStorage:getDataDir() .. "/cache/" .. f, "mode") == "file" then stray[#stray + 1] = f end
        end
        check("Keine Hilfsdateien direkt in cache/", #stray == 0, table.concat(stray, ", "))
        local s = G_reader_settings:readSetting("drivelibrary")
        s.prefetch_next, s.prefetch_count = nil, nil
    end,
}

UIManager:scheduleIn(0.5, run_steps)
