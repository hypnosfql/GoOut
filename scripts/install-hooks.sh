#!/bin/bash
# 安装 git hooks（pre-commit：单元测试 100% 通过才允许提交）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
git config core.hooksPath .githooks
chmod +x .githooks/pre-commit
echo "git hooks installed: core.hooksPath=.githooks"
