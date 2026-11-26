#!/usr/bin/env bash
# Разворачиваем XAPK → достаём libil2cpp.so и global-metadata.dat.
# XAPK = ZIP, внутри несколько APK (base + arch splits + лок пакеты) и OBB.
# arm64 нативная либа лежит в config.arm64_v8a.apk/lib/arm64-v8a/libil2cpp.so,
# глобальная метадата — в base.apk/assets/bin/Data/Managed/Metadata/global-metadata.dat.

set -euo pipefail
XAPK="${1:?path to xapk}"
OUT="${2:-./extracted}"

mkdir -p "$OUT"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "[1/4] unpacking xapk → $work"
unzip -q -o "$XAPK" -d "$work"

echo "[2/4] finding native lib + metadata"
LIB=$(find "$work" -name "libil2cpp.so" -path "*arm64-v8a*" -print -quit)
META=$(find "$work" -name "global-metadata.dat" -print -quit)

if [[ -z "$LIB" ]]; then
    # Some xapk have split apk — unzip the arm64 split
    SPLIT=$(find "$work" -maxdepth 2 -name "*arm64_v8a*.apk" -print -quit \
            || find "$work" -maxdepth 2 -name "config.arm64*.apk" -print -quit)
    [[ -n "$SPLIT" ]] && unzip -q -o "$SPLIT" "lib/arm64-v8a/libil2cpp.so" -d "$work/split" \
        && LIB="$work/split/lib/arm64-v8a/libil2cpp.so"
fi
if [[ -z "$META" ]]; then
    BASE=$(find "$work" -maxdepth 2 -name "base.apk" -print -quit)
    [[ -n "$BASE" ]] && unzip -q -o "$BASE" "assets/bin/Data/Managed/Metadata/global-metadata.dat" -d "$work/base" \
        && META="$work/base/assets/bin/Data/Managed/Metadata/global-metadata.dat"
fi

[[ -f "$LIB"  ]] || { echo "libil2cpp.so not found"; exit 1; }
[[ -f "$META" ]] || { echo "global-metadata.dat not found"; exit 1; }

echo "[3/4] copying"
cp "$LIB"  "$OUT/libil2cpp.so"
cp "$META" "$OUT/global-metadata.dat"
sha256sum "$OUT/libil2cpp.so" "$OUT/global-metadata.dat" > "$OUT/SHA256"

echo "[4/4] done"
ls -la "$OUT"
