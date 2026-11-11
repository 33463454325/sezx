#!/usr/bin/env bash
# ВСЁ-В-ОДНОМ: распаковывает скрипты почтового сервера и консоли отправки и запускает установку.
# Запуск от root:  CLEANUP_VPN=1 bash all-in-one.sh
#   EXTRACT_ONLY=1 — только распаковать, не запускать установку
#   INSTALL_CONSOLE=0 — не ставить веб-консоль отправки
set -euo pipefail
BUNDLE_DIR="${BUNDLE_DIR:-/opt/mailserver-src}"
mkdir -p "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/."
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
apt-get install -y -qq curl ca-certificates dnsutils openssl python3 unattended-upgrades >/dev/null
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
# Продление сертификата: скрипт на хосте (в контейнере certbot нет docker),
# почта перезапускается только если сертификат реально изменился.
cat > /usr/local/bin/mailserver-cert-renew.sh <<EOF
#!/usr/bin/env bash
CERT="/etc/letsencrypt/live/${MAIL_HOST}/fullchain.pem"
before="\$(sha256sum "\$CERT" 2>/dev/null | cut -d' ' -f1)"
docker run --rm -p 80:80 -v /etc/letsencrypt:/etc/letsencrypt certbot/certbot renew --quiet
after="\$(sha256sum "\$CERT" 2>/dev/null | cut -d' ' -f1)"
if [[ "\$before" != "\$after" ]]; then
  docker restart mailserver >/dev/null
  docker restart mail-console >/dev/null 2>&1 || true
fi
EOF
chmod +x /usr/local/bin/mailserver-cert-renew.sh
cat > /etc/cron.d/mailserver-certbot <<'EOF'
17 3 * * * root /usr/local/bin/mailserver-cert-renew.sh
EOF

# ---------------------------------------------------------------- docker-mailserver
step "Настройка docker-mailserver в $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
for f in check.sh cleanup-vpn.sh send-test.sh install-console.sh; do [[ -f "$SCRIPT_DIR/$f" ]] && cp "$SCRIPT_DIR/$f" "$INSTALL_DIR/$f"; done
[[ -d "$SCRIPT_DIR/console" && "$SCRIPT_DIR" != "$INSTALL_DIR" ]] && cp -r "$SCRIPT_DIR/console" "$INSTALL_DIR/" || true
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
echo "Жду готовности почтового сервера (до 3 минут)..."
for _ in $(seq 1 90); do
  if docker exec mailserver setup email list >/dev/null 2>&1 \
     || docker exec mailserver supervisorctl status postfix 2>/dev/null | grep -q RUNNING; then break; fi
  sleep 2
done
sleep 3
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
  if ! dms config dkim keysize 2048 selector mail domain "$d"; then
    c_warn "Первая попытка DKIM для $d не удалась, пробую без селектора"
    dms config dkim keysize 2048 domain "$d" || c_err "DKIM для $d НЕ создан! Без него Gmail отправит письма в спам."
  fi
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

# ---------------------------------------------------------------- консоль отправки (по умолчанию включена)
if [[ "${INSTALL_CONSOLE:-1}" == "1" && -f "$SCRIPT_DIR/install-console.sh" ]]; then
  MAIL_HOST="$MAIL_HOST" ACCOUNTS="$ACCOUNTS" INSTALL_DIR="$INSTALL_DIR" CRED_FILE="$CRED_FILE" \
    bash "$SCRIPT_DIR/install-console.sh" || c_warn "Консоль не установилась (почта работает). Повторить: bash $INSTALL_DIR/install-console.sh"
fi
exit 0
__DMS_FILE_END__
mkdir -p "$BUNDLE_DIR/."
cat > "$BUNDLE_DIR/check.sh" <<'__DMS_FILE_END__'
#!/usr/bin/env bash
# Проверка DNS, доставляемости и безопасности почтового сервера для всех доменов.
#
# Запуск на сервере:                 bash check.sh
# Запуск с ПК ДО установки (только DNS):  SERVER_IP=31.76.94.174 DNS_ONLY=1 bash check.sh
# (нужен dig: Linux/macOS/WSL — пакет dnsutils / bind-tools)
MAIL_HOST="${MAIL_HOST:-mail.dpsradar.world}"
ACCOUNTS="${ACCOUNTS:-info@dpsradar.world mail@dpsradar.net}"
DOMAINS="$(for a in $ACCOUNTS; do echo "${a#*@}"; done | sort -u)"
command -v dig >/dev/null || { echo "Нужен dig (пакет dnsutils)"; exit 1; }

IP="${SERVER_IP:-$(curl -4 -fsS --max-time 10 https://api.ipify.org)}"
[[ -n "$IP" ]] || { echo "Не удалось определить IP. Задайте SERVER_IP=..."; exit 1; }

# Если контейнера нет — проверяем только DNS
if [[ "${DNS_ONLY:-0}" != "1" ]]; then
  command -v docker >/dev/null && docker inspect mailserver >/dev/null 2>&1 || DNS_ONLY=1
fi

ok=0; bad=0; skip=0
chk()  { if eval "$2"; then printf '\033[32m[OK]\033[0m %s\n' "$1"; ok=$((ok+1)); else printf '\033[31m[XX]\033[0m %s\n' "$1"; bad=$((bad+1)); fi; }
note() { printf '\033[33m[--]\033[0m %s\n' "$1"; skip=$((skip+1)); }
q() { dig +short "$@" @1.1.1.1; }

relay_closed() {  # 0 = открытого релея нет
  python3 - <<'PY'
import smtplib, sys
try:
    s = smtplib.SMTP("127.0.0.1", 25, timeout=15)
    s.ehlo("relaytest.example")
    s.mail("probe@example.org")
    code, _ = s.rcpt("someone@gmail.com")
    s.quit()
    sys.exit(0 if code >= 400 else 1)
except Exception:
    sys.exit(0)
PY
}

echo "== Сервер ($IP) =="
chk "A $MAIL_HOST = $IP"        '[[ "$(q A "$MAIL_HOST" | tail -n1)" == "$IP" ]]'
chk "PTR $IP -> $MAIL_HOST"     '[[ "$(q -x "$IP" | sed "s/\.$//")" == "$MAIL_HOST" ]]'
chk "Нет AAAA (IPv6) у $MAIL_HOST" '[[ -z "$(q AAAA "$MAIL_HOST")" ]]'

if [[ "$DNS_ONLY" != "1" ]]; then
  chk "Контейнер mailserver работает" '[[ "$(docker inspect -f "{{.State.Running}}" mailserver 2>/dev/null)" == "true" ]]'
  for p in 25 465 587 993; do chk "Порт $p слушается" "timeout 5 bash -c 'exec 3<>/dev/tcp/127.0.0.1/$p' 2>/dev/null"; done
  chk "Исходящий порт 25 открыт"  "timeout 10 bash -c 'exec 3<>/dev/tcp/gmail-smtp-in.l.google.com/25' 2>/dev/null"
  chk "Нет открытого релея (чужие адреса без пароля отклоняются)" 'relay_closed'
  chk "Сертификат TLS на 465 валиден" "echo | timeout 10 openssl s_client -connect 127.0.0.1:465 -servername '$MAIL_HOST' 2>/dev/null | openssl x509 -noout -checkend 604800 >/dev/null 2>&1"
  if docker inspect mail-console >/dev/null 2>&1; then
    chk "Консоль отправки работает (https://$MAIL_HOST:8443)" "[[ \"\$(curl -sk -o /dev/null -w '%{http_code}' https://127.0.0.1:8443/)\" == 200 ]]"
  else
    note "Консоль отправки не установлена (bash /opt/mailserver/install-console.sh)"
  fi
else
  note "Режим DNS_ONLY: проверки контейнера, портов и релея пропущены"
fi

echo "== Чёрные списки IP =="
REV="$(awk -F. '{print $4"."$3"."$2"."$1}' <<<"$IP")"
for bl in zen.spamhaus.org bl.spamcop.net b.barracudacentral.org dnsbl-1.uceprotect.net; do
  r="$(dig +short "$REV.$bl" A 2>/dev/null | head -n1)"
  if [[ -z "$r" ]]; then printf '\033[32m[OK]\033[0m не в списке %s\n' "$bl"; ok=$((ok+1))
  elif [[ "$r" == 127.255.255.* ]]; then note "$bl не отвечает на запросы с этого DNS (проверьте вручную на mxtoolbox.com)"
  else printf '\033[31m[XX]\033[0m IP В СПИСКЕ %s (%s)\n' "$bl" "$r"; bad=$((bad+1)); fi
done

for d in $DOMAINS; do
  echo "== $d =="
  chk "MX $d -> $MAIL_HOST"       "q MX '$d' | grep -q '$MAIL_HOST'"
  chk "SPF ($d) содержит ip4:$IP" "q TXT '$d' | grep -q 'ip4:$IP'"
  chk "SPF ($d) заканчивается на -all" "q TXT '$d' | grep -q 'ip4:$IP.*-all'"
  chk "Нет AAAA у $d"             "[[ -z \"\$(q AAAA '$d')\" ]]"
  chk "DMARC ($d)"                "q TXT '_dmarc.$d' | grep -q 'v=DMARC1'"
  chk "DKIM mail._domainkey ($d)" "q TXT 'mail._domainkey.$d' | grep -q 'p='"
  f="/opt/mailserver/dkim-$d.txt"
  if [[ "$DNS_ONLY" != "1" && -s "$f" ]]; then
    want="$(grep -o 'p=MI[A-Za-z0-9+/=]*' "$f" | head -c 60)"
    [[ -n "$want" ]] && chk "DKIM в DNS совпадает с ключом сервера ($d)" \
      "q TXT 'mail._domainkey.$d' | tr -d '\" \t\n' | grep -Fq '$want'"
  fi
done

echo; echo "Итого: OK=$ok, ошибок=$bad, пропущено=$skip"
if [[ $bad -eq 0 ]]; then echo "Всё в порядке. Дальше: send-test.sh и https://www.mail-tester.com (цель 9-10/10)."
else echo "Исправьте пункты [XX]. DNS обновляется до 15-60 минут — повторите проверку позже."; fi
__DMS_FILE_END__
mkdir -p "$BUNDLE_DIR/."
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
mkdir -p "$BUNDLE_DIR/."
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
mkdir -p "$BUNDLE_DIR/."
cat > "$BUNDLE_DIR/install-console.sh" <<'__DMS_FILE_END__'
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
__DMS_FILE_END__
mkdir -p "$BUNDLE_DIR/console"
cat > "$BUNDLE_DIR/console/server.js" <<'__DMS_FILE_END__'
'use strict';
// HTTPS-консоль для ручной отправки писем через собственный почтовый сервер.
// Защита от спама встроена: вход по паролю, отправка только с ваших ящиков,
// лимиты в час и в сутки (с «прогревом» нового IP), не более N получателей,
// проверка домена получателя, список отклонённых адресов, проверка текста.

const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const dns = require('dns').promises;
const { promisify } = require('util');
const nodemailer = require('nodemailer');
const { lint } = require('./lint');
const scrypt = promisify(crypto.scrypt);

// ------------------------------------------------------------------ конфигурация
const DATA_DIR = process.env.DATA_DIR || '/data';
const CONFIG_PATH = process.env.CONFIG_PATH || path.join(DATA_DIR, 'config.json');
const cfg = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));

const MAIL_HOST = cfg.mailHost || 'mail.localhost';
const SMTP_HOST = cfg.smtpHost || '127.0.0.1';
const SMTP_PORT = Number(cfg.smtpPort || 587);
const PORT = Number(process.env.PORT || cfg.port || 8443);
const HTTPS_ON = process.env.INSECURE_HTTP !== '1';
const MAX_RECIPIENTS = Number(cfg.maxRecipients || 5);
const PER_HOUR = Number(cfg.perHour || 20);
const ALLOWED_IPS = Array.isArray(cfg.allowedIps) ? cfg.allowedIps : [];
const PUBLIC_DIR = path.join(__dirname, 'public');

const accounts = {};
for (const [addr, v] of Object.entries(cfg.accounts || {})) {
  accounts[addr.toLowerCase()] = { pass: typeof v === 'string' ? v : v.pass, name: (v && v.name) || '' };
}
if (!Object.keys(accounts).length) throw new Error('В config.json нет ни одного ящика (accounts)');
if (!cfg.adminPassword || String(cfg.adminPassword).length < 10) throw new Error('adminPassword должен быть не короче 10 символов');

// пароль администратора хранится в памяти только как scrypt-хеш
const SALT = crypto.randomBytes(16);
const ADMIN_HASH = crypto.scryptSync(String(cfg.adminPassword), SALT, 32);

// ------------------------------------------------------------------ хранилище
fs.mkdirSync(DATA_DIR, { recursive: true });
const LOG_FILE = path.join(DATA_DIR, 'sent.jsonl');
const STATE_FILE = path.join(DATA_DIR, 'state.json');
const SUPPRESS_FILE = path.join(DATA_DIR, 'suppressed.json');

function readJson(file, fallback) { try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return fallback; } }
function writeJson(file, obj) { fs.writeFileSync(file, JSON.stringify(obj, null, 2), { mode: 0o600 }); }

const state = readJson(STATE_FILE, null) || { startedAt: Date.now() };
if (!state.startedAt) state.startedAt = Date.now();
writeJson(STATE_FILE, state);

const suppressed = readJson(SUPPRESS_FILE, {});   // { "addr": { reason, at } }

let history = [];
try {
  history = fs.readFileSync(LOG_FILE, 'utf8').split('\n').filter(Boolean).slice(-5000).map((l) => JSON.parse(l));
} catch { /* файла ещё нет */ }
function pushLog(entry) {
  history.push(entry);
  if (history.length > 5000) history.shift();
  fs.appendFileSync(LOG_FILE, JSON.stringify(entry) + '\n', { mode: 0o600 });
}

// ------------------------------------------------------------------ лимиты
function warmupDay() { return Math.floor((Date.now() - state.startedAt) / 86400000) + 1; }
function dailyLimit() {
  if (cfg.dailyLimit) return Number(cfg.dailyLimit);
  if (cfg.warmup === false) return 300;
  const d = warmupDay();
  if (d <= 3) return 10;
  if (d <= 7) return 30;
  if (d <= 14) return 100;
  return 300;
}
function usage() {
  const now = Date.now();
  let hour = 0, day = 0;
  for (const e of history) {
    if (e.status !== 'sent') continue;
    const age = now - Date.parse(e.t);
    const n = (e.to || []).length;
    if (age < 3600e3) hour += n;
    if (age < 86400e3) day += n;
  }
  return { hour: { used: hour, limit: PER_HOUR }, day: { used: day, limit: dailyLimit() }, warmupDay: warmupDay(), maxRecipients: MAX_RECIPIENTS };
}

// ------------------------------------------------------------------ утилиты
const EMAIL_RE = /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]{1,64}@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$/;
const isEmail = (s) => typeof s === 'string' && s.length <= 254 && EMAIL_RE.test(s);
const norm = (s) => String(s || '').trim().toLowerCase();

function parseList(v) {
  const arr = Array.isArray(v) ? v : String(v || '').split(/[\s,;]+/);
  return [...new Set(arr.map(norm).filter(Boolean))];
}

function cleanName(s) {
  return String(s || '').replace(/[\r\n"<>\\]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 60);
}

async function domainCanReceive(domain) {
  const missing = (e) => e && (e.code === 'ENODATA' || e.code === 'ENOTFOUND' || e.code === 'NXDOMAIN');
  try {
    const mx = await dns.resolveMx(domain);
    if (mx.length === 1 && mx[0].exchange === '') return false;      // «Null MX»: домен не принимает почту
    if (mx.length) return true;
  } catch (e) { if (!missing(e)) return true; }                      // сбой DNS — не блокируем
  try { return (await dns.resolve4(domain)).length > 0; } catch (e) { return !missing(e); }
}

function ipAllowed(ip) {
  if (!ALLOWED_IPS.length) return true;
  const plain = String(ip || '').replace(/^::ffff:/, '');
  return ALLOWED_IPS.includes(plain);
}

// ------------------------------------------------------------------ сессии и защита входа
const sessions = new Map();     // sid -> { csrf, expires, last }
const attempts = new Map();     // ip -> { n, first }
const SESSION_ABS = 12 * 3600e3, SESSION_IDLE = 2 * 3600e3;
const LOGIN_MAX = 5, LOGIN_WINDOW = 15 * 60e3;

setInterval(() => {
  const now = Date.now();
  for (const [k, s] of sessions) if (now > s.expires || now - s.last > SESSION_IDLE) sessions.delete(k);
  for (const [k, a] of attempts) if (now - a.first > LOGIN_WINDOW) attempts.delete(k);
}, 60e3).unref();

function parseCookies(req) {
  const out = {};
  for (const part of String(req.headers.cookie || '').split(';')) {
    const i = part.indexOf('=');
    if (i > 0) out[part.slice(0, i).trim()] = part.slice(i + 1).trim();
  }
  return out;
}
function getSession(req) {
  const sid = parseCookies(req).sid;
  const s = sid && sessions.get(sid);
  if (!s) return null;
  const now = Date.now();
  if (now > s.expires || now - s.last > SESSION_IDLE) { sessions.delete(sid); return null; }
  s.last = now;
  s.sid = sid;
  return s;
}
function safeEqual(a, b) {
  const x = Buffer.from(String(a)), y = Buffer.from(String(b));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

// ------------------------------------------------------------------ HTTP-помощники
const SEC_HEADERS = {
  'Content-Security-Policy': "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'",
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
  'Referrer-Policy': 'no-referrer',
  'Cache-Control': 'no-store',
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Cross-Origin-Resource-Policy': 'same-origin',
};
if (HTTPS_ON) SEC_HEADERS['Strict-Transport-Security'] = 'max-age=31536000';

function send(res, status, body, headers = {}) {
  res.writeHead(status, { ...SEC_HEADERS, ...headers });
  res.end(body);
}
function sendJson(res, status, obj, headers = {}) {
  send(res, status, JSON.stringify(obj), { 'Content-Type': 'application/json; charset=utf-8', ...headers });
}

function readBody(req, limit = 600 * 1024) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > limit) { reject(Object.assign(new Error('too large'), { status: 413 })); req.destroy(); return; }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}
async function readJsonBody(req) {
  const raw = await readBody(req);
  try { return raw ? JSON.parse(raw) : {}; } catch { throw Object.assign(new Error('bad json'), { status: 400 }); }
}

const STATIC = {
  '/': ['index.html', 'text/html; charset=utf-8'],
  '/app.js': ['app.js', 'text/javascript; charset=utf-8'],
  '/app.css': ['app.css', 'text/css; charset=utf-8'],
};

// ------------------------------------------------------------------ отправка
let sending = false;

function friendlySmtpError(err) {
  const r = String(err && err.response || '');
  if (err && err.code === 'EAUTH') return 'Почтовый сервер не принял пароль ящика. Проверьте /opt/mailserver/console-data/config.json.';
  if (err && (err.code === 'ECONNECTION' || err.code === 'ESOCKET' || err.code === 'ETIMEDOUT')) return 'Не удалось соединиться с почтовым сервером (порт 587). Проверьте, что контейнер mailserver запущен.';
  if (/rate|too many|limit/i.test(r)) return 'Почтовый сервер временно ограничил скорость отправки. Подождите и повторите.';
  return (r || (err && err.message) || 'Неизвестная ошибка отправки').slice(0, 300);
}

async function handleSend(req, res) {
  const b = await readJsonBody(req);
  const fail = (status, error, extra = {}) => sendJson(res, status, { ok: false, error, ...extra });

  // отправитель — только собственные ящики
  const from = norm(b.from);
  const account = accounts[from];
  if (!account) return fail(400, 'Отправлять можно только с ящиков, созданных на этом сервере: ' + Object.keys(accounts).join(', '));

  // получатели
  const to = parseList(b.to), cc = parseList(b.cc), bcc = parseList(b.bcc);
  const all = [...new Set([...to, ...cc, ...bcc])];
  if (!to.length) return fail(422, 'Укажите хотя бы одного получателя в поле «Кому».');
  const badAddr = all.find((a) => !isEmail(a));
  if (badAddr) return fail(422, `Некорректный адрес: ${badAddr}`);
  if (all.length > MAX_RECIPIENTS) return fail(422, `Слишком много получателей (${all.length}). Максимум ${MAX_RECIPIENTS}: это консоль для личной переписки, а не для рассылок.`);
  const replyTo = norm(b.replyTo);
  if (replyTo && !isEmail(replyTo)) return fail(422, 'Некорректный адрес в поле «Ответить на».');

  // тема и тело
  const subject = String(b.subject || '').trim();
  if (subject.length > 200) return fail(422, 'Тема слишком длинная (максимум 200 символов).');
  const textIn = String(b.text || ''), htmlIn = String(b.html || '');
  if (textIn.length > 200e3 || htmlIn.length > 200e3) return fail(422, 'Письмо слишком большое (максимум 200 КБ на часть).');
  const result = lint({ subject, text: textIn, html: htmlIn });
  const errors = result.issues.filter((i) => i.level === 'error');
  if (errors.length) return fail(422, errors[0].text, { issues: result.issues });

  // список адресов, которые сервер уже отклонял
  const sup = all.find((a) => suppressed[a]);
  if (sup) return fail(422, `Адрес ${sup} ранее был отклонён почтовым сервером получателя. Повторные попытки вредят репутации — исправьте адрес или уберите его.`);

  // Одно письмо за раз. Замок берём ДО проверки лимитов и DNS: иначе параллельные
  // запросы проходят проверку по одному и тому же счётчику и превышают лимит.
  if (sending) return fail(429, 'Предыдущее письмо ещё отправляется. Подождите пару секунд.');
  sending = true;
  const entry = { t: new Date().toISOString(), from, to: all, subject, status: 'failed' };
  try {
    // лимиты
    const u = usage();
    if (u.hour.used + all.length > u.hour.limit) return fail(429, `Лимит в час исчерпан (${u.hour.used} из ${u.hour.limit}). Подождите немного.`);
    if (u.day.used + all.length > u.day.limit) return fail(429, `Дневной лимит исчерпан (${u.day.used} из ${u.day.limit}). Лимит растёт по мере «прогрева» нового IP.`);

    // домены получателей должны существовать и принимать почту
    if (process.env.SKIP_MX_CHECK !== '1') {
      for (const d of [...new Set(all.map((a) => a.split('@')[1]))]) {
        if (!(await domainCanReceive(d))) return fail(422, `Домен «${d}» не принимает почту (нет MX-записей). Проверьте адрес на опечатки.`);
      }
    }

    const fromName = cleanName(b.fromName) || cleanName(account.name);
    const transport = nodemailer.createTransport({
      host: SMTP_HOST, port: SMTP_PORT, secure: false, requireTLS: true, name: MAIL_HOST,
      auth: { user: from, pass: account.pass },
      tls: { servername: MAIL_HOST, rejectUnauthorized: process.env.SMTP_TLS_INSECURE !== '1' },
      connectionTimeout: 15000, greetingTimeout: 15000, socketTimeout: 60000,
    });
    const info = await transport.sendMail({
      from: fromName ? { name: fromName, address: from } : from,
      to, cc: cc.length ? cc : undefined, bcc: bcc.length ? bcc : undefined,
      replyTo: replyTo || undefined,
      subject,
      text: result.text,
      html: result.html || undefined,
      xMailer: false,
    });
    transport.close();
    entry.status = info.rejected && info.rejected.length ? (info.accepted.length ? 'partial' : 'failed') : 'sent';
    entry.messageId = info.messageId;
    if (info.rejected && info.rejected.length) {
      entry.error = 'Отклонены сервером: ' + info.rejected.join(', ');
      for (const a of info.rejected) suppressed[norm(a)] = { reason: 'rejected', at: entry.t };
      writeJson(SUPPRESS_FILE, suppressed);
    }
    if (entry.status === 'partial') entry.status = 'sent';
    pushLog(entry);
    if (info.accepted && !info.accepted.length) return fail(502, entry.error || 'Сервер отклонил всех получателей.');
    return sendJson(res, 200, { ok: true, messageId: info.messageId, accepted: info.accepted, rejected: info.rejected, usage: usage(), issues: result.issues });
  } catch (err) {
    entry.error = friendlySmtpError(err);
    // постоянный отказ для получателя (5xx) — запоминаем, чтобы не долбить повторно
    if (err && err.responseCode >= 500 && err.rejected && err.rejected.length) {
      for (const a of err.rejected) suppressed[norm(a)] = { reason: entry.error, at: entry.t };
      writeJson(SUPPRESS_FILE, suppressed);
    }
    pushLog(entry);
    return fail(502, entry.error);
  } finally {
    sending = false;
  }
}

// ------------------------------------------------------------------ маршруты
async function handler(req, res) {
  try {
    if (!ipAllowed(req.socket.remoteAddress)) return send(res, 403, 'Forbidden', { 'Content-Type': 'text/plain' });
    const url = new URL(req.url, 'http://x');
    const p = url.pathname;

    if (req.method === 'GET' && STATIC[p]) {
      const [file, type] = STATIC[p];
      return send(res, 200, fs.readFileSync(path.join(PUBLIC_DIR, file)), { 'Content-Type': type });
    }

    if (req.method === 'POST' && p === '/api/login') {
      const ip = req.socket.remoteAddress;
      const now = Date.now();
      let a = attempts.get(ip);
      if (!a || now - a.first > LOGIN_WINDOW) { a = { n: 0, first: now }; attempts.set(ip, a); }
      if (a.n >= LOGIN_MAX) {
        const wait = Math.ceil((LOGIN_WINDOW - (now - a.first)) / 60e3);
        return sendJson(res, 429, { ok: false, error: `Слишком много попыток входа. Повторите через ${wait} мин.` });
      }
      const b = await readJsonBody(req);
      const given = await scrypt(String(b.password || ''), SALT, 32);   // асинхронно: не блокирует сервер
      if (!crypto.timingSafeEqual(given, ADMIN_HASH)) {
        a.n++;
        await new Promise((r) => setTimeout(r, 700));
        return sendJson(res, 401, { ok: false, error: 'Неверный пароль.' });
      }
      attempts.delete(ip);
      const sid = crypto.randomBytes(32).toString('hex');
      sessions.set(sid, { csrf: crypto.randomBytes(24).toString('hex'), expires: now + SESSION_ABS, last: now });
      const cookie = `sid=${sid}; HttpOnly; SameSite=Strict; Path=/; Max-Age=${SESSION_ABS / 1000}${HTTPS_ON ? '; Secure' : ''}`;
      return sendJson(res, 200, { ok: true }, { 'Set-Cookie': cookie });
    }

    const sess = getSession(req);

    if (req.method === 'GET' && p === '/api/session') {
      if (!sess) return sendJson(res, 200, { authenticated: false });
      return sendJson(res, 200, {
        authenticated: true, csrf: sess.csrf, mailHost: MAIL_HOST,
        accounts: Object.entries(accounts).map(([address, v]) => ({ address, name: v.name })),
        usage: usage(),
      });
    }

    // ниже — только для вошедших
    if (!sess) return sendJson(res, 401, { ok: false, error: 'Требуется вход.' });

    if (req.method === 'GET' && p === '/api/log') {
      const items = history.slice(-30).reverse().map((e) => ({ t: e.t, from: e.from, to: e.to, subject: e.subject, status: e.status, error: e.error }));
      return sendJson(res, 200, { items });
    }

    if (req.method === 'POST' && p === '/preview') {
      const form = new URLSearchParams(await readBody(req));
      if (!safeEqual(form.get('csrf') || '', sess.csrf)) return send(res, 403, 'CSRF', { 'Content-Type': 'text/plain' });
      const l = lint({ subject: 'x', text: form.get('text') || '', html: form.get('html') || '' });
      const esc = (s) => s.replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
      const content = l.html || `<pre style="white-space:pre-wrap;font:inherit">${esc(l.text)}</pre>`;
      const page = `<!doctype html><meta charset="utf-8"><style>body{margin:16px;background:#fff;color:#111;font:14px/1.55 system-ui,sans-serif}img{max-width:100%;height:auto}</style>${content}`;
      return send(res, 200, page, {
        'Content-Type': 'text/html; charset=utf-8',
        'Content-Security-Policy': "sandbox; default-src 'none'; style-src 'unsafe-inline'; img-src https: data:; font-src https: data:",
        'X-Frame-Options': 'SAMEORIGIN',
      });
    }

    if (req.method === 'POST') {
      if (!safeEqual(req.headers['x-csrf-token'] || '', sess.csrf)) return sendJson(res, 403, { ok: false, error: 'Сессия устарела. Обновите страницу.' });
      if (p === '/api/logout') { sessions.delete(sess.sid); return sendJson(res, 200, { ok: true }, { 'Set-Cookie': 'sid=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0' }); }
      if (p === '/api/lint') {
        const b = await readJsonBody(req);
        const l = lint({ subject: String(b.subject || ''), text: String(b.text || ''), html: String(b.html || '') });
        return sendJson(res, 200, { issues: l.issues });
      }
      if (p === '/api/send') return await handleSend(req, res);
    }

    return sendJson(res, 404, { ok: false, error: 'Not found' });
  } catch (err) {
    const status = err.status || 500;
    if (status === 500) console.error('Ошибка:', err);
    if (!res.headersSent) sendJson(res, status, { ok: false, error: status === 413 ? 'Слишком большой запрос.' : 'Внутренняя ошибка сервера.' });
  }
}

// ------------------------------------------------------------------ запуск
function createServer() {
  if (!HTTPS_ON) return http.createServer(handler);
  const certDir = process.env.CERT_DIR || `/etc/letsencrypt/live/${MAIL_HOST}`;
  const load = () => ({ key: fs.readFileSync(path.join(certDir, 'privkey.pem')), cert: fs.readFileSync(path.join(certDir, 'fullchain.pem')) });
  const server = https.createServer({ ...load(), minVersion: 'TLSv1.2' }, handler);
  // подхватываем обновлённый сертификат без перезапуска
  setInterval(() => { try { server.setSecureContext(load()); } catch (e) { console.error('Не удалось перечитать сертификат:', e.message); } }, 6 * 3600e3).unref();
  return server;
}

const server = createServer();
server.listen(PORT, process.env.HOST || '0.0.0.0', () => {
  console.log(`Почтовая консоль: ${HTTPS_ON ? 'https' : 'http'}://0.0.0.0:${PORT}  (ящики: ${Object.keys(accounts).join(', ')})`);
});
__DMS_FILE_END__
mkdir -p "$BUNDLE_DIR/console"
cat > "$BUNDLE_DIR/console/lint.js" <<'__DMS_FILE_END__'
'use strict';
// Проверки письма перед отправкой, очистка HTML и создание текстовой версии.
// Цель — чтобы письмо не выглядело как спам и не вредило репутации сервера.

const SHORTENERS = ['bit.ly', 'tinyurl.com', 't.co', 'goo.gl', 'cutt.ly', 'is.gd', 'ow.ly', 'rebrand.ly', 'shorturl.at'];

const SPAM_PATTERNS = [
  /бесплатн/i, /выигр[аы]ш/i, /без\s+отказа/i, /100\s*%\s*гарант/i, /только\s+сегодня/i,
  /казино/i, /микрозайм/i, /быстрый\s+заработок/i,
  /\bviagra\b/i, /\bcasino\b/i, /\bfree\s+money\b/i, /\bclick\s+here\b/i, /\bact\s+now\b/i,
  /\bwinner\b/i, /\bno\s+obligation\b/i, /\bearn\s+\$/i,
];

const ENTITIES = { nbsp: ' ', amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", laquo: '«', raquo: '»', mdash: '—', ndash: '–', hellip: '…', copy: '©' };

function decodeEntities(s) {
  return s
    .replace(/&#(\d+);/g, (_, n) => { try { return String.fromCodePoint(Number(n)); } catch { return ''; } })
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => { try { return String.fromCodePoint(parseInt(n, 16)); } catch { return ''; } })
    .replace(/&([a-z]+);/gi, (m, n) => (ENTITIES[n.toLowerCase()] !== undefined ? ENTITIES[n.toLowerCase()] : m));
}

// Убирает опасные и «спамные» для почты элементы. HTML пишет сам пользователь,
// поэтому это гигиена, а не защита от злоумышленника.
function sanitizeHtml(html) {
  let s = String(html || '');
  s = s.replace(/<(script|iframe|object|embed|applet|form)\b[\s\S]*?<\/\1\s*>/gi, '');
  s = s.replace(/<\/?(script|iframe|object|embed|applet|form|input|button|textarea|select|link)\b[^>]*>/gi, '');
  s = s.replace(/<meta\s+http-equiv[^>]*>/gi, '');
  s = s.replace(/\s+on[a-z]+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)/gi, '');
  s = s.replace(/(href|src)\s*=\s*(["'])\s*javascript:[^"']*\2/gi, '$1=$2#$2');
  return s;
}

function htmlToText(html) {
  let s = String(html || '');
  s = s.replace(/<(script|style|head|title)\b[\s\S]*?<\/\1\s*>/gi, '');
  s = s.replace(/<a\s[^>]*?href\s*=\s*["']?([^"'\s>]+)["']?[^>]*>([\s\S]*?)<\/a\s*>/gi, (m, href, inner) => {
    const label = inner.replace(/<[^>]+>/g, '').trim();
    if (!label || label === href || /^mailto:/i.test(href) || href.startsWith('#')) return label || href;
    return `${label} (${href})`;
  });
  s = s.replace(/<br\s*\/?>/gi, '\n');
  s = s.replace(/<li\b[^>]*>/gi, '• ');
  s = s.replace(/<\/(p|div|h[1-6]|li|tr|table|ul|ol|blockquote|section|article)\s*>/gi, '\n\n');
  s = s.replace(/<[^>]+>/g, '');
  s = decodeEntities(s);
  return s.replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim();
}

function extractUrls(text, html) {
  const urls = new Set();
  const re = /https?:\/\/[^\s<>"')\]]+/gi;
  for (const src of [text || '', html || '']) for (const m of src.matchAll(re)) urls.add(m[0].replace(/[.,;:!?]+$/, ''));
  return [...urls];
}

function hostOf(u) {
  try { return new URL(u).hostname.toLowerCase().replace(/^www\./, ''); } catch { return ''; }
}

/**
 * Возвращает { issues: [{level, text}], text, html }
 * level: 'error' — отправка запрещена, 'warn' — предупреждение, 'info' — заметка.
 */
function lint({ subject = '', text = '', html = '' } = {}) {
  const issues = [];
  const add = (level, t) => issues.push({ level, text: t });

  subject = String(subject);
  const cleanHtml = html ? sanitizeHtml(html) : '';
  const hasText = String(text).trim().length > 0;
  const hasHtml = cleanHtml.trim().length > 0;

  // --- обязательное
  if (!subject.trim()) add('error', 'Укажите тему письма. Письма без темы чаще попадают в спам.');
  if (/[\r\n]/.test(subject)) add('error', 'В теме не должно быть переводов строк.');
  if (!hasText && !hasHtml) add('error', 'Письмо пустое: введите текст или HTML.');
  if (html && cleanHtml !== html) add('info', 'Из HTML удалены скрипты, формы и другие небезопасные элементы: почтовые клиенты их не поддерживают, а спам-фильтры не любят.');

  // --- текстовая версия
  let finalText = String(text);
  if (!hasText && hasHtml) {
    finalText = htmlToText(cleanHtml);
    add('info', 'Текстовая версия создана автоматически из HTML. Письмо уйдёт сразу в двух форматах, это улучшает доставляемость.');
  } else if (hasText && !hasHtml) {
    add('info', 'Письмо уйдёт простым текстом. Это нормально и даже надёжнее для личной переписки.');
  }

  // --- тема
  if (subject.length > 78) add('warn', `Тема длинная (${subject.length} символов). Лучше уложиться в 60–70.`);
  const letters = subject.replace(/[^A-Za-zА-Яа-яЁё]/g, '');
  const upper = letters.replace(/[^A-ZА-ЯЁ]/g, '');
  if (letters.length >= 8 && upper.length / letters.length > 0.6) add('warn', 'Тема написана ЗАГЛАВНЫМИ буквами: фильтры считают это признаком спама.');
  if (/!{2,}|\${2,}|\?{3,}/.test(subject)) add('warn', 'В теме много «!», «?» или «$». Уберите лишние знаки.');
  if (/^\s*(re|fwd?|отв|пересл)\s*:/i.test(subject)) add('warn', 'Тема начинается с «Re:»/«Fwd:», но это не ответ на письмо. Так делать нельзя: это приём спамеров.');

  // --- слова-триггеры
  const body = `${subject}\n${finalText}\n${hasHtml ? htmlToText(cleanHtml) : ''}`;
  const hits = SPAM_PATTERNS.filter((re) => re.test(body));
  if (hits.length) add('warn', `Найдены «спамные» формулировки (${hits.length}). Перепишите нейтральнее.`);

  // --- ссылки
  const urls = extractUrls(finalText, cleanHtml);
  const hosts = [...new Set(urls.map(hostOf).filter(Boolean))];
  if (urls.length > 3) add('warn', `В письме ${urls.length} ссылок. Для первых писем держитесь в пределах 1–3.`);
  const short = hosts.filter((h) => SHORTENERS.includes(h));
  if (short.length) add('warn', `Сокращатели ссылок (${short.join(', ')}) сильно повышают риск спама. Используйте полные адреса.`);
  if (urls.some((u) => u.startsWith('http://'))) add('warn', 'Есть ссылки на http://. Лучше использовать https://.');
  for (const m of cleanHtml.matchAll(/<a\s[^>]*?href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/a\s*>/gi)) {
    const label = m[2].replace(/<[^>]+>/g, '').trim();
    if (/^https?:\/\//i.test(label) && hostOf(label) && hostOf(m[1]) && hostOf(label) !== hostOf(m[1])) {
      add('warn', `Текст ссылки показывает «${hostOf(label)}», а ведёт она на «${hostOf(m[1])}». Это выглядит как фишинг.`);
      break;
    }
  }

  // --- содержимое HTML
  if (hasHtml) {
    const imgs = (cleanHtml.match(/<img\b/gi) || []).length;
    const visible = htmlToText(cleanHtml).length;
    if (imgs > 0 && visible < 200) add('warn', 'Много картинок и мало текста: такие письма часто считаются спамом. Добавьте текст.');
    if (imgs > 5) add('warn', `В письме ${imgs} картинок. Старайтесь не больше 3–5.`);
    if (/<img\b(?![^>]*\balt\s*=)[^>]*>/i.test(cleanHtml)) add('info', 'У некоторых картинок нет атрибута alt: добавьте описание.');
    if (cleanHtml.length > 100 * 1024) add('warn', 'HTML очень большой (больше 100 КБ). Gmail обрежет такое письмо.');
  }
  if (urls.length >= 1 && finalText.replace(/https?:\/\/\S+/g, '').trim().length < 40 && !hasHtml) {
    add('warn', 'Письмо почти целиком состоит из ссылки. Добавьте пару предложений текста.');
  }

  return { issues, text: finalText, html: cleanHtml };
}

module.exports = { lint, sanitizeHtml, htmlToText };
__DMS_FILE_END__
mkdir -p "$BUNDLE_DIR/console"
cat > "$BUNDLE_DIR/console/package.json" <<'__DMS_FILE_END__'
{
  "name": "mail-console",
  "version": "1.0.0",
  "description": "Консоль ручной отправки писем через собственный почтовый сервер",
  "private": true,
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "test": "node test/e2e.js"
  },
  "engines": { "node": ">=20" },
  "dependencies": {
    "nodemailer": "10.5.0"
  },
  "devDependencies": {
    "mailparser": "3.14.3",
    "smtp-server": "3.21.4"
  }
}
__DMS_FILE_END__
mkdir -p "$BUNDLE_DIR/console"
cat > "$BUNDLE_DIR/console/Dockerfile" <<'__DMS_FILE_END__'
FROM node:22-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund
COPY server.js lint.js ./
COPY public ./public
ENV NODE_ENV=production
CMD ["node", "server.js"]
__DMS_FILE_END__
mkdir -p "$BUNDLE_DIR/console/public"
cat > "$BUNDLE_DIR/console/public/index.html" <<'__DMS_FILE_END__'
<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex,nofollow">
  <meta name="color-scheme" content="light dark">
  <title>Почтовая консоль</title>
  <link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='32' height='32' rx='9' fill='%234f46e5'/%3E%3Cpath d='M8 11.5h16v9a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 8 20.5z' fill='none' stroke='white' stroke-width='1.8' stroke-linejoin='round'/%3E%3Cpath d='m8.5 12 7.5 5.5 7.5-5.5' fill='none' stroke='white' stroke-width='1.8' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E">
  <link rel="stylesheet" href="/app.css">
</head>
<body>

<!-- ============ Вход ============ -->
<div id="login" class="login" hidden>
  <form id="loginForm" class="login-card" autocomplete="off">
    <span class="logo" aria-hidden="true">
      <svg viewBox="0 0 24 24" width="26" height="26" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="5.5" width="18" height="13" rx="2.5"/><path d="m4 7.5 8 6 8-6"/></svg>
    </span>
    <h1>Почтовая консоль</h1>
    <p class="muted">Введите пароль администратора, чтобы отправлять письма с ваших доменов.</p>
    <label class="field">
      <span>Пароль</span>
      <input id="loginPass" type="password" autocomplete="current-password" required autofocus>
    </label>
    <p id="loginError" class="form-error" role="alert" hidden></p>
    <button class="btn primary block" type="submit">Войти</button>
  </form>
</div>

<!-- ============ Консоль ============ -->
<div id="app" hidden>
  <header class="topbar">
    <div class="brand">
      <span class="logo sm" aria-hidden="true">
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="5.5" width="18" height="13" rx="2.5"/><path d="m4 7.5 8 6 8-6"/></svg>
      </span>
      <div class="brand-text"><strong>Почтовая консоль</strong><small id="hostPill"></small></div>
    </div>
    <div class="top-actions">
      <button id="themeBtn" class="icon-btn" type="button" aria-label="Сменить тему" title="Сменить тему">
        <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M20 14.5A8 8 0 0 1 9.5 4 8 8 0 1 0 20 14.5z"/></svg>
      </button>
      <button id="logoutBtn" class="btn ghost" type="button">Выйти</button>
    </div>
  </header>

  <main class="layout">
    <form id="composeForm" class="card compose" novalidate>
      <div class="card-head">
        <h2>Новое письмо</h2>
        <span id="fromState" class="badge" hidden></span>
      </div>

      <div id="formError" class="banner" role="alert" hidden></div>

      <div class="rows">
        <div class="row">
          <label for="from">От кого</label>
          <div class="cell"><input id="from" type="email" list="accountList" autocomplete="off" spellcheck="false" placeholder="ящик на вашем сервере"><datalist id="accountList"></datalist></div>
          <div class="cell name"><input id="fromName" type="text" maxlength="60" autocomplete="off" placeholder="Имя (необязательно)" aria-label="Имя отправителя"></div>
        </div>

        <div class="row">
          <label for="toInput">Кому</label>
          <div class="cell"><div class="chips" id="toChips" data-field="to"><input id="toInput" type="text" autocomplete="off" spellcheck="false" placeholder="адрес и Enter"></div></div>
          <button id="moreBtn" class="link" type="button" aria-expanded="false">Копия</button>
        </div>
        <div class="row opt" hidden>
          <label for="ccInput">Копия</label>
          <div class="cell"><div class="chips" id="ccChips" data-field="cc"><input id="ccInput" type="text" autocomplete="off" spellcheck="false" placeholder="адрес и Enter"></div></div>
        </div>
        <div class="row opt" hidden>
          <label for="bccInput">Скрытая</label>
          <div class="cell"><div class="chips" id="bccChips" data-field="bcc"><input id="bccInput" type="text" autocomplete="off" spellcheck="false" placeholder="адрес и Enter"></div></div>
        </div>
        <div class="row opt" hidden>
          <label for="replyTo">Ответить на</label>
          <div class="cell"><input id="replyTo" type="email" autocomplete="off" spellcheck="false" placeholder="если ответы нужны на другой адрес"></div>
        </div>

        <div class="row">
          <label for="subject">Тема</label>
          <div class="cell"><input id="subject" type="text" maxlength="200" autocomplete="off" placeholder="О чём письмо"></div>
          <span id="subjCount" class="count">0</span>
        </div>
      </div>

      <div class="editor">
        <div class="tabs" role="tablist" aria-label="Содержимое письма">
          <button type="button" role="tab" data-tab="text" aria-selected="true">Текст</button>
          <button type="button" role="tab" data-tab="html" aria-selected="false">HTML</button>
          <button type="button" role="tab" data-tab="preview" aria-selected="false">Предпросмотр</button>
        </div>
        <p id="tabHint" class="tab-hint"></p>
        <textarea id="text" placeholder="Напишите текст письма…" aria-label="Текст письма"></textarea>
        <textarea id="html" class="mono" hidden spellcheck="false" placeholder="<p>HTML-версия письма (необязательно)</p>" aria-label="HTML письма"></textarea>
        <div id="previewPane" class="preview" hidden>
          <iframe id="previewFrame" name="previewFrame" sandbox title="Предпросмотр письма"></iframe>
        </div>
      </div>

      <div class="card-foot">
        <span class="hint">Ctrl + Enter — отправить</span>
        <button id="sendBtn" class="btn primary" type="submit">
          <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 2 11 13"/><path d="m22 2-7 20-4-9-9-4z"/></svg>
          <span>Проверить и отправить</span>
        </button>
      </div>
    </form>

    <aside class="side">
      <section class="card">
        <h3>Лимиты отправки</h3>
        <div id="meters"></div>
        <p id="warmNote" class="muted small"></p>
      </section>

      <section class="card">
        <h3>Проверка письма</h3>
        <ul id="checks" class="checks"></ul>
      </section>

      <section class="card">
        <h3>Последние письма</h3>
        <ul id="logList" class="log"></ul>
      </section>
    </aside>
  </main>
</div>

<!-- предпросмотр отправляется обычной формой в изолированный iframe -->
<form id="previewForm" method="post" action="/preview" target="previewFrame" hidden>
  <input type="hidden" name="csrf" id="pvCsrf">
  <input type="hidden" name="text" id="pvText">
  <input type="hidden" name="html" id="pvHtml">
</form>

<dialog id="confirm" class="dialog">
  <form method="dialog" id="confirmForm">
    <h2>Отправить письмо?</h2>
    <dl id="confirmInfo" class="summary"></dl>
    <ul id="confirmWarn" class="checks"></ul>
    <div class="dialog-actions">
      <button class="btn ghost" value="cancel" type="submit">Назад</button>
      <button class="btn primary" id="confirmYes" value="ok" type="submit">Отправить</button>
    </div>
  </form>
</dialog>

<div id="toast" class="toast" role="status" aria-live="polite" hidden></div>

<script src="/app.js" defer></script>
</body>
</html>
__DMS_FILE_END__
mkdir -p "$BUNDLE_DIR/console/public"
cat > "$BUNDLE_DIR/console/public/app.css" <<'__DMS_FILE_END__'
:root {
  color-scheme: light;
  --bg: #f3f4fa;
  --card: #ffffff;
  --ink: #161a2e;
  --muted: #6a7291;
  --line: #e3e6f2;
  --soft: #f6f7fc;
  --accent: #4f46e5;
  --accent-hover: #4338ca;
  --accent-soft: #eceeff;
  --accent-ink: #ffffff;
  --ok: #15803d;
  --ok-soft: #e6f6ec;
  --warn: #b45309;
  --warn-soft: #fff4e0;
  --err: #c81e1e;
  --err-soft: #fdeaea;
  --info: #475a8a;
  --info-soft: #eaf0fb;
  --shadow: 0 1px 2px rgba(20, 24, 60, .05), 0 8px 24px rgba(20, 24, 60, .06);
  --radius: 16px;
  --font: ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, "Noto Sans", sans-serif;
  --mono: ui-monospace, SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace;
}
:root[data-theme="dark"] {
  color-scheme: dark;
  --bg: #0d1020;
  --card: #151932;
  --ink: #e9ecfa;
  --muted: #98a0c6;
  --line: #262c4d;
  --soft: #1a1f3c;
  --accent: #7c83ff;
  --accent-hover: #9097ff;
  --accent-soft: #232a57;
  --accent-ink: #0d1020;
  --ok: #4ade80;
  --ok-soft: #12301f;
  --warn: #fbbf24;
  --warn-soft: #382a0c;
  --err: #ff7b7b;
  --err-soft: #3a1618;
  --info: #9fb4ee;
  --info-soft: #1c2748;
  --shadow: 0 1px 2px rgba(0, 0, 0, .3), 0 10px 30px rgba(0, 0, 0, .28);
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    color-scheme: dark;
    --bg: #0d1020; --card: #151932; --ink: #e9ecfa; --muted: #98a0c6; --line: #262c4d; --soft: #1a1f3c;
    --accent: #7c83ff; --accent-hover: #9097ff; --accent-soft: #232a57; --accent-ink: #0d1020;
    --ok: #4ade80; --ok-soft: #12301f; --warn: #fbbf24; --warn-soft: #382a0c; --err: #ff7b7b; --err-soft: #3a1618;
    --info: #9fb4ee; --info-soft: #1c2748;
    --shadow: 0 1px 2px rgba(0, 0, 0, .3), 0 10px 30px rgba(0, 0, 0, .28);
  }
}

* { box-sizing: border-box; }
[hidden] { display: none !important; }
html { -webkit-text-size-adjust: 100%; }
body {
  margin: 0;
  background: var(--bg);
  color: var(--ink);
  font: 15px/1.5 var(--font);
  -webkit-font-smoothing: antialiased;
}
h1, h2, h3 { margin: 0; letter-spacing: -.01em; }
button, input, textarea { font: inherit; color: inherit; }
.muted { color: var(--muted); }
.small { font-size: 13px; }

/* ---------- кнопки ---------- */
.btn {
  display: inline-flex; align-items: center; justify-content: center; gap: 8px;
  height: 42px; padding: 0 18px; border-radius: 11px; border: 1px solid transparent;
  background: var(--soft); color: var(--ink); font-weight: 600; cursor: pointer;
  transition: background .15s, transform .05s, box-shadow .15s, opacity .15s;
}
.btn:active { transform: translateY(1px); }
.btn.primary { background: var(--accent); color: var(--accent-ink); box-shadow: 0 6px 16px -6px var(--accent); }
.btn.primary:hover { background: var(--accent-hover); }
.btn.ghost { background: transparent; border-color: var(--line); }
.btn.ghost:hover { background: var(--soft); }
.btn.block { width: 100%; }
.btn[disabled] { opacity: .6; cursor: progress; }
.icon-btn {
  width: 42px; height: 42px; border-radius: 11px; border: 1px solid var(--line);
  background: transparent; color: var(--muted); display: grid; place-items: center; cursor: pointer;
}
.icon-btn:hover { background: var(--soft); color: var(--ink); }
.link { background: none; border: 0; color: var(--accent); font-weight: 600; font-size: 13px; cursor: pointer; padding: 6px 4px; }
.link:hover { text-decoration: underline; }
:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }

/* ---------- вход ---------- */
.login { min-height: 100vh; display: grid; place-items: center; padding: 24px 16px; }
.login-card {
  width: 100%; max-width: 400px; background: var(--card); border: 1px solid var(--line);
  border-radius: 20px; padding: 32px 28px; box-shadow: var(--shadow); display: grid; gap: 14px;
}
.login-card h1 { font-size: 24px; }
.login-card p { margin: 0; }
.logo {
  width: 52px; height: 52px; border-radius: 15px; display: grid; place-items: center;
  background: linear-gradient(135deg, var(--accent), #8b5cf6); color: #fff;
  box-shadow: 0 10px 24px -10px var(--accent);
}
.logo.sm { width: 38px; height: 38px; border-radius: 11px; }
.field { display: grid; gap: 6px; font-size: 13px; color: var(--muted); font-weight: 600; }
.field input {
  height: 44px; padding: 0 14px; border-radius: 11px; border: 1px solid var(--line);
  background: var(--soft); font-size: 15px; font-weight: 400; color: var(--ink);
}
.field input:focus { outline: none; border-color: var(--accent); box-shadow: 0 0 0 3px var(--accent-soft); }
.form-error { margin: 0; padding: 10px 12px; border-radius: 10px; background: var(--err-soft); color: var(--err); font-size: 14px; }

/* ---------- шапка ---------- */
.topbar {
  max-width: 1180px; margin: 0 auto; padding: 18px 20px;
  display: flex; align-items: center; justify-content: space-between; gap: 12px;
}
.brand { display: flex; align-items: center; gap: 12px; min-width: 0; }
.brand-text { display: grid; line-height: 1.2; min-width: 0; }
.brand-text small { color: var(--muted); font-size: 12px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.top-actions { display: flex; gap: 8px; }

/* ---------- раскладка ---------- */
.layout {
  max-width: 1180px; margin: 0 auto; padding: 4px 20px 48px;
  display: grid; grid-template-columns: minmax(0, 1fr) 340px; gap: 22px; align-items: start;
}
.side { display: grid; gap: 18px; }
.card {
  background: var(--card); border: 1px solid var(--line); border-radius: var(--radius);
  box-shadow: var(--shadow);
}
.side .card { padding: 18px 20px; }
.side h3 { font-size: 13px; text-transform: uppercase; letter-spacing: .06em; color: var(--muted); margin-bottom: 14px; }

/* ---------- форма письма ---------- */
.compose { overflow: hidden; }
.card-head { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 18px 22px 14px; }
.card-head h2 { font-size: 19px; }
.badge { font-size: 12px; font-weight: 600; padding: 4px 10px; border-radius: 99px; }
.badge.ok { background: var(--ok-soft); color: var(--ok); }
.badge.err { background: var(--err-soft); color: var(--err); }
.banner { margin: 0 22px 12px; padding: 11px 14px; border-radius: 11px; font-size: 14px; background: var(--err-soft); color: var(--err); }

.rows { border-top: 1px solid var(--line); }
.row {
  display: grid; grid-template-columns: 86px minmax(0, 1fr) auto; align-items: center; gap: 8px;
  padding: 4px 22px; border-bottom: 1px solid var(--line); min-height: 52px;
  transition: background .15s;
}
.row:focus-within { background: var(--soft); }
.row > label { color: var(--muted); font-size: 13px; font-weight: 600; }
.row .cell { min-width: 0; display: flex; gap: 8px; }
.row .cell.name { width: 200px; padding-left: 12px; border-left: 1px solid var(--line); }
.row input { width: 100%; min-width: 0; border: 0; background: transparent; padding: 10px 0; font-size: 15px; outline: none; }
.row input::placeholder, textarea::placeholder { color: color-mix(in srgb, var(--muted) 70%, transparent); }
.row .count { color: var(--muted); font-size: 12px; font-variant-numeric: tabular-nums; }
.row:has(.cell.name) { grid-template-columns: 86px minmax(0, 1fr) auto; }

.chips { display: flex; flex-wrap: wrap; gap: 6px; align-items: center; width: 100%; padding: 6px 0; }
.chips input { flex: 1 1 140px; width: auto; min-width: 120px; padding: 6px 0; }
.chips input.bad { color: var(--err); }
.chip {
  display: inline-flex; align-items: center; gap: 4px; max-width: 100%;
  background: var(--accent-soft); color: var(--accent); border-radius: 99px; padding: 3px 4px 3px 12px; font-size: 14px; font-weight: 500;
}
.chip span { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.chip button {
  width: 22px; height: 22px; border-radius: 50%; border: 0; background: transparent; color: inherit; cursor: pointer;
  display: grid; place-items: center; font-size: 16px; line-height: 1; flex: none;
}
.chip button:hover { background: color-mix(in srgb, var(--accent) 22%, transparent); }

/* ---------- редактор ---------- */
.editor { padding: 14px 22px 6px; }
.tabs { display: inline-flex; gap: 4px; padding: 4px; background: var(--soft); border: 1px solid var(--line); border-radius: 12px; }
.tabs button {
  border: 0; background: transparent; color: var(--muted); padding: 7px 14px; border-radius: 9px;
  font-size: 14px; font-weight: 600; cursor: pointer;
}
.tabs button[aria-selected="true"] { background: var(--card); color: var(--ink); box-shadow: 0 1px 3px rgba(20, 24, 60, .12); }
.tab-hint { margin: 10px 0 0; font-size: 13px; color: var(--muted); min-height: 19px; }
.editor textarea {
  display: block; width: 100%; min-height: 300px; margin-top: 6px; padding: 14px 16px; resize: vertical;
  border: 1px solid var(--line); border-radius: 12px; background: var(--card); line-height: 1.6; outline: none;
}
.editor textarea:focus { border-color: var(--accent); box-shadow: 0 0 0 3px var(--accent-soft); }
.editor textarea.mono { font: 13px/1.6 var(--mono); }
.preview { margin-top: 6px; border: 1px solid var(--line); border-radius: 12px; overflow: hidden; background: #fff; }
.preview iframe { display: block; width: 100%; height: 360px; border: 0; background: #fff; }

.card-foot { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 14px 22px 20px; }
.hint { color: var(--muted); font-size: 13px; }

/* ---------- боковая панель ---------- */
.meter + .meter { margin-top: 14px; }
.meter-top { display: flex; justify-content: space-between; font-size: 14px; margin-bottom: 6px; }
.meter-top b { font-variant-numeric: tabular-nums; }
.bar { height: 8px; border-radius: 99px; background: var(--soft); border: 1px solid var(--line); overflow: hidden; }
.bar i { display: block; height: 100%; width: var(--w, 0%); background: var(--accent); border-radius: 99px; transition: width .3s; }
.meter.hot .bar i { background: var(--warn); }
.meter.full .bar i { background: var(--err); }
#warmNote { margin: 14px 0 0; }

.checks { list-style: none; margin: 0; padding: 0; display: grid; gap: 8px; }
.checks li {
  display: grid; grid-template-columns: 22px 1fr; gap: 10px; align-items: start;
  font-size: 14px; line-height: 1.4; padding: 9px 11px; border-radius: 11px; background: var(--soft);
}
.checks li::before {
  content: "i"; width: 22px; height: 22px; border-radius: 50%; display: grid; place-items: center;
  font-size: 12px; font-weight: 800; background: var(--info-soft); color: var(--info);
}
.checks li.ok::before { content: "✓"; background: var(--ok-soft); color: var(--ok); }
.checks li.warn::before { content: "!"; background: var(--warn-soft); color: var(--warn); }
.checks li.error::before { content: "✕"; background: var(--err-soft); color: var(--err); }

.log { list-style: none; margin: 0; padding: 0; display: grid; gap: 4px; }
.log li { display: grid; grid-template-columns: 10px 1fr auto; gap: 10px; align-items: center; padding: 8px 4px; border-radius: 10px; }
.log li + li { border-top: 1px solid var(--line); }
.log .dot { width: 9px; height: 9px; border-radius: 50%; background: var(--ok); }
.log .dot.failed { background: var(--err); }
.log .main { min-width: 0; display: grid; }
.log .main b { font-weight: 600; font-size: 14px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.log .main small { color: var(--muted); font-size: 12px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.log time { color: var(--muted); font-size: 12px; white-space: nowrap; }
.log .empty { display: block; color: var(--muted); font-size: 14px; padding: 4px; }

/* ---------- диалог и уведомление ---------- */
.dialog {
  width: min(480px, calc(100vw - 32px)); border: 1px solid var(--line); border-radius: 18px; padding: 24px;
  background: var(--card); color: var(--ink); box-shadow: 0 30px 80px rgba(10, 12, 40, .35);
}
.dialog::backdrop { background: rgba(10, 12, 30, .5); backdrop-filter: blur(3px); }
.dialog h2 { font-size: 20px; margin-bottom: 16px; }
.summary { margin: 0 0 14px; display: grid; gap: 10px; }
.summary div { display: grid; grid-template-columns: 76px 1fr; gap: 10px; font-size: 14px; }
.summary dt { color: var(--muted); }
.summary dd { margin: 0; word-break: break-word; font-weight: 500; }
.dialog .checks { margin-bottom: 4px; }
.dialog-actions { display: flex; justify-content: flex-end; gap: 10px; margin-top: 18px; }

.toast {
  position: fixed; left: 50%; top: 22px; transform: translateX(-50%); max-width: calc(100vw - 32px);
  background: var(--ink); color: var(--bg); padding: 12px 18px; border-radius: 12px; font-weight: 600; font-size: 14px;
  box-shadow: 0 14px 40px rgba(10, 12, 40, .35); z-index: 50;
}
.toast.err { background: var(--err); color: #fff; }

/* ---------- адаптивность ---------- */
@media (max-width: 980px) {
  .layout { grid-template-columns: minmax(0, 1fr); }
}
@media (max-width: 560px) {
  .topbar { padding: 14px 14px; }
  .layout { padding: 0 12px 40px; gap: 16px; }
  .card-head, .editor, .card-foot { padding-left: 16px; padding-right: 16px; }
  .row { grid-template-columns: 64px minmax(0, 1fr) auto; padding: 2px 16px; }
  .row:has(.cell.name) { grid-template-columns: 64px minmax(0, 1fr); }
  .row .cell.name { grid-column: 2; width: auto; padding-left: 0; border-left: 0; border-top: 1px dashed var(--line); }
  .banner { margin-left: 16px; margin-right: 16px; }
  .hint { display: none; }
  .card-foot { justify-content: stretch; }
  .card-foot .btn { width: 100%; }
  .editor textarea { min-height: 240px; }
}
@media (prefers-reduced-motion: reduce) { * { transition: none !important; } }
__DMS_FILE_END__
mkdir -p "$BUNDLE_DIR/console/public"
cat > "$BUNDLE_DIR/console/public/app.js" <<'__DMS_FILE_END__'
(() => {
  'use strict';

  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const EMAIL = /^[^\s@,;]+@[^\s@,;]+\.[^\s@,;]+$/;

  const state = { csrf: '', accounts: [], usage: null, issues: [], maxRecipients: 5 };
  const chips = { to: [], cc: [], bcc: [] };
  let lintTimer = 0;
  let lintSeq = 0;

  // ---------------------------------------------------------------- утилиты
  function el(tag, props = {}, ...kids) {
    const n = document.createElement(tag);
    for (const [k, v] of Object.entries(props)) {
      if (k === 'class') n.className = v;
      else if (k === 'text') n.textContent = v;
      else n.setAttribute(k, v);
    }
    for (const kid of kids) if (kid) n.append(kid);
    return n;
  }

  async function api(path, body) {
    const opts = { method: body === undefined ? 'GET' : 'POST', headers: {}, credentials: 'same-origin' };
    if (body !== undefined) {
      opts.headers['Content-Type'] = 'application/json';
      opts.headers['X-CSRF-Token'] = state.csrf;
      opts.body = JSON.stringify(body);
    }
    let res;
    try { res = await fetch(path, opts); } catch { throw Object.assign(new Error('Нет связи с сервером.'), { network: true }); }
    let data = {};
    try { data = await res.json(); } catch { /* пустой ответ */ }
    if (res.status === 401 && path !== '/api/login') { showLogin(); throw Object.assign(new Error('Требуется вход.'), { handled: true }); }
    if (!res.ok) throw Object.assign(new Error(data.error || `Ошибка ${res.status}`), { data, status: res.status });
    return data;
  }

  let toastTimer = 0;
  function toast(text, isErr) {
    const t = $('#toast');
    t.textContent = text;
    t.className = 'toast' + (isErr ? ' err' : '');
    t.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { t.hidden = true; }, isErr ? 6000 : 3200);
  }

  // ---------------------------------------------------------------- тема
  function applyTheme(t) {
    if (t) document.documentElement.setAttribute('data-theme', t);
  }
  try { applyTheme(localStorage.getItem('theme')); } catch { /* хранилище недоступно */ }
  $('#themeBtn').addEventListener('click', () => {
    const cur = document.documentElement.getAttribute('data-theme')
      || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
    const next = cur === 'dark' ? 'light' : 'dark';
    applyTheme(next);
    try { localStorage.setItem('theme', next); } catch { /* ignore */ }
  });

  // ---------------------------------------------------------------- вход / выход
  function showLogin() {
    $('#app').hidden = true;
    $('#login').hidden = false;
    $('#loginPass').value = '';
    $('#loginPass').focus();
  }
  function showApp() {
    $('#login').hidden = true;
    $('#app').hidden = false;
  }

  $('#loginForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    const err = $('#loginError');
    err.hidden = true;
    const btn = $('#loginForm button[type=submit]');
    btn.disabled = true;
    try {
      await api('/api/login', { password: $('#loginPass').value });
      await boot();
    } catch (ex) {
      err.textContent = ex.message;
      err.hidden = false;
      $('#loginPass').select();
    } finally { btn.disabled = false; }
  });

  $('#logoutBtn').addEventListener('click', async () => {
    try { await api('/api/logout', {}); } catch { /* всё равно выходим */ }
    showLogin();
  });

  // ---------------------------------------------------------------- получатели (чипсы)
  function initChips(box) {
    const key = box.dataset.field;
    const input = $('input', box);

    function render() {
      $$('.chip', box).forEach((c) => c.remove());
      chips[key].forEach((addr, i) => {
        const rm = el('button', { type: 'button', 'aria-label': `Убрать ${addr}`, text: '×' });
        rm.addEventListener('click', () => { chips[key].splice(i, 1); render(); scheduleCheck(); });
        box.insertBefore(el('span', { class: 'chip' }, el('span', { text: addr }), rm), input);
      });
    }

    function commit() {
      const parts = input.value.split(/[\s,;]+/).filter(Boolean);
      let bad = false;
      for (const p of parts) {
        const a = p.toLowerCase();
        if (!EMAIL.test(a)) { bad = true; continue; }
        if (!chips[key].includes(a)) chips[key].push(a);
      }
      input.value = bad ? parts.filter((p) => !EMAIL.test(p.toLowerCase())).join(' ') : '';
      input.classList.toggle('bad', bad);
      render();
      scheduleCheck();
      return !bad;
    }

    input.addEventListener('keydown', (e) => {
      if (['Enter', ',', ';', ' ', 'Tab'].includes(e.key) && input.value.trim()) {
        if (e.key !== 'Tab') e.preventDefault();
        commit();
      } else if (e.key === 'Backspace' && !input.value && chips[key].length) {
        chips[key].pop(); render(); scheduleCheck();
      }
    });
    input.addEventListener('blur', () => { if (input.value.trim()) commit(); });
    input.addEventListener('paste', () => setTimeout(commit, 0));
    input.addEventListener('input', () => input.classList.remove('bad'));
    box.addEventListener('click', (e) => { if (e.target === box) input.focus(); });
    box.commit = commit;
    box.render = render;
  }
  $$('.chips').forEach(initChips);

  $('#moreBtn').addEventListener('click', () => {
    const open = $$('.row.opt')[0].hidden;
    $$('.row.opt').forEach((r) => { r.hidden = !open; });
    $('#moreBtn').setAttribute('aria-expanded', String(open));
    $('#moreBtn').textContent = open ? 'Скрыть' : 'Копия';
  });

  // ---------------------------------------------------------------- отправитель
  function fromStatus() {
    const v = $('#from').value.trim().toLowerCase();
    const badge = $('#fromState');
    if (!v) { badge.hidden = true; return null; }
    const known = state.accounts.some((a) => a.address === v);
    badge.hidden = false;
    badge.className = 'badge ' + (known ? 'ok' : 'err');
    badge.textContent = known ? 'Ящик подключён' : 'Нет такого ящика на сервере';
    return known;
  }
  $('#from').addEventListener('input', () => {
    fromStatus();
    const acc = state.accounts.find((a) => a.address === $('#from').value.trim().toLowerCase());
    if (acc && acc.name && !$('#fromName').value) $('#fromName').value = acc.name;
    scheduleCheck();
  });

  // ---------------------------------------------------------------- вкладки
  const HINTS = {
    text: 'Простой текст. Так лучше всего читаются личные письма.',
    html: 'Если оставить «Текст» пустым, текстовая версия создастся из HTML автоматически.',
    preview: 'Так письмо увидит получатель (скрипты и формы удалены).',
  };
  let currentTab = 'text';
  function setTab(tab) {
    currentTab = tab;
    $$('.tabs button').forEach((b) => b.setAttribute('aria-selected', String(b.dataset.tab === tab)));
    $('#text').hidden = tab !== 'text';
    $('#html').hidden = tab !== 'html';
    $('#previewPane').hidden = tab !== 'preview';
    $('#tabHint').textContent = HINTS[tab];
    if (tab === 'preview') {
      $('#pvCsrf').value = state.csrf;
      $('#pvText').value = $('#text').value;
      $('#pvHtml').value = $('#html').value;
      $('#previewForm').submit();
    }
  }
  $$('.tabs button').forEach((b) => b.addEventListener('click', () => setTab(b.dataset.tab)));

  // ---------------------------------------------------------------- проверка письма
  function allRecipients() {
    return [...new Set([...chips.to, ...chips.cc, ...chips.bcc])];
  }

  function clientChecks() {
    const out = [];
    const known = fromStatus();
    if (known === false) out.push({ level: 'error', text: 'Отправитель не совпадает ни с одним ящиком сервера. Письмо не будет отправлено.' });
    const n = allRecipients().length;
    if (n > state.maxRecipients) out.push({ level: 'error', text: `Получателей ${n}, а можно не больше ${state.maxRecipients}. Это консоль для личных писем, не для рассылок.` });
    return out;
  }

  function renderChecks() {
    const list = $('#checks');
    list.replaceChildren();
    const items = [...clientChecks(), ...state.issues];
    if (!items.length) items.push({ level: 'ok', text: 'Замечаний нет. Письмо выглядит нормально.' });
    for (const it of items) list.append(el('li', { class: it.level, text: it.text }));
  }

  function scheduleCheck() {
    renderChecks();
    clearTimeout(lintTimer);
    lintTimer = setTimeout(runLint, 500);
  }

  async function runLint() {
    const seq = ++lintSeq;
    const subject = $('#subject').value, text = $('#text').value, html = $('#html').value;
    if (!subject && !text && !html) { state.issues = []; renderChecks(); return; }
    try {
      const r = await api('/api/lint', { subject, text, html });
      if (seq !== lintSeq) return;
      // пока письмо не заполнено, ошибки «пусто» не показываем
      const incomplete = !subject.trim() || (!text.trim() && !html.trim());
      state.issues = r.issues.filter((i) => !(incomplete && i.level === 'error'));
      renderChecks();
    } catch { /* проверка необязательна */ }
  }

  $('#subject').addEventListener('input', () => { $('#subjCount').textContent = String($('#subject').value.length); scheduleCheck(); });
  $('#text').addEventListener('input', scheduleCheck);
  $('#html').addEventListener('input', scheduleCheck);
  $('#fromName').addEventListener('input', scheduleCheck);

  // ---------------------------------------------------------------- лимиты и журнал
  function renderUsage() {
    const u = state.usage;
    if (!u) return;
    const box = $('#meters');
    box.replaceChildren();
    for (const [label, m] of [['За последний час', u.hour], ['За сутки', u.day]]) {
      const pct = Math.min(100, Math.round((m.used / m.limit) * 100));
      const meter = el('div', { class: 'meter' + (pct >= 100 ? ' full' : pct >= 80 ? ' hot' : '') },
        el('div', { class: 'meter-top' }, el('span', { text: label }), el('b', { text: `${m.used} / ${m.limit}` })),
        el('div', { class: 'bar' }, el('i')));
      $('i', meter).style.setProperty('--w', pct + '%');
      box.append(meter);
    }
    $('#warmNote').textContent = u.warmupDay <= 14
      ? `Идёт «прогрев» нового сервера, день ${u.warmupDay}. Лимит растёт сам: так Gmail и другие почтовики привыкают к вашему адресу.`
      : 'Лимиты считаются по числу получателей.';
    state.maxRecipients = u.maxRecipients || 5;
  }

  async function loadLog() {
    try {
      const { items } = await api('/api/log');
      const ul = $('#logList');
      ul.replaceChildren();
      if (!items.length) { ul.append(el('li', { class: 'empty', text: 'Пока ничего не отправлено.' })); return; }
      for (const it of items.slice(0, 8)) {
        const who = it.to[0] + (it.to.length > 1 ? ` и ещё ${it.to.length - 1}` : '');
        const when = new Date(it.t).toLocaleString('ru-RU', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
        const li = el('li', { title: it.error || '' },
          el('span', { class: 'dot ' + (it.status === 'sent' ? '' : 'failed') }),
          el('div', { class: 'main' }, el('b', { text: it.subject || '(без темы)' }), el('small', { text: `${it.from} → ${who}` })),
          el('time', { text: when }));
        ul.append(li);
      }
    } catch { /* ignore */ }
  }

  // ---------------------------------------------------------------- отправка
  function showFormError(msg) {
    const b = $('#formError');
    b.textContent = msg || '';
    b.hidden = !msg;
    if (msg) b.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  }

  function payload() {
    return {
      from: $('#from').value.trim().toLowerCase(),
      fromName: $('#fromName').value.trim(),
      to: chips.to, cc: chips.cc, bcc: chips.bcc,
      replyTo: $('#replyTo').value.trim(),
      subject: $('#subject').value.trim(),
      text: $('#text').value,
      html: $('#html').value,
    };
  }

  function validateLocal(p) {
    if (!p.from) return 'Укажите, с какого ящика отправлять.';
    if (!state.accounts.some((a) => a.address === p.from)) return 'Такого ящика нет на сервере. Отправлять можно только с созданных ящиков.';
    if (!p.to.length) return 'Добавьте хотя бы одного получателя в поле «Кому».';
    if (allRecipients().length > state.maxRecipients) return `Слишком много получателей (максимум ${state.maxRecipients}).`;
    if (!p.subject) return 'Укажите тему письма.';
    if (!p.text.trim() && !p.html.trim()) return 'Письмо пустое: напишите текст или вставьте HTML.';
    return '';
  }

  $('#composeForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    showFormError('');
    $$('.chips').forEach((c) => c.commit && c.commit());
    const p = payload();
    const problem = validateLocal(p);
    if (problem) { showFormError(problem); return; }

    // свежая серверная проверка для окна подтверждения
    let issues = [];
    try { issues = (await api('/api/lint', { subject: p.subject, text: p.text, html: p.html })).issues; } catch (ex) { if (ex.handled) return; }
    const blocking = issues.find((i) => i.level === 'error');
    if (blocking) { showFormError(blocking.text); return; }

    const info = $('#confirmInfo');
    info.replaceChildren();
    const row = (k, v) => info.append(el('div', {}, el('dt', { text: k }), el('dd', { text: v })));
    row('От', p.fromName ? `${p.fromName} <${p.from}>` : p.from);
    row('Кому', p.to.join(', '));
    if (p.cc.length) row('Копия', p.cc.join(', '));
    if (p.bcc.length) row('Скрытая', p.bcc.join(', '));
    row('Тема', p.subject);
    row('Формат', p.html.trim() ? (p.text.trim() ? 'текст + HTML' : 'HTML + автотекст') : 'простой текст');
    const w = $('#confirmWarn');
    w.replaceChildren();
    issues.filter((i) => i.level === 'warn').forEach((i) => w.append(el('li', { class: 'warn', text: i.text })));

    const dlg = $('#confirm');
    $('#confirmForm').onsubmit = null;
    dlg.returnValue = '';
    dlg.showModal();
    dlg.onclose = () => { if (dlg.returnValue === 'ok') doSend(p); };
  });

  async function doSend(p) {
    const btn = $('#sendBtn');
    const label = $('span', btn);
    btn.disabled = true;
    label.textContent = 'Отправляю…';
    try {
      const r = await api('/api/send', p);
      state.usage = r.usage;
      renderUsage();
      toast('Письмо отправлено');
      chips.to = []; chips.cc = []; chips.bcc = [];
      $$('.chips').forEach((c) => c.render());
      $('#subject').value = ''; $('#subjCount').textContent = '0';
      $('#text').value = ''; $('#html').value = '';
      state.issues = [];
      renderChecks();
      if (currentTab === 'preview') setTab('text');
      loadLog();
    } catch (ex) {
      if (ex.handled) return;
      showFormError(ex.message);
      toast('Письмо не отправлено', true);
      loadLog();
    } finally {
      btn.disabled = false;
      label.textContent = 'Проверить и отправить';
    }
  }

  document.addEventListener('keydown', (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key === 'Enter' && !$('#app').hidden && !$('#confirm').open) {
      e.preventDefault();
      $('#composeForm').requestSubmit();
    }
  });

  // ---------------------------------------------------------------- запуск
  async function boot() {
    let s;
    try { s = await api('/api/session'); } catch (ex) { showLogin(); return; }
    if (!s.authenticated) { showLogin(); return; }
    state.csrf = s.csrf;
    state.accounts = s.accounts;
    state.usage = s.usage;
    $('#hostPill').textContent = s.mailHost;
    const dl = $('#accountList');
    dl.replaceChildren(...s.accounts.map((a) => el('option', { value: a.address })));
    if (!$('#from').value && s.accounts.length) {
      $('#from').value = s.accounts[0].address;
      if (s.accounts[0].name) $('#fromName').value = s.accounts[0].name;
    }
    $('#tabHint').textContent = HINTS[currentTab];
    showApp();
    fromStatus();
    renderUsage();
    renderChecks();
    loadLog();
  }
  boot();
})();
__DMS_FILE_END__
chmod +x "$BUNDLE_DIR"/*.sh
echo "Скрипты распакованы в $BUNDLE_DIR"
[[ "${EXTRACT_ONLY:-0}" == "1" ]] && exit 0
exec bash "$BUNDLE_DIR/install.sh"
