#!/usr/bin/env bash

# Fetches the fixed datasets into data/ (fully git-ignored).
# Sizes: ~300 MB total. sha256 prefixes checked after download.

set -euo pipefail
cd "$(dirname "$0")/data"

# <sha256-16> <file> <url>
while read -r sum file url; do
    if [ ! -e "$file" ]; then
        case "$url" in
        http*) echo "fetching $file"; curl -sL -o "$file" "$url" ;;
        *)     echo "MISSING $file: $url"; exit 1 ;;
        esac
    fi
    echo "$(sha256sum "$file" | cut -c1-16)  $file"
    [ "$(sha256sum "$file" | cut -c1-16)" = "$sum" ] || {
        echo "CHECKSUM FAIL: $file"; exit 1;
    }
done <<TABLE
598327b5ddfac398 wikimedia.chat unzip-of-old/wikimedia.chat.zip-(tpd-21)
208776c9906d5d19 yyy.mbox use-01-output-(tpd-21-usenet,-see-old/)
ed92031e75185b1e se/coffee.7z https://archive.org/download/stackexchange/coffee.stackexchange.com.7z
d94735d9b4e88e3f se/vegetarianism.7z https://archive.org/download/stackexchange/vegetarianism.stackexchange.com.7z
f98d1118f780f128 se/retrocomputing.7z https://archive.org/download/stackexchange/retrocomputing.stackexchange.com.7z
6979dc44c79cc2b0 se/interpersonal.7z https://archive.org/download/stackexchange/interpersonal.stackexchange.com.7z
3f7e3116329410a6 se/politics.7z https://archive.org/download/stackexchange/politics.stackexchange.com.7z
TABLE

# extract SE sites (derived dirs, also ignored)
for z in se/*.7z; do
    d=se/$(basename "$z" .7z)
    [ -d "$d" ] || 7z x -y -o"$d" "$z" > /dev/null
done
echo OK
