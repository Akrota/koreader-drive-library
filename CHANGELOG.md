# Drive-Bibliothek – Änderungen

## 0.5.2
- Das Vorladen des nächsten Bands scheiterte, wenn der Hintergrund-Auftrag direkt nach dem Einschalten des WLANs nicht starten konnte. Jetzt gibt es einen zweiten Versuch nach 3 s und einen weiteren Vorlade-Versuch nach 2 Minuten (höchstens 3 pro Buch).

## 0.5.1
- Absturz beim Schließen eines Comics behoben: Hilfsdateien liegen jetzt in einem Unterordner von `cache/` (`cache/drivelibrary/`), weil KOReaders Seiten-Zwischenspeicher über gelöschte Dateien direkt in `cache/` stolpert.

## 0.5
- Aufträge (Laden, Hochladen) laufen als eigener kleiner Prozess (`gdl_worker.lua`) statt als Abzweig von KOReader. Das braucht deutlich weniger Arbeitsspeicher (gemessen höchstens 6 MB) und verhindert Abstürze bei großen Comics. Hochladen in 2-MB-Stücken.
- Optionen (ab Werk aus): nächsten Band im Hintergrund vorladen, gelesene Bände automatisch auslagern, `.sdr` beim Schließen sichern.

## 0.4 und früher
- Auswahl-Modus, Cloud-Ansicht, Auslagern mit Prüfsumme, `.sdr` geht mit nach Drive.
