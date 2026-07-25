#!/usr/bin/env bash
# =============================================================================
# R64-gate-exempt-narrative-canary.sh — F1 实证金丝雀 #2: narrative 提及不触发 §2b 误报
# =============================================================================
# 漏洞史 (R64 commit 8052b4d → R64-HOTFIX):
#   §2b 若没有 EOL $ 锚, markdown 反引号包裹 / 括号后接 等 narrative 形式会误报
#   (例 03:388 立法行含 `R51-D1722` 字面, `<!-- gate-exempt: ... -->` 后接反引号或括号,
#    在无 $ 锚时 `\bD[0-9]+\b` 仍会抽出, 然后 §2b 反伪规则自伤合法叙述豁免).
# 修复: §2b 加 EOL `$` 锚 `<!-- gate-exempt(-file)?:.*-->[[:space:]]*$` (与抽取器同款).
# 本断言实证修复方向 (positive canary — 验证 "无 false-positive"):
#   - mktemp副本 注入三种 narrative 提及 (反引号包裹 / 括号后接 / 斜杠后接):
#       a) `<!-- gate-exempt: D172 -->` 反引号包裹
#       b) `<!-- gate-exempt: D175 --> (单 D 形式)` 括号后接
#       c) `<!-- gate-exempt: D### --> / <!-- gate-exempt: R##-D### -->` 斜杠后接
#   - 在副本上跑 check-d-backlinks.sh → 必须 exit 0 (narrative 不被 §2b 当 marker 抽)
#   - 若 RC=0 → positive PASS (修复有效, 无 false-positive)
#   - 若 RC=1 → positive FAIL (EOL $ 锚失效, narrative 误报)
# 与 R64-gate-exempt-d999-in-03_negative 配对: 一个抓真 violation, 一个证无 false-positive
# GOV (R49-GOV.6): 变异只发生在 mktemp 副本, 真 spec 恒不可变
# =============================================================================
set -euo pipefail

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp -r docs "$WORK/docs"
mkdir -p "$WORK/docs/ci"
cp docs/ci/*.sh "$WORK/docs/ci/" 2>/dev/null || true

# F1 canary #2: 在 05-call-gate.md (典型 narrative 文件) 注入三种 narrative 提及
# 真 marker (在 EOL) 也加一行, 确保 §2b 仍能正确处理合法 marker + 排除 narrative
cat >> "$WORK/docs/05-call-gate.md" <<'EOF'

<!-- F1 canary: legitimate marker at EOL (control) -->
some real text <!-- gate-exempt: D175 -->
<!-- F1 canary: narrative form 1, backtick-wrapped -->
describes marker `<!-- gate-exempt: D172 -->` in narrative
<!-- F1 canary: narrative form 2, paren-followed -->
shows form <!-- gate-exempt: D175 --> (单 D 形式)
<!-- F1 canary: narrative form 3, slash-followed (multi-marker line) -->
formats: <!-- gate-exempt: D### --> / <!-- gate-exempt: R##-D### --> / <!-- gate-exempt: D###,D### -->
EOF

# 副本上跑 §2b 完整逻辑 (含反向链 §1 + canary §3)
if ( cd "$WORK" && bash docs/ci/check-d-backlinks.sh >/dev/null 2>&1 ); then
  RC=0
else
  RC=$?
fi

# 期望: §2b 抓到唯一的真 marker D175 (合法), 忽略三种 narrative (EOL $ 锚生效) → exit 0
if [[ "$RC" -eq 0 ]]; then
  echo "PASS: R64-gate-exempt-narrative-canary (F1 修复实证: EOL \$ 锚生效, narrative 不误报)"
  exit 0
else
  echo "FAIL: R64-gate-exempt-narrative-canary (EOL \$ 锚失效: narrative 触发 §2b 误报, RC=$RC)" >&2
  exit 1
fi