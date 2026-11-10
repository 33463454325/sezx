# Почтовый сервер dpsradar.world + dpsradar.net

Отправка и приём почты с двух ваших доменов на одном сервере
`mail.dpsradar.world` (IP `31.76.94.174`). docker-mailserver: SMTP/IMAP,
DKIM/SPF/DMARC, антиспам Rspamd, Fail2ban, TLS Let's Encrypt.

Ящики: `info@dpsradar.world`, `mail@dpsradar.net`.

> Это не «спуфинг». Чтобы письма с `dpsradar.net` не попадали в спам Gmail,
> у домена `dpsradar.net` должны быть свои записи SPF/DKIM/DMARC (см. ниже).
> Иначе Google отклонит или положит их в спам — обойти это нельзя.

## Шаг 1. DNS — добавьте уже сейчас

**dpsradar.world**
```
A     mail       31.76.94.174
MX    @          mail.dpsradar.world.   (приоритет 10)
TXT   @          v=spf1 ip4:31.76.94.174 -all
TXT   _dmarc     v=DMARC1; p=none; rua=mailto:dmarc@dpsradar.world; adkim=r; aspf=r
```

**dpsradar.net**
```
MX    @          mail.dpsradar.world.   (приоритет 10)
TXT   @          v=spf1 ip4:31.76.94.174 -all
TXT   _dmarc     v=DMARC1; p=none; rua=mailto:dmarc@dpsradar.net; adkim=r; aspf=r
```

- **НЕ добавляйте AAAA (IPv6)** — сервер шлёт только по IPv4.
- `mail._domainkey` (DKIM) добавите **после** шага 2: ключ сгенерирует сервер
  и покажет в конце установки (и в файле `/opt/mailserver/DNS-RECORDS.txt`).

## Шаг 2. У хостинга сервера

1. **PTR (обратная запись):** `31.76.94.174` → `mail.dpsradar.world`.
   Настраивается в панели VPS или через тикет в поддержку. Без неё Gmail режет почту.
2. **Откройте исходящий порт 25.** Многие провайдеры его блокируют. Если скрипт
   напишет «порт 25 закрыт» — напишите в поддержку, чтобы разблокировали.

## Самый простой путь: один файл

Файл `all-in-one.sh` содержит все скрипты внутри. Скопируйте его на сервер
(например, вставьте в `nano all-in-one.sh` в Termius) и запустите:

```bash
passwd                                  # сначала смените пароль root
CLEANUP_VPN=1 bash all-in-one.sh        # удалит VPN и поставит почту
```

Скрипты распакуются в `/opt/mailserver-src`, остальное сделает установка.
Если нужны отдельные файлы — читайте шаг 3 ниже.

## Шаг 3. Установка отдельными файлами (по желанию)

Зайдите по SSH (с телефона — Termius/JuiceSSH) под root и выполните:

```bash
# смените root-пароль (он засветился), потом ставьте сервер:
passwd

curl -fsSL https://raw.githubusercontent.com/<ваш-гит>/sezx/claude/google-gemini-integration-k8oaw1/mailserver/install.sh -o install.sh
curl -fsSL https://raw.githubusercontent.com/<ваш-гит>/sezx/claude/google-gemini-integration-k8oaw1/mailserver/cleanup-vpn.sh -o cleanup-vpn.sh
curl -fsSL https://raw.githubusercontent.com/<ваш-гит>/sezx/claude/google-gemini-integration-k8oaw1/mailserver/check.sh -o check.sh

sudo CLEANUP_VPN=1 bash install.sh
```

`CLEANUP_VPN=1` сначала удалит VPN-ПО (xray/v2ray/x-ui/wireguard/openvpn и т.п.),
освободит порты и только потом поставит почту. Без него VPN не трогается.

Если код ещё не в GitHub — просто скопируйте три файла на сервер любым способом
(в Termius можно вставить содержимое в `nano install.sh`).

## Шаг 4. Добавьте DKIM и проверьте

В конце установки появится запись `mail._domainkey` для каждого домена —
добавьте её в DNS. Потом на сервере:

```bash
bash /opt/mailserver/check.sh
```

Все пункты должны быть `[OK]`. Финальный тест — письмо на адрес с
<https://www.mail-tester.com> (цель 9–10/10).

## Как не попасть в спам: первые 2–3 недели

Новый IP и домен не имеют репутации. Технически всё настроено, но репутацию набирает только время:

| Период | Сколько писем в день | Кому |
|---|---|---|
| Дни 1–3 | 5–10 | Людям, которые ответят (знакомые) |
| Дни 4–7 | 20–30 | Тем же и новым, письма разные |
| Неделя 2 | 50–100 | Постепенно, без резких скачков |
| Неделя 3+ | по потребности | Следите за жалобами |

- Не рассылайте одинаковый текст пачками и не вставляйте много ссылок в первых письмах.
- Если получатель нашёл письмо в спаме — попросите нажать «Не спам» и ответить.
- Подключите оба домена в Google Postmaster Tools (postmaster.google.com): он покажет репутацию.
- Через 1–2 недели с чистыми DMARC-отчётами поменяйте в `_dmarc` `p=none` на `p=quarantine`.
- Проверка перед отправкой важных писем: `bash send-test.sh info@dpsradar.world you@gmail.com`,
  затем в Gmail «Показать оригинал»: SPF, DKIM, DMARC — все PASS.
- Домены на зоне `.world` и `.net` фильтры иногда встречают настороженно: это нормально, лечится временем.

## Файлы

| Файл | Назначение |
|---|---|
| `install.sh` | Установка и настройка почтового сервера |
| `cleanup-vpn.sh` | Удаление VPN/proxy-ПО (запускается при `CLEANUP_VPN=1` или отдельно) |
| `check.sh` | Проверка DNS и сервера по обоим доменам |

## Параметры install.sh (необязательно)

```bash
MAIL_HOST=mail.dpsradar.world \
ACCOUNTS="info@dpsradar.world mail@dpsradar.net" \
CLEANUP_VPN=1 \
sudo bash install.sh
```
`SKIP_CHECKS=1` — продолжать даже при неуспешных предварительных проверках.

## Почтовый клиент

```
IMAP: mail.dpsradar.world  порт 993  SSL/TLS
SMTP: mail.dpsradar.world  порт 465  SSL/TLS  (или 587 STARTTLS)
Логин — полный адрес, пароль — из /root/mail-credentials.txt
```
