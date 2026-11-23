#!/usr/bin/env python3
# ab-metrics.py - compare abharness layout metrics with and without a WM
#
# SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
#
# usage: ab-metrics.py SCALE MODE A_BARE A_WM B_BARE B_WM
# Each argument after MODE is a run directory holding <capture>.metrics
# files (see dumpMetrics() in abmain.m).  Prints a Markdown section and
# exits with the number of flagged groups:
#   - a window's metrics that move by more than TOLERANCE device pixels
#     between the bare and the wm run of the same side (the window manager
#     must not change the theme's own layout), and
#   - any item whose wm-vs-bare change in B is not the one A shows.
import glob
import os
import sys

TOLERANCE = 1.0   # device pixels
SAME = 0.005      # rounding of the printed values
EXAMPLES = 4


def load(run):
    items = {}
    for path in sorted(glob.glob(os.path.join(run, "*.metrics"))):
        capture = os.path.basename(path)[:-len(".metrics")]
        with open(path, encoding="utf-8") as f:
            for line in f:
                parts = line.rstrip("\n").split("\t")
                if len(parts) != 5:
                    continue
                win, vpath, cls, kind, rect = parts
                items[(capture, win, vpath, kind)] = (cls, tuple(float(v) for v in rect.split()))
    return items


def delta(bare, wm):
    """Per-item change from the bare run to the wm run (None = missing)."""
    out = {}
    for key in set(bare) | set(wm):
        b, w = bare.get(key), wm.get(key)
        if b is None or w is None or b[0] != w[0]:
            out[key] = None
        else:
            out[key] = tuple(round(wv - bv, 2) for bv, wv in zip(b[1], w[1]))
    return out


def fmt(entry):
    return "missing" if entry is None else "%s %s" % (entry[0], " ".join("%g" % v for v in entry[1]))


def main():
    scale, mode, a_bare, a_wm, b_bare, b_wm = sys.argv[1:7]
    runs = {"A": (load(a_bare), load(a_wm)), "B": (load(b_bare), load(b_wm))}
    if not all(runs["A"]) or not all(runs["B"]):
        print("- scale %s, %s: metrics missing (a run failed?)\n" % (scale, mode))
        return 1
    deltas = {side: delta(*runs[side]) for side in runs}
    groups = {}

    def flag(reason, side, key, detail):
        groups.setdefault((reason, side, key[0], key[1]), []).append((key, detail))

    for side in ("A", "B"):
        bare, wm = runs[side]
        for key, d in deltas[side].items():
            if d is None or max(abs(v) for v in d) > TOLERANCE:
                flag("wm moves the theme's layout", side, key,
                     "%s -> %s" % (fmt(bare.get(key)), fmt(wm.get(key))))
    for key in set(deltas["A"]) | set(deltas["B"]):
        da, db = deltas["A"].get(key), deltas["B"].get(key)
        if da is None and db is None:
            continue
        if da is None or db is None or max(abs(x - y) for x, y in zip(da, db)) > SAME:
            flag("B's wm change differs from A's", "B", key,
                 "A %s, B %s" % ("missing" if da is None else da, "missing" if db is None else db))

    print("### scale %s, %s\n" % (scale, mode))
    if not groups:
        print("No differences beyond %g px, and B changes exactly as A does.\n" % TOLERANCE)
        return 0
    print("| check | side | capture | window | items | examples (view path, kind: detail) |")
    print("|---|---|---|---|---|---|")
    for (reason, side, capture, win), entries in sorted(groups.items()):
        entries.sort()
        examples = "<br>".join("%s %s: %s" % (k[2], k[3], d) for k, d in entries[:EXAMPLES])
        print("| %s | %s | %s | %s | %d | %s |" % (reason, side, capture, win, len(entries), examples))
    print()
    return min(len(groups), 100)


if __name__ == "__main__":
    sys.exit(main())
