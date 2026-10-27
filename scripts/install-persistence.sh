#!/bin/sh
# install-persistence.sh — Make optimizations survive TV reboots
# Run AFTER optimize-tv.sh, over root telnet (port 23)
#
# REWRITTEN 2026-10-25. The original version of this script would have
# OVERWRITTEN /var/lib/webosbrew/startup.sh — the real Homebrew Channel boot
# script, which is what starts telnetd/dropbear, binds the update-block hosts
# file, and runs the failsafe mechanism. That file must never be replaced.
#
# The correct, safe extension point is /var/lib/webosbrew/init.d/ — an empty
# directory that startup.sh itself already calls via `run-parts` near the end
# of every normal (non-failsafe) boot. Any executable file dropped there runs
# automatically, with zero risk to HBC's own logic.
#
# Root fs is a read-only overlay (`overlay (ro, lowerdir=/mnt/bsppart/bsp:/)`)
# with no writable upper layer, so /etc/init/*.override files (the usual way
# to disable an Upstart job) are not possible here. Instead, this hook
# proactively calls `initctl stop` on boot, before the ~30s resourcemon delay
# in webos-preload-manager's own Upstart job lets it do real preloading work.

LOG="/tmp/persistence.log"
echo "=== Installing Persistence Hook (init.d, not startup.sh) ===" | tee "$LOG"
date | tee -a "$LOG"

HOOK="/var/lib/webosbrew/init.d/50-lgtv-tune"

cat > "$HOOK" << 'HOOK_EOF'
#!/bin/sh
# Installed by lgtv-tune. Runs at every boot via webosbrew startup.sh's
# run-parts call to /var/lib/webosbrew/init.d — NOT by editing startup.sh.
initctl stop webos-preload-manager 2>/dev/null || true
initctl stop contentminer 2>/dev/null || true
echo 10 > /proc/sys/vm/swappiness 2>/dev/null

# Auto-launch the custom home screen shortly after boot. Backgrounded with a
# delay so this hook itself returns immediately (run-parts/boot isn't
# blocked waiting on it) and so the app manager has had time to come up --
# this only auto-launches an app, it does not touch the physical Home
# button's own target, which still opens webOS's stock launcher.
(
  sleep 15
  luna-send-pub -n 1 luna://com.webos.applicationManager/launch '{"id":"com.lgtvtune.homescreen"}' >/dev/null 2>&1
) &
HOOK_EOF

chmod +x "$HOOK"
echo "Hook installed: $HOOK" | tee -a "$LOG"
cat "$HOOK" | tee -a "$LOG"

echo "" | tee -a "$LOG"
echo "=== PERSISTENCE INSTALLED ===" | tee -a "$LOG"
echo "Update-block flag, if not already set, should also be touched:" | tee -a "$LOG"
echo "  touch /var/luna/preferences/webosbrew_block_updates" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "Reboot the TV, then verify with:" | tee -a "$LOG"
echo "  initctl list | grep -iE 'preload|content'   (expect: stop/waiting)" | tee -a "$LOG"
echo "  cat /proc/sys/vm/swappiness                 (expect: 10)" | tee -a "$LOG"
echo "  ls /var/luna/preferences/webosbrew_block_updates" | tee -a "$LOG"
