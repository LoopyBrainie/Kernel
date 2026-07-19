#!/usr/bin/env bash
# =============================================================================
# Wriggly-Octopus D# Back-link Gate (P0-5)
# =============================================================================
# Purpose: every D# in 03-design-decisions.md status table from D126+ must be
#          greppable in at least one subsystem docs/ file (excluding catalog
#          and audit-history files). Empty back-link = propagation未闭环 = FAIL.
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
  "ci/check-docs.sh"
  "ci/check-d-backlinks.sh"
)

EXIT=0

# 1. Collect D126+ from the status table rows in 03.
mapfile -t D_TAGS < <(grep -oE '\| D(12[6-9]|1[3-5][0-9]) \|' "$LEDGER" | sed -E 's/\| D([0-9]+) \|/\1/' | sort -u)

if [[ ${#D_TAGS[@]} -lt 27 ]]; then
  echo "[FATAL] $GATE_NAME expected ≥27 D126-D152 tags in $LEDGER, got ${#D_TAGS[@]}"
  exit 2
fi

# 2. For each D# tag, grep across subsystem docs (excluding audit/catalog files).
EXCLUDE_GREP=$(printf -- '--exclude=%s ' "${EXCLUDE_FILES[@]}")

MISSING=()
for d in "${D_TAGS[@]}"; do
  # Search for the D# as a token (word boundary on both sides)
  hits=$(grep -rnE "(^|[^0-9])D$d([^0-9]|$)" $EXCLUDE_GREP docs/ 2>/dev/null | wc -l)
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

echo "✓ $GATE_NAME passed (${#D_TAGS[@]} D126-D152 tags, all back-linked)"
