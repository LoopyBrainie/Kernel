# Neur-Aegis 🐙

> A triple-language-verifiable RISC-V S-Mode microkernel — specified, not yet implemented.

**One invariant binds everything:** `Block == RpcUnit == NetworkFrame == 1536 B`. From a 16 KB-stack embedded SoC to a multi-socket NUMA server, that single number never changes.

---

## Why this exists

Most microkernel specs live in a single language and a single document. When implementation begins, the spec drifts — C headers say one thing, Rust types say another, Zig structs say a third. **Wriggly-Octopus** solves this by making the spec *triple-language-verifiable* before a single line of kernel code is committed:

- **Zig** kernel dispatcher + build system
- **C** HAL (hardware abstraction layer)
- **Rust** `no_std` shell (userspace co-resident in S-Mode)

Every cross-language ABI decision is frozen in `docs/` and mechanically enforced by a documentation gate. The compiler catches spec bugs before they become kernel bugs.

## Quick start

You don't build a kernel here — you verify the spec.

```bash
# Clone and run the gate suite (all five must pass):
bash docs/ci/check-docs.sh        # 149 forbidden-word phrases
bash docs/ci/check-d-backlinks.sh # every design decision (D126+) must be cited
bash docs/ci/check_goal_manifest.sh # GOAL*.md manifests (R49-GOV.1, Q76)
bash tools/spec_lab/run_all.sh    # compile assertions extracted from docs
bash tools/spec_lab/run_negative.sh # prove the runner catches broken code
```

> [!NOTE]
> This is a **spec-only repo**. There is no `Makefile` or `build.zig` at the top level. Implementation artifacts live under `mvp/` (gitignored). `SPEC.md` references `make build` / `make test` as Phase 0 goals — not as commands you can run today.

Read the architecture in 5 minutes:

```bash
cat docs/00-ffi-pillars.md        # the 4 red lines everything else must cite
cat docs/01-system-overview.md    # 18-box architecture + phase matrix
```

## The invariant

```
1536 B = 8 B header + 1528 B payload
       = 14 B MAC header + 1522 B Ethernet frame (external wire)
       = one block_t = one RpcUnit = one NetworkFrame
```

This isn't a convention — it's a **compiler-enforced type identity** (`offsetof` assertions across Zig, C, and Rust). Change the number anywhere, and the doc-gate melts down.

## Architecture (18 boxes)

```
Dispatch     ① Rust Shell           ② Zig Dispatcher       ③ Scheme Router
Subsystems   ④ file://  ⑤ dev://uart0  ⑥ dev://network  ⑦ scheme://
HAL + C ABI  ⑧ C HAL                ⑨ RISC-V HAL (FS/VS, AIA, csrr time)
Invariants   ⑩ BlockPool  ⑪ NodePool (132KB NOLOAD)  ⑫ RpcUnit  ⑬ NetworkFrame
             ⑭ block_t ≡ RpcUnit ≡ NetworkFrame (cross-language offsetof)
Evolution    ⑮ Phase 0 soft-boundary  →  ⑯ Phase 1 Sv39 PTE hard isolation
Profiles     ⑰ Static (RR, 16KB stack)  ⑱ Server (Work-Stealing, FS/VS lazy)
```

See `docs/01-system-overview.md` for the full diagram.

## Four pillars

Every subsystem doc must cite these. A restatement without a back-link is a doc-gate violation.

| Pillar | Red line | Defined in |
|--------|----------|------------|
| **1. ABI & FFI** | Cross-language structs: only `u8/u16/u32/u64 + u8[N]` | `04-abi-contract.md` |
| **2. `sys_result_t` 16 B** | Return value fits in a0/a1 register pair | `14-syscall-api.md` |
| **3. `sscratch` + `in_kernel_space`** | Trap entry dual-defense: HLCB per-hart | `05-call-gate.md` |
| **4. Graceful degradation** | A-extension absent? Fall back. No coherence? IPI timeout. | `08-risc-v-hal.md` |

Single source of truth: `docs/00-ffi-pillars.md` (D125).

## Documentation map

| If you need to know about… | Read |
|----------------------------|------|
| The 1536 B invariant and how it's enforced | `docs/09-memory-subsystem.md` |
| How syscalls cross the S-Mode boundary | `docs/05-call-gate.md`, `docs/14-syscall-api.md` |
| The boot sequence (Step 0 → Step 1 → Step 2) | `docs/06-boot-sequence.md` |
| How errors propagate across languages | `docs/10-error-handling.md` |
| The scheduler (RR vs Work-Stealing) | `docs/12-scheduler.md` |
| Network driver and Shim Layer | `docs/11-network-driver.md` |
| Every design decision ever made (D1–D175) | `docs/03-design-decisions.md` |
| ISA/ABI profile matrix (D160) | `docs/16-profile-matrix.md` |
| What "frozen" means and how it's verified | `tools/spec_lab/README.md` |
| Phase 0 MVP task list (T1.1–T1.28) | `docs/15-phase0-mvp.md` |

## The spec lab

> **R49 legislation**: any instruction-level or ABI-level code snippet written into `docs/*.md` must survive a compiler. Otherwise it doesn't get "frozen" status.

The spec lab (`tools/spec_lab/`) extracts code fences from markdown by anchor, feeds them to real compilers (`clang`, `zig build-obj`, `riscv64-linux-gnu-gcc`), and verifies they compile. Each positive assertion has a negative twin that deliberately breaks the code — proving the runner actually catches failures.

```bash
bash tools/spec_lab/run_all.sh      # "can this spec code compile?" → expect all PASS
bash tools/spec_lab/run_negative.sh # "does the runner catch broken code?" → expect all FAIL
```

No copies of code are stored in the lab — everything is extracted live from `docs/`. A copy that's three months old is a doc-drift time bomb.

## Branch discipline

```
dev ───────●────●────●────●────●──→  (linear, no merge commits, pull --rebase)
            \         \        \
             → main    → main   → main  (--no-ff archive, no tag)
                        \              → release (--no-ff + tag, always the tip)
```

- **`dev`** — single source of truth. Every commit lands here.
- **`main`** — key-version archive. `--no-ff` merge from dev, no tag required.
- **`release`** — publication port. Must carry a tag. **Order: main first, release second** (so release is always `git log --graph` tip).

After every merge to main or release, immediately `git checkout dev`. Dev's HEAD must never sit on a merge commit.

## Contributing

Spec-only contributions. Open against `dev`. Every change needs a contamination-surface checklist (R36): which docs are affected, which task numbers, which forbidden-word entries.

Before committing:
```bash
bash docs/ci/check-docs.sh && bash docs/ci/check-d-backlinks.sh && \
  bash docs/ci/check_goal_manifest.sh && \
  bash tools/spec_lab/run_all.sh && bash tools/spec_lab/run_negative.sh
```

## Adjacent work

- **Phase 1** (Sv39 PTE alignment, Work-Stealing scheduler, Page-Aggregation compact storage) — fully scoped, deferred
- **External master plan**: `C:\Users\LamKo\.claude\plans\specification-writing-risc-v-ultimate-wiggly-octopus.md` (~5500 lines, R1–R47 audit rounds)
- **Implementation sandboxes**: under `mvp/` (QEMU logs, kernel ELF builds, shell binaries)
