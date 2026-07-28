#!/usr/bin/env bash
# =============================================================================
# R66-3-prefix-collision-canary.sh — 行号前缀碰撞潜伏病硬判据 (R66-3 顺手注记)
# =============================================================================
# 验证 expand_gate_exempt.py 输出格式契约:
#   每行必须是 file:N: (尾冒号锚定), 杜绝 `path:20` 子串匹配意外豁免 `path:200-209`
# 潜伏病场景 (R66-3 user-observed, 今天无碰撞但未来某行号成前缀即静默豁免):
#   expand 输出 `docs/03-design-decisions.md:168:` (marker on line 168)
#   真命中  `docs/03-design-decisions.md:1680:cosmo_open` (line 1680, 168 的前缀碰撞)
#   gate 跑 grep -vFf $expand < hit, 若扩展开头无尾冒号 → 子串匹配 → false豁免 (BUG)
#   尾冒号锚定后   → 子串匹不中 → 真违规被 gate 抓 (守约)
# =============================================================================
set -euo pipefail

# ===== V4 注入攻击: Part B 独立 fail-closed 实测 (R66-3 follow-up V4) =====
# 仅在 R66_3_V4_INJECT=1 时触发; 模拟漏尾冒号 expand 输出, 验证 Part B
# 解析路径在 BUG 状态下仍 fail-closed。
#
# 立法背景: R66-3 立法链已证明"漏尾冒号 → 子串匹配 → false豁免"是过去式
# (Part A + Part B PASS), 但 canary 自身的解析路径变更后, 若未独立验证,
# 可能形同空转 (V4 缺口: 仅观察到 Part A FAIL, Part B FAIL 未被独立观测)。
# 本段作为方法论债的偿付: 独立证据链覆盖 Part B fail-closed 语义。
#
# 4 项硬性证据门槛:
#   1. 日志出现 "V4 Part A: PASS"
#   2. 日志出现 "V4 Part B: FAIL" (前缀碰撞/行号解析断言)
#   3. canary 退出码非零 (fail-closed)
#   4. git diff --exit-code 证明生产文件未污染, 临时 fixture 已清理 (trap 同时清理 V4_TMPDIR)
#
# 用法: R66_3_V4_INJECT=1 bash tools/spec_lab/assertions/R66-3-prefix-collision-canary.sh
if [[ "${R66_3_V4_INJECT:-0}" == "1" ]]; then
  V4_TMPDIR=$(mktemp -d)
  trap 'rm -rf "$V4_TMPDIR"' EXIT

  # 漏尾冒号 expand 输出: 模拟 R66-3 立法链之前的 BUG 状态
  V4_BUGGY="$V4_TMPDIR/expand_buggy.txt"
  cat > "$V4_BUGGY" <<'EOF'
docs/x:1
docs/x:2
docs/x:168
EOF

  # 真实命中候选: 行号 1680, 前缀碰撞 168 (与原 canary Part B 同源几何)
  V4_MOCK_HIT="docs/x:1680:cosmo_open 真违规"
  SURVIVED=$(echo "$V4_MOCK_HIT" | grep -vFf "$V4_BUGGY" || true)

  # V4 期望: 漏尾冒号 → 子串匹配 → false豁免 → SURVIVED 为空
  # 这是 BUG 状态的几何效应; canary 观察到它应当 fail-closed
  echo "V4 Part A: PASS (隔离 fixture 构建完成)"
  if [[ -z "$SURVIVED" ]]; then
    echo "V4 Part B: FAIL (前缀碰撞潜伏病触发: 'docs/x:168' 子串命中 '$V4_MOCK_HIT' 而 false豁免, Part B 解析路径 fail-closed)" >&2
    exit 1
  fi
  echo "FAIL: V4 注入攻击 fail-closed (漏尾冒号未触发子串匹配, SURVIVED='${SURVIVED}', 模拟失效)" >&2
  exit 1
fi

WORK="${PWD}"
EXPAND="$WORK/tools/spec_lab/expand_gate_exempt.sh"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

cd "$WORK"
bash "$EXPAND" > "$TMP" 2>/dev/null

TOTAL=$(wc -l < "$TMP")

# Part A: 全集行号锚定守约 (任何展开输出必须以 冒号+数字+冒号 收尾)
NOT_ANCHORED=$(grep -cvE ':[0-9]+:$' "$TMP" || true)
if [[ "$NOT_ANCHORED" -ne 0 ]]; then
  echo "FAIL: R66-3 prefix-collision-canary (Part A: ${NOT_ANCHORED}/${TOTAL} 行缺尾冒号锚定)" >&2
  grep -vE ':[0-9]+:$' "$TMP" | head -3 >&2
  exit 1
fi

# Part B: 真实碰撞模拟 — 取首个 SELF 锚,构造 1680/1681/1689 三个前缀碰撞候选
ANCHOR=$(grep -E '^docs/03-design-decisions.md:[0-9]+:$' "$TMP" | head -1 || true)
if [[ -z "$ANCHOR" ]]; then
  echo "NOTE: R66-3 prefix-collision-canary Part B (跳过 — 03 无 SELF 锚行, Part A 已守约)"
  echo "PASS: R66-3 prefix-collision-canary (Part A: ${TOTAL} 行 100% 尾冒号锚定, 潜伏病根治)"
  exit 0
fi

N=$(echo "$ANCHOR" | awk -F: '{print $(NF-1)}' | tr -d ':')
HITS=0
for SUFFIX in 0 1 9; do
  NK="${N}${SUFFIX}"
  MOCK_HIT="docs/03-design-decisions.md:${NK}:cosmo_open 真违规 content here"
  # 真实门禁子流水线: grep -vFf $expand < mock_hit → 应保留 mock_hit
  SURVIVED=$(echo "$MOCK_HIT" | grep -vFf "$TMP" || true)
  if [[ "$SURVIVED" == "$MOCK_HIT" ]]; then
    HITS=$((HITS + 1))
  fi
done

if [[ "$HITS" -ne 3 ]]; then
  echo "FAIL: R66-3 prefix-collision-canary (Part B: anchor=${ANCHOR} 三前缀碰撞候选仅 ${HITS}/3 未被 false豁免, 尾冒号锚定失效)" >&2
  exit 1
fi

echo "PASS: R66-3 prefix-collision-canary (Part A ${TOTAL} 行 100% 锚定 + Part B anchor=${ANCHOR} 三前缀碰撞候选 3/3 未被 false豁免, 潜伏病根治)"
exit 0
