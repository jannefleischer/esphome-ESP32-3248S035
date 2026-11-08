#!/usr/bin/env bash
# Read-only diagnosis of slow Home Assistant updates. Changes nothing on the Pi.
STACK="$HOME/dockerhome/homeassistant"
ZIP="https://github.com/jannefleischer/switchbot-vacuum/archive/refs/heads/prod.zip"
FMT='http=%{http_code} dns=%{time_namelookup}s connect=%{time_connect}s tls=%{time_appconnect}s first_byte=%{time_starttransfer}s total=%{time_total}s bytes=%{size_download} speed=%{speed_download}B/s\n'

section() { printf '\n===== %s =====\n' "$1"; }

section "time / load"
date; uptime

section "cpu and io wait: wa column, 10 s"
vmstat 2 5

section "disk"
df -h / "$STACK" 2>/dev/null
command -v iostat >/dev/null && iostat -x 2 3

section "disk write speed test skipped; recent kernel storage errors"
sudo -n dmesg 2>/dev/null | grep -iE 'mmc|i/o error|ext4-fs error|under-voltage|throttl' | tail -n 15 || true

section "memory"
free -h

section "pi power and temperature"
command -v vcgencmd >/dev/null && { vcgencmd get_throttled; vcgencmd measure_temp; }

section "containers"
cd "$STACK" 2>/dev/null && docker compose ps
docker stats --no-stream

section "network from the pi"
ping -c 5 -q 1.1.1.1
for i in 1 2 3; do curl -s -L -o /dev/null -m 60 -w "$FMT" "$ZIP"; done

CID=$(docker ps --format '{{.ID}} {{.Image}} {{.Names}}' | grep -i 'home-assistant\|homeassistant' | head -n 1 | cut -d' ' -f1)
section "network from the HA container ($CID)"
if [ -n "$CID" ]; then
  for i in 1 2; do docker exec "$CID" curl -s -L -o /dev/null -m 60 -w "$FMT" "$ZIP"; done

  section "HA database and config size"
  docker exec "$CID" sh -c 'du -sh /config/home-assistant_v2.db* /config/custom_components 2>/dev/null'

  section "marketplace and github lines in the HA log"
  docker logs --since 1h "$CID" 2>&1 | grep -iE 'marketplace|hacs|github|504|Timeout' | tail -n 25 | cut -c1-220
fi
section "done"
