#!/usr/bin/env bash
# =============================================================================
# R51-M6-size-csv.sh — 正向断言: size-csv 工具链锁定 --elf-output-style=JSON
# =============================================================================
# 抽取源: docs/13-build-pipeline.md, anchor "R51-M6"
# 期望: llvm-readobj --elf-output-style=JSON + jq '[].Symbols[].Symbol'
#       旧旗标 --syms --json 仅出现在 OBSOLETED 上下文中, 不在活代码中
# 失败模式: 活代码仍用 --syms --json (LLVM 18 空表空真过)
# =============================================================================
set -euo pipefail

SRC="docs/13-build-pipeline.md"

# 验证 1: 活代码块含 --elf-output-style=JSON
LIVE_LINES=$(grep -n 'elf-output-style=JSON' "$SRC" | grep -v '#' | grep -v OBSOLETED | grep -v '//' || true)
if [ -z "$LIVE_LINES" ]; then
  echo "FAIL: R51-M6 活代码中缺失 --elf-output-style=JSON" >&2
  exit 1
fi

# 验证 2: jq 三层路径存在
if ! grep -q "Symbols.*Symbol" "$SRC"; then
  echo "FAIL: R51-M6 jq 三层路径缺失 (.[].Symbols[].Symbol)" >&2
  exit 1
fi

# 验证 3: 活代码不得含 --syms --json 旧旗标.
#         豁免: 审计注释 (错误命令 / R47 草图 / R47 勘误 / P3-7 / R51-M6 说明 / OBSOLETED)
if grep -n '\-\-syms.*\-\-json' "$SRC" \
    | grep -v 'OBSOLETED' \
    | grep -v '错误命令' \
    | grep -v 'R47 草图' \
    | grep -v 'R47 勘误' \
    | grep -v 'P3-7' \
    | grep -v 'R51-M6' \
    | grep -v '# R51' \
    | grep -v '旧命令' \
    | grep -v '旧脚本' \
    | grep -q .; then
  echo "FAIL: R51-M6 活代码仍含 --syms --json (LLVM 18 不存在 --json)" >&2
  grep -n '\-\-syms.*\-\-json' "$SRC" | grep -v 'OBSOLETED' | grep -v '错误命令' | grep -v 'R47 草图' | grep -v 'R47 勘误' | grep -v 'P3-7' | grep -v 'R51-M6' | grep -v '# R51' | grep -v '旧命令' | grep -v '旧脚本' >&2
  exit 1
fi

echo "PASS: R51-M6-size-csv (--elf-output-style=JSON + jq [].Symbols[].Symbol)"
exit 0
