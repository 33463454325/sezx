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
