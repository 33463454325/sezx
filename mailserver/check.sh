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
