#!/usr/bin/env bash
# Собирает all-in-one.sh: один файл, который содержит все скрипты и файлы консоли
# и сам их распаковывает. Так на сервер (особенно с телефона) нужно перенести только один файл.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]:-$0}")"
OUT=all-in-one.sh
FILES="install.sh check.sh cleanup-vpn.sh send-test.sh install-console.sh
console/server.js console/lint.js console/package.json console/Dockerfile
console/public/index.html console/public/app.css console/public/app.js"

for f in $FILES; do
  [[ -f "$f" ]] || { echo "Нет файла $f" >&2; exit 1; }
  grep -q '__DMS_FILE_END__' "$f" && { echo "В $f встречается служебный маркер" >&2; exit 1; }
done

{
cat <<'HEAD'
#!/usr/bin/env bash
# ВСЁ-В-ОДНОМ: распаковывает скрипты почтового сервера и консоли отправки и запускает установку.
# Запуск от root:  CLEANUP_VPN=1 bash all-in-one.sh
#   EXTRACT_ONLY=1 — только распаковать, не запускать установку
#   INSTALL_CONSOLE=0 — не ставить веб-консоль отправки
set -euo pipefail
BUNDLE_DIR="${BUNDLE_DIR:-/opt/mailserver-src}"
mkdir -p "$BUNDLE_DIR"
HEAD
for f in $FILES; do
  echo "mkdir -p \"\$BUNDLE_DIR/$(dirname "$f")\""
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
echo "Собран $OUT ($(wc -c < "$OUT") байт, файлов: $(echo "$FILES" | wc -w))"
