# Stack Renamer — Lightroom Classic Plugin

Benennt Stacks **konsistent** um: Jedes Mitglied eines Stacks (z. B. `IMG_1234.CR3` + `.DNG` + `.JPEG`)
erhält denselben Basisnamen; nur die Dateiendung bleibt pro Datei erhalten. Unstackte Fotos werden
wie Stacks der Größe 1 behandelt.

> **Hinweis (SDK-Limitierung):** Das Lightroom-SDK kann Foto-Dateien **nicht direkt umbenennen**
> (es gibt keine File-Rename-API in `LrCatalog`/`LrPhoto`). Das Plugin bereitet den Umbenennungs-Schritt
> daher vor (Schreibt den fertigen Namen in ein IPTC-Feld); die Ausführung übernimmt Lightrooms eigenes
> **„Fotos umbenennen"** (F2) — inkl. Endungen, XMP-Sidecars und Undo.

## Installation

1. Ordner `stack-renamer.lrplugin` ablegen und in Lightroom Classic öffnen:
   **Datei → Plug-in-Manager… → Hinzufügen…** → Ordner wählen.
2. Nach dem Start erscheint der Menüpunkt unter **Datei → Plug-in-Extras → Stacks konsistent umbenennen…**

Anforderungen: Lightroom Classic (SDK 8.0).

## Bedienung (2-Schritt)

1. **Fotos auswählen** (Grid/Filmstreifen) → Menüpunkt klicken.
2. Im Dialog **Namensmuster** (z. B. `{date}_{custom}_{seq}`) einstellen, Vorschau prüfen → **Anwenden**.
   Das Plugin schreibt für **jede echte Datei jedes Stacks** den aufgelösten Basisnamen (z. B. `25_Island_02`)
   in das gewählte IPTC-Feld — voreingestellt **„Instructions"**, umschaltbar auf „Headline" (`Namens-Feld`).
3. Die Fotos bleiben ausgewählt gelassen → **F2** drücken → in der Dateinamen-Vorlage den IPTC-Wert
   **„Anweisungen" (bzw. „Überschrift")** einfügen → OK. Lightroom benennt die Dateien um.

Das F2-Template muss nur **einmal** erstellt werden (F2 → „Edit…" → Token einfügen → „Save as New Preset”)
und steht danach dauerhaft zur Verfügung.

## Namensmuster

Token-basiert, per Bearbeitungsfeld im Dialog überschreibbar — Standard: `{date}_{custom}_{seq}`.

| Token | Bedeutung |
|---|---|
| `{date}` bzw. `{date:<fmt>}` | Aufnahmedatum (fehlt es, wird „heute" verwendet). Formate: `DD` (Tag, Standard), `YY`, `YYYYMMDD`, `DD.MM.YYYY`, … — oder nativ `%d`, `%Y%m%d`, … |
| `{custom}` | Freitext aus dem Dialog (z. B. „Island"), für alle Stacks gleich |
| `{seq}` | Laufnummer je Stack, null-padded (Breite = „Padding"), konfigurierbarer Startwert |
| `{orig}` | bisheriger Basisname des Stacks |

Die Dateiendung ist nie Teil des Musters — Lightroom erhält sie beim Umbenennen automatisch.

## Einstellungen im Dialog

Alle Einstellungen werden beim Schließen persistiert (`LrPrefs`) und beim nächsten Öffnen wieder geladen:

| Einstellung | Bedeutung |
|---|---|
| Freitext | Wert für `{custom}` |
| Datumsformat | Token für `{date}` (siehe oben) |
| Startnummer / Padding | Startwert und Nullbreite für `{seq}` |
| Namensmuster | Tokens + fester Text |
| Sortierung | **Aktuelle Reihenfolge** (wie Lightroom die Auswahl liefert, z. B. Custom Sort) · **Aufnahmezeit** · **Dateiname** — bestimmt die `{seq}`-Vergabe |
| In-Stack-Ordnung | DNG auf Position 1, Non-Raw (JPEG/HEIC/…) auf Position 2, Rest bleibt relativ (z. B. `CR3,DNG,JPEG` → `DNG,JPEG,CR3`) |
| Namens-Feld | IPTC-Feld, in das der Basisname geschrieben wird: **Instructions** (Standard) oder **Headline** |

## Verhalten & Design

- **Stack-Erweiterung:** Selektierst du nur ein Foto eines Stacks, werden beim Umbenennen trotzdem
  **alle Stack-Mitglieder** erfasst (`stackInFolderMembers`).
- **Virtuelle Kopien** werden übersprungen (sie teilen die Datei des Masters).
- Ein einziger `withWriteAccessDo`-Block pro Lauf → **ein Undo-Schritt**.
- Kollisionsprüfung (case-insensitive): Bei doppelt vergebenen Basisnamen bleibt „Anwenden" deaktiviert.

## Dateien

| Datei | Rolle |
|---|---|
| `Info.lua` | Manifest, Menü-Registrierung (`LrExportMenuItems` → Datei → Plug-in-Extras) |
| `RenameStacks.lua` | Entry-Modul (wird von Lightroom direkt ausgeführt), Fehlerabfang |
| `RenameCore.lua` | Selektion → Gruppierung (Stacks/„size-1") → Plan → Feld schreiben |
| `RenameDialog.lua` | Einstellungen + Live-Vorschau + Bestätigen (UI Deutsch) |
| `Utils.lua` | Muster-Parser, Datumsformat, Stack-Schlüssel, Kollisionen, Format-Klassen |

## Bekannte Punkte

- Automatisches Erzeugen des F2-Templates durch das Plugin ist nicht umgesetzt (Token-Codierung der
  `.lrtemplate`-Dateien ist undokumentiert/fragil); das Template wird einmal manuell erstellt.
- Dateitoken „Originalname" (`{orig}`) bei Stacks bezieht sich auf den Repräsentanten.