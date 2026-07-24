# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## What this repo is

`Wriggly-Octopus` — frozen RISC-V S-Mode microkernel **spec blueprint**, tri-lingual (Zig kernel + C HAL + Rust `no_std` Shell). One invariant: **Block == RpcUnit == NetworkFrame == 1536 B**. Implementation artifacts (QEMU logs, syms.json) live under `mvp/` (the only `.gitignore` entry). Top-level: `SPEC.md`. External master plan: `C:\Users\LamKo\.claude\plans\specification-writing-risc-v-ultimate-wiggly-octopus.md` (~5500 lines, R1–R47).

**This is a spec-only repo at top level.** There is no `Makefile`, `build.zig`, or `Cargo.toml` here — `SPEC.md` references `make build`/`make test` as Phase 0 goals, not implemented commands. Actual compilation artifacts are under `mvp/` (gitignored). The only runnable verification is the documentation gate + spec_lab assertion suite.

### Non-obvious paths

| Path | Role |
|------|------|
| `SPEC.md` | Headline claims, D-tag index, Phase 0 task table |
| `tools/spec_lab/` | "frozen = 编译过的" extract-and-compile assertion suite (R49) |
| `mvp/` | Gitignored — implementation artifacts (kernel.elf, QEMU logs, sandbox deliveries) |
| `.gitattributes` | `*.sh text eol=lf` — all shell scripts must be LF on Windows checkout |

## Quick commands (gate suite — MUST pass before commit)

```bash
bash docs/ci/check-docs.sh        # forbidden-word gate (145 phrases)
bash docs/ci/check-d-backlinks.sh # D# back-link gate (D126+)

# spec_lab assertions extracted from docs/*.md code fences
bash tools/spec_lab/run_all.sh      # positive (expect all PASS)
bash tools/spec_lab/run_negative.sh # negative (expect all FAIL — proves runner works)

# R51 迭代协议 — 收官轮次全量重跑 (硬性签发前提):
bash docs/ci/check-docs.sh && bash docs/ci/check-d-backlinks.sh && \
  bash tools/spec_lab/run_all.sh && bash tools/spec_lab/run_negative.sh
```

- **Forbidden-word gate exit codes**: exit 1 = phrase hit; **exit 2 = `EXPECTED_TOTAL` mismatch** (census row in `docs/20-documentation-gate.md` was not updated). Never ignore exit 2.
- **R51 迭代协议**: 收官轮次 (R## closed) 最后一个 commit 之后, **必须全量重跑所有门禁**. R51 D# 悬空 (D156/D157/D159) 的直接成因是 AGENDA commit 后未重跑回链门 — 中段 "passed (34)" 掩盖了终态 "34/37 FAIL". 此后每个收口轮次, 门禁全量重跑是硬性签发前提.

## Branch & commit discipline

- **`dev`** — single linear branch. Pull = `--rebase`. **No merge commits ever**, no `--no-ff`.
- **`main`** — key-archive only. `dev → main` with `--no-ff` (no tag required).
- **`release`** — publication port. `dev → release` with `--no-ff` **+ tag** (no tag = not a real release).
- **Order is fixed**: `main` first, then `release` (so `release` stays `git log --graph` tip).
- After every merge to `main`/`release`, run `git checkout dev` immediately — never let dev HEAD sit on a merge commit.

## Architecture (18-box)

```
Layer 1 Dispatch   —  ① Rust no_std Shell     ② Zig Kernel Dispatcher     ③ Scheme Router
Layer 2 Subsystems —  ④ file://     ⑤ dev://uart0     ⑥ dev://network (14B MAC DMA + Shim)
                       ⑦ scheme:// (RpcUnit)
Layer 3 HAL+C ABI  —  ⑧ C HAL       ⑨ RISC-V HAL (AIA/PLIC, FS/VS, csrr time)
Invariants         —  ⑩ BlockPool   ⑪ NodePool (132KB NOLOAD)
                       ⑫ RpcUnit     ⑬ NetworkFrame
                       ⑭ block_t ≡ RpcUnit ≡ NetworkFrame (D57/D85 offsetof)
Evolution          —  ⑮ Phase 0 软边界 → ⑯ Phase 1 Sv39 PTE 强隔离
Profiles           —  ⑰ Static (RR, 16KB Hart-Local stack)
                       ⑱ Server (Work-Stealing, FS/VS lazy)
```

**4 Pillars** (single source: `docs/00-ffi-pillars.md`, D125) — restating a pillar in any other doc MUST back-link the anchor, else doc-gate fails.

| Pillar | Red lines | Authority |
|---|---|---|
| 1. ABI & FFI | D86, D90, D103, D119, D121 | `04-abi-contract.md` |
| 2. `sys_result_t` 16B a0/a1 | D86, D101, D119 | `14-syscall-api.md` |
| 3. `sscratch` + `in_kernel_space` | D82, D92, D106, D107 | `05-call-gate.md` |
| 4. Graceful degradation | D87, D94, D104→D118, D117 | `08-risc-v-hal.md` |

## Phase 0 do-not-implement-yet gotchas

- **Syscall arity**: 6 args (a0-a5). The 7th arg (if any) falls on **a6** — never a7. a7 holds the syscall number (must be written via inline `asm!`, D129).
- **`sys_result_t` shape** (R48 canonical): `struct { u32 header; u32 reserved; union payload { u64 value; struct error_pack { u16 remote_node_id; u16 subsystem_id; i32 error_code; } } }`, `repr(C, align(8))`, 16B / 8B align. Older `code:` / `status:` / `uint32_t code` shapes are forbidden phrases.
- **ABI SSOT**: `kernel/include/sys/abi.zig` is the source; `arch/riscv64/abi.rs` and `kernel/include/sys/abi.h` are **auto-generated** (D74). Never hand-edit.
- **Boot order is locked** (R47 P3-2): D95 Anti-Trampling → D92 sscratch init → D92 sp init → D136 tp=a0 → .bss 清零 → D107 Hart-Local sp. Reordering is a forbidden word.

## Extending `docs/`

1. Any pillar restatement outside `00-*` MUST back-link the anchor (otherwise doc-gate fails).
2. Each edit needs a contamination-surface checklist (R36 元规则四): affected docs + task numbers + forbidden-word entries touched.
3. Numbers must carry units (`644 KB ceiling`); ledger/measured values stay on separate tracks (D133) — never feed `(估)` into an assertion.
4. Audit history: mark `DEPRECATED` / `SUPERSEDED` in the ledger, do not delete; cite the supersede chain.
5. New forbidden word = update **both** the script array AND `20-documentation-gate.md` census (the `EXPECTED_TOTAL` mismatch causes exit 2).
6. New D# = append to `03-design-decisions.md` with class (1/2/3) and status; `check-d-backlinks.sh` then enforces a subsystem-doc hit.

## Naming Migration Discipline (R53-R61 lessons)

- **Reverse-grep before batch closure** — plan § enumeration often misses symbols; `grep -rn "old_prefix" docs/` to verify completeness (R59 missed 5 HAL-exposed syscall 编号表 11-15 entries that were not in plan §1.2).
- **`Edit replace_all=true` catches prefix substrings** — `cosmo_open` → `neura_open` auto-catches `cosmo_open_stub` and `cosmo_pte_map_6arg_fn`. Use for naming migrations when new prefix is unambiguous.
- **30-open-questions.md is dual-mode** — fence-internal code (三连反引号 围栏内) MUST sync to current naming; fence-external narrative is D172-exempt. Stale cross-references pointing to migrated symbols are NOT D172-exempt — cross-refs must reflect current state.
- **AUDIT_LINE_FILTER must be extended per R##** — historical-reference exemption patterns (`R55|R60|D171|D172`) added alongside new forbidden words in `check-docs.sh`. Without this extension, every R## finalization breaks the gate on its own D-tag entries.
- **Naming layer interface abstraction** — syscall interface strips internal layer qualifier: `basal_hal_set_next_timer` (HAL backend) → `neura_set_next_timer` (syscall interface). Apply at every cross-layer syscall addition; the interface is the abstraction boundary.
- **spec_lab reverse-grep before R## commit** — `grep -rln "old_symbol" tools/spec_lab/assertions/ tools/spec_lab/extracted/` to sync hardcoded names in assertion scripts and extracted code fences before commit. Skipping this breaks `run_all.sh`.
