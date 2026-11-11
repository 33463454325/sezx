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
