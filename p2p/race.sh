#!/usr/bin/env bash

# Race test: K senders `sync send` CONCURRENTLY into one `--hub`
# peer while the hub posts locally (L posts). Every action must
# end up in the hub's `list order`. Then each sender re-sends
# sequentially, to see whether lost actions are recovered.
# Freechains takes no lock and moves HEAD without compare-and-
# swap, so lost actions are expected (see 260924-topology.md).
# usage: p2p/race.sh [senders] [posts-per-sender] [hub-posts]
# env:   PORT (18399), TMP (fresh mktemp dir), ROUNDS (3)

set -uo pipefail
K=${1:-8}
M=${2:-5}
L=${3:-10}
PORT=${PORT:-18399}
ROUNDS=${ROUNDS:-3}
TMP=${TMP:-$(mktemp -d)}
A=/race

#--[[
#-- Run freechains on one peer root.
#-- Inputs:
#--  - $1 [string]: peer name (dir under $TMP)
#--  - $@ [strings]: freechains arguments
#-- Outputs:
#--  - stdout/stderr of freechains
#-- Callers:
#--  - round, main [race.sh]
#--]]
fc () {
    local r=$1
    shift
    freechains --root="$TMP/$r" "$@"
}

#--[[
#-- Post one inline message on a peer, signed by the peer's key.
#-- Inputs:
#--  - $1 [string]: peer name
#--  - $2 [string]: text
#-- Outputs:
#--  - stdout: the new cid (or an error line)
#-- Callers:
#--  - round [race.sh]
#--]]
post () {
    fc "$1" chain $A post --sign="$TMP/keys/$1" inline "$2" 2>&1 | tail -1
}

#--[[
#-- One race round: senders post, then all send at once while
#-- the hub posts; then check the hub, re-send, check again.
#-- Inputs:
#--  - $1 [integer]: round number
#-- Outputs:
#--  - stdout: one summary line
#-- Callers:
#--  - main [race.sh]
#--]]
round () {
    local n=$1 exp=$TMP/exp-$n
    : > "$exp"
    for i in $(seq 1 "$K"); do
        for j in $(seq 1 "$M"); do
            post "s$i" "r$n s$i p$j" >> "$exp"
        done
    done
    # the race: K sends + L hub posts, all at once
    local pids=()
    for i in $(seq 1 "$K"); do
        fc "s$i" chain $A sync send localhost:"$PORT" \
            > "$TMP/send-$n-$i.log" 2>&1 &
        pids+=($!)
    done
    local hpids=()
    for j in $(seq 1 "$L"); do
        post hub "r$n hub p$j" >> "$exp" &
        hpids+=($!)
    done
    local fails=0
    for p in "${pids[@]}"; do
        wait "$p" || fails=$((fails+1))
    done
    for p in "${hpids[@]}"; do
        wait "$p"
    done
    local bad
    bad=$(grep -cvE '^[0-9a-f]{40}$' "$exp")
    grep -vE '^[0-9a-f]{40}$' "$exp" | sort | uniq -c | sort -rn \
        | head -3 | sed "s/^/    post error: /"
    # check: every expected cid in the hub's order
    fc hub chain $A list order > "$TMP/order-$n" 2>&1
    local lost
    lost=$(grep -E '^[0-9a-f]{40}$' "$exp" | grep -cvFf "$TMP/order-$n")
    # recovery: sequential re-sends
    for i in $(seq 1 "$K"); do
        fc "s$i" chain $A sync send localhost:"$PORT" \
            >> "$TMP/resend-$n.log" 2>&1
    done
    fc hub chain $A list order > "$TMP/order2-$n" 2>&1
    local lost2
    lost2=$(grep -E '^[0-9a-f]{40}$' "$exp" | grep -cvFf "$TMP/order2-$n")
    local reps
    reps=$(fc hub chain $A reps member "$TMP/keys/s1.pub" 2>&1 | tail -1)
    echo "round $n: actions $(wc -l < "$exp")  post errors $bad" \
         " send fails $fails  lost $lost  lost after resend $lost2" \
         " reps(s1) $reps"
}

# setup: hub (open chain, daemon --hub), K senders cloned
mkdir -p "$TMP/keys"
for p in hub $(seq -f 's%g' 1 "$K"); do
    ssh-keygen -t ed25519 -N '' -C '' -f "$TMP/keys/$p" -q
done
fc hub chains add $A init > /dev/null
fc hub daemon start --hub --port="$PORT" > "$TMP/daemon.log" 2>&1 &
sleep 1
for i in $(seq 1 "$K"); do
    fc "s$i" chains add $A clone "$TMP/hub/chains/race/" > /dev/null
done
echo "== race: senders=$K posts=$M hub-posts=$L rounds=$ROUNDS tmp=$TMP"

for n in $(seq 1 "$ROUNDS"); do
    round "$n"
done

fc hub daemon stop --port="$PORT" > /dev/null 2>&1
echo "== send errors (by message):"
cat "$TMP"/send-*.log | grep 'ERROR' | sed 's/^remote: //; s/[0-9a-f]\{40\}/<cid>/g; s#/tmp/[^ ]*#<path>#g' \
    | cut -c1-140 | sort | uniq -c | sort -rn | head -8
