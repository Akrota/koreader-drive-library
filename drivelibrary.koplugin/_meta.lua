local ok, lang = pcall(function() return G_reader_settings:readSetting("language") end)
local de = ok and type(lang) == "string" and lang:sub(1, 2):lower() == "de"
return {
    fullname = de and "Drive-Bibliothek" or "Drive Library",
    description = de
        and "Google Drive als Cloud-Bibliothek: Bücher und Comics hochladen, erst nach bestandener Prüfung vom Gerät entfernen und bei Bedarf wieder herunterladen. Lesestand und eigene Angaben bleiben."
        or "Google Drive as a cloud library: upload books and comics, remove them from the device only after a passed check, and download them again when needed. Reading progress and your own metadata stay.",
    version = "0.5.4",
}
