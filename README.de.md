# Drive-Bibliothek für KOReader

*English: [README.md](README.md)*

<!-- byline -->
Ein Plugin von **Akrota und Claude**.

<!-- lang-note -->
*Funktioniert auf **Deutsch und Englisch**: Menüs und Texte richten sich nach der KOReader-Sprache.*

Google Drive als Cloud-Bibliothek: Bücher und Comics vom Gerät auslagern und bei Bedarf wieder herunterladen. Lesestand und eigene Angaben bleiben erhalten.

## Bildschirmfotos

*Die Bildschirmfotos zeigen die englische Oberfläche; in einem deutschen KOReader sind die Texte deutsch.*

<table>
<tr><td align="center" valign="top" width="33%"><img src="docs/screenshots/menu.png" width="260" alt="Menü der Drive-Bibliothek"><br><sub>Menü der Drive-Bibliothek</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/not-signed-in.png" width="260" alt="Meldung, solange die Anmeldung fehlt"><br><sub>Meldung, solange die Anmeldung fehlt</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/how-it-works.png" width="260" alt="Hilfetext zu Herunterladen, Auslagern und Hintergrund-Aufträgen"><br><sub>Hilfetext zu Herunterladen, Auslagern und Hintergrund-Aufträgen</sub></td></tr>
<tr><td align="center" valign="top" width="33%"><img src="docs/screenshots/cloud-library.png" width="260" alt="Cloud-Bibliothek: der Drive-Ordner"><br><sub>Cloud-Bibliothek: der Drive-Ordner</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/cloud-folder.png" width="260" alt="Eine Reihe: auf dem Gerät (Haken) oder nur in der Cloud (Wolke)"><br><sub>Eine Reihe: auf dem Gerät (Haken) oder nur in der Cloud (Wolke)</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/cloud-select.png" width="260" alt="Auswahl-Modus: Ausgewählte herunterladen"><br><sub>Auswahl-Modus: Ausgewählte herunterladen</sub></td></tr>
<tr><td align="center" valign="top" width="33%"><img src="docs/screenshots/offload-confirm.png" width="260" alt="Rückfrage vor dem Auslagern eines Buchs"><br><sub>Rückfrage vor dem Auslagern eines Buchs</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/progress.png" width="260" alt="Statuszeile beim Hochladen"><br><sub>Statuszeile beim Hochladen</sub></td><td align="center" valign="top" width="33%"><img src="docs/screenshots/settings.png" width="260" alt="Einstellungen"><br><sub>Einstellungen</sub></td></tr>
<tr><td align="center" valign="top" width="33%"><img src="docs/screenshots/preload-menu.png" width="260" alt="Nächsten Band vorladen: aus, 1, 2"><br><sub>Nächsten Band vorladen: aus, 1, 2</sub></td></tr>
</table>

## Was es macht

- **In Cloud auslagern:** Lang auf ein Buch oder einen Ordner drücken. Das Plugin lädt die Datei hoch, falls sie noch fehlt, vergleicht die Prüfsumme und löscht sie erst danach vom Gerät.
- **Cloud-Bibliothek:** Werkzeuge → Drive-Bibliothek. Zeigt den Drive-Ordner und bei jedem Buch, ob es nur in der Cloud (☁) oder auch auf dem Gerät (✓) liegt. Antippen lädt es herunter oder öffnet es.
- **Mehrere auf einmal:** Im Auswahl-Modus Bücher markieren, dann Werkzeuge → Drive-Bibliothek → „Ausgewählte auslagern“ oder die Geste dafür.
- **Optional:** Nach dem Schließen eines fertig gelesenen Buchs fragen, ob es ausgelagert werden soll.

Der Ordner in Drive heißt standardmäßig `Kobo Bibliothek`. Seine Unterordner entsprechen denen der lokalen Bibliothek. Lädst du am PC selbst hoch, nimm dieselben Ordnernamen, dann erkennt das Plugin die Dateien und lädt sie nicht doppelt hoch.

## Installation

1. ZIP aus den [Releases](../../releases) laden und entpacken, oder das Projekt herunterladen.
2. Den Ordner **`drivelibrary.koplugin`** nach `koreader/plugins/` kopieren (Kobo: `.adds/koreader/plugins/`).
3. KOReader neu starten und die Einrichtung unten durchgehen.

## Wichtig zu wissen

- **Der `.sdr`-Ordner (Lesestand, eigene Titel, Notizen) geht beim Auslagern mit nach Drive** und bleibt zusätzlich als Sicherheitskopie in `.adds/koreader/drivelibrary/sdr/`. In der Bibliothek bleibt nichts zurück, leere Ordner verschwinden. Beim Herunterladen kommt die `.sdr` zurück; eine vorhandene `.sdr` wird nie überschrieben.
- **Ausgelagerte Bücher fehlen in Bibliothek und Reihen**, bis du sie wieder herunterlädst.
- **Es wird nie etwas überschrieben.** Liegt in Drive eine andere Datei mit demselben Namen, bleibt die lokale Datei liegen und du bekommst eine Meldung.
- **Das Plugin braucht vollen Zugriff auf dein Drive**, sonst sieht es keine Dateien, die du im Browser hochlädst. Es arbeitet nur im gewählten Ordner, das stellt aber nur der Code des Plugins sicher, nicht Google. Geht das Gerät verloren: Zugriff unter myaccount.google.com/permissions entziehen.

## Einrichtung (einmalig)

Jeder braucht ein eigenes kleines Google-Cloud-Projekt. Das ist kostenlos.

1. **Projekt anlegen:** console.cloud.google.com → neues Projekt, z. B. „Kobo Drive“.
2. **API einschalten:** „APIs & Dienste“ → Bibliothek → „Google Drive API“ → Aktivieren.
3. **Zustimmungsbildschirm:** Zielgruppe „Extern“, App-Name und E-Mail eintragen, dann **„App veröffentlichen“ / „In Produktion“**. Im Status „Test“ läuft die Anmeldung nach 7 Tagen ab. Eine Prüfung durch Google ist für den eigenen Gebrauch nicht nötig.
4. **Zugangsdaten:** „Anmeldedaten“ → OAuth-Client-ID → Typ „Webanwendung“. Als autorisierte Weiterleitungs-URI eintragen: `https://developers.google.com/oauthplayground`. Die JSON-Datei herunterladen und `client_id.json` nennen.
5. **Zugang holen:** developers.google.com/oauthplayground öffnen. Oben rechts das Zahnrad → „Use your own OAuth credentials“ → Client-ID und Secret eintragen. Links `https://www.googleapis.com/auth/drive` eintragen, „Authorize APIs“, mit deinem Konto anmelden und die Warnung „Google hat diese App nicht überprüft“ bestätigen (es ist deine eigene App). Dann „Exchange authorization code for tokens“. Den **Refresh token** in eine Textdatei `refresh_token.txt` kopieren.
6. **Auf den Kobo:** Beide Dateien nach `.adds/koreader/drivelibrary/` legen (den Ordner anlegen). **Nicht** in den Plugin-Ordner.
7. **Prüfen:** Werkzeuge → Drive-Bibliothek → Einstellungen → „Anmeldung prüfen“. Der Ordner `Kobo Bibliothek` wird dabei in Drive angelegt, falls er fehlt.

Wird der Zugang länger als 6 Monate nicht benutzt, läuft er ab. Dann Schritt 5 wiederholen und `refresh_token.txt` ersetzen.

## Sicherheit

Die Verbindung zu Google läuft mit geprüftem Zertifikat. `client_id.json` und `refresh_token.txt` sind wie Passwörter: nicht teilen, nicht veröffentlichen.

## Danksagung

Die Idee, den Zugang über den OAuth Playground zu holen, stammt aus [gdrive.koplugin](https://github.com/moohaad/gdrive.koplugin) von moohaad (MIT). Code wurde nicht übernommen.

## Getestet auf

Kobo Libra Colour mit KOReader 2026.07.1 und ZenOS. Die automatischen Tests laufen gegen ein nachgebautes Drive (`tests/fake_drive.py`), dazu wurde alles mit einem echten Drive-Konto von Hand geprüft.

## Wer das gemacht hat

Der Code wurde vollständig von **Claude** geschrieben, einer KI von Anthropic (in Claude Code). Der Besitzer dieses Projekts hatte die Idee, hat das Plugin auf dem Kobo getestet und Rückmeldungen gegeben, aber keinen Code geschrieben.

Es gibt keine Gewährleistung und keinen festen Support. Fehlermeldungen gern als [Issue](../../issues), bitte mit der `crash.log` aus dem KOReader-Ordner. **Vorsicht:** Das Plugin löscht Dateien vom Gerät (erst nach bestandener Prüfsumme). Probiere es zuerst mit Büchern, die du ersetzen kannst.

## Weitere Plugins von Akrota und Claude

- [Comic Display](https://github.com/Akrota/koreader-comic-display): Refresh gegen Ghosting, dunkle Ränder und Uhr für Comics
- [Levels / Tonwerte](https://github.com/Akrota/koreader-comic-levels): Tonwertkurve für Comics
- [Comic Panel Zoom](https://github.com/Akrota/koreader-comic-panel-zoom): Panel-für-Panel-Ansicht (Fork von JorgeTheFox)
- [Comic Dual Page](https://github.com/Akrota/koreader-comic-dual-page): Doppelseiten mit Erkennung (Fork von KORComic)
- [CBZ Converter](https://github.com/Akrota/koreader-cbz-converter): Comics, PDF und EPUB auf dem Gerät in CBZ umwandeln
- [Folder to series](https://github.com/Akrota/koreader-folder-to-series): Comic-Ordner zu Reihen mit Bandnummern
- [Story Recall](https://github.com/Akrota/koreader-story-recall): Spoilerfreier KI-Rückblick auf Bücher
- [Guitar Tab Reader](https://github.com/Akrota/koreader-guitar-tab-reader): Gitarren-Tabs und Chords für E-Ink
- [Wi-Fi while charging](https://github.com/Akrota/koreader-wifi-while-charging): WLAN anlassen, solange das Gerät lädt
- [Zen page browser gesture](https://github.com/Akrota/koreader-zen-page-browser-gesture): Geste für den ZenOS-Seitenbrowser

## Lizenz

[MIT](LICENSE)
