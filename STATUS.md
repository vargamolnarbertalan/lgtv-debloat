# Status

**Model:** 43UM7000PLA | webOS 4.10.2-29 | Firmware 05.40.97

---

## What is done

| Step | Status | Notes |
|------|--------|-------|
| Rooting via DejaVuln | DONE | |
| Homebrew Channel installed | DONE | webosbrew 0.7.3, root status "ok" |
| Quick Start+ disabled | DONE | |
| Root shell access | DONE | Telnet port 23, passwordless |
| Block firmware updates | DONE | Native HBC flag file |
| Disable preload manager | DONE | Upstart job, stopped + hooked to stay stopped |
| Disable content miner (recommendations) | DONE | Same mechanism |
| Swappiness tuned to 10 | DONE | |
| Reboot verification | DONE | Confirmed after a full unplug/replug — all four changes survived |
| ACR / Live Plus disable | N/A | `com.webos.service.livePlus` **does not exist** on this firmware/region (Telekom HU, webOS 4.10.2). Nothing to disable. |
| Telemetry (NDP / LGPMS) disable | ALREADY DONE by HBC | HBC's own `startup.sh` unconditionally read-only-bind-mounts the telemetry spool dirs to an empty dir on every boot. No telemetry processes were found running. |
| Persistence via boot hook | DONE | Via `/var/lib/webosbrew/init.d/`, not `startup.sh` or Upstart `.override` files — see corrections below |
| Minimal home screen (apps + clock) | IN PROGRESS | See `homescreen/` |
| Home screen auto-launch at boot | IN PROGRESS | Extends the same init.d hook used for the optimizations above |

---

## Important corrections (read before reusing older notes)

1. **This device has zero systemd units.** `systemctl list-units --type=service --all` returns 0. The real preload/recommendation daemons are **Upstart jobs** (`webos-preload-manager`, `contentminer`), managed with `initctl`.
2. **`/` is a fully read-only overlay** (`overlay (ro, lowerdir=/mnt/bsppart/bsp:/)`), no writable upper layer. `/etc/init/*.override` files (the normal way to permanently disable an Upstart job) **cannot be written**. HBC's own boot script prints an explicit on-screen warning that touching system partitions can brick the TV — don't attempt to remount root read-write.
3. **Never overwrite `/var/lib/webosbrew/startup.sh`** — that's HBC's own telnet/SSH-enable logic, update-block hosts handling, and failsafe mechanism. The correct, safe extension point — which HBC's startup.sh already calls via `run-parts` — is the empty directory `/var/lib/webosbrew/init.d/`. A hook is installed at `/var/lib/webosbrew/init.d/50-lgtv-tune`.
4. **Persistence for the two Upstart jobs**: since `.override` files aren't possible, the init.d hook actively calls `initctl stop webos-preload-manager` and `initctl stop contentminer` on every boot, early enough (before `resourcemon`'s ~30s CPU-settle delay) to pre-empt real preload work.
5. **BusyBox `ps` has no `--sort` flag** (GNU/procps-only) — use `ps aux | sort -k4 -rn` instead.
6. All scripts in `scripts/` are safe to re-run (idempotent) — e.g. after a factory reset + re-root.

---

## Result — verified after a full unplug/replug reboot

All four optimization changes survived:

```
initctl list | grep -iE 'preload|content'   → webos-preload-manager stop/waiting
                                               contentminer stop/waiting
cat /proc/sys/vm/swappiness                  → 10
ls /var/luna/preferences/webosbrew_block_updates  → exists
/etc/hosts  → HBC auto-regenerated it with the LG update-server block entries
```

RAM, ~1 min post-boot vs. the old baseline (~14 min post-boot, old config):

| | available RAM | Netflix/YouTube preloaded? |
|---|---|---|
| Before | 178 MB | Yes (~91MB + ~96MB) |
| After | 462 MB | No — absent from top memory users entirely |

Not a perfectly matched comparison (different uptime at capture time), but
the qualitative result is unambiguous: preload-manager is no longer loading
Netflix/Cobalt into RAM at boot, and that ~190MB is simply not spent anymore
on a device with under 1GB total. Full detail in `docs/baseline-after.txt`.

**Original goal checklist:**
- [x] Kill preload manager (biggest RAM hog) — done, verified persistent
- [x] Block firmware updates permanently — done, verified persistent, via HBC's native mechanism
- [x] Kill telemetry / phone-home — already done by HBC itself out of the box
- [x] All changes persist across reboots — verified via real unplug/replug
- [N/A] Kill ACR / Live Plus — feature doesn't exist on this firmware/region
- [ ] Home button response under 1 second — not explicitly re-timed since the optimization; `measure-performance.sh`'s last line gives a quick way to check

## Optional follow-up (not required — telnet already gives full root)

Add a public key to `/home/root/.ssh/authorized_keys` (chmod 600, owned by
root) via telnet, then SSH on port 22 works without the `alpine` placeholder
password and without the "default password" MOTD warning.

---

## What's next: the minimal home screen

Goal: a fast, minimalist webOS app — a clock and your installed apps,
nothing else — auto-launched at boot via the same init.d hook already used
for the optimizations above, so it's the first thing you see. The actual
physical Home button still goes to webOS's own stock launcher; remapping
that key is a separate, more invasive change not attempted here.

Built the same way as the sister [Flex](https://github.com/vargamolnarbertalan/flex)
Plex client: vanilla ES5 JavaScript (this TV's embedded Chromium is version
53 — no async/await, no modern syntax), no frameworks, packaged as a
standard webOS `.ipk`. See `homescreen/README.md` for its own status.
