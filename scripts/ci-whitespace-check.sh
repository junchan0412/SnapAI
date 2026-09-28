#!/usr/bin/env bash
# CI 的空白检查:对「本次改动的范围」跑 git diff --check。
#
# 为什么需要它:Actions 的工作区永远是干净检出,直接跑 `git diff --check`
# 恒为空 —— 看似在检查,实际什么都没查。本机 preflight 检查的是未提交改动,
# 语义不同,所以 CI 这边显式传入基线提交。
#
# 用法:
#   scripts/ci-whitespace-check.sh              # 本机:检查工作区(等价 git diff --check)
#   scripts/ci-whitespace-check.sh <base>       # CI:检查 base..HEAD 范围
set -euo pipefail
cd "$(dirname "$0")/.."

base="${1:-}"
zero="0000000000000000000000000000000000000000"

if [ -z "$base" ] || [ "$base" = "$zero" ]; then
  echo "==> 没有可比对的基线提交(新建分支/本地),退回工作区检查"
  git diff --check
  exit 0
fi

if ! git cat-file -e "$base^{commit}" 2>/dev/null; then
  echo "==> 基线 $base 不在本地,退回检查最近一次提交"
  git log -1 --check --pretty=format: HEAD
  exit 0
fi

echo "==> 检查 $base..HEAD 的空白问题"
git diff --check "$base..HEAD"
