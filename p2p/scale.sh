#!/bin/sh
# Scaling: post / sync / clone cost vs chain size (no forks in the
# history, so only size changes).
# Builds one chain on peer A (posts only, 10 keys round robin, 10 min
# apart), and at each checkpoint N times, 3 reps each (median):
#  - post   : one post on A
#  - noop   : B (a copy of A, warmed up by one pull) recv A,
#             nothing new
#  - ff     : A posts 1, B recv A (fast-forward, 1 commit)
#  - merge  : A posts 1, B posts 1, B recv A (fork, 1 vs 1)
#  - clone  : a fresh peer clones A
# Usage: sh scale.sh [N1 N2 ...] (default 1000 5000 10000 34000 100000)
# Output: logs/scale.log, one line per checkpoint (secs)

cd "$(dirname "$0")" || exit 1
BASE=$(pwd)/.freechains-scale
LOG=logs/scale.log
CPS=${*:-1000 5000 10000 34000 100000}
T0=1700000000
NK=10

rm -rf $BASE
mkdir -p $BASE/keys
for k in $(seq 1 $NK); do
    ssh-keygen -t ed25519 -N '' -C '' -f $BASE/keys/k$k -q
done
A=$BASE/A
freechains --root=$A --now=$T0 chains add /s init > /dev/null || exit 1

N=0             # posts on A
NOW=$T0         # chain time of the last post

# secs since epoch, ns precision
ts () {
    date +%s.%N
}

# median of 3 numbers
med3 () {
    printf '%s\n' "$@" | sort -g | sed -n 2p
}

# one post on root $1, key index $2 (advances N and NOW)
post () {
    NOW=$((NOW + 600))
    N=$((N + 1))
    freechains --root=$1 --now=$NOW chain /s post \
        --sign=$BASE/keys/k$2 inline "post $N" > /dev/null || exit 1
}

# elapsed secs of a command
timed () {
    t=$(ts)
    # a failure stops the whole run (we are in a subshell)
    "$@" > /dev/null 2>&1 || { echo "FAIL: $*" >&2; kill $$; exit 1; }
    echo "$(ts) - $t" | bc
}

# repo of root $1
repo () {
    echo $1/chains/s/
}

echo "== start $(date +%H:%M) checkpoints: $CPS" | tee $LOG
for C in $CPS; do
    # build up to C (sweep every 1000, as peers do)
    t=$(ts)
    while [ $N -lt $C ]; do
        post $A $((N % NK + 1))
        if [ $((N % 1000)) -eq 0 ]; then
            freechains --root=$A --now=$NOW chain /s sweep > /dev/null
        fi
    done
    bt=$(echo "$(ts) - $t" | bc)
    P=""; O=""; F=""; M=""; K=""
    for r in 1 2 3; do
        B=$BASE/B
        rm -rf $B; cp -a $A $B
        # warm up: A never pulled, so B's first pull would pay a
        # one-off full payload pass (no `payloads-missing` yet)
        freechains --root=$B --now=$NOW chain /s sync recv $(repo $A) > /dev/null || exit 1
        # post (on A, keeps A ahead of B by 1)
        NOW=$((NOW + 600)); N=$((N + 1))
        P="$P $(timed freechains --root=$A --now=$NOW chain /s post --sign=$BASE/keys/k1 inline "post $N")"
        # ff: B recv A (1 new commit)
        F="$F $(timed freechains --root=$B --now=$((NOW + 60)) chain /s sync recv $(repo $A))"
        # noop: again, nothing new
        O="$O $(timed freechains --root=$B --now=$((NOW + 60)) chain /s sync recv $(repo $A))"
        # merge: A and B post concurrently, B recv A
        NOW=$((NOW + 600)); N=$((N + 1))
        freechains --root=$A --now=$NOW chain /s post --sign=$BASE/keys/k2 inline "post $N a" > /dev/null || exit 1
        freechains --root=$B --now=$NOW chain /s post --sign=$BASE/keys/k3 inline "post $N b" > /dev/null || exit 1
        M="$M $(timed freechains --root=$B --now=$((NOW + 60)) chain /s sync recv $(repo $A))"
        # clone: fresh peer
        rm -rf $BASE/C
        K="$K $(timed freechains --root=$BASE/C chains add /s clone $(repo $A))"
    done
    rm -rf $BASE/B $BASE/C
    sz=$(du -sm $(repo $A) | cut -f1)
    cm=$(git -C $(repo $A) rev-list --count HEAD)
    printf "== N=%6d commits=%6d repo=%4dMB build=%6.0fs  post=%.3f  noop=%.3f  ff=%.3f  merge=%.3f  clone=%.2f  (%s)\n" \
        $C $cm $sz $bt $(med3 $P) $(med3 $O) $(med3 $F) $(med3 $M) $(med3 $K) "$(date +%H:%M)" | tee -a $LOG
done
echo "== done $(date +%H:%M)" | tee -a $LOG
