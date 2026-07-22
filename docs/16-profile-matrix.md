# 16 · ISA/ABI Profile Matrix

**Status**: R50 立法 (D160 ACTIVE)
**Source**: `03-design-decisions.md` D160
**Back-link anchor**: D138 (mabi) / D126 (stride) / D146 (cache line) / D45 (BlockPool layout) / D49 (V2.2 ceiling) / D48 (cache line profile) / D71 (RpcUnit align baseline) / D85 (three-end offsetof)

---

## Purpose

This doc is the **canonical index** for the ISA × ABI × 粒度 profile matrix. It does not redefine profile-specific values — those live in their authoritative source D# docs. The matrix exists so that:

1. A reader can see all profile combinations in one place (no doc-hopping).
2. The frozen invariant `block_t ≡ RpcUnit ≡ NetworkFrame ≡ 1536 B` is held to the *granularity column* — currently 1536B for all three profiles; any future deviation is gated by frozen-house rules.
3. Sandbox/audit builds that override spec (e.g. R49-EMBEDDED-LP64) can be retroactively recognized as conforming to a specific profile variant, rather than treated as silent overrides.

## Three-profile matrix (D160)

| Profile | ISA | mabi | RpcUnit 粒度 | BlockPool 池 | cache line | 16KB Hart-Local 栈 |
|---------|-----|------|--------------|--------------|------------|---------------------|
| **embedded** | `rv64imac` | `lp64` | **1536 B** (D57/D85 frozen) | 精简池 (D45 sparse) | 64 B (D48 Embedded) | ✓ D6 |
| **qemu_virt** (基线) | `rv64imac` | `lp64` | **1536 B** | 全量池 (D126 stride=512 KB sparse / 384 KB compact) | 64 B (D48 Embedded) | ✓ D6 |
| **qemu_virt** (特许变体) | `rv64gc` | `lp64d` | **1536 B** | 全量池 | 64 B | ✓ D6 (FPU 需求时启用) |
| **server_compact** | `rv64gc` | `lp64d` | **1536 B** | 96 页 compact 池 (D126 server_compact=384 KB) | 128 B (D48 Server) | Phase 1+ only (D6 Hart-Local 16 KB 仍适用) |

**粒度列** 当前一律 1536 B. `endpoint_compact = 256 B` 记 **PROVISIONAL** 候选 (见下节).

**回追批准** (D160 子条款, R50 收官):

- 沙箱二 `lp64d` 构建追认为 `qemu_virt` **特许变体** 合规 (与 R51-F2 一致; R49-EMBEDDED-LP64 追认的 D-号化见 D160 本行).
- 沙箱三 `imac` 构建追认为 `qemu_virt` **基线** 合规 (与 R51-F2 一致).

两追认均为 "O2 不视为违规产物" (R49-GOV.2 处置), 矩阵立法后正式落 D-号 (= D160), 沙箱自查未拦截问题由 `check_goal_manifest.sh` 后续覆盖.

## endpoint_compact = 256 B (PROVISIONAL, 不激活)

| 属性 | 值 | 状态 |
|------|-----|------|
| 粒度 | 256 B | **PROVISIONAL — 本轮不激活** |
| 触发条件 | Phase 1+ IPC endpoint 通道极小包场景 (e.g. 16-byte sensor beacons) | 待 Q78 立法研究 |
| 触及 frozen 门 | `rpc_unit_t = 1536 B` (D57/D85) | 需独立 Q78 立法 + D# 升 `block_t` 三方等价 |
| 当前禁用依据 | 任何 `rpc_unit_t = 256B` 字面即视为漂移, 已入 `check-docs.sh` 禁词 (R50 D160 配套) | ✓ |

**Q78 OPEN** (R50 挂账): endpoint_compact 256B 粒度研究 — 是否立法为新 profile, 如何保持 `block_t ≡ RpcUnit ≡ NetworkFrame` 1536B frozen 门, 需独立 Q 研究. 本轮**不立**, 仅作 PROVISIONAL 候选登记.

## Why matrix-as-index (not matrix-as-source)

Each 五元组 cell has a source-of-truth D# — e.g. mabi=`lp64d` is D138, stride=512 KB is D126, cache line=128B is D48. The matrix does **not** re-define these values. It only:

- Renders them in a side-by-side table for cross-profile comparison.
- Pins the frozen 1536B invariant as a column-wide constant (gates future drift).
- Records endpoint_compact PROVISIONAL status (so the candidate doesn't get re-litigated every round).
- Hosts the 回追批准 clauses (so sandbox overrides are first-class, not silent).

If a value in the matrix disagrees with its source D#, the source D# wins. The matrix's role is to **make the disagreement obvious**, not to adjudicate it.

## Cross-references (matrix ←→ D#)

- **D138** (kernel FP 编译期防御, mabi per profile): `08-risc-v-hal.md` § D138 增补 — see `16-profile-matrix.md` for profile × mabi table.
- **D126** (stride gate profile×layout 派生): `13-build-pipeline.md` § D126 增补 — see `16-profile-matrix.md` for stride value per profile.
- **D146** (cache line per profile align): `02-memory-topology.md` § D49 增补 — see `16-profile-matrix.md` for cache line per profile.
- **D45** (4KB page = 2×1536B + 1024B padding): `02-memory-topology.md` § BlockPool layout — granularity 1536B invariant.
- **D49** (V2.2 ceiling 644 KB): `02-memory-topology.md` § D49 双行制 — applies to embedded / qemu_virt 池 sizing.
- **D48** (Cache Line Profile 64B Embedded / 128B Server): profile × cache line column.

## Forbidden phrases (D160 enforcement)

- `rpc_unit_t = 256B` — R50 D160 配套禁词, endpoint_compact=256B 未立法, 任何现行 RpcUnit 形态暗示 256B 即熔断.

## R50 收口传染面

- `08-risc-v-hal.md` § D138 加 "见 16-profile-matrix.md" 索引注 (mabi 列) — **R50 任务3 落**
- `13-build-pipeline.md` § D126 加 "见 16-profile-matrix.md" 索引注 (stride 列) — **R50 任务3 落**
- `02-memory-topology.md` § D49 加 "见 16-profile-matrix.md" 索引注 (cache line / BlockPool) — **R50 任务3 落**
- `04-abi-contract.md` § D71 / D146 加 "见 16-profile-matrix.md" 索引注 (RpcUnit align / cache line) — **R50 任务3 落**
- `03-design-decisions.md` D160 ACTIVE 行 — 立法
- `20-documentation-gate.md` census + 防御表 — 同步
- `30-open-questions.md` Q78 OPEN (endpoint_compact 256B 研究) — 挂账
- `README.md` 文档地图 + D1–D161 — 同步
- `docs/README.md` 索引行 + CI 列表 — 同步
- `check-docs.sh` 4 新禁词 (GOV.4 三 + D160 一) — 同步
- `check-d-backlinks.sh` 正则扩 D160+ — 同步

---

*Last updated: R50 立法 (D160). Frozen 1536B 粒度门不可由本矩阵立法修改 — 任何粒度变更需走 D# 升 / supersede 链.*
