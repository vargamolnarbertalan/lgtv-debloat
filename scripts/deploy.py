"""
deploy.py -- build, install, and launch a webOS app on the real TV.

Why this exists instead of `ares-install`/`ares-launch`: this TV's dropbear
SSH rejects a second exec-channel request per connection. This script
sidesteps SSH entirely: it uploads over the telnet root shell and
installs/launches via luna-send-pub against the same Luna services
Homebrew Channel itself uses on a non-Developer-Mode TV.

`ares-package` (pure local, no device I/O) is unaffected and still runs
separately -- see Usage.

Usage:
    cd homescreen && ares-package .
    python scripts/deploy.py homescreen com.lgtvtune.homescreen
"""
import sys
import os
import base64
import json
import glob

sys.path.insert(0, os.path.dirname(__file__))
from tv_telnet import TVShell  # noqa: E402

REPO_ROOT = os.path.join(os.path.dirname(__file__), "..")


def main():
    if len(sys.argv) < 3:
        print("Usage: python scripts/deploy.py <app-folder> <app-id>")
        print("e.g.:  python scripts/deploy.py homescreen com.lgtvtune.homescreen")
        sys.exit(1)
    app_folder, app_id = sys.argv[1], sys.argv[2]

    ipk_matches = glob.glob(os.path.join(REPO_ROOT, app_folder, "%s_*_all.ipk" % app_id))
    if not ipk_matches:
        print("No .ipk found for %s in %s -- run ares-package first." % (app_id, app_folder))
        sys.exit(1)
    local_ipk = ipk_matches[0]
    remote_ipk = "/tmp/" + os.path.basename(local_ipk)

    with open(local_ipk, "rb") as f:
        raw = f.read()
    b64 = base64.b64encode(raw).decode()

    chunk = 700
    lines = ["rm -f %s.b64 %s" % (remote_ipk, remote_ipk)]
    for i in range(0, len(b64), chunk):
        lines.append("echo '%s' >> %s.b64" % (b64[i:i + chunk], remote_ipk))
    lines.append("base64 -d %s.b64 > %s && rm -f %s.b64" % (remote_ipk, remote_ipk, remote_ipk))
    lines.append("wc -c < %s" % remote_ipk)

    sh = TVShell()
    print("--- upload %s (expect byte count = %d) ---" % (os.path.basename(local_ipk), len(raw)))
    print(sh.run("\n".join(lines), timeout=60))

    install_cmd = (
        "luna-send-pub -n 1 -f luna://com.webos.appInstallService/dev/install "
        + "'" + json.dumps({"id": app_id, "ipkUrl": remote_ipk, "subscribe": True}) + "'"
    )
    print("--- install (overwrite) ---")
    print(sh.run(install_cmd, timeout=30))

    # The install call returning success doesn't mean the system has finished
    # settling it -- launching immediately after can hit {"errorCode":-102,
    # "errorText":"app is locked"}. Retry on that specific error rather than
    # guess at a fixed delay that's either too short (still races) or wastes
    # time on every normal run.
    print("--- close if running, then launch (retries on 'app is locked') ---")
    print(sh.run(
        "luna-send-pub -n 1 luna://com.webos.applicationManager/closeByAppId "
        "'{\"id\":\"%s\"}' >/dev/null 2>&1\n"
        "sleep 1\n"
        "for i in 1 2 3 4 5; do\n"
        "  out=$(luna-send-pub -n 1 luna://com.webos.applicationManager/launch '{\"id\":\"%s\"}')\n"
        "  echo \"$out\"\n"
        "  echo \"$out\" | grep -q 'app is locked' || break\n"
        "  sleep 2\n"
        "done" % (app_id, app_id),
        timeout=30,
    ))
    sh.close()


if __name__ == "__main__":
    main()
