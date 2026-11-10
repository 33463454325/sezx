#!/usr/bin/env bash
# Собирает all-in-one.sh: один файл, который содержит все скрипты и сам их распаковывает.
# Так на сервер (особенно с телефона) нужно вставить только один файл.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]:-$0}")"
OUT=all-in-one.sh
FILES="install.sh check.sh cleanup-vpn.sh send-test.sh"

{
cat <<'HEAD'
#!/usr/bin/env bash
# ВСЁ-В-ОДНОМ: распаковывает скрипты почтового сервера и запускает установку.
# Запуск от root:  CLEANUP_VPN=1 bash all-in-one.sh
#   EXTRACT_ONLY=1 — только распаковать, не запускать установку
set -euo pipefail
BUNDLE_DIR="${BUNDLE_DIR:-/opt/mailserver-src}"
mkdir -p "$BUNDLE_DIR"
HEAD
for f in $FILES; do
  echo "cat > \"\$BUNDLE_DIR/$f\" <<'__DMS_FILE_END__'"
  cat "$f"
  echo "__DMS_FILE_END__"
done
cat <<'TAIL'
chmod +x "$BUNDLE_DIR"/*.sh
echo "Скрипты распакованы в $BUNDLE_DIR"
[[ "${EXTRACT_ONLY:-0}" == "1" ]] && exit 0
exec bash "$BUNDLE_DIR/install.sh"
TAIL
} > "$OUT"
bash -n "$OUT"
echo "Собран $OUT ($(wc -c < "$OUT") байт)"
