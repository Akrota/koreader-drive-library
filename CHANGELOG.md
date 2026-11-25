# Changelog – Drive Library

*Deutsche Fassung weiter unten.*

## 0.5.3
- **The default folder in Drive is now called `KOReader Library`** (before: `Kobo Bibliothek`), so it also fits English users and other devices. If you already use another folder, set it under Settings → "Folder in Drive".

## 0.5.2
- Preloading the next volume failed if the background job could not start right after Wi-Fi was switched on. There is now a second attempt after 3 s and another preload attempt after 2 minutes (at most 3 per book).

## 0.5.1
- Fixed a crash when closing a comic: helper files now live in a subfolder of `cache/` (`cache/drivelibrary/`), because KOReader's page cache trips over deleted files directly in `cache/`.

## 0.5
- Jobs (download, upload) run as a separate small process (`gdl_worker.lua`) instead of a fork of KOReader. This needs far less memory (measured: at most 6 MB) and prevents crashes with large comics. Upload in 2 MB pieces.
- Options (off by default): preload the next volume in the background, move finished volumes to the cloud automatically, back up the `.sdr` folder on close.

## 0.4 and earlier
- Selection mode, cloud view, moving to the cloud with a checksum, the `.sdr` folder goes to Drive as well.

---

# Deutsch

## 0.5.3
- **Der Standardordner in Drive heißt jetzt `KOReader Library`** (vorher `Kobo Bibliothek`), damit er auch für englische Nutzer und andere Geräte passt. Wer schon einen anderen Ordner benutzt, stellt ihn unter Einstellungen → „Ordner in Drive“ ein.

## 0.5.2
- Das Vorladen des nächsten Bands scheiterte, wenn der Hintergrund-Auftrag direkt nach dem Einschalten des WLANs nicht starten konnte. Jetzt gibt es einen zweiten Versuch nach 3 s und einen weiteren Vorlade-Versuch nach 2 Minuten (höchstens 3 pro Buch).

## 0.5.1
- Absturz beim Schließen eines Comics behoben: Hilfsdateien liegen jetzt in einem Unterordner von `cache/` (`cache/drivelibrary/`), weil KOReaders Seiten-Zwischenspeicher über gelöschte Dateien direkt in `cache/` stolpert.

## 0.5
- Aufträge (Laden, Hochladen) laufen als eigener kleiner Prozess (`gdl_worker.lua`) statt als Abzweig von KOReader. Das braucht deutlich weniger Arbeitsspeicher (gemessen höchstens 6 MB) und verhindert Abstürze bei großen Comics. Hochladen in 2-MB-Stücken.
- Optionen (ab Werk aus): nächsten Band im Hintergrund vorladen, gelesene Bände automatisch auslagern, `.sdr` beim Schließen sichern.

## 0.4 und früher
- Auswahl-Modus, Cloud-Ansicht, Auslagern mit Prüfsumme, `.sdr` geht mit nach Drive.
