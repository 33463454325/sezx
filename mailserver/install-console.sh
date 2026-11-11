#!/usr/bin/env bash
# Установка HTTPS-консоли для ручной отправки писем (запускается после install.sh).
# Консоль открывается по адресу https://mail.dpsradar.world:8443
# и использует тот же сертификат Let's Encrypt, что и почтовый сервер.
#
# Параметры: MAIL_HOST, ACCOUNTS, INSTALL_DIR, CRED_FILE, CONSOLE_PORT
#   CONSOLE_CONFIG_ONLY=1 — только создать config.json (для проверки)
set -euo pipefail

MAIL_HOST="${MAIL_HOST:-mail.dpsradar.world}"
ACCOUNTS="${ACCOUNTS:-info@dpsradar.world mail@dpsradar.net}"
INSTALL_DIR="${INSTALL_DIR:-/opt/mailserver}"
CRED_FILE="${CRED_FILE:-/root/mail-credentials.txt}"
CONSOLE_PORT="${CONSOLE_PORT:-8443}"
CONFIG_ONLY="${CONSOLE_CONFIG_ONLY:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DATA_DIR="$INSTALL_DIR/console-data"
CFG="$DATA_DIR/config.json"

c_ok()   { printf '\033[32m[OK]\033[0m %s\n' "$*"; }
c_warn() { printf '\033[33m[!!]\033[0m %s\n' "$*"; }
c_err()  { printf '\033[31m[XX]\033[0m %s\n' "$*"; }
step()   { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

step "Установка консоли отправки писем"
if [[ "$CONFIG_ONLY" != "1" ]]; then
  [[ $EUID -eq 0 ]] || { c_err "Запустите от root"; exit 1; }
  command -v docker >/dev/null || { c_err "Docker не найден: сначала выполните install.sh"; exit 1; }
  [[ -f "/etc/letsencrypt/live/$MAIL_HOST/fullchain.pem" ]] || { c_err "Нет сертификата для $MAIL_HOST: сначала выполните install.sh"; exit 1; }
fi
command -v python3 >/dev/null || { c_err "Нужен python3 (apt-get install -y python3)"; exit 1; }
[[ -f "$CRED_FILE" ]] || { c_err "Нет файла $CRED_FILE с паролями ящиков (его создаёт install.sh)"; exit 1; }

mkdir -p "$DATA_DIR"; chmod 700 "$DATA_DIR"

# ---------------------------------------------------------------- файлы приложения
if [[ "$CONFIG_ONLY" != "1" ]]; then
  [[ -f "$SCRIPT_DIR/console/server.js" ]] || { c_err "Не найдены файлы консоли в $SCRIPT_DIR/console"; exit 1; }
  mkdir -p "$INSTALL_DIR/console/public"
  cp "$SCRIPT_DIR/console/server.js" "$SCRIPT_DIR/console/lint.js" "$SCRIPT_DIR/console/package.json" "$SCRIPT_DIR/console/Dockerfile" "$INSTALL_DIR/console/"
  cp "$SCRIPT_DIR"/console/public/* "$INSTALL_DIR/console/public/"
  c_ok "Файлы приложения скопированы"
fi

# ---------------------------------------------------------------- конфиг с паролями
NEW_PW=0
if [[ -f "$CFG" ]]; then
  ADMIN_PW="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["adminPassword"])' "$CFG")"
else
  ADMIN_PW="$(openssl rand -base64 36 | tr -dc 'A-Za-z0-9' | head -c 20)"
  NEW_PW=1
fi

ADMIN_PW="$ADMIN_PW" python3 - "$CRED_FILE" "$CFG" "$MAIL_HOST" "$CONSOLE_PORT" $ACCOUNTS <<'PY'
import json, os, sys
cred_file, cfg_path, mail_host, port, *wanted = sys.argv[1:]
creds = {}
for line in open(cred_file, encoding="utf-8"):
    parts = line.rstrip("\n").split(None, 1)
    if len(parts) == 2:
        creds[parts[0].lower()] = parts[1].strip()
cfg = {}
if os.path.exists(cfg_path):
    cfg = json.load(open(cfg_path, encoding="utf-8"))
accounts = {}
for addr in wanted:
    if addr.lower() in creds:
        old = cfg.get("accounts", {}).get(addr.lower())
        name = old.get("name", "") if isinstance(old, dict) else ""
        accounts[addr.lower()] = {"pass": creds[addr.lower()], "name": name}
    else:
        print(f"[!!] Нет пароля для {addr} в {cred_file}: этот ящик в консоли не появится", file=sys.stderr)
if not accounts:
    sys.exit("[XX] Не найдено ни одного ящика с паролем")
cfg.update({"mailHost": mail_host, "smtpHost": "127.0.0.1", "smtpPort": 587,
            "port": int(port), "accounts": accounts, "adminPassword": os.environ["ADMIN_PW"]})
cfg.setdefault("maxRecipients", 5)
cfg.setdefault("perHour", 20)
fd = os.open(cfg_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
print("[OK] Ящики в консоли: " + ", ".join(accounts))
PY
chmod 600 "$CFG"
if [[ "$NEW_PW" == "1" ]]; then
  echo "console-admin  $ADMIN_PW" >> "$CRED_FILE"
  chmod 600 "$CRED_FILE"
fi
[[ "$CONFIG_ONLY" == "1" ]] && exit 0

# ---------------------------------------------------------------- запуск контейнера
cat > "$INSTALL_DIR/console-compose.yaml" <<EOF
services:
  console:
    build: ./console
    container_name: mail-console
    network_mode: host
    restart: always
    read_only: true
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    tmpfs:
      - /tmp
    environment:
      - PORT=${CONSOLE_PORT}
      - DATA_DIR=/data
      - CONFIG_PATH=/data/config.json
    volumes:
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - ./console-data:/data
EOF
cd "$INSTALL_DIR"
docker compose -p mail-console -f console-compose.yaml up -d --build
c_ok "Контейнер консоли запущен"

if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  ufw allow "${CONSOLE_PORT}/tcp" >/dev/null && c_ok "Порт ${CONSOLE_PORT} открыт в ufw"
else
  c_warn "ufw не активен: убедитесь, что порт ${CONSOLE_PORT} открыт в панели хостинга"
fi

# ---------------------------------------------------------------- проверка
ready=0
for _ in $(seq 1 30); do
  code="$(curl -sk -o /dev/null -w '%{http_code}' "https://127.0.0.1:${CONSOLE_PORT}/" || true)"
  [[ "$code" == "200" ]] && { ready=1; break; }
  sleep 1
done
if [[ $ready -eq 1 ]]; then c_ok "Консоль отвечает"; else c_err "Консоль не ответила. Логи: docker logs mail-console"; fi

cat <<EOF

Консоль:   https://${MAIL_HOST}:${CONSOLE_PORT}
EOF
if [[ "$NEW_PW" == "1" ]]; then
  echo "Пароль:    $ADMIN_PW   (сохранён в $CRED_FILE как console-admin)"
else
  echo "Пароль:    не менялся, смотрите строку console-admin в $CRED_FILE"
fi
cat <<EOF

Защита от спама уже включена: вход по паролю, отправка только с ваших ящиков,
не больше 5 получателей, лимит в час и в сутки (растёт по мере «прогрева» IP),
проверка домена получателя и текста письма.
Настройки лимитов:  $CFG   (после правки: docker restart mail-console)
Логи:               docker logs mail-console
EOF
