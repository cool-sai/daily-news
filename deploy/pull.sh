#!/usr/bin/env bash
# 从 GitHub 拉取最新内容；失败时保留旧内容。
set -uo pipefail
REPO_DIR="${REPO_DIR:-/srv/daily-news}"
BRANCH="${BRANCH:-main}"
LOG="${LOG:-/var/log/daily-news-pull.log}"
LOCK="${LOCK:-/run/daily-news-pull.lock}"
RETRIES="${RETRIES:-3}"
TIMEOUT="${TIMEOUT:-120}"

log() { echo "[$(date '+%F %T')] $*" >>"$LOG"; }

exec 9>"$LOCK"
if ! flock -n 9; then log "上一次拉取仍在运行，跳过"; exit 0; fi

cd "$REPO_DIR" || { log "目录 $REPO_DIR 不存在"; exit 1; }
export GIT_TERMINAL_PROMPT=0
for i in $(seq 1 "$RETRIES"); do
  if timeout "$TIMEOUT" git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 \
       fetch --depth 1 origin "$BRANCH" >>"$LOG" 2>&1; then
    old=$(git rev-parse HEAD)
    if git reset --hard "origin/$BRANCH" >>"$LOG" 2>&1; then
      new=$(git rev-parse HEAD)
      [ "$old" = "$new" ] && log "无更新 ($new)" || log "已更新 $old -> $new"
      exit 0
    fi
  fi
  log "第 $i 次拉取失败，保留旧内容"
  sleep $((i * 10))
done
log "拉取最终失败，网站继续使用旧内容"
exit 1
