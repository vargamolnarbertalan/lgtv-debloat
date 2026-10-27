#!/bin/sh
# optimize-tv.sh — Run on TV after rooting, over root telnet (port 23)
# Model: 43UM7000PLA | webOS 4.10.2-29 | Firmware: 05.40.97 | Telekom HU region
#
# VERIFIED against the real device on 2026-10-25 — this replaces an earlier
# version written speculatively before shell access existed. Key corrections:
#   - This device has ZERO systemd units (`systemctl list-units` returns 0).
#     Preload/content-recommendation are Upstart jobs, not systemd services.
#   - com.webos.service.livePlus / ACR luna methods DO NOT EXIST on this
#     region/firmware build — the original script's calls were silent no-ops.
#     Dropped rather than kept as fake coverage.
#   - Telemetry phone-home (rdxd/uploadd spool dirs) is ALREADY neutered by
#     Homebrew Channel's own startup.sh via read-only bind mounts, every boot,
#     unconditionally. Nothing to do here.
#   - Firmware-update blocking has a native HBC mechanism: touching
#     /var/luna/preferences/webosbrew_block_updates makes startup.sh bind-mount
#     a patched /etc/hosts itself. Hand-editing /etc/hosts directly is both
#     unnecessary and not persistent (root fs is read-only overlay).
#   - / is `overlay (ro, lowerdir=/mnt/bsppart/bsp:/)` — fully read-only, no
#     writable upper layer. /etc/init/*.override is NOT possible. Never try
#     to remount root read-write (HBC's own boot script prints an explicit
#     on-screen warning that this can brick the TV).
#
# Connect: telnet <your-tv-ip> 23   (drops straight into a root shell, no
#          login prompt — this is the exploit/HBC's always-on root telnet).
# Usage:   paste this script's contents into the telnet session, or transfer
#          it in base64 chunks (telnet has no file-transfer protocol) and
#          run: sh /tmp/optimize-tv.sh

LOG="/tmp/optimize.log"
echo "=== LG TV Optimization (verified) ===" | tee "$LOG"
date | tee -a "$LOG"

echo "" | tee -a "$LOG"
echo "--- BEFORE ---" | tee -a "$LOG"
free -m | tee -a "$LOG"

echo "" | tee -a "$LOG"
echo "--- 1. Block firmware updates (native HBC mechanism) ---" | tee -a "$LOG"
touch /var/luna/preferences/webosbrew_block_updates
ls -la /var/luna/preferences/webosbrew_block_updates | tee -a "$LOG"

echo "" | tee -a "$LOG"
echo "--- 2. Stop preload manager + content miner (Upstart jobs) ---" | tee -a "$LOG"
initctl stop webos-preload-manager 2>&1 | tee -a "$LOG"
initctl stop contentminer 2>&1 | tee -a "$LOG"

echo "" | tee -a "$LOG"
echo "--- 3. Tune swappiness ---" | tee -a "$LOG"
echo 10 > /proc/sys/vm/swappiness 2>/dev/null
cat /proc/sys/vm/swappiness | tee -a "$LOG"

echo "" | tee -a "$LOG"
echo "--- AFTER (immediate — the real RAM win only shows after a reboot," | tee -a "$LOG"
echo "    since already-preloaded Netflix/YouTube instances stay resident" | tee -a "$LOG"
echo "    until the next boot, when preload-manager no longer launches them) ---" | tee -a "$LOG"
free -m | tee -a "$LOG"

echo "" | tee -a "$LOG"
echo "=== DONE — run install-persistence.sh next, then reboot to verify ===" | tee -a "$LOG"
