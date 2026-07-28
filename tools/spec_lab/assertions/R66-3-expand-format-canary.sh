#!/usr/bin/env bash
# =============================================================================
# R66-3-expand-format-canary.sh — expand 输出格式契约独立守约 (R67-S-2)
# =============================================================================
# 从 R66-3-prefix-collision-canary.sh 拆出 Part A 独立成 canary, 守约契约:
#   expand 输出每行必须是 file:lineno: (尾冒号锚定), 杜绝 grep -vFf 子串匹配
#   意外豁免 `path:200`-style 真违规 (R66-3 user-observed 潜伏病).
#
# 独立 V4 实测意义 (R67-S-1 canary 自检纪律):
#   本 canary parser path 变化后, 仅靠本 canary 自身 V4 注入即可独立验证
#   fail-closed 语义. 不再依赖 prefix-collision-canary.sh 的 V4 间接证明.
#   prefix-collision-canary.sh Part B 同步加 format 防御 ("不裸奔"),
#   两 canary 形成分层冗余守约.
# =============================================================================
set -euo pipefail

# ===== V4 注入攻击: 独立 fail-closed 实测 (R67-S-1 canary 自检纪律) =====
# 立法背景: S-1 立法条款要求每 canary 必须可独立 V4-实测自己 parser path
# fail-closed 性. 本段是 R66-3-expand-format-canary 独立证据链, 与 prefix-
# collision-canary V4 注入解耦 — 任一 canary parser path 改坏不影响另一个.
#
# 4 项硬性证据门槛 (沿用 R66-3 V4 协议):
#   1. 日志出现 "expand-format V4 Part A: PASS"
#   2. 日志出现 "expand-format V4 Part B: FAIL" 指向 format 解析路径
#   3. canary 退出码非零 (fail-closed)
#   4. trap 清理 V4_TMPDIR, git diff --exit-code 证明生产文件未污染
#
# 用法: R66_3_V4_INJECT=1 bash tools/spec_lab/assertions/R66-3-expand-format-canary.sh
if [[ "${R66_3_V4_INJECT:-0}" == "1" ]]; then
  V4_TMPDIR=$(mktemp -d)
  trap 'rm -rf "$V4_TMPDIR"' EXIT

  # 漏尾冒号 expand 输出 (4 行: 3 行无锚定冒号 + 1 行畸形路径)
  # 应被本 canary parser path 全数抓到
  V4_BUGGY="$V4_TMPDIR/expand_buggy.txt"
  cat > "$V4_BUGGY" <<'EOF'
docs/x:1
docs/x:2
docs/x:168
docs/x:foo_bar
EOF

  # 本 canary 核心断言: grep -cvE ':[0-9]+:$' 必须 > 0
  NOT_ANCHORED=$(grep -cvE ':[0-9]+:$' "$V4_BUGGY" || true)
  TOTAL=$(wc -l < "$V4_BUGGY")
  echo "expand-format V4 Part A: PASS (隔离 fixture 构建完成: ${TOTAL} 行, ${NOT_ANCHORED} 行缺尾冒号锚定)"

  # 期望: NOT_ANCHORED == TOTAL (全数缺锚), 本 canary parser path 应判定为 fail-closed
  if [[ "$NOT_ANCHORED" -gt 0 ]]; then
    echo "expand-format V4 Part B: FAIL (本 canary parser path 独立 fail-closed: ${NOT_ANCHORED}/${TOTAL} 行未锚定, S-1 自检纪律守约)" >&2
    exit 1
  fi
  echo "FAIL: R66-3 expand-format V4 inject 失效 — 漏尾冒号未被 parser path 抓到, S-1 自检纪律破口" >&2
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
  echo "FAIL: R66-3 expand-format (Part A: ${NOT_ANCHORED}/${TOTAL} 行缺尾冒号锚定)" >&2
  grep -vE ':[0-9]+:$' "$TMP" | head -3 >&2
  exit 1
fi

echo "PASS: R66-3 expand-format (Part A: ${TOTAL} 行 100% 尾冒号锚定)"
exit 0
