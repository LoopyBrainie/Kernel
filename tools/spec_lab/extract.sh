#!/usr/bin/env bash
# =============================================================================
# spec_lab/extract.sh — anchor → fence 抽取器
# =============================================================================
# 用法: extract.sh <anchor_text> <source_md>
# 行为: 在 source_md 里 grep anchor 所在行, 取其后第一个代码围栏
#       (```` ``` ````  配对), 写到 stdout (或 extracted/<id>.ext)
# R49 立骨: 禁止写死代码副本到 assertion 目录, 必须走本抽取器
# =============================================================================
set -euo pipefail

ANCHOR="${1:-}"
SRC="${2:-}"
OUT="${3:-/dev/stdout}"

if [[ -z "$ANCHOR" || -z "$SRC" ]]; then
  echo "usage: extract.sh <anchor_text> <source_md> [out_path]" >&2
  exit 2
fi
if [[ ! -f "$SRC" ]]; then
  echo "ERR: source not found: $SRC" >&2
  exit 2
fi

# 1. 找 anchor 行号
ANCHOR_LINE=$(grep -n -F "$ANCHOR" "$SRC" | head -1 | cut -d: -f1)
if [[ -z "$ANCHOR_LINE" ]]; then
  echo "ERR: anchor not found in $SRC: $ANCHOR" >&2
  exit 3
fi

# 2. 找 anchor 行所在的最小围栏 (向上找最近围栏起点 + 向下找围栏终点)
#    R49-F1 修法: anchor 可能位于围栏内 (作为勘误注释), 不能简单找 anchor 之后的下一个围栏
FENCE_OPEN=$(awk -v end="$ANCHOR_LINE" 'NR <= end && /^```[a-zA-Z]*/ { last = NR } END { print last }' "$SRC")
if [[ -z "$FENCE_OPEN" || "$FENCE_OPEN" == "0" ]]; then
  echo "ERR: no opening code fence before anchor at line $ANCHOR_LINE" >&2
  exit 4
fi

FENCE_CLOSE=$(awk -v start="$FENCE_OPEN" 'NR > start && /^```$/ { print NR; exit }' "$SRC")
if [[ -z "$FENCE_CLOSE" ]]; then
  echo "ERR: unclosed code fence starting at line $FENCE_OPEN" >&2
  exit 5
fi

# 3. 抽取围栏内容 (不含 ``` 标记本身)
sed -n "$((FENCE_OPEN + 1)),$((FENCE_CLOSE - 1))p" "$SRC" > "$OUT"

if [[ "$OUT" != "/dev/stdout" ]]; then
  echo "extracted: $OUT (lines $((FENCE_OPEN + 1))-$((FENCE_CLOSE - 1)) of $SRC)" >&2
fi