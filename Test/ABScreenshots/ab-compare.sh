#!/bin/sh
# ab-compare.sh - pixel A/B test of Eau against a reference revision
#
# SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
#
# A = a git ref (default origin/dev) built in a temporary worktree,
# B = this working tree.  Both are driven by the same abharness binary under
# Xvfb at every requested GSScaleFactor and decoration mode, twice for A so
# harness noise shows up as A-vs-A differences.  See README.md.
#
# usage: ab-compare.sh [-r REF] [-s "1 1.4 2"] [-d "eau bare wm"] [-w WM]
#                      [-m "full quick"] [-o OUTDIR] [-b] [-k] [-S]
#   -r REF     reference revision (default origin/dev)
#   -s SCALES  GSScaleFactor values (default "1 1.4")
#   -d DECOS   decoration modes (default "eau bare", plus "wm" with -w):
#              eau  - no window manager, Eau draws the titlebars
#              bare - no window manager, GSBackHandlesWindowDecorations YES
#              wm   - the window manager WM decorates (the Gershwin desktop)
#   -w WM      window manager binary for the wm mode, e.g. a built
#              gershwin-windowmanager's WindowManager.app/WindowManager
#   -m MODES   capture modes (default "full quick")
#   -o OUTDIR  where screenshots and the report go (default ./ab-out)
#   -b         keep the A runs already in OUTDIR and run only B again
#   -k         keep the reference worktree afterwards
#   -S         leave GBAutoSheets on (by default both sides run with it off,
#              so modal alerts stay comparable with pre-sheet references)
# Exit status: number of images that differ between A and B.

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
REF=origin/dev
SCALES="1 1.4"
DECOS=
WM=
MODES="full quick"
OUT="$PWD/ab-out"
ONLYB=0
KEEP=0
AUTOSHEETS=NO
while getopts r:s:d:w:m:o:bkS opt; do
  case $opt in
    r) REF=$OPTARG ;;
    s) SCALES=$OPTARG ;;
    d) DECOS=$OPTARG ;;
    w) WM=$OPTARG ;;
    m) MODES=$OPTARG ;;
    o) OUT=$OPTARG ;;
    b) ONLYB=1 ;;
    k) KEEP=1 ;;
    S) AUTOSHEETS=YES ;;
    *) sed -n '11,27p' "$0"; exit 64 ;;
  esac
done
case $OUT in /*) ;; *) OUT="$PWD/$OUT" ;; esac
if [ -z "$DECOS" ]; then
  DECOS="eau bare"
  [ -n "$WM" ] && DECOS="$DECOS wm"
fi
for d in $DECOS; do
  case $d in
    eau|bare) ;;
    wm) [ -x "$WM" ] || { echo "ab-compare: the wm mode needs -w <window manager binary>" >&2; exit 64; } ;;
    *) echo "ab-compare: unknown decoration mode $d" >&2; exit 64 ;;
  esac
done
case $WM in ''|/*) ;; *) WM="$PWD/$WM" ;; esac

for tool in xvfb-run import compare convert montage git gmake; do
  command -v $tool >/dev/null 2>&1 || { echo "ab-compare: $tool is required" >&2; exit 69; }
done
# shellcheck disable=SC1091
. /System/Library/Makefiles/GNUstep.sh
export LD_LIBRARY_PATH="/System/Library/Libraries${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# Only now: GNUstep.sh reads unset variables.
set -u

if [ $ONLYB -eq 1 ]; then
  [ -d "$OUT/runs" ] || { echo "ab-compare: -b needs the runs of an earlier report in $OUT" >&2; exit 64; }
  rm -rf "$OUT"/runs/B_* "$OUT/diff"
else
  rm -rf "$OUT"
fi
mkdir -p "$OUT/runs" "$OUT/diff" "$OUT/cache"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ab-compare.XXXXXX")
cleanup()
{
  if [ $KEEP -eq 0 ]; then
    git -C "$REPO" worktree remove --force "$WORK/A" 2>/dev/null
    rm -rf "$WORK"
  else
    echo "reference worktree kept at $WORK/A"
  fi
}
trap cleanup EXIT

build()
{
  echo "building $1"
  (cd "$1" && gmake > "$OUT/build-$2.log" 2>&1) || { echo "build of $2 failed, see $OUT/build-$2.log" >&2; exit 70; }
}

git -C "$REPO" worktree add --detach "$WORK/A" "$REF" > /dev/null 2>&1 \
  || { echo "cannot check out $REF" >&2; exit 65; }
# In wm mode the window manager itself runs the tree's Eau.theme, so a run
# of A is decorated by A's theme and a run of B by B's - a regression in how
# the window manager's own decorations draw would otherwise never show up.
build "$WORK/A" A
build "$REPO" B
build "$HERE" harness

# One run: theme and behaviors bundle (if the revision has one) of tree $2.
# deco eau: Eau draws the titlebars and libs-gui loads the bundle through
# GSAppKitUserBundles.  deco bare and wm: the Gershwin desktop's setup -
# the window manager decorates (GSBackHandlesWindowDecorations YES, as in
# its NSGlobalDomain) and, with no GSAppKitUserBundles, the theme loads the
# bundle itself from a Library/Bundles directory (here the private HOME's),
# later than libs-gui would.  bare has no window manager at all, wm runs
# the real one in the same display.
run()
{
  name=$1 tree=$2 scale=$3 quick=$4 deco=$5
  dir="$OUT/runs/$name"
  rm -rf "$dir"
  mkdir -p "$dir/home"
  if [ $deco = eau ]; then decorations=NO; else decorations=YES; fi
  set -- -GSTheme "$tree/Eau.theme" -GSBackHandlesWindowDecorations $decorations \
    -GSScaleFactor "$scale" -GBAutoSheets "$AUTOSHEETS"
  if [ -d "$tree/Behaviors/GershwinBehaviors.bundle" ]; then
    if [ $deco = eau ]; then
      set -- "$@" -GSAppKitUserBundles "(\"$tree/Behaviors/GershwinBehaviors.bundle\")"
    else
      mkdir -p "$dir/home/Library/Bundles"
      ln -s "$tree/Behaviors/GershwinBehaviors.bundle" "$dir/home/Library/Bundles/"
    fi
  fi
  if [ $deco = wm ]; then
    set -- "$HERE/ab-withwm.sh" "$WM" "$dir/wm-log.txt" "$HERE/abharness.app/abharness" "$@"
    # The window manager is a themed GNUstep app itself: it must draw with
    # the same tree's theme (and load the same tree's behaviors bundle,
    # through the Library/Bundles symlink already set up above, from the
    # same private HOME) as the client it is deciding under - otherwise a
    # regression in how B's Eau draws the window manager's own decorations
    # would never show up.  Without compositing: its fades and translucent
    # menus would still be blending when a capture is taken, so two runs of
    # A would differ.
    WM_ARGS="-dc -GSTheme $tree/Eau.theme -GSScaleFactor $scale"
  else
    set -- "$HERE/abharness.app/abharness" "$@"
    WM_ARGS=
  fi
  # A private HOME keeps the user's defaults out; C locale and UTC keep text
  # and dates identical between runs.
  if [ "$quick" = 1 ]; then export AB_QUICK=1; else unset AB_QUICK; fi
  WM_ARGS="$WM_ARGS" AB_OUT="$dir" HOME="$dir/home" XDG_CACHE_HOME="$OUT/cache" LANG=C LC_ALL=C TZ=UTC \
    timeout -s KILL 400 xvfb-run -a -s "-screen 0 1600x1200x24 -dpi 96" "$@" > "$dir/log.txt" 2>&1
  echo "  $name: $(ls "$dir"/*.png 2>/dev/null | wc -l) screenshots"
}

# Runs are serial: two GNUstep apps on separate Xvfb displays stall each other.
for s in $SCALES; do
  for deco in $DECOS; do
    for mode in $MODES; do
      q=0; [ $mode = quick ] && q=1
      if [ $ONLYB -eq 0 ]; then
        run "A_${deco}_${mode}_s$s" "$WORK/A" "$s" $q $deco
        run "A2_${deco}_${mode}_s$s" "$WORK/A" "$s" $q $deco
      fi
      run "B_${deco}_${mode}_s$s" "$REPO" "$s" $q $deco
    done
  done
done

# Differing pixels between two screenshots, or "missing".
ae()
{
  [ -f "$1" ] && [ -f "$2" ] || { echo missing; return; }
  compare -metric AE "$1" "$2" "$3" 2>&1 >/dev/null
}

REPORT="$OUT/RESULTS.md"
{
  echo "# Eau A/B pixel test"
  echo
  echo "A = \`$REF\` ($(git -C "$WORK/A" rev-parse --short HEAD)), B = working tree ($(git -C "$REPO" rev-parse --short HEAD)$(git -C "$REPO" diff --quiet || echo ', modified')). Scales: $SCALES. Decorations: $DECOS."
  echo
  echo "## A vs B"
  echo
  echo "Per-window captures (\`*w_*\`) are of the client window only, so a window"
  echo "manager's frame never counts."
  echo
  echo "| deco | mode | scale | image | A vs A (noise) | A vs B |"
  echo "|---|---|---|---|---|---|"
} > "$REPORT"

deviations=0
noisy=0
for s in $SCALES; do
  for deco in $DECOS; do
    for mode in $MODES; do
      r="${deco}_${mode}_s$s"
      A="$OUT/runs/A_$r" A2="$OUT/runs/A2_$r" B="$OUT/runs/B_$r"
      for f in "$A"/*.png; do
        [ -f "$f" ] || continue
        n=$(basename "$f" .png)
        d="$OUT/diff/${r}_$n"
        noise=$(ae "$f" "$A2/$n.png" /dev/null)
        diff=$(ae "$f" "$B/$n.png" "$d-diff.png")
        if [ "$diff" = 0 ]; then
          rm -f "$d-diff.png"
        else
          deviations=$((deviations + 1))
          [ -f "$B/$n.png" ] && montage -label A "$f" -label B "$B/$n.png" -label diff "$d-diff.png" \
            -tile 3x1 -geometry +4+4 "$d-AB.png" 2>/dev/null && rm -f "$d-diff.png"
        fi
        [ "$noise" = 0 ] || noisy=$((noisy + 1))
        echo "| $deco | $mode | $s | $n | $noise | $diff |" >> "$REPORT"
      done
    done
  done
done
{
  echo
  echo "$deviations image(s) differ between A and B; $noisy image(s) differ between two runs of A (harness noise)."
  echo "Side-by-side A | B | diff images for every deviation are in \`diff/\`."
} >> "$REPORT"

# Metrics: the same layout with and without a window manager.
metrics_flags=0
case " $DECOS " in
  *" wm "*)
    case " $DECOS " in
      *" bare "*)
        {
          echo
          echo "## Metrics with and without the window manager"
          echo
          echo "Content sizes and every view, text rect and field editor frame, in device"
          echo "pixels inside the content view (\`*.metrics\` next to each screenshot),"
          echo "from the wm runs against the bare runs.  Window placement and frames"
          echo "belong to the window manager and are not compared."
          echo
        } >> "$REPORT"
        for s in $SCALES; do
          for mode in $MODES; do
            python3 "$HERE/ab-metrics.py" "$s" "$mode" \
              "$OUT/runs/A_bare_${mode}_s$s" "$OUT/runs/A_wm_${mode}_s$s" \
              "$OUT/runs/B_bare_${mode}_s$s" "$OUT/runs/B_wm_${mode}_s$s" >> "$REPORT"
            metrics_flags=$((metrics_flags + $?))
          done
        done
        ;;
    esac
    ;;
esac

echo
grep 'image(s) differ between A and B' "$REPORT"
[ $metrics_flags -eq 0 ] || echo "metrics: $metrics_flags flagged difference(s), see the report" >&2
echo "report: $REPORT"
[ $noisy -eq 0 ] || echo "warning: A differs from itself - results are not trustworthy until that is 0" >&2
exit $deviations
