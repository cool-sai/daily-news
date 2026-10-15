# news.lssl.work 自托管部署

服务器定时从 GitHub 拉取本仓库，用 Nginx 直接提供静态文件。不会修改服务器上已有的站点（如 www.lssl.work），只新增一个独立的 `news.lssl.work` 配置文件。

## 1. 安装（root）

```bash
curl -fsSL https://raw.githubusercontent.com/cool-sai/daily-news/main/deploy/install.sh -o /tmp/install.sh && sudo bash /tmp/install.sh
```

GitHub 访问不畅时可加镜像前缀（会拼在 `https://github.com/...` 前面）：

```bash
sudo GH_MIRROR=https://你的镜像/ bash /tmp/install.sh
```

脚本会：安装 git/nginx（已装则跳过）→ clone 到 `/srv/daily-news` → 写入 nginx 配置（Debian/Ubuntu 用 sites-available，其余用 conf.d）→ `nginx -t` 通过才 reload，失败自动回滚 → 安装 systemd timer（每 15 分钟及每天 10:30 拉取）。可重复执行。

## 2. 腾讯云 DNS
在 DNSPod 控制台把主机记录 `news` 的 **CNAME（cool-sai.github.io）改为 A 记录**，值为服务器公网 IP。

## 3. 放行端口
腾讯云安全组（轻量服务器叫“防火墙”）入站放行 TCP 80、443。系统防火墙如有开启：
```bash
firewall-cmd --permanent --add-service=http --add-service=https && firewall-cmd --reload   # CentOS/Rocky
ufw allow 80,443/tcp                                                                    # Ubuntu
```

## 4. 申请证书（DNS 生效后）
```bash
# Ubuntu/Debian
apt install -y certbot python3-certbot-nginx
# CentOS/RHEL/Rocky/OpenCloudOS
dnf install -y epel-release; dnf install -y certbot python3-certbot-nginx
certbot --nginx -d news.lssl.work --agree-tos -m 你的邮箱 --redirect
```
备选 acme.sh：`acme.sh --issue -d news.lssl.work -w /var/www/letsencrypt`，再按其文档 `--install-cert` 并在配置中加 443 段。certbot 自带自动续期。

## 5. 验证
```bash
dig +short news.lssl.work          # 应为服务器 IP
curl -I http://news.lssl.work/     # 200
curl -I https://news.lssl.work/    # 证书后 200
curl -I https://news.lssl.work/.git/config   # 应 404
systemctl list-timers daily-news-pull.timer
```

## 6. 日志与手动拉取
```bash
tail -f /var/log/daily-news-pull.log
sudo systemctl start daily-news-pull.service    # 立即拉一次
journalctl -u daily-news-pull.service
```

## 7. 卸载
```bash
sudo bash /srv/daily-news/deploy/uninstall.sh   # PURGE=1 同时删除 /srv/daily-news
```

## 8. 关于仓库根目录 CNAME / GitHub Pages
DNS 改成 A 记录并在服务器上签好证书、`https://news.lssl.work` 验证正常之后，再删除仓库根目录的 `CNAME` 文件（或在 Pages 设置里清空自定义域名）。在此之前不要删，否则 Pages 和自托管之间会有一段时间打不开。删除后 GitHub Pages 回到 `cool-sai.github.io/daily-news/` 作为备用地址。
