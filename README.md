# lgtv-debloat

Rooting and debloating an LG webOS TV, plus a minimalist, fast-loading
home screen to replace the stock launcher's slow, ad-laden one.

**Model tested:** LG 43UM7000PLA | webOS 4.10.2-29 | Firmware 05.40.97

Sister project: a from-scratch [Plex client](https://github.com/vargamolnarbertalan/flex)
for the same TV, built for the same reason — the stock apps on this hardware
are slow and bloated.

---

## What this gets you

- **Preload manager disabled** — the single biggest RAM win. Stock webOS
  preloads Netflix and YouTube/Cobalt into RAM at every boot "to make them
  launch faster," at the cost of ~190MB permanently gone on a device with
  under 1GB total. Disabling it is the difference between 178MB and 462MB
  available RAM post-boot (see `docs/baseline-after.txt`).
- **Content-recommendation engine disabled** — the "content miner" Upstart
  job that scans your usage for recommendations.
- **Firmware updates blocked permanently** — via Homebrew Channel's own
  native mechanism, not a hand-edited `/etc/hosts` that gets wiped on
  reboot.
- **Swappiness tuned** from the stock ~60 down to 10, so data stays in RAM
  longer on a device this memory-constrained.
- **All of it survives reboots**, installed as a boot-time hook — verified
  with a real unplug/replug, not just a soft reboot.
- **(In progress)** a minimal custom home screen — just a clock and your
  installed apps, nothing else — auto-launched at boot in place of the
  stock launcher's slower one. See `homescreen/`.

### What this does **not** touch
HDMI inputs, ARC/eARC, CEC, Netflix/YouTube/streaming apps themselves, or
the Magic Remote. This only strips preloading and telemetry, it doesn't
remove any app you'd actually use.

### What it couldn't do on this firmware/region
Live Plus / ACR (LG's automatic content recognition) doesn't exist as a
service on this Telekom HU regional build — there was nothing to disable.
Telemetry phone-home (NDP/LGPMS) turned out to already be neutered by
Homebrew Channel itself, unconditionally, on every boot — also nothing left
to do there. Worth checking on your own region/firmware before assuming
either step is needed.

---

## Prerequisites

- An LG webOS TV whose firmware is rootable via a known exploit. Check
  [cani.rootmy.tv](https://cani.rootmy.tv) for your exact model/firmware.
- This was done with [DejaVuln](https://github.com/throwaway96/dejavuln-autoroot)
  (CVE-2023-6319 variant) — get the exploit archive from that repo directly,
  it's not bundled here.
- A USB drive (FAT32 or NTFS).

---

## Step 1 — Root the TV (physical, ~5 minutes)

1. Format a USB drive as FAT32 (or use one that already is).
2. Extract the DejaVuln zip to the **root** of the USB drive — not inside a
   subfolder. You should see `autoroot.sh`, `hbchannel.ipk`, and a
   specially-named trigger directory at the drive's top level.
3. Remove the LG Developer Mode app from the TV if it's installed (it
   interferes with the exploit).
4. Plug the USB drive into the TV.
5. Open the Music app (or Media Player), navigate to the USB drive, browse
   into the exploit trigger directory, and try to play the (intentionally
   0-byte) MP3 file inside it. Playback will fail — that's expected.
6. Watch for on-screen toasts: "Installing Homebrew Channel..." then
   "Rooting complete!"
7. Eject the USB drive. Don't reboot yet.
8. In Homebrew Channel (now on your home screen), go to Settings and enable
   SSH if you want it (optional — see Step 2).

If it fails: check `autoroot.log` on the USB drive, delete `autoroot.once`
from it (or reboot) and retry. Make sure nothing was extracted into a
subfolder.

---

## Step 2 — Shell access

**Root telnet on port 23 is enabled by default** by Homebrew Channel's own
startup script, and drops straight into a root shell with **no login
prompt at all**:

```sh
telnet <your-tv-ip> 23
```

(SSH via dropbear is also available on plain port 22 if you enable it in
HBC's settings, with a default password of `alpine` unless you've already
provisioned a key — but telnet alone is enough for everything in this repo.)

Telnet has no file-transfer protocol, so `scripts/tv_telnet.py` wraps it
with a Python helper that handles command batching and base64 file
transfer in one round trip — edit the `HOST` constant at the top to your
TV's IP first.

```sh
python scripts/tv_telnet.py
```

---

## Step 3 — Run the optimization

Transfer and run, in order, over the telnet session (paste directly, or use
`TVShell.upload_text()` from `tv_telnet.py`):

1. `scripts/optimize-tv.sh` — disables preload manager + content miner,
   blocks firmware updates, tunes swappiness.
2. `scripts/install-persistence.sh` — installs a boot-time hook so all of
   the above survives reboots.

```sh
sh /tmp/optimize-tv.sh
sh /tmp/install-persistence.sh
```

---

## Step 4 — Verify after a reboot

Reboot the TV (a real unplug/replug if you want to be thorough — this was
tested that way, not just a soft reboot), then over telnet:

```sh
initctl list | grep -iE 'preload|content'          # expect: stop/waiting for both
cat /proc/sys/vm/swappiness                         # expect: 10
ls /var/luna/preferences/webosbrew_block_updates    # expect: file exists
```

`scripts/measure-performance.sh` takes a full before/after snapshot (RAM,
top processes, Upstart job status, disk, swappiness, update-block flag,
and a home-button response timing) if you want to compare your own device.

---

## Important corrections if you're starting from older/different notes

1. **Don't assume systemd.** This device has zero systemd units — the
   preload/recommendation daemons are **Upstart jobs**, managed with
   `initctl`, not `systemctl`.
2. **`/` is a fully read-only overlay filesystem**, no writable upper
   layer. `/etc/init/*.override` files — the normal way to permanently
   disable an Upstart job — can't be written. Never try to remount root
   read-write; Homebrew Channel's own boot script prints an on-screen
   warning that this can brick the TV.
3. **Never overwrite `/var/lib/webosbrew/startup.sh`.** That's Homebrew
   Channel's own boot script — it's what enables telnet/SSH, blocks
   firmware updates, and runs HBC's failsafe mechanism. The correct,
   zero-risk persistence point is the empty `/var/lib/webosbrew/init.d/`
   directory, which `startup.sh` already calls via `run-parts` on every
   normal boot. Drop an executable file there instead.
4. **BusyBox `ps` has no `--sort` flag** (that's GNU/procps-only) — use
   `ps aux | sort -k4 -rn` instead.
5. Scripts here are idempotent — safe to re-run after a factory reset and
   re-root.

---

## Repo layout

```
scripts/
  tv_telnet.py              Python helper: root shell + file upload over telnet
  optimize-tv.sh            The actual optimization (run once)
  install-persistence.sh    Makes it survive reboots (run once, after the above)
  measure-performance.sh    Before/after snapshot tool
docs/
  baseline-before.txt       Real RAM/process snapshot before optimization
  baseline-after.txt        Real RAM/process snapshot after, ~1 min post-boot
homescreen/
  A minimal webOS app: a clock and your installed apps, nothing else.
  See homescreen/README.md.
```

---

## License

MIT — see `LICENSE`.

If this saved you some RAM and a headache, [buy me a coffee](https://revolut.me/vargamolnarb).
