#!/usr/bin/env bash
# =============================================================================
# R51-F5-rev8.sh — 正向断言: 06 § rev8 字节反转实现必须显式 slli+srli
# =============================================================================
# 抽取源: docs/06-boot-sequence.md, anchor "R51-F5 (D-13) byte-swap t0"
# 期望: 抽取出的 asm 围栏内非注释行含 slli 与 srli 指令, 不应含 rev8 (rv64imac 无 Zbb)
# 通过条件: 非注释行含 slli 指令 + 含 srli 指令 + 不含 rev8
# 失败模式: 草图退化为 `rev8 t0, t0` 或忽略 Zbb 不可用假设
# =============================================================================
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="docs/06-boot-sequence.md"
ANCHOR="R51-F5 (D-13) byte-swap t0"
EXTRACT="$LAB_DIR/extracted/R51-F5-rev8.ext"

bash "$LAB_DIR/extract.sh" "$ANCHOR" "$SRC" "$EXTRACT" >&2

# Filter non-comment lines (msys-safe: ^\s* 替代 [[:space:]])
NOCOM=$(grep -vE '^\s*(#|//)' "$EXTRACT")

# 验证 1a: 非注释行必须含 slli 指令
if ! echo "$NOCOM" | grep -qE '^\s*slli\b'; then
  echo "FAIL: R51-F5-rev8 抽取的非注释行不含 'slli' 指令" >&2
  echo "---- 抽取内容 ----" >&2
  cat "$EXTRACT" >&2
  exit 1
fi

# 验证 1b: 非注释行必须含 srli 指令
if ! echo "$NOCOM" | grep -qE '^\s*srli\b'; then
  echo "FAIL: R51-F5-rev8 抽取的非注释行不含 'srli' 指令" >&2
  echo "---- 抽取内容 ----" >&2
  cat "$EXTRACT" >&2
  exit 1
fi

# 验证 2: 非注释行必须不含 rev8 (rv64imac 无 Zbb)
if echo "$NOCOM" | grep -qE '^\s*rev8\b'; then
  echo "FAIL: R51-F5-rev8 指令行仍含 'rev8' — 假设 Zbb 不可用, 必须 slli+srli" >&2
  exit 1
fi

echo "PASS: R51-F5-rev8 (06-boot-sequence.md § byte-swap 已显式化为 slli+srli)"
exit 0