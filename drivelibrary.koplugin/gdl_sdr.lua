-- Drive-Bibliothek: Lesedaten (.sdr) mitnehmen.
-- Beim Auslagern gehen Buch und .sdr nach Drive. Die .sdr verschwindet aus der Bibliothek, bleibt aber als
-- Sicherheitskopie im Plugin-Ordner (drivelibrary/sdr/...), damit der Lesestand doppelt vorhanden ist.
-- Beim Herunterladen kommt sie zuerst aus dieser Kopie, sonst aus Drive. Eine vorhandene .sdr wird nie ersetzt.
local DocSettings = require("docsettings")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")

local Sdr = {}

--- Name des .sdr-Ordners in Drive (immer neben dem Buch, wie in KOReaders Standard-Einstellung)
function Sdr.driveName(book_name)
    return (book_name:match("^(.*)%.[^.]+$") or book_name) .. ".sdr"
end

--- .sdr auf dem Geraet (folgt KOReaders Einstellung, wo Lesedaten liegen)
function Sdr.localDir(book_path)
    local ok, dir = pcall(DocSettings.getSidecarDir, DocSettings, book_path)
    if ok and dir and dir ~= "" then return dir end
    return (book_path:match("^(.*)%.[^.]+$") or book_path) .. ".sdr"
end

function Sdr.archiveRoot(data_dir)
    return data_dir .. "/drivelibrary/sdr"
end

--- Sicherheitskopie: gleiche Ordner wie in der Bibliothek, unter drivelibrary/sdr
-- @param rel Ordnerteile relativ zur Bibliothek, @param book_name Dateiname des Buchs
function Sdr.archivePath(data_dir, rel, book_name)
    local parts = { Sdr.archiveRoot(data_dir) }
    for _, p in ipairs(rel or {}) do parts[#parts + 1] = p end
    parts[#parts + 1] = Sdr.driveName(book_name)
    return table.concat(parts, "/")
end

function Sdr.isDir(path)
    return path and lfs.attributes(path, "mode") == "directory"
end

--- Hat der Ordner Dateien (auch in Unterordnern)?
function Sdr.hasFiles(dir)
    if not Sdr.isDir(dir) then return false end
    for e in lfs.dir(dir) do
        if e ~= "." and e ~= ".." then
            local p = dir .. "/" .. e
            local mode = lfs.attributes(p, "mode")
            if mode == "file" or (mode == "directory" and Sdr.hasFiles(p)) then return true end
        end
    end
    return false
end

local function copy_file(from, to)
    local src = io.open(from, "rb")
    if not src then return false end
    local dst = io.open(to, "wb")
    if not dst then src:close(); return false end
    local ok = true
    while true do
        local chunk = src:read(256 * 1024)
        if not chunk then break end
        if not dst:write(chunk) then ok = false; break end
    end
    src:close()
    if not dst:close() then ok = false end
    return ok and lfs.attributes(from, "size") == lfs.attributes(to, "size")
end

local function copy_tree(src, dst)
    util.makePath(dst)
    for e in lfs.dir(src) do
        if e ~= "." and e ~= ".." then
            local s, d = src .. "/" .. e, dst .. "/" .. e
            local mode = lfs.attributes(s, "mode")
            if mode == "directory" then
                if not copy_tree(s, d) then return false end
            elseif mode == "file" then
                if not copy_file(s, d) then return false end
            end
        end
    end
    return true
end

--- Ordner vollstaendig kopieren. Das Ziel entsteht erst, wenn alles kopiert ist; ein vorhandenes Ziel
--- wird nur ersetzt, wenn replace gesetzt ist. @return true oder false
function Sdr.copyDir(src, dst, replace)
    if not Sdr.isDir(src) then return false end
    if Sdr.isDir(dst) and not replace then return false end
    local tmp = dst .. ".part"
    if Sdr.isDir(tmp) then ffiutil.purgeDir(tmp) end
    if not copy_tree(src, tmp) then
        ffiutil.purgeDir(tmp)
        return false
    end
    if Sdr.isDir(dst) then ffiutil.purgeDir(dst) end
    local ok = os.rename(tmp, dst)
    if not ok then ffiutil.purgeDir(tmp) end
    return ok and true or false
end

function Sdr.remove(dir)
    if Sdr.isDir(dir) then ffiutil.purgeDir(dir) end
    return not Sdr.isDir(dir)
end

local function is_empty(dir)
    for e in lfs.dir(dir) do
        if e ~= "." and e ~= ".." then return false end
    end
    return true
end

--- Leere Ordner von dir aufwaerts loeschen, hoechstens bis unter stop (stop selbst bleibt).
function Sdr.removeEmptyParents(dir, stop)
    stop = stop and stop:gsub("/+$", "")
    while dir and stop and dir ~= stop and dir:sub(1, #stop + 1) == stop .. "/" do
        if not Sdr.isDir(dir) or not is_empty(dir) then return end
        if not lfs.rmdir(dir) then return end
        dir = dir:match("^(.*)/[^/]+$")
    end
end

return Sdr
