#!/bin/sh
# Post hoc evidence from the kept peers of one run (S1 = p00,
# L45 = p58): same order, clamps, reorders per merge.
# Queries scratch copies: `.freechains-keep/<run>` stays untouched.
# usage: ev.sh <run> <now>    (e.g. usenet-5k-lf-slot 741478668)
#  - now: chain time for `list order` (last event + 1 h)
cd "$(dirname "$0")" || exit 1
K=../.freechains-keep/$1
N=$2
T=$(mktemp -d)
for p in p00 p58; do
    cp -a $K/$p $T/
    freechains --root=$T/$p --now=$N chain /usenet list order > $T/$p.order
    git -C $T/$p/chains/usenet log --format='%H %at' HEAD > $T/$p.times
    echo "== $p order $(wc -l < $T/$p.order) md5 $(md5sum < $T/$p.order | cut -c1-8)"
done
cmp -s $T/p00.order $T/p58.order && echo "== same order" || echo "== ORDER DIFFERS"
for p in p00 p58; do
    echo "== $p clamps"
    python3 clamps.py $T/$p.order $T/$p.times
done
for p in p00 p58; do
    python3 reorders.py $T/$p 0 1 $N > $T/$p.reorders &
done
wait
for p in p00 p58; do
    echo "== $p reorders: $(head -1 $T/$p.reorders)"
    python3 sumr.py $T/$p.reorders
done
rm -rf $T
