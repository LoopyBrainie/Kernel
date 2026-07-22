#!/usr/bin/env bash
# =============================================================================
# Wriggly-Octopus D# Back-link Gate (P0-5)
# =============================================================================
# Purpose: every D# in 03-design-decisions.md status table from D126+ must be
#          greppable in at least one subsystem docs/ file (excluding catalog
#          and audit-history files). Empty back-link = propagation未闭环 = FAIL.
# R51-FIX (终态核验): 原版本 `hits=$(grep ... | wc -l)` 在 set -euo pipefail 下
#   当 grep 零命中时 pipefail 触发 set -e 静默退出 — 一个 [ERROR] 都不打.
#   新版本: if/then/else 包裹, pipefail 不影响分支走向; 并加金丝雀自检.
# Source: D# ledger in docs/03-design-decisions.md
# Exit codes: 0 = all back-links present, 1 = dangling D# found
# =============================================================================
set -euo pipefail

LEDGER=docs/03-design-decisions.md
QA=docs/30-open-questions.md
GATE_NAME=check-d-backlinks

# Files where the D# appears as data, not as content (must be excluded)
EXCLUDE_FILES=(
  "03-design-decisions.md"
  "20-documentation-gate.md"
  "30-open-questions.md"
  "check-docs.sh"
  "check-d-backlinks.sh"
)

EXIT=0

# 1. Collect D126-D159 from the status table rows in 03.
mapfile -t D_TAGS < <(grep -oE '\| D(12[6-9]|1[3-5][0-9]) \|' "$LEDGER" | sed -E 's/\| D([0-9]+) \|/\1/' | sort -u)

# R51-FIX: with D153-D159 added, floor is 34 (D126-D159 = 34)
if [[ ${#D_TAGS[@]} -lt 34 ]]; then
  echo "[FATAL] $GATE_NAME expected >=34 D126-D159 tags in $LEDGER, got ${#D_TAGS[@]}"
  exit 2
fi

# 2. For each D# tag, grep across subsystem docs (excluding audit/catalog files).
EXCLUDE_GREP=$(printf -- '--exclude=%s ' "${EXCLUDE_FILES[@]}")

MISSING=()
for d in "${D_TAGS[@]}"; do
  # R51-FIX: if/then/else 替代 `hits=$(grep ... | wc -l)`, 消除 pipefail 静默死亡.
  #   当 grep 零命中 (exit=1) 时, if 条件为 false → hits=0 明确赋值.
  if result=$(grep -rnE "(^|[^0-9])D$d([^0-9]|$)" $EXCLUDE_GREP docs/ 2>/dev/null); then
    hits=$(echo "$result" | wc -l)
  else
    hits=0
  fi
  if [[ "$hits" -eq 0 ]]; then
    MISSING+=("$d")
    echo "[ERROR] D#$d not found in any subsystem docs (excluding catalog/history)"
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo ""
  echo "[FAIL] $GATE_NAME: ${#MISSING[@]} dangling D# back-links: ${MISSING[*]}"
  echo "       Fix by promoting the D-tag into its contagion target doc."
  exit 1
fi

# 3. Canary self-test (R51-FIX): 用单次命中 D156 做金丝雀 (D126 有 17 hits, 无法单行删除).
#    删掉 D156 回链 → 必须触发 MISSING → 否则门禁机制失效.
CANARY_TMP=$(mktemp -d)
CANARY_D="D156"
CANARY_DOC="docs/10-error-handling.md"
HIT_LINE=$(grep -nE "(^|[^0-9])D156([^0-9]|$)" "$CANARY_DOC" | head -1 | cut -d: -f1)
if [[ -z "$HIT_LINE" ]]; then
  echo "[FATAL] Canary pre-check failed: D156 not found in $CANARY_DOC (gate mechanism broken)"
  rm -rf "$CANARY_TMP"
  exit 2
fi
CANARY_ORIG=$(sed -n "${HIT_LINE}p" "$CANARY_DOC")
# 临时删除 D156 令牌: D156 → CANARY_DELETED
sed -i "${HIT_LINE}s/D156/CANARY_DELETED/g" "$CANARY_DOC"

# 用主循环同逻辑检查
if canary_result=$(grep -rnE "(^|[^0-9])D156([^0-9]|$)" $EXCLUDE_GREP docs/ 2>/dev/null); then
  canary_hits=$(echo "$canary_result" | wc -l)
else
  canary_hits=0
fi

# 恢复
sed -i "${HIT_LINE}c\\${CANARY_ORIG}" "$CANARY_DOC"
rm -rf "$CANARY_TMP"

if [[ "$canary_hits" -ne 0 ]]; then
  echo "[FATAL] Canary FAILED: D156 still found after deletion — gate mechanism broken"
  echo "        (grep matched $canary_hits lines after canary removal)"
  exit 2
fi

echo "✓ $GATE_NAME passed (${#D_TAGS[@]} D126-D159 tags, all back-linked, canary self-test OK)"
