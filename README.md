# Wandpanel: ESPHome-Firmware

ESPHome-Projekt für ein ESP32-3248S035 (3,5", kapazitiver Touch) als Home-Assistant-Panel im Flur am Stromkasten, Querformat 480×320.

Hardware-Details, Pinbelegung und Recherche stehen in [`CLAUDE.md`](CLAUDE.md).

## Stand

| Punkt | Status |
|---|---|
| Build | erfolgreich mit ESPHome 2026.10.2: Flash ca. 1,06 MB von 1,75 MB (58 %), RAM statisch ca. 57 KB |
| Am Gerät (2026-11-08) | läuft: Bild, Touch, WLAN und Bedienung. Raumstart des Roboters getestet (Saugen) |
| Backup Originalfirmware | `backup_4MB.bin` (4 MB, SHA256 `9EE1BE1C…3568A0`) |
| WLAN | verbunden (2,4 GHz, WPA3) |
| Home Assistant | ESPHome-Integration eingerichtet, Aktionen freigegeben |
| Roboter-Integration | `switchbot_vacuum` aus dem Fork [`jannefleischer/switchbot-vacuum`](https://github.com/jannefleischer/switchbot-vacuum), Zweig `prod` |
| Noch nicht geprüft | Waschmaschinen-Restzeit während eines Waschgangs; Knöpfe „Wischen“ und Ganzhaus-Start; Firmware-Update über WLAN |
| Offen | Farben wirken am Display möglicherweise vertauscht (Rot/Blau), Prüfung am Gerät steht aus |

## Inhalt

| Pfad | Zweck | In Git? |
|---|---|---|
| `wandpanel.yaml` | Hauptdatei: WLAN, API, Fonts, HA-Entitäten, Seiten | ja |
| `hardware/esp32-3248s035.yaml` | Display, Touch, Backlight | ja |
| `ui/room_sensors.yaml` | Heizung: Ist, Soll und gepufferte Sollwert-Logik eines Raums | ja |
| `ui/room_climate.yaml` | Heizung: Temperatur und Feuchte vom Hygrometer | ja |
| `ui/room_row.yaml` | eine Zeile der Heizungsseite | ja |
| `ui/vacuum_room_sensors.yaml` | Putzen: wann ein Raum zuletzt gesaugt und gewischt wurde | ja |
| `ui/vacuum_room_row.yaml` | eine Zeile der Putzen-Seite, mit Start-Knöpfen | ja |
| `ui/format_time.h` | formatiert Zeiten als „heute 11:23“, „gestern 11:23“ oder „08.11. 11:23“ | ja |
| `diagnose_ha_slow.sh` | rein lesende Diagnose des Raspi bei langsamem HA | ja |
| `secrets.example.yaml` | Vorlage für `secrets.yaml` | ja |
| `secrets.yaml` | WLAN, API-Key, OTA-Passwort | **nein** |
| `.env` | Adresse von Home Assistant | **nein** |
| `secrets/*.secret` | Tokens und Passwörter für HA, WLAN, SwitchBot und GitHub. Nur für Abfragen und zum Erzeugen von `secrets.yaml`, nicht Teil der Firmware | **nein** |
| `logs/` | Build-, Flash- und Diagnose-Logs | nein |
| `.esphome/`, `.venv/` | Build-Dateien und Python-Umgebung | nein |
| `backup_*.bin` | Sicherung der Originalfirmware | nein |

Der Ordner `Elektronik` ist derzeit kein Git-Repo. Die `.gitignore` greift erst, wenn hier eines angelegt wird.

## Einrichtung

Einmalig in PowerShell in diesem Ordner:

```powershell
python -m venv .venv
.\.venv\Scripts\python -m pip install esphome
Copy-Item secrets.example.yaml secrets.yaml
```

Dann `secrets.yaml` ausfüllen. Der ESP32 kann nur **2,4-GHz-WLAN**. Den API-Key erzeugt der Befehl, der als Kommentar in der Vorlage steht.

Der erste Build lädt ESP-IDF und den Compiler nach `%LOCALAPPDATA%\esphome\Cache`, das dauert einige Minuten. Spätere Builds nutzen diesen Cache.

## Bauen

**Immer in PowerShell bauen.** ESP-IDF bricht in Git Bash mit `MSys/Mingw is not supported` ab.

```powershell
$log = "logs\compile-$(Get-Date -Format yyyyMMdd-HHmmss).log"
$env:PYTHONUNBUFFERED = '1'
$env:IDF_GITHUB_ASSETS = 'dl.espressif.com/github_assets'
cmd /c ".\.venv\Scripts\esphome.exe compile wandpanel.yaml 2>&1" |
  ForEach-Object { $_; Add-Content -Path $log -Value $_ -Encoding utf8 }
```

Das Log wächst dabei Zeile für Zeile in `logs\` und lässt sich im Editor live mitlesen. Nur prüfen ohne Bauen: `.\.venv\Scripts\esphome.exe config wandpanel.yaml`.

### Wenn der Download mit 504 scheitert

Am 2026-11-08 lieferte GitHub für Release-Dateien dauerhaft `504 Gateway Time-out`.

- `IDF_GITHUB_ASSETS` (siehe oben) leitet die Build-Werkzeuge auf Espressifs Spiegel um.
- Für ESP-IDF selbst muss zusätzlich unter `esp32:` in `hardware/esp32-3248s035.yaml` eine Quelle stehen. Das ist bewusst nicht dauerhaft eingetragen und nur nötig, solange GitHub streikt:

```yaml
  framework:
    type: esp-idf
    version: 5.5.6
    source: https://dl.espressif.com/github_assets/espressif/esp-idf/releases/download/v5.5.6/esp-idf-v5.5.6.zip
```

## Flashen

Das Board hängt an **COM3**. Ein offener serieller Monitor blockiert den Port.

Vor dem ersten Flash die Originalfirmware sichern:

```powershell
.\.venv\Scripts\python -m esptool --port COM3 --baud 460800 read-flash 0 0x400000 backup_4MB.bin
```

**Baudrate für den CH340:** 230400 lief zuverlässig. 460800 sollte laut Recherche auch gehen, ist hier aber ungetestet. 921600 brach beim Auslesen mit `Corrupt data` ab.

Dann per USB aufspielen und das Log ansehen:

```powershell
.\.venv\Scripts\esphome.exe upload wandpanel.yaml --device COM3
.\.venv\Scripts\esphome.exe logs wandpanel.yaml --device COM3
```

Sobald das Panel im WLAN ist, entfällt USB: `--device wandpanel.local` oder dessen IP-Adresse.

Zurück zur Sicherung:

```powershell
.\.venv\Scripts\python -m esptool --port COM3 write-flash 0 backup_4MB.bin
```

## Home Assistant anbinden

1. Nach dem ersten Start erscheint das Panel unter Einstellungen → Geräte & Dienste. Sonst die ESPHome-Integration von Hand mit der IP-Adresse hinzufügen und den `api_key` eingeben.
2. Beim Gerät unter „Konfigurieren“ die Option **„Allow the device to perform Home Assistant actions“** aktivieren. Ohne sie zeigt das Panel Werte an, aber Schalter und Solltemperatur wirken nicht.

Dieses Home Assistant läuft ohne Supervisor, es gibt also kein ESPHome-Add-on. Gebaut wird auf dem PC.

## Oberfläche

Sprache auf dem Display: Deutsch. Nach 30 Sekunden ohne Berührung geht die Beleuchtung aus; die erste Berührung weckt nur auf und löst keinen Knopf aus.

**Übersicht:** Außentemperatur und Wetter, Stromverbrauch mit Balkonkraftwerk und Prognose, Restzeit der Waschmaschine, Schalter für Flurlampe und Heißwasser Küche mit An/Aus-Anzeige.

**Heizung:** Für Arbeitszimmer, Schlafzimmer, Küche, Laurie, Johanna und Erkerzimmer jeweils Ist am Thermostat, Raumtemperatur, relative Feuchte und Soll. Plus und Minus ändern das Soll in 0,5-°C-Schritten. Die Werte werden gepuffert: Erst 1 Sekunde nach dem letzten Druck geht der Wert an Home Assistant. Nicht erreichbare Thermostate zeigen `--`, die Tasten bleiben dann ohne Wirkung.

**Putzen:** Status und Akku, die letzte Fahrt, dazu je Raum, wann zuletzt gesaugt und gewischt wurde.

- Knöpfe oben rechts starten das ganze Haus, die Knöpfe am Zeilenende einen einzelnen Raum.
- Gestartet wird nur, wenn der Roboter in der Station oder bereit ist.
- Der Raumstart nutzt Saugkraft Standard. Der Ganzhaus-Start setzt den Modus in der Integration dauerhaft um.
- Status und Akku kommen über Bluetooth; beim Ausfall springt für den Status die Cloud ein. Fehlen Verlaufsdaten, steht dort „Verlauf gerade nicht verfügbar“ bzw. `--`. `--` bei „Gewischt“ heißt auch: noch nie gewischt.

### Ändern

- **Raum ergänzen:** in `wandpanel.yaml` je eine `!include`-Zeile unter `packages:` (Sensoren) und in der Seite (Zeile) anlegen. `room` muss eindeutig sein. Heizung (6 Zeilen) und Putzen (8 Zeilen) sind voll belegt.
- **Roboter-Räume:** Die Zuordnung Name zu `ROOM_…` steht in den `!include`-Zeilen. Benennst du Räume in der App um, bleiben die Entitäten gleich, und das Panel zeigt den neuen Namen, sobald die Integration ihn kennt (`force_refresh` oder spätestens nach einem Tag).
- **Neue Texte:** Jedes Zeichen muss in `glyphs:` des jeweiligen Fonts stehen, sonst bleibt es leer. `font_big` enthält nur Ziffern und wenige Zeichen.
- **Farben und Layout:** Das Layout arbeitet mit festen Koordinaten für 480×320.

## Bekannte Grenzen

- **RAM ist der Engpass.** Das Board hat kein PSRAM, der Bildpuffer belegt bei 25 % schon 76,8 KB. Meldet LVGL einen Allokationsfehler, `buffer_size` auf 12 % senken.
- **Bilder sparsam einsetzen.** Sie kommen in den Flash, die SD-Karte wird nicht genutzt (Begründung in der `CLAUDE.md`).
- **Touch:** Die Ausrichtung passt. `transform` steht unter `touchscreen:` in der Hardware-Datei; die Bildausrichtung liegt getrennt davon beim Display.
- **Touch ohne Interrupt:** läuft bewusst per Polling, GPIO 21 und 25 sind noch nicht getestet.
- **Offene ESPHome-Warnungen:** `ili9xxx` ist veraltet (Ziel `mipi_spi`), und für OTA wird `encryption` statt `password` empfohlen. Beides ist noch offen.
- Die Warnungen zu den Strapping-Pins GPIO 2, 12 und 15 sind bei diesem Board normal, die Belegung gibt die Platine vor.
