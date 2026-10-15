#!/bin/sh
# pingwing -- redraw the README's showcase from the templates themselves.
#
#   guix shell -m manifest.scm -- ./docs/make-demo-gif.sh
#
# Nothing here is a screenshot somebody took by hand.  The script renders the
# messages through the same modules a delivery calls (docs/render-demo.scm),
# photographs each one in a headless browser, and stitches the frames into
# docs/pingwing-demo.gif -- so changing a template changes the picture, and a
# picture that disagrees with the code cannot be committed by accident.
#
# Two things about the browser are worth knowing, because both are there to
# make the output the same on every machine:
#
#   * The colour scheme is chosen with --blink-settings=preferredColorScheme,
#     not by the desktop's own theme.  A headless browser otherwise answers
#     prefers-color-scheme with whatever the machine it runs on happens to
#     prefer, so "show me the dark reading" would be a coin toss: 1 is light,
#     0 is dark, and both are passed explicitly.
#   * --disable-remote-fonts is passed, so the @font-face sources the head
#     names are left unfetched and the shots settle on the fallback stacks
#     instead of racing a download.  The picture therefore shows what a client
#     that refuses a web font sees -- no network, no timing, no surprise.
#
# Needs a Chromium-family browser and ImageMagick on the PATH; the rendered
# documents are built into tmp/demo/, which is ignored by git, and the only
# thing written under version control is the GIF itself.

set -eu

# The repository root, so the script works from any directory.  The path is
# resolved rather than left carrying a `..' -- both because every path below is
# then the one that appears in an error, and because ImageMagick's security
# policy refuses a path that still contains one.  A `cd' whose argument begins
# with a dot also cannot be redirected by a CDPATH in the caller's environment.
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

chrome=${CHROME:-google-chrome}
if ! command -v "$chrome" >/dev/null 2>&1; then
  echo "$0: no '$chrome' on the PATH; set CHROME to a Chromium-family browser" >&2
  exit 1
fi
if ! command -v magick >/dev/null 2>&1; then
  echo "$0: no 'magick' on the PATH; ImageMagick is needed to encode the GIF" >&2
  exit 1
fi

work="$root/tmp/demo"
frames="$work/frames"
shots="$work/shots"
pngs="$work/png"

rm -rf "$pngs"
mkdir -p "$frames" "$shots" "$pngs"

# 1. Render.  This writes tmp/demo/frames/<name>.html (the template's own
#    output, byte for byte) and tmp/demo/shots/<name>.html (the same document
#    with one added rule, so a message shorter than the window still paints the
#    window rather than leaving the area under it bare).  Only the second copy
#    is ever photographed.
guile "$root/docs/render-demo.scm"

# 2. Photograph.  The window is the frame: every shot is taken at the same
#    size, so the frames of the GIF line up without any cropping afterwards.
light=--blink-settings=preferredColorScheme=1
dark=--blink-settings=preferredColorScheme=0

shoot () {
  # shoot <source name> <output name> <scheme flag>
  "$chrome" \
    --headless=new --disable-gpu --no-sandbox --hide-scrollbars \
    --disable-remote-fonts --force-device-scale-factor=1 \
    --window-size=1000,990 --virtual-time-budget=5000 \
    "$3" --screenshot="$pngs/$2.png" "file://$shots/$1.html" >/dev/null 2>&1
  test -s "$pngs/$2.png" || {
    echo "$0: the browser wrote no frame for $1" >&2
    exit 1
  }
  echo "shot $2.png"
}

shoot 1-new-ticket      1-new-ticket       "$light"
shoot 2-password-reset  2-password-reset   "$light"
shoot 3-system-alert    3-system-alert     "$light"
# The same two documents again, read by a client that asks for a dark palette:
# the ticket notice, so the panel, the fact list and the button can be compared
# with their light reading, and the alert, whose monospaced block is the other
# kind of body a message carries.
shoot 1-new-ticket      4-new-ticket-dark  "$dark"
shoot 3-system-alert    5-alert-dark       "$dark"

# 3. Encode.  The light frames hold for a moment each; the dark pair holds a
#    little longer, because it is the part a reader is being asked to compare.
#    The delay that precedes a frame is the delay it is shown for, so the last
#    delay is the one the GIF loops back to.
magick -background none -loop 0 \
  -delay 100 "$pngs/1-new-ticket.png" \
  -delay 120 "$pngs/2-password-reset.png" \
  -delay 120 "$pngs/3-system-alert.png" \
  -delay 220 "$pngs/4-new-ticket-dark.png" \
  -delay 240 "$pngs/5-alert-dark.png" \
  -filter Lanczos -resize 820x -layers OptimizePlus \
  -colors 255 "$root/docs/pingwing-demo.gif"

echo "wrote docs/pingwing-demo.gif"
magick identify "$root/docs/pingwing-demo.gif" | sed 's/^/  /'
