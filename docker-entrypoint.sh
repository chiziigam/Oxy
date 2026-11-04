#!/bin/sh
# A headed Chromium is what gets past a retailer's bot wall; headless is refused at the
# checkout handover. Fly machines have no display, so start a virtual one and point the
# browser at it. If Xvfb is missing or dies, the browser launcher falls back to headless
# rather than the app refusing to boot.
set -e

if [ "${BROWSER_HEADLESS:-true}" = "false" ] && command -v Xvfb >/dev/null 2>&1; then
  Xvfb :99 -screen 0 "${OXY_XVFB_SCREEN:-1920x1080x24}" -nolisten tcp >/tmp/xvfb.log 2>&1 &
  export DISPLAY=:99
  # Wait for the socket rather than sleeping blind, but never block boot on it.
  i=0
  while [ $i -lt 30 ] && [ ! -S /tmp/.X11-unix/X99 ]; do
    i=$((i + 1))
    sleep 0.1
  done
  if [ -S /tmp/.X11-unix/X99 ]; then
    echo "[entrypoint] virtual display :99 ready"
  else
    echo "[entrypoint] virtual display did not start; browser will fall back to headless" >&2
  fi
fi

exec "$@"
