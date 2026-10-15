#!/usr/bin/env bash
# news.lssl.work 一键部署（需 root，可重复执行）
# 可选环境变量：
#   GH_MIRROR   GitHub 镜像前缀，如 https://ghproxy.example.com/ （留空直连）
#   DOMAIN      默认 news.lssl.work
#   EMAIL       申请证书用的邮箱（可选）
#   SKIP_SYSTEMD=1  不安装/启动 timer（测试用）
set -euo pipefail
DOMAIN="${DOMAIN:-news.lssl.work}"
REPO_URL="https://github.com/cool-sai/daily-news.git"
GH_MIRROR="${GH_MIRROR:-}"
DEST=/srv/daily-news
CLONE_URL="${GH_MIRROR}${REPO_URL}"

[ "$(id -u)" -eq 0 ] || { echo "请用 root 运行（sudo bash install.sh）"; exit 1; }
say() { echo -e "\033[32m==>\033[0m $*"; }

# 1. 安装依赖
if command -v apt-get >/dev/null; then PM=apt
elif command -v dnf >/dev/null; then PM=dnf
elif command -v yum >/dev/null; then PM=yum
else echo "不支持的发行版（无 apt/dnf/yum）"; exit 1; fi
need=()
for c in git nginx flock timeout; do command -v "$c" >/dev/null || need+=("$c"); done
if [ ${#need[@]} -gt 0 ]; then
  pkgs=()
  for c in "${need[@]}"; do
    case $c in flock|timeout) pkgs+=(util-linux coreutils);; *) pkgs+=("$c");; esac
  done
  say "安装: ${pkgs[*]}"
  if [ $PM = apt ]; then apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
  else $PM install -y "${pkgs[@]}" || { $PM install -y epel-release && $PM install -y "${pkgs[@]}"; }; fi
else say "git/nginx 已安装，跳过"; fi

# 2. 克隆仓库（带重试和超时）
if [ -d "$DEST/.git" ]; then
  say "$DEST 已存在，更新 remote"
  git -C "$DEST" remote set-url origin "$CLONE_URL"
else
  ok=0
  for i in 1 2 3 4 5; do
    rm -rf "$DEST.tmp"
    if timeout 300 git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 \
         clone --depth 1 "$CLONE_URL" "$DEST.tmp"; then ok=1; break; fi
    echo "clone 第 $i 次失败，$((i*10)) 秒后重试..."; sleep $((i*10))
  done
  [ $ok = 1 ] || { echo "clone 失败。可设置 GH_MIRROR 镜像前缀后重试"; exit 1; }
  [ -e "$DEST" ] && mv "$DEST" "$DEST.bak.$(date +%s)"
  mv "$DEST.tmp" "$DEST"
fi
chmod 755 "$DEST"
install -m 755 "$DEST/deploy/pull.sh" /usr/local/bin/daily-news-pull
touch /var/log/daily-news-pull.log

# 3. nginx 配置（独立文件，不碰已有站点）
if [ -d /etc/nginx/sites-available ] && grep -q 'sites-enabled' /etc/nginx/nginx.conf; then
  CONF=/etc/nginx/sites-available/$DOMAIN.conf; LINK=/etc/nginx/sites-enabled/$DOMAIN.conf
else
  CONF=/etc/nginx/conf.d/$DOMAIN.conf; LINK=""
fi
mkdir -p /var/www/letsencrypt
BACKUP=""
[ -f "$CONF" ] && { BACKUP="$CONF.bak.$(date +%s)"; cp -a "$CONF" "$BACKUP"; }
# 已签证书时保留 HTTPS 段（certbot --nginx 写入的内容不覆盖）
if [ -n "$BACKUP" ] && grep -q 'ssl_certificate' "$CONF"; then
  say "$CONF 已含 HTTPS 配置，保留不覆盖"
else
cat >"$CONF" <<NGX
# 由 daily-news/deploy/install.sh 生成
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    root $DEST;
    index index.html;

    location ^~ /.well-known/acme-challenge/ { root /var/www/letsencrypt; default_type text/plain; }
    location ~ /\.(?!well-known) { deny all; return 404; }
    location ^~ /deploy/ { deny all; return 404; }
    location ~* \.(py|sh|md)$ { deny all; return 404; }

    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml image/svg+xml;

    location ~* \.(css|js|png|jpg|jpeg|gif|svg|ico|woff2?)$ { expires 7d; add_header Cache-Control "public"; }
    location ~* \.json$ { expires 5m; add_header Cache-Control "public, must-revalidate"; }
    location / { try_files \$uri \$uri/ =404; add_header Cache-Control "no-cache"; }
}
NGX
fi
[ -n "$LINK" ] && ln -sf "$CONF" "$LINK"

if nginx -t; then
  if pgrep -x nginx >/dev/null; then nginx -s reload; say "nginx 已 reload"
  elif command -v systemctl >/dev/null && [ "${SKIP_SYSTEMD:-0}" != 1 ]; then systemctl enable --now nginx
  else say "nginx 未运行，请手动启动"; fi
else
  echo "nginx -t 失败，回滚配置，不 reload"
  if [ -n "$BACKUP" ]; then mv -f "$BACKUP" "$CONF"; else rm -f "$CONF"; [ -n "$LINK" ] && rm -f "$LINK"; fi
  exit 1
fi

# 4. systemd timer
cat >/etc/systemd/system/daily-news-pull.service <<UNIT
[Unit]
Description=Pull daily-news from GitHub
Wants=network-online.target
After=network-online.target
[Service]
Type=oneshot
Environment=REPO_DIR=$DEST
ExecStart=/usr/local/bin/daily-news-pull
UNIT
cat >/etc/systemd/system/daily-news-pull.timer <<UNIT
[Unit]
Description=Pull daily-news every 15 min and at 10:30
[Timer]
OnCalendar=*:0/15
OnCalendar=*-*-* 10:30:00
Persistent=true
RandomizedDelaySec=30
[Install]
WantedBy=timers.target
UNIT
if [ "${SKIP_SYSTEMD:-0}" != 1 ] && command -v systemctl >/dev/null; then
  systemctl daemon-reload && systemctl enable --now daily-news-pull.timer
  say "timer 已启用"
fi

IP=$(curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null || echo "本机公网IP")
cat <<MSG

部署完成（HTTP）。下一步：
 1. 腾讯云 DNS：把 news 的 CNAME 记录改为 A 记录 -> $IP
 2. 安全组/防火墙放行 80、443
 3. 解析生效后申请证书：
    certbot --nginx -d $DOMAIN ${EMAIL:+-m $EMAIL} --agree-tos --redirect
    （无 certbot：apt install certbot python3-certbot-nginx / dnf install certbot python3-certbot-nginx）
 4. 验证：curl -I http://$DOMAIN/
MSG
