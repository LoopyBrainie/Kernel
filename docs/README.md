# Neur-Aegis Subsystem Docs

This directory contains per-subsystem specs extracted from the master plan.

**Master spec**: `../SPEC.md`
**Master plan**: `C:\Users\LamKo\.claude\plans\specification-writing-risc-v-ultimate-wiggly-octopus.md` (full detail, ~5500 lines, R1–R47 closed)

## Index

| # | Doc | Plan reference | Status |
|---|-----|----------------|--------|
| 01 | system-overview.md | §二 (18-box architecture) | R48 ACTIVE (subsystem doc locked) |
| 02 | memory-topology.md | §九 (V2.2 644KB ceiling) | R48 ACTIVE; D49 双行制 (R48 F5 勘误增补: 预算上限 = 已命名子段 + 未分配余量) |
| 03 | design-decisions.md | §一 (D1–D174 full table, R47 ledger closed + R51 R#-anchored + R50 D160 profile matrix + R53-R62 命名迁移立法) | R62 ACTIVE |
| 04 | abi-contract.md | §四 + D74/D85/D86/D89/D90/D101/D121 | R48 ACTIVE; sys_result_t 形态四形归一 (R48 F3) |
| 05 | call-gate.md | §五 + D56/D62/D73/D82/D92/D106/D107/D136 | R48 ACTIVE; HLCB extern struct 命名常量同源派生 (R48 F2) |
| 06 | boot-sequence.md | §六 + D92/D95/D99/D100/D107/D132/D136 | R48 ACTIVE; D136 trap_entry asm 命名常量 (R48 F2) |
| 07 | shell-architecture.md | §七 + D97 | R48 ACTIVE; shell_io_pool 静态池来源 (R48 F4) |
| 08 | risc-v-hal.md | §八 + D21/D32/D38/D67/D83/D87/D94/D104/D138 | R48 ACTIVE |
| 09 | memory-subsystem.md | §九 + D29/D31/D61/D84/D102/D133 | R48 ACTIVE |
| 10 | error-handling.md | §十 + D28/D40/D89/D91 | R48 ACTIVE |
| 11 | network-driver.md | §十一 + D60/D79/D96/D108/D131 | R48 ACTIVE |
| 12 | scheduler.md | §十二 + D43/D104/D144/D145 | R48 ACTIVE |
| 13 | build-pipeline.md | §十三 + D74/D93/D100/D101/D105/D113/D124/D126 | R48 ACTIVE |
| 14 | syscall-api.md | §十四 + D55/D86/D90/D103/D119/D129 | R48 ACTIVE; FFI ownership P2-4 path_pool 机制 |
| 15 | phase0-mvp.md | §十五 (T1.1–T1.28) | R48 ACTIVE; T1.2/T1.3 sys_result_t 全改 canonical (R48 F3) |
| 20 | documentation-gate.md | §二十.7 (forbidden word census + defensive table) | R48 ACTIVE; 防御对象表补 R33–R47 (R48 M2) + 3 条 R48 F3 (R48 F3) |
| 30 | open-questions.md | (Q1–Q78: Q1-Q67 closed, Q68-Q78挂账) | R50 ACTIVE (append-only audit history; Q76 closed in R50) |
| 16 | profile-matrix.md | (R50 D160 立法) | R50 ACTIVE (三档 profile 五元组索引) |

## CI

- `docs/ci/check-docs.sh` — Documentation gate; **N = `${#FORBIDDEN[@]}` 派生** (实时计算, 禁硬编码). 唯一真相源.
- `docs/ci/check-d-backlinks.sh` — D# back-link gate (R48 P0-5 元规则四; R50 扩 D160+)
- `docs/ci/check_goal_manifest.sh` — GOAL manifest gate (R50 立法, Q76 交付; 3 双向 canary)

## Cross-reference rules

Per user instruction *"要注意正确互相引用"*:
- Every decision must reference its origin (R# round, D# number, §plan section)
- Every `D#` mentioned in a doc must trace back to `03-design-decisions.md`
- The forbidden words list in `20-documentation-gate.md` is the single source of truth; `N` derived from `${#FORBIDDEN[@]}`, never hardcoded
- No new decisions may be added to subsystem docs without first updating `03-design-decisions.md` and the master plan

## How to extend

1. Read `../SPEC.md` first (top-level summary, D-table, architecture)
2. Identify the subsystem you want to extract into a dedicated doc
3. Extract the relevant §plan section, preserve all D# references
4. Add cross-references to other subsystem docs that depend on it
5. Run `bash docs/ci/check-docs.sh` to verify the forbidden-word gate still passes (output `0/N` where N is derived live)