# Wriggly-Octopus

RISC-V S-Mode microkernel blueprint — tri-lingual (Zig kernel + C HAL + Rust no_std Shell).
1536 B unified invariant seed (`Block == RpcUnit == NetworkFrame`), 4 Pillars red-line aggregation, zero-heap static pool invariant, 16 KB Hart-Local stack, embedded MVP footprint target.

## Status (R47 close-out)

- **Audit rounds**: R1–R46 closed, R47 勘误增补 landed (`docs/03-design-decisions.md` § R47: P1-5 rollback of R46 D151 84B/4.2KB misjudgement).
- **Decision ledger**: D1–D152 ACTIVE in `docs/03-design-decisions.md` (D62 DEPRECATED; D91/D96/D101/D104/D106/D116 SUPERSEDED).
- **Q&A register**: Q22–Q67 全闭 (`docs/30-open-questions.md` 0 OPEN).
- **Documentation gate**: `bash docs/ci/check-docs.sh` — currently `0/N forbidden words` where `N = ${#FORBIDDEN[@]}` 派生 (no hardcoded magic number).
- **R46+ 恢复条件**: any of (a) `make build` triggers new doc-gate熔断, (b) RISC-V Profile RVA23 + AIA + RVV 1.0 introduces new Pillar, (c) Phase 1 Sv39 SATP 启用时审计 D26/D31/D84/D109/D143 联动.

## Repo contents

| Path | Purpose |
|------|---------|
| `SPEC.md` | Top-level claim page (R47 rewrite per D120) |
| `GOAL.md` | R47 close-out task list (P0→P3 + C1–C15) |
| `README.md` | This file |
| `docs/00-ffi-pillars.md` | 4 Pillars aggregation, single source of red lines (D125) |
| `docs/01-system-overview.md` | System diagram and phase matrix |
| `docs/02-memory-topology.md` | V2.2 memory map + ceiling/measured dual-track (D133) |
| `docs/03-design-decisions.md` | Full decision ledger D1–D152 with status + supersede chains |
| `docs/04-abi-contract.md` | Syscall ABI, 16 B red line (D86) |
| `docs/05-call-gate.md` | Call Gate stub, HLCB layout extern struct (D153 candidate) |
| `docs/06-boot-sequence.md` | entry.S, Step 0/1/2 sequence, D95 Anti-Trampling |
| `docs/07-shell-architecture.md` | Phase 0 Shell S-Mode co-residency (D97) |
| `docs/08-risc-v-hal.md` | RISC-V HAL, FS/VS state machine, SBI fallbacks |
| `docs/09-memory-subsystem.md` | BlockPool/NodePool layout, FILE_TABLE |
| `docs/10-error-handling.md` | sys_error_decode, negative errno convention |
| `docs/11-network-driver.md` | Shim Layer, network_frame_t wire format |
| `docs/12-scheduler.md` | RR + Work-Stealing + Pin-Binding (D145) |
| `docs/13-build-pipeline.md` | check_elf_sizes.sh, build.zig profile×layout |
| `docs/14-syscall-api.md` | arity table, signing rules, path-pool mechanism |
| `docs/15-phase0-mvp.md` | Phase 0 DoD T-tasks (T1.1–T1.28) |
| `docs/20-documentation-gate.md` | Gate contract + forbidden word census |
| `docs/30-open-questions.md` | Q&A audit history (R37–R46, append-only) |
| `docs/ci/check-docs.sh` | Forbidden-word gate (runs in CI) |

## Quick start

```bash
# Forbidden-word gate (must pass before any commit)
bash docs/ci/check-docs.sh

# Read the 4 Pillars first — everything downstream cites these
cat docs/00-ffi-pillars.md

# For any new D-tag proposal, follow the contagion-surface checklist
# in docs/03-design-decisions.md § "元规则: RATIFIED 传染面清单"
```

## Conventions

- 每处修改附传染面清单 (R36 元规则四): 受影响文档 + 任务编号 + 禁词条目。
- 数字必须带量纲标签 (e.g. `644 KB ceiling`, `~497.5 KB measured`), 派生值不得 `(估)` 喂断言 (R39 D133)。
- 审计历史 (superseded 内容) 保留并显式标注, 不删除 (GOAL §2.4)。
- 仅修改文档, 不编写实现代码 (Phase 0 进入实现期后由 R47+ DoD 接管, see `SPEC.md` 收官注脚)。

## Contributing

Spec-only contributions. Open against `dev` branch (linear, no merge commits); archive to `main` via `--no-ff`; release to `release` via `--no-ff` + tag.
