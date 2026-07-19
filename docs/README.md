# Wriggly-Octopus Subsystem Docs

This directory contains per-subsystem specs extracted from the master plan.

**Master spec**: `../SPEC.md`
**Master plan**: `C:\Users\LamKo\.claude\plans\specification-writing-risc-v-ultimate-wiggly-octopus.md` (full detail, ~5500 lines, 30 audit rounds)

## Index

| # | Doc | Plan reference | Status |
|---|-----|----------------|--------|
| 01 | system-overview.md | §二 (18-box architecture) | ⏳ to split |
| 02 | memory-topology.md | §九 (V2.2 644KB) | ⏳ to split |
| 03 | design-decisions.md | §一 (D1-D106 full table) | ⏳ to split |
| 04 | abi-contract.md | §四 + D74/D85/D86/D90/D101 (5-layer) | ⏳ to split |
| 05 | call-gate.md | §五 + D56/D62/D73/D82/D92/D106 (6-layer) | ⏳ to split |
| 06 | boot-sequence.md | §六 + D92/D95/D99/D100 | ⏳ to split |
| 07 | shell-architecture.md | §七 + D97 | ⏳ to split |
| 08 | risc-v-hal.md | §八 + D21/D32/D38/D67/D83/D87/D94/D104 | ⏳ to split |
| 09 | memory-subsystem.md | §九 + D29/D31/D61/D84/D102 | ⏳ to split |
| 10 | error-handling.md | §十 + D28/D40/D89/D91 | ⏳ to split |
| 11 | network-driver.md | §十一 + D60/D79/D96 | ⏳ to split |
| 12 | scheduler.md | §十二 + D43/D104 | ⏳ to split |
| 13 | build-pipeline.md | §十三 + D74/D93/D100/D101/D105 | ⏳ to split |
| 14 | syscall-api.md | §十四 + D55/D103 | ⏳ to split |
| 15 | phase0-mvp.md | §十五 (Day 4 templates) | ⏳ to split |
| 20 | documentation-gate.md | §二十.7 (58 forbidden words) | ⏳ to split |
| 30 | open-questions.md | (none; Q22 closed R25) | ✅ empty |

## CI

- `ci/check-docs.sh` — Documentation gate (58 forbidden words hard melt-down)

## Cross-reference rules

Per user instruction *"要注意正确互相引用"*:
- Every decision must reference its origin (R# round, D# number, §plan section)
- Every `D#` mentioned in a doc must trace back to `03-design-decisions.md`
- The 58 forbidden words list in `20-documentation-gate.md` is the single source of truth
- No new decisions may be added to subsystem docs without first updating `03-design-decisions.md` and the master plan

## How to extend

1. Read `../SPEC.md` first (top-level summary, D-table, architecture)
2. Identify the subsystem you want to split out
3. Extract the relevant §plan section, preserve all D# references
4. Add cross-references to other subsystem docs that depend on it
5. Run `bash ci/check-docs.sh` to verify the 58 forbidden words gate still passes
