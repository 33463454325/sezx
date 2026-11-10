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
apt-get install -y -qq curl ca-certificates dnsutils openssl unattended-upgrades >/dev/null
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
if [[ "\$before" != "\$after" ]]; then docker restart mailserver >/dev/null; fi
EOF
chmod +x /usr/local/bin/mailserver-cert-renew.sh
cat > /etc/cron.d/mailserver-certbot <<'EOF'
17 3 * * * root /usr/local/bin/mailserver-cert-renew.sh
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
exit 0
