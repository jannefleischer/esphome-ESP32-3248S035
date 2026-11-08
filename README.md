# Wall panel: ESPHome firmware

ESPHome project that turns an ESP32-3248S035 (3.5", capacitive touch) into a Home Assistant wall panel, in landscape at 480×320. The text on the display is German.

Hardware details, pinout and background research are in [`CLAUDE.md`](CLAUDE.md).

## Status

| Item | Status |
|---|---|
| Build | Succeeds with ESPHome 2026.10.2: about 1.06 MB of 1.75 MB flash (58 %), about 57 KB static RAM |
| On the device (2026-11-08) | Display, touch, Wi-Fi and controls work. Starting the robot for a single room was tested (vacuuming) |
| Original firmware backup | `backup_4MB.bin` (4 MB, SHA256 `9EE1BE1C…3568A0`) |
| Wi-Fi | Connected (2.4 GHz, WPA3) |
| Home Assistant | ESPHome integration set up, actions allowed |
| Robot integration | `switchbot_vacuum` from the fork [`jannefleischer/switchbot-vacuum`](https://github.com/jannefleischer/switchbot-vacuum), branch `prod` |
| Not verified yet | Washing machine remaining time during a cycle; the mop buttons and whole-home start; firmware updates over Wi-Fi |
| Open | Colours may look swapped on the display (red/blue); still to be checked on the device |

## Contents

| Path | Purpose | In Git? |
|---|---|---|
| `wandpanel.yaml` | Main file: Wi-Fi, API, fonts, Home Assistant entities, pages | yes |
| `hardware/esp32-3248s035.yaml` | Display, touch, backlight | yes |
| `ui/room_sensors.yaml` | Heating: current and target temperature, buffered setpoint logic for one room | yes |
| `ui/room_climate.yaml` | Heating: temperature and humidity from the hygrometer | yes |
| `ui/room_row.yaml` | One row of the heating page | yes |
| `ui/vacuum_room_sensors.yaml` | Cleaning: when a room was last vacuumed and mopped | yes |
| `ui/vacuum_room_row.yaml` | One row of the cleaning page, with start buttons | yes |
| `ui/format_time.h` | Formats timestamps as `heute`, `gestern` or `vor 3 Tagen` | yes |
| `secrets.example.yaml` | Template for `secrets.yaml` | yes |
| `secrets.yaml` | Wi-Fi, API key, OTA password | **no** |
| `.env` | Home Assistant address | **no** |
| `secrets/*.secret` | Tokens and passwords for Home Assistant, Wi-Fi, SwitchBot and GitHub. Only used for queries and to create `secrets.yaml`, not part of the firmware | **no** |
| `logs/` | Build, flash and diagnostic logs | no |
| `.esphome/`, `.venv/` | Build files and Python environment | no |
| `backup_*.bin` | Backup of the original firmware | no |

## Setup

Once, in PowerShell in this folder:

```powershell
python -m venv .venv
.\.venv\Scripts\python -m pip install esphome
Copy-Item secrets.example.yaml secrets.yaml
```

Then fill in `secrets.yaml`. The ESP32 only supports **2.4 GHz Wi-Fi**. The command that generates the API key is a comment in the template.

The first build downloads ESP-IDF and the compiler to `%LOCALAPPDATA%\esphome\Cache`, which takes a few minutes. Later builds reuse this cache.

## Building

**Always build in PowerShell.** ESP-IDF aborts in Git Bash with `MSys/Mingw is not supported`.

```powershell
$log = "logs\compile-$(Get-Date -Format yyyyMMdd-HHmmss).log"
$env:PYTHONUNBUFFERED = '1'
$env:IDF_GITHUB_ASSETS = 'dl.espressif.com/github_assets'
cmd /c ".\.venv\Scripts\esphome.exe compile wandpanel.yaml 2>&1" |
  ForEach-Object { $_; Add-Content -Path $log -Value $_ -Encoding utf8 }
```

The log grows line by line in `logs\`, so you can follow it live in an editor. To validate without building: `.\.venv\Scripts\esphome.exe config wandpanel.yaml`.

### If the download fails with 504

On 2026-11-08, GitHub returned `504 Gateway Time-out` for release files for a long stretch.

- `IDF_GITHUB_ASSETS` (see above) redirects the build tools to Espressif's mirror.
- ESP-IDF itself also needs a source under `esp32:` in `hardware/esp32-3248s035.yaml`. This is deliberately not committed and only needed while GitHub is failing:

```yaml
  framework:
    type: esp-idf
    version: 5.5.6
    source: https://dl.espressif.com/github_assets/espressif/esp-idf/releases/download/v5.5.6/esp-idf-v5.5.6.zip
```

## Flashing

The board is on **COM3**. An open serial monitor blocks the port.

Back up the original firmware before the first flash:

```powershell
.\.venv\Scripts\python -m esptool --port COM3 --baud 230400 read-flash 0 0x400000 backup_4MB.bin
```

**Baud rate for the CH340:** 230400 worked reliably. 460800 should work according to research but is untested here. 921600 failed while reading with `Corrupt data`.

Then upload over USB and view the log:

```powershell
.\.venv\Scripts\esphome.exe upload wandpanel.yaml --device COM3
.\.venv\Scripts\esphome.exe logs wandpanel.yaml --device COM3
```

Once the panel is on Wi-Fi, USB is no longer needed: use `--device wandpanel.local` or its IP address.

To restore the backup:

```powershell
.\.venv\Scripts\python -m esptool --port COM3 write-flash 0 backup_4MB.bin
```

## Connecting Home Assistant

1. After the first start, the panel appears under Settings → Devices & services. Otherwise add the ESPHome integration manually with the IP address and enter the `api_key`.
2. On the device, under "Configure", enable **"Allow the device to perform Home Assistant actions"**. Without it the panel shows values, but switches and setpoints have no effect.

This Home Assistant runs without Supervisor, so there is no ESPHome add-on. Builds run on the PC.

## User interface

After 30 seconds without touch the backlight turns off. The first touch only wakes the panel and does not trigger a button.

**Overview (Übersicht):** Outdoor temperature and weather, power use with balcony solar and forecast, washing machine remaining time, on/off switches for the hallway lamp and kitchen hot water.

**Heating (Heizung):** For each room, thermostat temperature, room temperature, relative humidity and target temperature. Plus and minus change the target in 0.5 °C steps. Presses are buffered: the value is sent to Home Assistant 1 second after the last press. Unreachable thermostats show `--` and their buttons have no effect.

**Cleaning (Putzen):** Status and battery, the last run, and for each room when it was last vacuumed and mopped.

- The buttons at the top right start the whole home, the buttons at the end of a row start a single room.
- A run only starts when the robot is docked or idle.
- Single-room runs use standard suction. Whole-home runs permanently change the mode set in the integration.
- Status and battery come from Bluetooth; the cloud is the fallback for status. Without history data the page shows `Verlauf gerade nicht verfügbar` or `--`. `--` under `Gewischt` can also mean a room has never been mopped.

### Making changes

- **Adding a room:** in `wandpanel.yaml`, add one `!include` line under `packages:` (sensors) and one in the page (row). `room` must be unique. Heating (6 rows) and cleaning (8 rows) are full.
- **Robot rooms:** The `ROOM_…` IDs are in the `!include` lines. If you rename a room in the app, the entities stay the same and the panel shows the new name once the integration knows it (`force_refresh`, or within a day).
- **New text:** Every character must be listed in the `glyphs:` of its font, otherwise it is not drawn. `font_big` only has digits and a few characters.
- **Layout:** The layout uses fixed coordinates for 480×320.

## Known limitations

- **RAM is the bottleneck.** The board has no PSRAM, and the display buffer alone takes 76.8 KB at 25 %. If LVGL reports an allocation error, reduce `buffer_size` to 12 %.
- **Use images sparingly.** They are stored in flash; the SD card is not used (see `CLAUDE.md` for why).
- **Touch alignment:** `transform` is under `touchscreen:` in the hardware file; the display orientation is configured separately.
- **Touch without interrupt:** Polling is used on purpose. GPIO 21 and 25 are untested.
- **Open ESPHome warnings:** `ili9xxx` is deprecated (target: `mipi_spi`), and `encryption` is recommended over `password` for OTA.
- The strapping pin warnings for GPIO 2, 12 and 15 are expected on this board, as the PCB fixes these pins.
