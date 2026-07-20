# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## What this repo is

`Wriggly-Octopus` — frozen RISC-V S-Mode microkernel **spec blueprint**, tri-lingual (Zig kernel + C HAL + Rust `no_std` Shell). One invariant: **Block == RpcUnit == NetworkFrame == 1536 B**. Implementation artifacts (QEMU logs, syms.json) live under `mvp/` (the only `.gitignore` entry). Top-level: `SPEC.md`. External master plan: `C:\Users\LamKo\.claude\plans\specification-writing-risc-v-ultimate-wiggly-octopus.md` (~5500 lines, R1–R47).

## Branch & commit discipline

- **`dev`** — single linear branch. Pull = `--rebase`. **No merge commits ever**, no `--no-ff`.
- **`main`** — key-archive only. `dev → main` with `--no-ff` (no tag required).
- **`release`** — publication port. `dev → release` with `--no-ff` **+ tag** (no tag = not a real release).
- **Order is fixed**: `main` first, then `release` (so `release` stays `git log --graph` tip).
- After every merge to `main`/`release`, run `git checkout dev` immediately — never let dev HEAD sit on a merge commit.

## Documentation gate (MUST pass before commit)

```bash
bash docs/ci/check-docs.sh        # forbidden-word gate (scans docs/ only)
bash docs/ci/check-d-backlinks.sh # D# back-link gate (D126+)
```

- **Forbidden-word gate**: 133 phrases in `docs/ci/check-docs.sh` (`EXPECTED_TOTAL=133`, hard self-check). Exit 1 = phrase hit; **exit 2 = `EXPECTED_TOTAL` mismatch** (the census row in `docs/20-documentation-gate.md` was not updated).
- **D# back-link gate**: every D# in `03-design-decisions.md` must be reachable from at least one subsystem doc via `grep`.

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
