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

# 1. 找 anchor 行号 (if/then/else 消除 pipefail 静默死亡 — 对齐 check-d-backlinks:50)
#    旧写法 $(grep ... | head | cut) 在 set -euo pipefail 下, grep 零命中 (exit 1)
#    经 pipefail 传播 → set -e 在本行即暴毙, 下方 exit 3 友好分支永不可达 (死代码).
if match=$(grep -n -F "$ANCHOR" "$SRC"); then
  first_line=${match%%$'\n'*}       # 取首个命中行
  ANCHOR_LINE=${first_line%%:*}     # 剥 grep -n 的行号前缀
else
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
#    先建 OUT 目录: extracted/ 是 gitignored, clean clone 上不存在,
#    否则 sed 重定向 "> $OUT" 在新克隆首跑即 "No such file or directory".
if [[ "$OUT" != "/dev/stdout" ]]; then
  mkdir -p "$(dirname "$OUT")"
fi
sed -n "$((FENCE_OPEN + 1)),$((FENCE_CLOSE - 1))p" "$SRC" > "$OUT"

if [[ "$OUT" != "/dev/stdout" ]]; then
  echo "extracted: $OUT (lines $((FENCE_OPEN + 1))-$((FENCE_CLOSE - 1)) of $SRC)" >&2
fi