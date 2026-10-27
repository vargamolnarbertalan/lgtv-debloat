# homescreen

A minimal webOS home screen: a clock and your installed apps, nothing
else. Built the same way as the sister [Flex](https://github.com/vargamolnarbertalan/flex)
Plex client — vanilla ES5 JavaScript (this TV's embedded Chromium is
version 53), no frameworks, packaged as a standard webOS `.ipk`.

**Status: working scaffold.** Grid of real installed apps with real icons,
a clock, D-pad navigation, and launch — all confirmed on real hardware.
Not yet wired to the boot-time auto-launch hook in this checkout (see
`scripts/install-persistence.sh` at the repo root for that).

## Two things that don't work the way you'd expect

**`listLaunchPoints` is denied on the public Luna bus, for everyone,
including root.** A sideloaded web app calling
`com.webos.applicationManager/listLaunchPoints` via `webOS.service.request`
gets `"Denied method call \"listLaunchPoints\" for category \"/\""` — and
declaring `requiredACG: ["application.operation"]` in `appinfo.json`
(the ACG LG's own LS2 API reference lists for this method) makes no
difference. Confirmed directly over root telnet that this isn't an
app-sandbox problem at all: `luna-send-pub` (public bus) gets the exact
same denial even as root, while plain `luna-send` (**private** bus, no
`-pub`) returns the real list immediately. A sideloaded app has no private-
bus access of its own, so this app routes the call through Homebrew
Channel's own `luna://org.webosbrew.hbchannel.service/exec` service
instead — it runs the command in a real root shell on the device (the
same way this repo's own `deploy.py` installs and launches apps over
telnet), which has private-bus access. `launch` itself works fine on the
public bus with no such issue.

**App icons can't be loaded as `<img src>` at all, any URI scheme.**
`listLaunchPoints` returns each app's icon as an absolute filesystem path
into *another* app's install directory (e.g.
`/media/cryptofs/apps/usr/palm/applications/netflix/SMALL_APP_ICON.png`).
Neither the bare absolute path nor an explicit `file://` prefix loads —
WAM sandboxes a web app's resource loading to its own bundle, with no
exception for other (even system) apps' public icon assets, confirmed by
testing both directly. Fix: read the icon bytes through the same `exec`
relay (`cat '<path>' | base64`) and hand them back as a `data:` URI,
sidestepping the browser's own resource loader entirely.

## Files

```
appinfo.json      webOS app manifest
index.html        Markup + styles
src/app.js        All logic: clock, app list, grid nav, launch, icon loading
webOSTVjs-1.2.13/  Vendored webOS JS bridge (Apache 2.0, own LICENSE kept)
icon.png / largeIcon.png
```

## Build and deploy

```sh
cd homescreen
ares-package .
cd ..
python scripts/deploy.py homescreen com.lgtvtune.homescreen
```

(`scripts/deploy.py` needs `scripts/tv_config_local.py` with your real TV
IP — copy `tv_config_local.py.example` and fill it in; it's gitignored.)

## Not done yet

- Boot-time auto-launch isn't verified on a real reboot yet (the hook exists
  in `scripts/install-persistence.sh`, untested end-to-end).
- No "Settings" or any way to configure what shows in the grid — it's
  everything `listLaunchPoints` returns, unfiltered.
- No remote-control edge cases audited (Back button, long-press, etc.) —
  only D-pad Left/Right/Up/Down + Enter are wired.
- Dev-only `devlog()` beacon in `src/app.js` points at a dev-machine IP —
  harmless if nothing's listening, but should be removed or gated before
  any real-world use, same note as the sister Flex project.
