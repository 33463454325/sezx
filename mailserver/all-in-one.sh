#!/usr/bin/env bash
# ВСЁ-В-ОДНОМ: распаковывает скрипты почтового сервера и запускает установку.
# Запуск от root:  CLEANUP_VPN=1 bash all-in-one.sh
#   EXTRACT_ONLY=1 — только распаковать, не запускать установку
set -euo pipefail
BUNDLE_DIR="${BUNDLE_DIR:-/opt/mailserver-src}"
mkdir -p "$BUNDLE_DIR"
cat > "$BUNDLE_DIR/install.sh" <<'__DMS_FILE_END__'
#!/usr/bin/env bash
# Полный почтовый сервер на docker-mailserver для нескольких доменов.
# SMTP (25/465/587) + IMAP (993), DKIM/SPF/DMARC, антиспам Rspamd, Fail2ban, Let's Encrypt.
#
# Запуск от root (Ubuntu 22.04/24.04 или Debian 12):
#   sudo bash install.sh
#
# Параметры (переменные окружения):
#   MAIL_HOST=mail.dpsradar.world          — имя сервера (его A и PTR)
#   ACCOUNTS="info@dpsradar.world mail@dpsradar.net"  — ящики (можно с любых ваших доменов)
#   CLEANUP_VPN=1                          — сначала удалить VPN-ПО (освободить порты)
#   SKIP_CHECKS=1                          — продолжать даже при неуспешных проверках
set -euo pipefail

MAIL_HOST="${MAIL_HOST:-mail.dpsradar.world}"
PRIMARY_DOMAIN="${MAIL_HOST#*.}"                         # dpsradar.world
ACCOUNTS="${ACCOUNTS:-info@dpsradar.world mail@dpsradar.net}"
INSTALL_DIR="${INSTALL_DIR:-/opt/mailserver}"
CRED_FILE="/root/mail-credentials.txt"
DMS_IMAGE="${DMS_IMAGE:-ghcr.io/docker-mailserver/docker-mailserver:latest}"
DKIM_DIR="docker-data/dms/config/rspamd/dkim"

# Список уникальных доменов из адресов
DOMAINS="$(for a in $ACCOUNTS; do echo "${a#*@}"; done | sort -u | tr '\n' ' ')"

c_ok()   { printf '\033[32m[OK]\033[0m %s\n' "$*"; }
c_warn() { printf '\033[33m[!!]\033[0m %s\n' "$*"; }
c_err()  { printf '\033[31m[XX]\033[0m %s\n' "$*"; }
step()   { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

[[ $EUID -eq 0 ]] || { c_err "Запустите от root: sudo bash $0"; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# ---------------------------------------------------------------- удаление VPN
if [[ "${CLEANUP_VPN:-0}" == "1" && -f "$SCRIPT_DIR/cleanup-vpn.sh" ]]; then
  step "Удаление VPN-ПО (по запросу CLEANUP_VPN=1)"
  bash "$SCRIPT_DIR/cleanup-vpn.sh" || c_warn "cleanup-vpn.sh завершился с ошибкой, продолжаю"
fi

# ---------------------------------------------------------------- пакеты
step "Установка необходимых пакетов"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl ca-certificates dnsutils openssl >/dev/null
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi
docker compose version >/dev/null 2>&1 || apt-get install -y -qq docker-compose-plugin >/dev/null
systemctl enable --now docker >/dev/null 2>&1 || true
c_ok "Docker: $(docker --version)"

# ---------------------------------------------------------------- проверки
step "Предварительные проверки"
PUBLIC_IP="$(curl -4 -fsS --max-time 10 https://api.ipify.org || curl -4 -fsS --max-time 10 https://ifconfig.me)"
[[ -n "$PUBLIC_IP" ]] || { c_err "Не удалось определить внешний IPv4 сервера"; exit 1; }
echo "Внешний IP сервера: $PUBLIC_IP"
echo "Домены: $DOMAINS"
FAILED=0; PTR_BAD=0

A_REC="$(dig +short A "$MAIL_HOST" @1.1.1.1 | tail -n1)"
if [[ "$A_REC" == "$PUBLIC_IP" ]]; then c_ok "A $MAIL_HOST -> $A_REC"
else c_err "A-запись $MAIL_HOST = '${A_REC:-нет}', должна быть $PUBLIC_IP"; FAILED=1; fi

PTR_REC="$(dig +short -x "$PUBLIC_IP" @1.1.1.1 | sed 's/\.$//' | head -n1)"
if [[ "$PTR_REC" == "$MAIL_HOST" ]]; then c_ok "PTR $PUBLIC_IP -> $PTR_REC"
else c_warn "PTR $PUBLIC_IP = '${PTR_REC:-нет}', должно быть $MAIL_HOST — ОБЯЗАТЕЛЬНО настройте у хостинга (иначе Gmail режет письма)."; PTR_BAD=1; fi

if timeout 10 bash -c 'exec 3<>/dev/tcp/gmail-smtp-in.l.google.com/25' 2>/dev/null; then
  c_ok "Исходящий порт 25 открыт"
else
  c_err "Исходящий порт 25 закрыт — напишите в поддержку хостинга, чтобы открыли (без него письма не уходят)"; FAILED=1
fi

REV_IP="$(awk -F. '{print $4"."$3"."$2"."$1}' <<<"$PUBLIC_IP")"
for bl in bl.spamcop.net b.barracudacentral.org dnsbl.sorbs.net; do
  [[ -n "$(dig +short "$REV_IP.$bl" A)" ]] && c_warn "IP в чёрном списке $bl"
done

if [[ $FAILED -eq 1 && "${SKIP_CHECKS:-0}" != "1" ]]; then
  c_err "Критичные проверки не пройдены. Исправьте и запустите снова (или SKIP_CHECKS=1)."
  exit 1
fi

# ---------------------------------------------------------------- firewall
step "Firewall"
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  for p in 25 80 465 587 993; do ufw allow "$p/tcp" >/dev/null; done
  c_ok "Порты 25, 80, 465, 587, 993 открыты в ufw"
else
  c_warn "ufw не активен — проверьте, что порты 25, 80, 465, 587, 993 открыты в панели хостинга"
fi

# ---------------------------------------------------------------- сертификат
step "Сертификат Let's Encrypt для $MAIL_HOST"
if ss -tlnp 2>/dev/null | grep -q ':80 '; then
  c_warn "Порт 80 занят — certbot может не получить сертификат. Запустите с CLEANUP_VPN=1 или освободите порт 80."
fi
if [[ ! -f "/etc/letsencrypt/live/$MAIL_HOST/fullchain.pem" ]]; then
  docker run --rm -p 80:80 -v /etc/letsencrypt:/etc/letsencrypt certbot/certbot \
    certonly --standalone --non-interactive --agree-tos --register-unsafely-without-email \
    -d "$MAIL_HOST"
fi
c_ok "Сертификат есть"
cat > /etc/cron.d/mailserver-certbot <<'EOF'
17 3 * * * root docker run --rm -p 80:80 -v /etc/letsencrypt:/etc/letsencrypt certbot/certbot renew --quiet --deploy-hook "docker restart mailserver"
EOF

# ---------------------------------------------------------------- docker-mailserver
step "Настройка docker-mailserver в $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
for f in check.sh cleanup-vpn.sh; do [[ -f "$SCRIPT_DIR/$f" ]] && cp "$SCRIPT_DIR/$f" "$INSTALL_DIR/$f"; done
cd "$INSTALL_DIR"
cat > compose.yaml <<EOF
services:
  mailserver:
    image: ${DMS_IMAGE}
    container_name: mailserver
    hostname: ${MAIL_HOST}
    ports:
      - "25:25"
      - "465:465"
      - "587:587"
      - "993:993"
    volumes:
      - ./docker-data/dms/mail-data/:/var/mail/
      - ./docker-data/dms/mail-state/:/var/mail-state/
      - ./docker-data/dms/mail-logs/:/var/log/mail/
      - ./docker-data/dms/config/:/tmp/docker-mailserver/
      - ./docker-data/dms/rspamd/:/var/lib/rspamd/
      - /etc/localtime:/etc/localtime:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
    environment:
      - SSL_TYPE=letsencrypt
      - POSTMASTER_ADDRESS=postmaster@${PRIMARY_DOMAIN}
      - ENABLE_RSPAMD=1
      - ENABLE_OPENDKIM=0
      - ENABLE_OPENDMARC=0
      - ENABLE_POLICYD_SPF=0
      - ENABLE_AMAVIS=0
      - ENABLE_SPAMASSASSIN=0
      - ENABLE_CLAMAV=0
      - ENABLE_FAIL2BAN=1
      - SPOOF_PROTECTION=1
      - PERMIT_DOCKER=none
      - ENABLE_POP3=0
      - POSTFIX_INET_PROTOCOLS=ipv4
      - ONE_DIR=1
      - LOG_LEVEL=info
    cap_add:
      - NET_ADMIN
    restart: always
    stop_grace_period: 1m
EOF
# Защита репутации: если чей-то ящик взломают, он не сможет разослать тысячи писем
# и сжечь IP. Лимиты только на порты отправки клиентов (587/465), входящая почта не затрагивается.
mkdir -p docker-data/dms/config
if [[ ! -f docker-data/dms/config/postfix-master.cf ]]; then
  cat > docker-data/dms/config/postfix-master.cf <<'EOF'
submission/inet/smtpd_client_message_rate_limit=30
submission/inet/smtpd_client_recipient_rate_limit=100
submissions/inet/smtpd_client_message_rate_limit=30
submissions/inet/smtpd_client_recipient_rate_limit=100
EOF
fi
docker compose pull -q
docker compose up -d
c_ok "Контейнер запущен"

dms() { docker exec mailserver setup "$@"; }

step "Почтовые ящики"
sleep 12
touch "$CRED_FILE"; chmod 600 "$CRED_FILE"
EXISTING="$(dms email list 2>/dev/null || true)"
for addr in $ACCOUNTS; do
  if grep -q "$addr" <<<"$EXISTING"; then c_ok "$addr уже существует"; continue; fi
  pass="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 20)"
  dms email add "$addr" "$pass"
  echo "$addr  $pass" >> "$CRED_FILE"
  c_ok "Создан $addr"
done

# первый ящик каждого домена — для алиасов этого домена
first_box_of() { for a in $ACCOUNTS; do [[ "${a#*@}" == "$1" ]] && { echo "$a"; return; }; done; }
for d in $DOMAINS; do
  fb="$(first_box_of "$d")"
  [[ -n "$fb" ]] || { c_warn "Для $d нет ящика — алиасы пропускаю"; continue; }
  for al in postmaster abuse dmarc; do
    printf '%s\n' $ACCOUNTS | grep -qx "${al}@${d}" && continue
    dms alias add "${al}@${d}" "$fb" 2>/dev/null && c_ok "Алиас ${al}@${d} -> $fb" || true
  done
done

step "DKIM-ключи (селектор mail, 2048 бит)"
# Явно генерируем ключ для каждого домена — так надёжнее, чем авто-режим
for d in $DOMAINS; do
  dms config dkim keysize 2048 selector mail domain "$d" 2>/dev/null \
    || dms config dkim keysize 2048 domain "$d" 2>/dev/null || true
done
docker compose restart mailserver >/dev/null
sleep 8

get_dkim() {  # $1 = домен -> печатает значение TXT
  local domain="$1" f val
  f="$(grep -rliE 'v=dkim1' "$DKIM_DIR" 2>/dev/null | grep -viE 'private|\.key$' \
        | xargs -r grep -liF "$domain" 2>/dev/null | head -n1 || true)"
  [[ -z "$f" ]] && for cand in "$DKIM_DIR"/*"$domain"*.txt "$DKIM_DIR"/*"$domain"*.pub; do
        [[ -e "$cand" && "$cand" != *private* ]] && { f="$cand"; break; }; done
  [[ -z "$f" ]] && { echo ""; return; }
  val="$(tr -d '\n\t' < "$f" | grep -o '"[^"]*"' | tr -d '"\n')"
  [[ "$val" == *p=* ]] || val="$(tr -d '\n\t "' < "$f" | grep -oE 'v=DKIM1[^)]*' | sed 's/).*//')"
  echo "$val" | tr -s ' ' | sed 's/; */; /g; s/^ *//; s/ *$//'
}

# ---------------------------------------------------------------- итог
step "ГОТОВО. Добавьте эти DNS-записи для каждого домена:"
{
echo
echo "ОБЩЕЕ (у хостинга сервера):"
echo "  PTR   $PUBLIC_IP  ->  $MAIL_HOST"
echo "  ВАЖНО: НЕ создавайте AAAA (IPv6) записи для доменов — сервер шлёт только по IPv4."
echo
for d in $DOMAINS; do
  dk="$(get_dkim "$d")"; [[ -n "$dk" ]] || dk="(ключ не найден — ls -R $INSTALL_DIR/$DKIM_DIR)"
  echo "$d:"
  if [[ "$d" == "$PRIMARY_DOMAIN" ]]; then
    echo "  A     mail             $PUBLIC_IP"
    echo "  MX    @                $MAIL_HOST   (приоритет 10)"
  else
    echo "  MX    @                $MAIL_HOST   (приоритет 10)   # нужен, чтобы ПОЛУЧАТЬ письма на этот домен"
  fi
  echo "  TXT   @                v=spf1 ip4:$PUBLIC_IP -all"
  echo "  TXT   _dmarc           v=DMARC1; p=none; rua=mailto:dmarc@$d; adkim=r; aspf=r"
  echo "  TXT   _smtp._tls       v=TLSRPTv1; rua=mailto:dmarc@$d          # необязательно, отчёты о TLS"
  echo "  TXT   mail._domainkey  $dk"
  echo
  echo "$dk" > "$INSTALL_DIR/dkim-$d.txt"
done
cat <<EOF
Пароли ящиков:  $CRED_FILE
Клиент (для каждого ящика):
  IMAP  $MAIL_HOST  993  SSL/TLS
  SMTP  $MAIL_HOST  465  SSL/TLS (или 587 STARTTLS)
  Логин — полный адрес (напр. info@$PRIMARY_DOMAIN), пароль — из файла выше.

После добавления DNS подождите ~15 мин и запустите:  bash $INSTALL_DIR/check.sh
Финальный тест доставляемости: письмо на адрес с https://www.mail-tester.com (цель 9-10/10).
EOF
} | tee "$INSTALL_DIR/DNS-RECORDS.txt"

[[ $PTR_BAD -eq 1 ]] && c_warn "PTR ещё не настроен для $PUBLIC_IP — без него Gmail не примет письма."
c_ok "Эти же записи сохранены в $INSTALL_DIR/DNS-RECORDS.txt"
exit 0
__DMS_FILE_END__
cat > "$BUNDLE_DIR/check.sh" <<'__DMS_FILE_END__'
#!/usr/bin/env bash
# Проверка DNS и состояния почтового сервера для всех доменов.
# Запуск: bash check.sh
MAIL_HOST="${MAIL_HOST:-mail.dpsradar.world}"
PRIMARY_DOMAIN="${MAIL_HOST#*.}"
ACCOUNTS="${ACCOUNTS:-info@dpsradar.world mail@dpsradar.net}"
DOMAINS="$(for a in $ACCOUNTS; do echo "${a#*@}"; done | sort -u)"
IP="$(curl -4 -fsS --max-time 10 https://api.ipify.org)"
ok=0; bad=0
chk() { if eval "$2"; then printf '\033[32m[OK]\033[0m %s\n' "$1"; ok=$((ok+1)); else printf '\033[31m[XX]\033[0m %s\n' "$1"; bad=$((bad+1)); fi; }
q() { dig +short "$@" @1.1.1.1; }

echo "== Сервер =="
chk "A $MAIL_HOST = $IP"        '[[ "$(q A "$MAIL_HOST" | tail -n1)" == "$IP" ]]'
chk "PTR $IP -> $MAIL_HOST"     '[[ "$(q -x "$IP" | sed "s/\.$//")" == "$MAIL_HOST" ]]'
chk "Контейнер mailserver"      '[[ "$(docker inspect -f "{{.State.Running}}" mailserver 2>/dev/null)" == "true" ]]'
for p in 25 465 587 993; do chk "Порт $p слушается" "timeout 5 bash -c 'exec 3<>/dev/tcp/127.0.0.1/$p' 2>/dev/null"; done
chk "Исходящий порт 25 открыт"  "timeout 10 bash -c 'exec 3<>/dev/tcp/gmail-smtp-in.l.google.com/25' 2>/dev/null"

for d in $DOMAINS; do
  echo "== $d =="
  chk "MX $d -> $MAIL_HOST"      "q MX '$d' | grep -q '$MAIL_HOST'"
  chk "SPF ($d) содержит ip4:$IP" "q TXT '$d' | grep -q 'ip4:$IP'"
  chk "DMARC ($d)"               "q TXT '_dmarc.$d' | grep -q 'v=DMARC1'"
  chk "DKIM mail._domainkey ($d)" "q TXT 'mail._domainkey.$d' | grep -q 'p='"
  f="/opt/mailserver/dkim-$d.txt"
  if [[ -s "$f" ]]; then
    want="$(grep -o 'p=MI[A-Za-z0-9+/=]*' "$f" | head -c 60)"
    [[ -n "$want" ]] && chk "DKIM в DNS совпадает с ключом сервера ($d)" \
      "q TXT 'mail._domainkey.$d' | tr -d '\" \t\n' | grep -Fq '$want'"
  fi
done

echo; echo "Итого: OK=$ok, ошибок=$bad"
echo "Финальная проверка: отправьте письмо на адрес с https://www.mail-tester.com (цель 9-10/10)."
__DMS_FILE_END__
cat > "$BUNDLE_DIR/cleanup-vpn.sh" <<'__DMS_FILE_END__'
#!/usr/bin/env bash
# Удаление распространённого VPN/proxy-ПО с сервера (освобождает порты 80/443 и др.).
# Запуск: sudo bash cleanup-vpn.sh
# Удаляет: xray, v2ray, v2raya, x-ui/3x-ui/hiddify/marzban-панели, wireguard,
#          openvpn, shadowsocks, trojan, outline (shadowbox), а также их конфиги.
# НЕ трогает: ssh, docker, системные пакеты, почтовый сервер.
set -uo pipefail
log() { printf '\033[36m[vpn-cleanup]\033[0m %s\n' "$*"; }

[[ $EUID -eq 0 ]] || { echo "Запустите от root"; exit 1; }

SERVICES="x-ui 3x-ui hiddify-panel hiddify marzban xray v2ray v2raya \
openvpn openvpn-server wg-quick@wg0 wireguard shadowsocks-libev ss-server \
trojan trojan-go sing-box tuic hysteria hysteria2 naive brook"

log "Останавливаю и отключаю сервисы..."
for s in $SERVICES; do
  if systemctl list-unit-files 2>/dev/null | grep -q "^${s}"; then
    systemctl stop "$s" 2>/dev/null
    systemctl disable "$s" 2>/dev/null
    log "  остановлен: $s"
  fi
done

log "Удаляю docker-контейнеры VPN/proxy (почтовый 'mailserver' не трогаю)..."
if command -v docker >/dev/null 2>&1; then
  for c in $(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -iE 'xray|v2ray|x-ui|3x-ui|hiddify|marzban|shadowbox|shadowsocks|trojan|outline|wireguard|wg-easy|\bvpn\b' | grep -viw mailserver); do
    docker rm -f "$c" 2>/dev/null && log "  удалён контейнер: $c"
  done
fi

log "Удаляю пакеты..."
export DEBIAN_FRONTEND=noninteractive
for p in openvpn wireguard wireguard-tools shadowsocks-libev xray v2ray; do
  dpkg -l "$p" >/dev/null 2>&1 && apt-get purge -y -qq "$p" >/dev/null 2>&1 && log "  удалён пакет: $p"
done

log "Удаляю файлы и каталоги..."
PATHS="/etc/openvpn /etc/wireguard /usr/local/x-ui /etc/x-ui /usr/local/3x-ui \
/opt/hiddify* /opt/marzban /etc/xray /usr/local/etc/xray /etc/v2ray /usr/local/etc/v2ray \
/etc/shadowsocks* /usr/local/bin/xray /usr/local/bin/v2ray /usr/bin/x-ui \
/root/*.ovpn /etc/trojan* /opt/outline /opt/shadowbox"
shopt -s nullglob
for pth in $PATHS; do
  for real in $pth; do
    [[ -e "$real" ]] || continue
    case "$real" in
      /|/bin|/boot|/dev|/etc|/home|/lib*|/proc|/root|/run|/sbin|/srv|/sys|/usr|/usr/bin|/usr/local|/usr/local/bin|/var)
        log "  ПРОПУСК (слишком широкий путь): $real"; continue;;
    esac
    rm -rf -- "$real" && log "  удалено: $real"
  done
done
shopt -u nullglob

log "Удаляю firewall-правила wireguard (если остались)..."
systemctl reset-failed 2>/dev/null

log "Порты, которые сейчас слушаются (проверьте, не остался ли VPN):"
ss -tlnp 2>/dev/null | awk 'NR==1 || /:(80|443|1194|51820|8388|10085|54321|2053) /'
log "Готово. Если видите чужой процесс на 80/443 — скажите, уберу адресно."
__DMS_FILE_END__
cat > "$BUNDLE_DIR/send-test.sh" <<'__DMS_FILE_END__'
#!/usr/bin/env bash
# Тестовая отправка письма через ваш же сервер (порт 465, с авторизацией).
# Использование: bash send-test.sh info@dpsradar.world you@gmail.com
# Пароль берётся из /root/mail-credentials.txt.
set -euo pipefail
FROM="${1:?Использование: bash send-test.sh FROM TO}"
TO="${2:?Использование: bash send-test.sh FROM TO}"
MAIL_HOST="${MAIL_HOST:-mail.dpsradar.world}"
CRED_FILE="${CRED_FILE:-/root/mail-credentials.txt}"
[[ -f "$CRED_FILE" ]] || { echo "Файл $CRED_FILE не найден (сначала запустите install.sh)"; exit 1; }
PASS="$(awk -v a="$FROM" '$1==a { $1=""; sub(/^[ \t]+/, ""); print }' "$CRED_FILE" | head -n1)"
[[ -n "$PASS" ]] || { echo "Не нашёл пароль для $FROM в $CRED_FILE"; exit 1; }

FROM="$FROM" TO="$TO" PASS="$PASS" MAIL_HOST="$MAIL_HOST" python3 - <<'PY'
import os, smtplib, ssl, email.utils
from email.message import EmailMessage
f, t, p, h = os.environ["FROM"], os.environ["TO"], os.environ["PASS"], os.environ["MAIL_HOST"]
m = EmailMessage()
m["From"], m["To"] = f, t
m["Subject"] = "Тест доставки с " + f.split("@")[1]
m["Date"] = email.utils.formatdate(localtime=True)
m["Message-ID"] = email.utils.make_msgid(domain=f.split("@")[1])
m.set_content("Проверка доставки. В Gmail откройте письмо -> три точки -> "
              "«Показать оригинал»: SPF, DKIM и DMARC должны быть PASS.")
with smtplib.SMTP_SSL(h, 465, context=ssl.create_default_context(), timeout=30) as s:
    s.login(f, p)
    s.send_message(m)
print("Отправлено:", f, "->", t)
PY
echo "Теперь в Gmail: «Показать оригинал» -> SPF: PASS, DKIM: PASS, DMARC: PASS."
__DMS_FILE_END__
chmod +x "$BUNDLE_DIR"/*.sh
echo "Скрипты распакованы в $BUNDLE_DIR"
[[ "${EXTRACT_ONLY:-0}" == "1" ]] && exit 0
exec bash "$BUNDLE_DIR/install.sh"
