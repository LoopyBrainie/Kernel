#!/usr/bin/env bash
# =============================================================================
# audit-rust-unsafe.sh — Rust shell unsafe 计数门禁 (R49 prev_cr 清零)
# =============================================================================
# 目标: 把 Rust shell 源码 unsafe 计数从沙箱二 O5 实测 5 处降到 ≤3
# 用法: bash audit-rust-unsafe.sh path/to/shell/src
# 通过条件: unsafe 计数 ≤ 3 (含 payload 解码 1 + FFI 调用 2)
# 失败模式: unsafe > 3, 必须通过封装 / 抽象把 unsafe 集中到 ≤3 处
# 沙箱执行: 本脚本在沙箱内对 shell/src/*.rs 递归 grep
#   grep -rn 'unsafe' shell/src --include='*.rs' | grep -v '//' | wc -l
# R49 落点: 沙箱三执行本脚本, 输出 artifacts/rust_unsafe_count.txt,
#          C7 证据补丁配套, run_all.sh 调用前须先有该 artifact
# =============================================================================
set -euo pipefail

SRC_DIR="${1:?usage: audit-rust-unsafe.sh <shell/src/path>}"

if [[ ! -d "$SRC_DIR" ]]; then
  echo "ERR: $SRC_DIR is not a directory" >&2
  exit 2
fi

# 1. 计数 unsafe 块 (粗略: 含 'unsafe' 关键字的行, 去注释/字符串)
UNSAFE_COUNT=$(grep -rn '\bunsafe\b' "$SRC_DIR" --include='*.rs' \
  | grep -v '^\s*//' \
  | grep -v '/\*' \
  | wc -l)

echo "Rust unsafe count: $UNSAFE_COUNT (target ≤ 3)"

# 2. 详细位置 (供降低时参考)
echo "---- unsafe locations ----"
grep -rn '\bunsafe\b' "$SRC_DIR" --include='*.rs' \
  | grep -v '^\s*//' || true

# 3. 闸门
if [[ "$UNSAFE_COUNT" -gt 3 ]]; then
  echo "FAIL: unsafe count $UNSAFE_COUNT > 3 (R49 prev_cr 清零目标 ≤3)" >&2
  exit 1
fi

echo "PASS: R49 prev_cr 警告清零 (unsafe ≤ 3)"
exit 0