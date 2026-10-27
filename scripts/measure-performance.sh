#!/bin/sh
# measure-performance.sh — Benchmark TV performance before/after
# Run over root telnet (port 23); this device has no scp-capable SSH, so
# paste this script's contents directly into the telnet session, or
# transfer via base64 chunks (see docs/ for the Python helper used in the
# 2026-10-25 session) and run: sh /tmp/measure-performance.sh
#
# FIXED 2026-10-25: this device's ps is BusyBox ps, which has no --sort flag
# (that's GNU/procps-only) — it was silently ignored before. Also, this
# device uses Upstart, not systemd (`systemctl list-units` returns 0 units),
# so service status is read via `initctl list` instead.

echo "=== TV Performance Snapshot ==="
date
uptime
echo ""

echo "--- MEMORY ---"
free -m
echo ""
cat /proc/meminfo | grep -E "MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree"

echo ""
echo "--- TOP MEMORY USERS (RSS, busybox ps has no --sort) ---"
ps aux 2>/dev/null | sort -k4 -rn | head -20

echo ""
echo "--- TOP CPU USERS ---"
ps aux 2>/dev/null | sort -k3 -rn | head -15

echo ""
echo "--- UPSTART JOBS (preload / content / telemetry-relevant) ---"
initctl list 2>/dev/null | grep -iE 'preload|content|ndp|lgpms|acr'

echo ""
echo "--- DISK USAGE ---"
df -h

echo ""
echo "--- SWAPPINESS ---"
cat /proc/sys/vm/swappiness 2>/dev/null

echo ""
echo "--- UPDATE-BLOCK FLAG ---"
ls -la /var/luna/preferences/webosbrew_block_updates 2>/dev/null || echo "not set"

echo ""
echo "--- HOME BUTTON RESPONSE (luna timing) ---"
time luna-send -n 1 'luna://com.webos.applicationManager/listRunningApps' '{}' 2>&1 | head -3

echo ""
echo "=== END SNAPSHOT ==="
