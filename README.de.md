# Drive-Bibliothek für KOReader

*English: [README.md](README.md)*

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

Deine **lokale Bibliothek** ist dein KOReader-Home-Ordner, also der Ordner, in dem deine Bücher liegen. Unter Einstellungen → „Lokale Bibliothek“ kannst du einen anderen wählen.

Der Ordner in Drive heißt standardmäßig `KOReader Library`. Seine Unterordner entsprechen denen der lokalen Bibliothek. Lädst du am PC selbst hoch, nimm dieselben Ordnernamen, dann erkennt das Plugin die Dateien und lädt sie nicht doppelt hoch.

## Installation

1. ZIP aus den [Releases](../../releases) laden und entpacken, oder das Projekt herunterladen.
2. Den Ordner **`drivelibrary.koplugin`** nach `koreader/plugins/` kopieren (auf dem Kobo zum Beispiel `.adds/koreader/plugins/`).
3. KOReader neu starten und die Einrichtung unten durchgehen.

## Wichtig zu wissen

- **Der `.sdr`-Ordner (Lesestand, eigene Titel, Notizen) geht beim Auslagern mit nach Drive** und bleibt zusätzlich als Sicherheitskopie in `.adds/koreader/drivelibrary/sdr/`. In der Bibliothek bleibt nichts zurück, leere Ordner verschwinden. Beim Herunterladen kommt die `.sdr` zurück; eine vorhandene `.sdr` wird nie überschrieben.
- **Ausgelagerte Bücher fehlen in Bibliothek und Reihen**, bis du sie wieder herunterlädst.
- **Es wird nie etwas überschrieben.** Liegt in Drive eine andere Datei mit demselben Namen, bleibt die lokale Datei liegen und du bekommst eine Meldung.
- **Das Plugin braucht vollen Zugriff auf dein Drive**, sonst sieht es keine Dateien, die du im Browser hochlädst. Es arbeitet nur im gewählten Ordner, das stellt aber nur der Code des Plugins sicher, nicht Google. Geht das Gerät verloren: Zugriff unter myaccount.google.com/permissions entziehen.

## Einrichtung (einmalig)

Das machst du nur einmal, am Computer, in etwa 10 bis 15 Minuten. Am Ende kopierst du **zwei kleine Dateien** auf den E-Reader. Klappe die drei Teile nacheinander auf:

| Teil | Du bekommst |
| --- | --- |
| 1. Eigenes Google-Projekt anlegen | `client_id.json` |
| 2. Zugriff auf dein Drive erlauben | `refresh_token.txt` |
| 3. Beide Dateien auf den E-Reader kopieren | fertig |

Alles ist kostenlos. Das Projekt gehört dir, also bekommt niemand sonst Zugriff auf dein Drive.

<details>
<summary><b>Teil 1: Google-Projekt anlegen</b> (du bekommst <code>client_id.json</code>)</summary>

Melde dich mit dem Google-Konto an, dessen Drive du benutzen willst.

**1. Neues Projekt**
- [console.cloud.google.com/projectcreate](https://console.cloud.google.com/projectcreate) öffnen
- **Projektname:** `KOReader Drive` → **Erstellen**
- Ab jetzt muss oben auf der Seite dieses Projekt ausgewählt sein.

**2. Google Drive einschalten**
- [Seite der Google Drive API](https://console.cloud.google.com/apis/library/drive.googleapis.com) öffnen
- **Aktivieren**

**3. App beschreiben**
- [Google Auth Platform](https://console.cloud.google.com/auth/overview) öffnen → **Erste Schritte**
- **App-Information:** Anwendungsname `KOReader Drive`, deine E-Mail als **Nutzersupport-E-Mail** → **Weiter**
- **Zielgruppe:** **Extern** → **Weiter**
- **Kontaktdaten:** deine E-Mail → **Weiter**
- **Fertig:** der Richtlinie zu Nutzerdaten zustimmen → **Weiter** → **Erstellen**

**4. App veröffentlichen**
- [Zielgruppe](https://console.cloud.google.com/auth/audience) öffnen → **App veröffentlichen** → bestätigen
- Der Veröffentlichungsstatus ist jetzt **In Produktion**

> Nicht auslassen. Im Status „Test“ läuft deine Anmeldung nach 7 Tagen ab. Für den eigenen Gebrauch brauchst du keine Prüfung durch Google.

**5. Erste Datei erzeugen**
- [Clients](https://console.cloud.google.com/auth/clients) öffnen → **Client erstellen**
- **Anwendungstyp:** **Webanwendung**
- Unter **Autorisierte Weiterleitungs-URIs** → **URI hinzufügen**, genau diese Adresse einfügen:
  ```
  https://developers.google.com/oauthplayground
  ```
- **Erstellen**
- **Sofort die JSON-Datei herunterladen** und in `client_id.json` umbenennen. Den geheimen Schlüssel zeigt Google nur dieses eine Mal.

</details>

<details>
<summary><b>Teil 2: Zugriff auf dein Drive erlauben</b> (du bekommst <code>refresh_token.txt</code>)</summary>

Dafür gibt es das Google-Werkzeug „OAuth 2.0 Playground“ (nur auf Englisch). Bis die Änderung aus Schritt 5 wirkt, kann es 5 Minuten (selten einige Stunden) dauern.

**6. Eigenen Client eintragen**
- [developers.google.com/oauthplayground](https://developers.google.com/oauthplayground) öffnen
- **Zahnrad** (oben rechts) → Haken bei **Use your own OAuth credentials**
- **OAuth Client ID** und **OAuth Client secret** ausfüllen. Beides steht in deiner `client_id.json` (mit einem Texteditor öffnen).

**7. Zugriff erlauben**
- Unten links in das Feld **Input your own scopes** einfügen:
  ```
  https://www.googleapis.com/auth/drive
  ```
- **Authorize APIs** und anmelden
- Google warnt, dass die App nicht überprüft ist. Das ist normal, es ist deine eigene App: **Erweitert** → weiter → erlauben

**8. Zweite Datei erzeugen**
- **Exchange authorization code for tokens**
- Den **Refresh token** kopieren (nur diesen, nicht den Access token)
- In eine neue Textdatei einfügen und als `refresh_token.txt` speichern

</details>

<details>
<summary><b>Teil 3: Auf den E-Reader kopieren und testen</b></summary>

**9. Beide Dateien in einen neuen Ordner `drivelibrary`** im KOReader-Ordner legen. Auf dem Kobo ist der KOReader-Ordner `.adds/koreader/` (versteckter Ordner).

```
koreader/
├── drivelibrary/                ← diesen Ordner anlegen
│   ├── client_id.json
│   └── refresh_token.txt
└── plugins/
    └── drivelibrary.koplugin/   ← das Plugin (siehe Installation)
```

Die zwei Dateien gehören **nicht** in den Plugin-Ordner.

**10. Ausprobieren**
- KOReader neu starten und WLAN verbinden
- Werkzeuge → **Drive-Bibliothek** → **Einstellungen** → **Anmeldung prüfen**
- Der Ordner `KOReader Library` wird jetzt in deinem Drive angelegt, falls er fehlt. Fertig!

</details>

<details>
<summary><b>Etwas klappt nicht?</b></summary>

| Problem | Lösung |
| --- | --- |
| „Noch nicht angemeldet“ | Ordnername, beide Dateinamen und den Ort prüfen (nicht im Plugin-Ordner). Unter Windows darf die Datei nicht `refresh_token.txt.txt` heißen. |
| `redirect_uri_mismatch` im Playground | Die Adresse aus Schritt 5 fehlt, hat einen Tippfehler oder wirkt noch nicht. Kurz warten. |
| Fenster geschlossen, ohne die JSON-Datei zu laden | Einen neuen Client erstellen (Schritt 5). |
| Geht nach 7 Tagen nicht mehr | Die App wurde nicht veröffentlicht (Schritt 4). Veröffentlichen, dann Schritt 6 bis 8 wiederholen. |
| Geht nach Monaten ohne Benutzung nicht mehr | Unbenutzter Zugang läuft nach 6 Monaten ab. Schritt 6 bis 8 wiederholen und `refresh_token.txt` ersetzen. |

</details>

## Sicherheit

Die Verbindung zu Google läuft mit geprüftem Zertifikat. `client_id.json` und `refresh_token.txt` sind wie Passwörter: nicht teilen, nicht veröffentlichen.

## Danksagung

Die Idee, den Zugang über den OAuth Playground zu holen, stammt aus [gdrive.koplugin](https://github.com/moohaad/gdrive.koplugin) von moohaad (MIT). Code wurde nicht übernommen.

## Getestet auf

Kobo Libra Colour mit KOReader 2026.07.1 und ZenOS. Die automatischen Tests laufen gegen ein nachgebautes Drive (`tests/fake_drive.py`), dazu wurde alles mit einem echten Drive-Konto von Hand geprüft.

## Wer das gemacht hat

Der Code wurde vollständig von **Claude** geschrieben, einer KI von Anthropic (in Claude Code). Der Besitzer dieses Projekts hatte die Idee, hat das Plugin auf dem Kobo getestet und Rückmeldungen gegeben, aber keinen Code geschrieben.

Es gibt keine Gewährleistung und keinen festen Support. Fehlermeldungen gern als [Issue](../../issues), bitte mit der `crash.log` aus dem KOReader-Ordner. **Vorsicht:** Das Plugin löscht Dateien vom Gerät (erst nach bestandener Prüfsumme). Probiere es zuerst mit Büchern, die du ersetzen kannst.

## Weitere Plugins

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
