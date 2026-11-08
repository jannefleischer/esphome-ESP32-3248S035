# Home Assistant wall panel (ESPHome)

Goal: a low-cost touch display (ESP32-3248S035, capacitive variant) as a wall panel for Home Assistant, showing information and controlling selected devices.

Status: 2026-11-08. The panel is in daily use. Building, flashing and usage are in `README.md`; the actual configuration is in `wandpanel.yaml`, `hardware/` and `ui/`. The earlier Arduino sketch is in `..\esp32-display`.

Text shown on the display stays German. Documentation and code identifiers in new work are English.

## Why ESPHome with LVGL

- The native API delivers states from Home Assistant and calls its actions, with no custom MQTT or REST code.
- OTA updates and logs over Wi-Fi are built in.
- The UI is declarative YAML. The existing Arduino sketch is only a demo UI without Wi-Fi or Home Assistant.

## Hardware

Read with `esptool` from the connected board on 2026-11-08:

| Property | Value |
|---|---|
| Chip | ESP32-D0WD-V3, revision 3.1, dual core, 240 MHz, 40 MHz crystal |
| Flash | 4 MB (manufacturer 0x5e, device 0x4016), boots in DIO mode |
| PSRAM | None (boot log: `PSRAM ID read error`; harmless, comes from the core) |
| USB serial | CH340 on **COM3** |

The authoritative pin source is schematic V1.1:
`\\qnapjjf\Familie\Janne\Elektronik\3.5inch_ESP32-3248S035\5-Schematic\`

| Function | GPIO | Note |
|---|---|---|
| TFT SCLK / MOSI / MISO | 14 / 13 / 12 | ST7796, 320×480. GPIO12 is a strapping pin |
| TFT CS / DC | 15 / 2 | Both strapping pins |
| TFT RST | – | On the ESP32 EN net |
| Backlight | 27 | PWM via MOSFET, HIGH = on |
| Touch SDA / SCL | 33 / 32 | GT911, address 0x5D |
| Touch RST | 25 | |
| Touch INT | **21** | Via R25 (0 Ω), see below |
| RGB LED | 4 / 16 / 17 | Active LOW, red/green/blue according to earlier notes |
| Light sensor (LDR) | 34 | Voltage divider, input only |
| Speaker | 26 | DAC into SC8002B amplifier |
| SD CS / MOSI / CLK / MISO | 5 / 23 / 18 / 19 | |
| BOOT button | 0 | LOW = pressed |
| Free on connector P3 | 21 / 22 / 35 | 35 is input only, 21 is also touch INT |

### Known pitfall: GPIO 21

Community sources report that GT911 INT is misrouted on some boards (to GND instead of through R25). In a forum thread, touch only worked without `interrupt_pin` and `reset_pin`. The panel therefore uses polling (`update_interval: 50ms`). Whether this board is affected, and whether `reset_pin: GPIO25` works, is untested.

## Talking to the hardware

Use the PlatformIO esptool; the board restarts when it is used:

```bash
python "$USERPROFILE/.platformio/packages/tool-esptoolpy/esptool.py" --port COM3 flash_id
```

Serial log at 115200 baud: `pio device monitor -p COM3 -b 115200`.
`esptool` baud rate: 230400 worked reliably, 460800 should work according to research but is untested. 921600 failed while reading with `Corrupt data`.
Only one process can hold the port, so an open monitor blocks flashing.

## ESPHome findings

### Memory is the main limit

- Without PSRAM, the ESPHome docs recommend `buffer_size: 25%`. At 320×480 in RGB565 that is **76,800 bytes**, which must be free in one contiguous block.
- If the allocation fails, LVGL goes to "Failed". An explicitly set size has no fallback; reduce it to 12 % in that case.
- Use fonts and images sparingly: only the glyphs you need, and no large bitmaps if possible.
- Drawing directly without LVGL fails because there is no full-frame buffer. Hence `update_interval: never` and `auto_clear_enabled: false`.

### SD card: not used for now

A search on 2026-11-08 found no official way to load LVGL images from SD in ESPHome; images in flash and over HTTP(S) are documented. SD would need a custom component and more RAM. RAM is the bottleneck, not flash. Icons therefore go in flash: 48×48 px in RGB565 is 4.6 KB, a full screen is 307 KB.

### Status

Runs on the device with ESPHome 2026.10.2. Open warnings: `ili9xxx` is deprecated (target: `mipi_spi`), and ESPHome recommends `encryption` over `password` for OTA.

### Home Assistant patterns

Read a state and trigger an action, here for a lamp:

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

# In the LVGL widget:
- button:
    id: light_btn
    checkable: true
    on_click:
      - homeassistant.action:
          action: light.toggle
          data:
            entity_id: light.remote_light
```

- **Required in Home Assistant:** under the ESPHome integration → device → Configure, enable "Allow the device to perform Home Assistant actions". Otherwise actions are rejected.
- Encrypt the API: `api: encryption: key: !secret api_key`.
- Actions sent right after connecting can be lost; add a short `delay` first.

## Conventions

- Wi-Fi credentials and the API key go only in `secrets.yaml` (excluded by `.gitignore`).
- Agree on flashing or erasing the board with Janne first.
- Add findings from tests on the device here; the schematic and `esptool` take precedence over older notes.
- Write long-running build logs unbuffered to `logs/`, so they can be followed live.

## Open points

- Home Assistant: 2026.11.0, address in `.env`, token in `secrets\ha_token.secret`. No Supervisor and therefore no add-ons: ESPHome runs on the PC.
- Mounting: landscape. Power supply and continuous operation are still open. The LDR on GPIO 34 is unused.
- Display colours: red and blue may be swapped (`color_order`); still to be checked on the device.
- The robot is connected through the fork `jannefleischer/switchbot-vacuum` (cloud, rooms, history) and the Bluetooth integration `switchbot` (live status, battery).

## Sources

- [ESPHome LVGL](https://esphome.io/components/lvgl/), [LVGL Cookbook](https://esphome.io/cookbook/lvgl/)
- [ESPHome GT911](https://esphome.io/components/touchscreen/gt911/), [mipi_spi](https://esphome.io/components/display/mipi_spi/), [Native API](https://esphome.io/components/api/)
- [Home Assistant forum: ESP32-3248S035](https://community.home-assistant.io/t/help-making-esp32-3248s035-work/748332)
- [Community pinout 3248S035C](https://github.com/rzeldent/platformio-espressif32-sunton/blob/main/esp32-3248S035C.json), [ESP3D hardware notes](https://esp3d.io/ESP3D-TFT/Version_1.X/hardware/esp32/sunton-35-3248)
