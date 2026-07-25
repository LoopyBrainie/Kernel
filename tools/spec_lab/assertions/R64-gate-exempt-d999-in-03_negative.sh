#!/usr/bin/env bash
# =============================================================================
# R64-gate-exempt-d999-in-03_negative.sh — F1 实证金丝雀 #1: D999 伪造 marker 落 03 必须被抓
# =============================================================================
# 漏洞史 (R64 commit 8052b4d → R64-HOTFIX):
#   R64 commit 中 §2b 复用 §1 EXCLUDE_GREP, 排除 03/20/30, 但 R65 起 49 个 marker
#   会落 03 + 1 文件级声明落 30 — 即 "R65 起任何不存在的 D### 立即 fail" 立法承诺
#   对 98% marker 不成立 (docs/99-tmp.md 伪造 D999 → exit 1; 同一伪造落 03 → exit 0).
# 修复: §2b 换独立排除集 (仅排 ci/ 脚本), 同步 EOL $ 锚 + SPEC.md 扫描面.
# 本断言实证修复方向:
#   - mktemp副本 docs/03-design-decisions.md 追加伪造 marker `<!-- gate-exempt: D999 -->`
#   - 在副本上跑 check-d-backlinks.sh → 必须 exit 1 (D999 不在 ledger)
#   - 若 RC=1 → 反向 PASS (修复有效, 漏洞回归有看守)
# GOV (R49-GOV.6): 变异只发生在 mktemp 副本, 真 spec 恒不可变
# =============================================================================
set -euo pipefail

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp -r docs "$WORK/docs"
mkdir -p "$WORK/docs/ci"
cp docs/ci/*.sh "$WORK/docs/ci/" 2>/dev/null || true

# F1 canary: 在 03-design-decisions.md (R65 起 49 marker 的落盘文件) 追加伪造 D999 marker
# 注意: marker 形貌必须严格匹配 §2b 正则 `<!-- gate-exempt(-file)?:.*-->[[:space:]]*$`,
#   即 `<!-- gate-exempt:` 紧跟, 不能加诊断前缀 (否则副本 §2b 抽不到, RC=0 但语义是"测试失能"非"修复有效")
printf '\n<!-- gate-exempt: D999 -->\n' >> "$WORK/docs/03-design-decisions.md"

# 副本上跑 §2b 完整逻辑 (含反向链 §1 + canary §3)
if ( cd "$WORK" && bash docs/ci/check-d-backlinks.sh >/dev/null 2>&1 ); then
  RC=0
else
  RC=$?
fi

# 期望: §2b 抓到 D999 → exit 1 (FAIL) → 反向 PASS
if [[ "$RC" -eq 1 ]]; then
  echo "PASS: R64-gate-exempt-d999-in-03_negative (F1 修复实证: 伪造 D999 in 03 被 §2b 抓到, RC=$RC)"
  exit 0
else
  echo "FAIL: R64-gate-exempt-d999-in-03_negative (F1 漏洞复发: §2b 未抓 D999 in 03, RC=$RC)" >&2
  exit 1
fi