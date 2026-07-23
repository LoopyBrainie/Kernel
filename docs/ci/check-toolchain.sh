#!/usr/bin/env bash
# =============================================================================
# Wriggly-Octopus Toolchain Lock Gate (R49-GOV / 工具链区间锁格式门)
# =============================================================================
# 校验根 toolchain.lock 存在且四工具 (zig/qemu/rustc/llvm) 均以区间形态锁定:
#   <tool> = [<下界: spec 现值>, <上界: 实测已验证>]
# 下界 = docs/ 现行锁定值; 上界 = mvp 实测通过值 (tool_versions.txt).
# 本门只验"格式立法 + 四工具齐全", 不做主机版本落区间比较
# (那属 build.zig 构建期 / Phase 1 实测, 不属文档门).
# Exit codes: 0 = 格式合规, 1 = 缺文件 / 缺工具 / 区间格式错
# =============================================================================
set -euo pipefail

LOCK="toolchain.lock"
GATE="check-toolchain"

if [[ ! -f "$LOCK" ]]; then
  echo "[FAIL] $GATE: 根 $LOCK 不存在 — docs/13 / docs/05 / docs/15 引它为权威源, 必须落盘"
  exit 1
fi

MISSING=()
for tool in zig qemu rustc llvm; do
  # 形态: tool = [lo, hi]  (方括号闭区间, 逗号分隔上下界)
  if ! grep -qE "^[[:space:]]*${tool}[[:space:]]*=[[:space:]]*\[[^],]+,[^]]+\]" "$LOCK"; then
    MISSING+=("$tool")
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "[FAIL] $GATE: 以下工具缺区间锁 [lo, hi]: ${MISSING[*]}"
  echo "       格式: <tool> = [<下界 spec 现值>, <上界 实测>]"
  exit 1
fi

echo "✓ $GATE passed (toolchain.lock 四工具区间锁齐全: zig/qemu/rustc/llvm)"
