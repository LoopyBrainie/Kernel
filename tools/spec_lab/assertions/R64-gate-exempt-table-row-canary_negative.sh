#!/usr/bin/env bash
# =============================================================================
# R64-gate-exempt-table-row-canary_negative.sh — F4 实证金丝雀 #3: 表格行末单元格 D999 marker 必须被抓
# =============================================================================
# 漏洞史 (R64-HOTFIX 留待 R65-α 修补):
#   R65 计划 49/50 marker 落在 docs/03-design-decisions.md 立法表 D-table 行,
#   表格行以 | 收尾, R64-HOTFIX 后正则 `<!-- gate-exempt(-file)?:.*-->[[:space:]]*$`
#   要求 `-->` 紧随行尾, 表格行内 marker (`-->` 后接 ` |`) 永远匹配不上.
#   等同于 49/50 marker "白写" (抽取器与 §2b 同时失明).
# 修复 (R65-α F4): regex 同步扩为 `-->[[:space:]]*\|?[[:space:]]*$`
#   (单字符 `\|?` 允许表格行末 ` |`, 与抽取器同款).
# 本断言实证修复方向 (反向断言 — 验证 §2b 抓得到):
#   - mktemp 副本 docs/03-design-decisions.md 追加 D-table 行:
#       `| D999 | X | ACTIVE | 伪造行 <!-- gate-exempt: D999 --> |`
#   - 在副本上跑 check-d-backlinks.sh → 必须 exit 1 (D999 不在 ledger)
#   - 若 RC=1 → 反向 PASS (F4 修复有效, 表格行 marker 不再失明)
#   - 若 RC=0 → 反向 FAIL (F4 漏洞: 表格行 marker 仍被 §2b 忽略)
# 与 R64-gate-exempt-d999-in-03_negative 配对 (后者测末行追加, 本断言测表格行内).
# GOV (R49-GOV.6): 变异只发生在 mktemp 副本, 真 spec 恒不可变
# =============================================================================
set -euo pipefail

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp -r docs "$WORK/docs"
mkdir -p "$WORK/docs/ci"
cp docs/ci/*.sh "$WORK/docs/ci/" 2>/dev/null || true

# F4 canary: 在 03-design-decisions.md (R65 起 49 marker 的落盘文件) 追加 D-table 行
# marker 放末单元格, 形貌严格匹配 F4 修复后的正则:
#   `<!-- gate-exempt(-file)?:.*-->[[:space:]]*\|?[[:space:]]*$`
# 关键: `-->` 后仅 ` |` (无诊断前缀, 无 narrative 字符)
printf '\n| F4 canary | X | ACTIVE | 伪造行 <!-- gate-exempt: D999 --> |\n' >> "$WORK/docs/03-design-decisions.md"

# 副本上跑 §2b 完整逻辑 (含反向链 §1 + canary §3)
if ( cd "$WORK" && bash docs/ci/check-d-backlinks.sh >/dev/null 2>&1 ); then
  RC=0
else
  RC=$?
fi

# 期望: §2b 抓到表格行内 D999 → exit 1 → 反向 PASS
if [[ "$RC" -eq 1 ]]; then
  echo "PASS: R64-gate-exempt-table-row-canary_negative (F4 修复实证: 表格行末单元格 D999 被 §2b 抓到, RC=$RC)"
  exit 0
else
  echo "FAIL: R64-gate-exempt-table-row-canary_negative (F4 漏洞复发: 表格行 marker §2b 仍失明, RC=$RC)" >&2
  exit 1
fi