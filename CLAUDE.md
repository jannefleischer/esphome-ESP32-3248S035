# Wandpanel für Home Assistant (ESPHome)

Ziel: China-Touch-Display (ESP32-3248S035, kapazitive Variante) als Wandpanel für Home Assistant: Informationen anzeigen, einzelne Geräte steuern.

Stand: 2026-11-08. Das Panel läuft produktiv. Build, Flashen und Bedienung stehen in `README.md`, die tatsächliche Konfiguration in `wandpanel.yaml`, `hardware/` und `ui/`. Der frühere Arduino-Sketch liegt in `..\esp32-display`.

## Warum ESPHome mit LVGL

- Die native API liefert Zustände aus HA und ruft HA-Actions auf, ohne eigenen MQTT- oder REST-Code.
- OTA-Updates und Logs über WLAN sind eingebaut.
- Die UI ist deklaratives YAML. Der vorhandene Arduino-Sketch ist nur eine Demo-UI ohne WLAN und HA.

## Hardware

Ausgelesen am 2026-11-08 per `esptool` am angeschlossenen Board:

| Eigenschaft | Wert |
|---|---|
| Chip | ESP32-D0WD-V3, Revision 3.1, Dual Core, 240 MHz, 40-MHz-Quarz |
| Flash | 4 MB (Manufacturer 0x5e, Device 0x4016), bootet im DIO-Modus |
| PSRAM | keiner (Boot-Log: `PSRAM ID read error`; harmlos, kommt vom Core) |
| USB-Seriell | CH340 auf **COM3** |

Die maßgebliche Pinquelle ist der Schaltplan V1.1:
`\\qnapjjf\Familie\Janne\Elektronik\3.5inch_ESP32-3248S035\5-Schematic\`

| Funktion | GPIO | Hinweis |
|---|---|---|
| TFT SCLK / MOSI / MISO | 14 / 13 / 12 | ST7796, 320×480. GPIO12 ist Strapping-Pin |
| TFT CS / DC | 15 / 2 | beides Strapping-Pins |
| TFT RST | – | am EN-Netz des ESP32 |
| Backlight | 27 | PWM über MOSFET, HIGH = an |
| Touch SDA / SCL | 33 / 32 | GT911, Adresse 0x5D |
| Touch RST | 25 | |
| Touch INT | **21** | über R25 (0 Ω), siehe unten |
| RGB-LED | 4 / 16 / 17 | active LOW, laut Notiz Rot/Grün/Blau |
| Lichtsensor (LDR) | 34 | Spannungsteiler, nur Eingang |
| Lautsprecher | 26 | DAC auf Verstärker SC8002B |
| SD CS / MOSI / CLK / MISO | 5 / 23 / 18 / 19 | |
| BOOT-Taste | 0 | LOW = gedrückt |
| Stecker P3 frei | 21 / 22 / 35 | 35 nur Eingang, 21 ist auch Touch-INT |

### Bekannte Stolperstelle GPIO 21

Community-Quellen berichten, dass GT911-INT auf manchen Boards fehlerhaft geroutet ist (auf GND statt über R25). Im Forum funktionierte Touch erst ohne `interrupt_pin` und `reset_pin`. Deshalb zuerst mit Polling starten (`update_interval: 50ms`) und `reset_pin: GPIO25` separat testen. Ob dieses Exemplar betroffen ist, ist ungetestet.

## Hardware ansprechen

Immer mit dem PlatformIO-esptool, das Board startet dabei neu:

```bash
python "$USERPROFILE/.platformio/packages/tool-esptoolpy/esptool.py" --port COM3 flash_id
```

Serielles Log mit 115200 Baud: `pio device monitor -p COM3 -b 115200`.
Baudrate für `esptool`: 230400 lief zuverlässig, 460800 ist laut Recherche möglich, aber ungetestet. 921600 brach beim Auslesen mit `Corrupt data` ab.
Der Port kann nur von einem Prozess gleichzeitig belegt werden. Ein offener Monitor blockiert also das Flashen.


## ESPHome-Erkenntnisse

### Speicher ist die Hauptgrenze

- Ohne PSRAM empfiehlt die ESPHome-Doku `buffer_size: 25%`. Das sind bei 320×480 in RGB565 **76.800 Bytes**, die zusammenhängend frei sein müssen.
- Schlägt die Allokation fehl, geht LVGL auf „Failed“. Bei explizit gesetzter Größe gibt es keinen Fallback; dann auf 12 % reduzieren.
- Fonts und Bilder sparsam einsetzen: nur benötigte Glyphen, möglichst keine großen Bitmaps. Das Limit von 4 MB Flash wird mit OTA-Partitionen knapper.
- Direktes Zeichnen ohne LVGL scheitert am fehlenden Vollbild-Puffer. Deshalb `update_interval: never` und `auto_clear_enabled: false`.

### SD-Karte: vorerst nicht nutzen

Eine Suche (2026-11-08) ergab keinen offiziellen Weg, LVGL-Bilder in ESPHome von SD zu laden; dokumentiert sind Bilder im Flash und per HTTP(S). SD bräuchte eine eigene Komponente und zusätzlichen RAM. Der Engpass ist RAM, nicht Flash. Icons kommen deshalb in den Flash: 48×48 px in RGB565 sind 4,6 KB, ein Vollbild dagegen 307 KB.

### Stand

Läuft auf dem Gerät mit ESPHome 2026.10.2. Offene Warnungen: `ili9xxx` ist veraltet (Ziel: `mipi_spi`), und für OTA empfiehlt ESPHome `encryption` statt `password`.

### Muster für Home Assistant

Zustand holen und Aktion auslösen, hier für eine Lampe:

```yaml
binary_sensor:
  - platform: homeassistant
    id: remote_light
    entity_id: light.remote_light
    trigger_on_initial_state: true
    on_state:
      then:
        lvgl.widget.update:
          id: light_btn
          state:
            checked: !lambda return x;

# Im LVGL-Widget:
- button:
    id: light_btn
    checkable: true
    on_click:
      - homeassistant.action:
          action: light.toggle
          data:
            entity_id: light.remote_light
```

- Für Klima: `homeassistant`-Sensor in eine Spinbox schreiben, deren `on_value` `climate.set_temperature` aufruft.
- **Pflicht in HA:** Unter Integration ESPHome → Gerät → Konfigurieren die Option „Allow the device to perform Home Assistant actions“ aktivieren. Sonst passieren die Aktionen nicht.
- API verschlüsseln: `api: encryption: key: !secret api_key`.
- Direkt nach dem Verbinden gesendete Actions können verloren gehen; vorher kurz `delay` einbauen.

## Konventionen

- WLAN-Daten und API-Key nur in `secrets.yaml` (dort per `.gitignore` ausgeschlossen).
- Flashen oder Löschen des Boards vorher mit Janne abstimmen.
- Erkenntnisse aus Tests am Gerät hier nachtragen; Schaltplan und `esptool` gehen vor älteren Notizen.

## Noch zu klären

- HA: 2026.11.0, Adresse in `.env`, Token in `secrets\ha_token.secret`. Kein Supervisor, also keine Add-ons: ESPHome läuft auf diesem PC.
- Montage: Flur am Stromkasten, quer. Stromversorgung und Dauerbetrieb sind noch offen. Der LDR an GPIO 34 ist ungenutzt.
- Display-Farben: Rot und Blau wirken möglicherweise vertauscht (`color_order`), Prüfung am Gerät steht aus.
- Der Roboter hängt über Fork `jannefleischer/switchbot-vacuum` (Cloud, Räume, Verlauf) und die Bluetooth-Integration `switchbot` (Live-Status, Akku) an HA.

## Quellen

- [ESPHome LVGL](https://esphome.io/components/lvgl/), [LVGL Cookbook](https://esphome.io/cookbook/lvgl/)
- [ESPHome GT911](https://esphome.io/components/touchscreen/gt911/), [mipi_spi](https://esphome.io/components/display/mipi_spi/), [Native API](https://esphome.io/components/api/)
- [HA-Forum: ESP32-3248S035](https://community.home-assistant.io/t/help-making-esp32-3248s035-work/748332)
- [Community-Pinbelegung 3248S035C](https://github.com/rzeldent/platformio-espressif32-sunton/blob/main/esp32-3248S035C.json), [Hardware-Notizen ESP3D](https://esp3d.io/ESP3D-TFT/Version_1.X/hardware/esp32/sunton-35-3248)
