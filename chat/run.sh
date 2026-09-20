#!/usr/bin/env bash

# Runs the 10k wikimedia chat simulation against the WORKING TREE
# freechains (not the installed one), then sweeps and reports the
# final disk floor.
# SINGLE INSTANCE: chat-02.lua wipes ../.freechains on start.

set -euo pipefail
cd "$(dirname "$0")"

# working-tree freechains first in PATH (chat-02 calls `freechains`)
: <<'SKIP'
VCS=/x/x/freechains/vcs
BIN=$(mktemp -d)
cat > "$BIN/freechains" <<EOF
#!/usr/bin/env bash
exec env LUA_PATH="$VCS/src/?.lua;$VCS/src/?/init.lua;;" \\
    lua5.4 $VCS/src/freechains.lua "\$@"
EOF
chmod +x "$BIN/freechains"
export PATH="$BIN:$PATH"
SKIP

# the sim: ~45min for N=10000; progress + disk every 500 msgs
time lua5.4 chat-02.lua 2>&1 | tee chat-02.log

# final floor: explicit gc (sweep), then measure
ROOT=$(realpath -m ../.freechains)/root
freechains --root="$ROOT" chain '#chat' sweep
DIR="$ROOT/chains/#chat/"
du -sh "$DIR"
git -C "$DIR" count-objects -vH
