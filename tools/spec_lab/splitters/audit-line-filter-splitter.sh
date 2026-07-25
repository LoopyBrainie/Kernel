#!/usr/bin/env bash
# R65-β 修后拆分器: 4-line core algorithm
# \ 转义跳过、(/) 计深度、深度 0 处按 | 切
#
# Why this exists: R65-β 用户复验指出原拆分器在 `D160 (配套|矩阵)` 的
# `(` 处误增深度, 把其后 ~80 条 alternation 合并成一个 blob, 导致:
# 1. total 算错 (161 vs 真实 239)
# 2. 死码/活跃分类错 (78 vs 真实 55)
#
# This splitter: char-level scan, skip `\X` as 2 chars literal, depth counter on
# unescaped ( and ), split on | at depth 0.
#
# Usage:
#   bash tools/spec_lab/splitters/audit-line-filter-splitter.sh          # 默认 docs/ci/check-docs.sh
#   bash tools/spec_lab/splitters/audit-line-filter-splitter.sh <file>   # 指定文件
set -euo pipefail

CHECK="${1:-docs/ci/check-docs.sh}"

# 1. Extract value (between first and last ')
value=$(grep -n '^AUDIT_LINE_FILTER' "$CHECK" | head -1 | awk -F"'" 'NF==3 {print $2}')

# 2. Strip leading "grep -vE \"" and trailing "\""
value="${value#grep -vE \"}"
value="${value%\"}"

# 3. FIXED 4-line split algorithm
alts=()
current=""
depth=0
n=${#value}
for ((i=0; i<n; i++)); do
  ch="${value:$i:1}"
  if [[ "$ch" == "\\" ]]; then
    # Skip escape + next char (literal sequence, no depth change)
    current+="$ch"
    if (( i+1 < n )); then
      current+="${value:$((i+1)):1}"
      i=$((i+1))
    fi
  elif [[ "$ch" == "(" ]]; then
    depth=$((depth+1))
    current+="$ch"
  elif [[ "$ch" == ")" ]]; then
    depth=$((depth-1))
    current+="$ch"
  elif [[ "$ch" == "|" && "$depth" -eq 0 ]]; then
    alts+=("$current")
    current=""
  else
    current+="$ch"
  fi
done
[[ -n "$current" ]] && alts+=("$current")

total=${#alts[@]}

# 4. Paren balance sanity check
opens=$(printf '%s' "$value" | tr -cd '(' | wc -c)
closes=$(printf '%s' "$value" | tr -cd ')' | wc -c)
balance_diff=$((opens - closes))

echo "Total top-level alternations: $total"
echo "Paren balance: (=$opens )=$closes diff=$balance_diff"

# 5. Classify each alt (active/dead) by hits in docs/ SPEC.md
#    Use a single mega-regex file for grep -f to avoid shell-quoting bugs.
declare -A alt_class

# Build mega-regex file (one pattern per line)
mega=$(mktemp)
printf '%s\n' "${alts[@]}" > "$mega"

for idx in "${!alts[@]}"; do
  alt="${alts[$idx]}"
  if [[ "$alt" == *"[OBSOLETED"* ]]; then
    alt_class[$idx]="R51"
    continue
  fi
  # Use grep -F -f (one-line pattern file) to test this single alt
  pattern_file=$(mktemp)
  printf '%s' "$alt" > "$pattern_file"
  if grep -rqE --exclude=check-docs.sh --exclude=check-d-backlinks.sh \
       --exclude=check_goal_manifest.sh --exclude=check-toolchain.sh \
       --exclude=20-documentation-gate.md --exclude=30-open-questions.md \
       -f "$pattern_file" docs/ SPEC.md 2>/dev/null; then
    alt_class[$idx]="active"
  else
    alt_class[$idx]="dead"
  fi
  rm -f "$pattern_file"
done
rm -f "$mega"

active=0
r51=0
dead=0
for idx in "${!alts[@]}"; do
  case "${alt_class[$idx]}" in
    active) active=$((active+1)) ;;
    R51)    r51=$((r51+1)) ;;
    dead)   dead=$((dead+1)) ;;
  esac
done

echo ""
echo "Active: $active"
echo "R51 ([OBSOLETED) keep: $r51"
echo "Dead:   $dead"
echo "Total:  $total"