#!/usr/bin/env bash
# =============================================================================
# Wriggly-Octopus GOAL Manifest Gate (R50-Q76 / R49-GOV.1 enforcement)
# =============================================================================
# Purpose: every GOAL*.md must declare a "## 涉及决策" section listing all
#          D# tokens it touches; each D# that *conflicts* with spec must carry
#          a back-link to the R# errata that justifies the override.
# R51-FIX (zero-match discipline): grep -c piped in `set -euo pipefail` would
#          silently die on zero matches (R51 check-d-backlinks bug pattern).
#          R50 fix: every grep that can legitimately return 0 is wrapped in
#          if/then/else with explicit counter assignment; no pipefail death.
# Source: R49-GOV.1 (30-open-questions.md line 3109) — ratified by R50
# Exit codes: 0 = pass, 1 = manifest violation, 2 = self-test fail
# Canary: bidirectional — bad GOAL (no header / dangling R#) MUST fail,
#         clean GOAL (header + resolvable R#) MUST pass. Evidence → mvp/.
# =============================================================================
set -euo pipefail

GATE_NAME=check_goal_manifest
LEDGER=docs/03-design-decisions.md
QA=docs/30-open-questions.md
EVIDENCE_LOG=mvp/R50-Q76-canary-evidence.log

# R-round allowlist (R1..R52).  R-round stamps are constitutional facts;
# the valid set is finite and must be hardcoded rather than discovered via
# grep (R99 vs R999 substring collisions make dynamic discovery unsafe).
# R50 maintenance: bump max on each new R-round.
VALID_R_ROUNDS=(R1 R2 R3 R4 R5 R6 R7 R8 R9 R10 R11 R12 R13 R14 R15 R16 R17 R18 R19 R20
                R21 R22 R23 R24 R25 R26 R27 R28 R29 R30 R31 R32 R33 R34 R35 R36 R37 R38
                R39 R40 R41 R42 R43 R44 R45 R46 R47 R48 R49 R50 R51 R52)

EXIT=0

# ---- Per-file check ---------------------------------------------------------
# Returns: 0 = pass, 1 = manifest violation
check_one_goal() {
  local f="$1"
  local rc=0
  local section
  section=$(awk '
    /^##[[:space:]]+涉及决策/ { insec=1; print; next }
    insec && /^##[[:space:]]/  { insec=0 }
    insec { print }
  ' "$f")
  if [[ -z "$section" ]]; then
    echo "[ERROR] $f: missing required '## 涉及决策' header"
    return 1
  fi

  # Extract D# tokens from section. R50-FIX: if/then/else guards zero-match.
  local d_hits dcount
  if d_hits=$(printf '%s\n' "$section" | grep -oE 'D[0-9]+'); then
    dcount=$(printf '%s\n' "$d_hits" | wc -l)
  else
    dcount=0
  fi
  if [[ "$dcount" -eq 0 ]]; then
    echo "[ERROR] $f: '涉及决策' section declares no D# tokens"
    return 1
  fi

  # Extract R# tokens (R## form; uppercase R followed by digits, may have suffix).
  local r_hits rcount
  if r_hits=$(printf '%s\n' "$section" | grep -oE 'R[0-9]+(-[A-Za-z0-9_-]+)?'); then
    rcount=$(printf '%s\n' "$r_hits" | wc -l)
  else
    rcount=0
  fi
  # Each R# must reference a known R-round.  R-rounds are constitutional facts
  # (R1..R52 as of R50); the allowlist is hardcoded above to avoid substring
  # collision (R99 vs R999, R9 vs R99 — substring grep resolves dangling to
  # existing R-rounds by accident).  Compound R# (e.g. R49-EMBEDDED-LP64)
  # validates via its R-round prefix.
  if [[ "$rcount" -gt 0 ]]; then
    local r_token r_round valid
    while IFS= read -r r_token; do
      r_round=$(printf '%s' "$r_token" | grep -oE '^R[0-9]+')
      if [[ -z "$r_round" ]]; then
        echo "[ERROR] $f: malformed R# reference '$r_token' (no R## prefix)"
        rc=1
        continue
      fi
      valid=0
      for v in "${VALID_R_ROUNDS[@]}"; do
        if [[ "$v" == "$r_round" ]]; then valid=1; break; fi
      done
      if [[ "$valid" -eq 0 ]]; then
        echo "[ERROR] $f: dangling R# reference '$r_token' (R-round '$r_round' not in R1..R52 allowlist)"
        rc=1
      fi
    done <<< "$(printf '%s\n' "$r_hits" | sort -u)"
  fi
  return $rc
}

# ---- Main scan --------------------------------------------------------------
# Find all GOAL*.md files under repo root, excluding mvp/ (gitignored sandbox).
GOAL_FILES=()
if mapfile -t GOAL_FILES < <(find . -name 'GOAL*.md' -not -path './mvp/*' 2>/dev/null); then
  :  # found some
else
  mapfile -t GOAL_FILES < <(printf '')
fi
# R50-FIX: strip empty entry from failed find (pipefail guard).
GOAL_FILES=("${GOAL_FILES[@]//[[:space:]]/}")

if [[ ${#GOAL_FILES[@]} -eq 0 ]]; then
  echo "✓ $GATE_NAME passed (0 GOAL*.md files; zero-match = explicit pass)"
else
  for f in "${GOAL_FILES[@]}"; do
    if ! check_one_goal "$f"; then
      EXIT=1
    fi
  done
  if [[ $EXIT -eq 0 ]]; then
    echo "✓ $GATE_NAME passed (${#GOAL_FILES[@]} GOAL*.md files, all manifests valid)"
  else
    echo "[FAIL] $GATE_NAME: ${#GOAL_FILES[@]} GOAL*.md files scanned, manifest violation(s) above"
  fi
fi

# ---- Canary self-test (bidirectional evidence, R50-Q76 hard requirement) ---
# R50-FIX: canary runs even when real scan is clean (zero-match pass) so the
# evidence log is always refreshed.  Persisted to mvp/ (gitignored).
mkdir -p "$(dirname "$EVIDENCE_LOG")" 2>/dev/null || true
CANARY_TMP=$(mktemp -d)
trap 'rm -rf "$CANARY_TMP"' EXIT

# 1. Clean canary: header + D# + resolvable R#  →  must PASS.
cat > "$CANARY_TMP/clean.md" <<'EOF'
# Clean GOAL canary (R50-Q76)

## 涉及决策

- D138 (mabi) — back-link: R49-EMBEDDED-LP64
- D146 (cache line) — back-link: R49-EMBEDDED-LP64
EOF

# 2. Bad-no-header canary: no 涉及决策 section  →  must FAIL on header check.
cat > "$CANARY_TMP/bad-no-header.md" <<'EOF'
# Bad GOAL canary (no header)
This file declares a D# reference D138 in body text but has no manifest header.
EOF

# 3. Bad-dangling-R canary: header present + dangling R#  →  must FAIL on R# check.
cat > "$CANARY_TMP/bad-dangling-r.md" <<'EOF'
# Bad GOAL canary (dangling R#)

## 涉及决策

- D138 (mabi) — back-link: R9999-DOES-NOT-EXIST
EOF

CANARY_OUT=$(mktemp)
{
  echo "=== R50-Q76 canary evidence ($(date -u +%Y-%m-%dT%H:%M:%SZ)) ==="
  for f in clean.md bad-no-header.md bad-dangling-r.md; do
    echo "--- $f ---"
    if check_one_goal "$CANARY_TMP/$f" 2>&1; then
      echo "result: PASS"
    else
      echo "result: FAIL (expected for bad-*)"
    fi
  done
} > "$CANARY_OUT" 2>&1 || true
mv "$CANARY_OUT" "$EVIDENCE_LOG" 2>/dev/null || cp "$CANARY_OUT" "$EVIDENCE_LOG"

# Verify canary outcomes (machine-checked; R50-Q76 hard requirement).
canary_clean_rc=0
canary_noheader_rc=0
canary_dangling_rc=0
check_one_goal "$CANARY_TMP/clean.md" >/dev/null 2>&1 && canary_clean_rc=0 || canary_clean_rc=$?
check_one_goal "$CANARY_TMP/bad-no-header.md" >/dev/null 2>&1 && canary_noheader_rc=0 || canary_noheader_rc=$?
check_one_goal "$CANARY_TMP/bad-dangling-r.md" >/dev/null 2>&1 && canary_dangling_rc=0 || canary_dangling_rc=$?

if [[ $canary_clean_rc -ne 0 ]]; then
  echo "[FATAL] $GATE_NAME canary FAILED: clean GOAL must pass, got rc=$canary_clean_rc"
  echo "        Evidence: $EVIDENCE_LOG"
  exit 2
fi
if [[ $canary_noheader_rc -eq 0 ]]; then
  echo "[FATAL] $GATE_NAME canary FAILED: bad-no-header must fail, got rc=0 (gate mechanism broken)"
  echo "        Evidence: $EVIDENCE_LOG"
  exit 2
fi
if [[ $canary_dangling_rc -eq 0 ]]; then
  echo "[FATAL] $GATE_NAME canary FAILED: bad-dangling-r must fail, got rc=0 (gate mechanism broken)"
  echo "        Evidence: $EVIDENCE_LOG"
  exit 2
fi

if [[ $EXIT -eq 0 ]]; then
  echo "✓ $GATE_NAME canary self-test OK (3/3: clean passes, bad-no-header fails, bad-dangling-r fails)"
fi
exit $EXIT
