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
