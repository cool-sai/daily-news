#!/usr/bin/env bash
# 移除 news.lssl.work 部署（不卸载 nginx/git，不动其它站点）
set -euo pipefail
DOMAIN="${DOMAIN:-news.lssl.work}"
[ "$(id -u)" -eq 0 ] || { echo "请用 root 运行"; exit 1; }
if command -v systemctl >/dev/null; then
  systemctl disable --now daily-news-pull.timer 2>/dev/null || true
fi
rm -f /etc/systemd/system/daily-news-pull.{service,timer} /usr/local/bin/daily-news-pull
command -v systemctl >/dev/null && systemctl daemon-reload || true
rm -f "/etc/nginx/sites-enabled/$DOMAIN.conf" "/etc/nginx/sites-available/$DOMAIN.conf" "/etc/nginx/conf.d/$DOMAIN.conf"
if nginx -t; then nginx -s reload 2>/dev/null || true; fi
[ "${PURGE:-0}" = 1 ] && rm -rf /srv/daily-news
echo "已卸载。站点文件保留在 /srv/daily-news（PURGE=1 可一并删除）；证书可用 certbot delete --cert-name $DOMAIN 删除。"
