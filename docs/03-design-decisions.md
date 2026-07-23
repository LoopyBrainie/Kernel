# 03 · Design Decisions (D1-D160 Full Table)

**Plan section**: §一 (R1-R50 audit rounds)
**Status**: 45 GAPs RATIFIED (R31-R45) + 7 R51 锚定 (D153-D159) + 1 R50 立法 (D160, profile matrix); 0 open questions
**Column legend**: `Status` = ACTIVE / DEPRECATED / SUPERSEDED; `Superseded by` 显式登记 supersede 链

---

## Overview

The full D1-D125 decision ledger with status column. Each row has class (1=evidence, 2=coherence, 3=taste), round stamp, status, supersede chain (if any), and one-line rationale. **DEPRECATED decisions preserve original text verbatim** — only status stamp and supersede pointer are added.

## Status 全表 (D122 落地约束 ② 普查结果)

| Supersede 链 | 状态 | 备注 |
|--------------|------|------|
| D62 →(R20 D70)→ D73 | DEPRECATED → ACTIVE | R35 D122 登记 |
| D106 → D107 | SUPERSEDED → ACTIVE | R31 D107 取代 |
| D96 → D108 | SUPERSEDED → ACTIVE | R31 D108 取代 |
| D101 → D113 | SUPERSEDED → ACTIVE | R32 D113 取代 |
| D91 → D110 | SUPERSEDED → ACTIVE | R32 D110 取代 |
| D116 → D112 | SUPERSEDED → ACTIVE | R32 D112 取代 (D116 是 ex_table 修补,被 D112 lwu→ld 取代) |
| D104 → D118 | SUPERSEDED → ACTIVE | R34 D118 纠正 FS=Clean 题面错误,改 FS=Off 懒切换 |
| D116 → D112 | SUPERSEDED → ACTIVE | R32 Q27 D112 用 `ld` (8B) 统一替 `lwu` (4B), D116.2 `.balign 4` 被 R39 D132 升 `.balign 3` 同步, 原 D116 ex_table 二分查找标 DEPRECATED supersede 链 |

## R1-R9: Initial MVP scope

| # | Class | Status | Decision |
|---|-------|--------|----------|
| D1 | 2 | ACTIVE | Tri-lingual stack: Zig kernel + C HAL + Rust no_std Shell |
| D2 | 2 | ACTIVE | Phase 0 = S-Mode logical isolation (no MMU) |
| D3 | 2 | ACTIVE | 1536B unified invariant seed |
| D4 | 2 | ACTIVE | Position transparency (64K Mesh node IDs) |
| D5 | 2 | ACTIVE | Zero-heap invariant (no malloc/free) |
| D6 | 2 | ACTIVE | 16KB Hart-Local stack (embedded MVP) |
| D7 | 2 | ACTIVE | OpenSBI as Phase 0 firmware layer |
| D8 | 2 | ACTIVE | RISC-V 64 medany ABI |
| D9 | 2 | ACTIVE | Scheme Router pattern (`scheme://[node]/path`) |
| D10 | 2 | ACTIVE | Round-Robin scheduler (Phase 0 default) |
| D11 | 1 | ACTIVE | RVV Feature Flag (build.zig) |
| D12 | 1 | ACTIVE | Physical base 0x80200000 (QEMU virt default) |
| D13 | 2 | ACTIVE | Initrd CPIO format for read-only file system |
| D14 | 1 | ACTIVE | RVV conditional compilation (server Profile) |
| D15 | 2 | ACTIVE | ELF relocatable kernel image |
| D16 | 2 | ACTIVE | User-mode trampoline (Phase 1+) |
| D17 | 2 | ACTIVE | Capability-based permission (Phase 1+) |
| D18 | 2 | ACTIVE | Microkernel IPC over shared memory |
| D19 | 2 | ACTIVE | Static device tree (no runtime probe) |
| D20 | 1 | ACTIVE | Floating-point disabled by default (Phase 0) |
| D21 | 1 | ACTIVE | `csrr time` zero-firmware tax clock (R10) |
| D22 | 2 | ACTIVE | v2.1 file service: initrd-backed |
| D23 | 2 | ACTIVE | initrd max 1MB (Phase 0) |
| D24 | 2 | ACTIVE | DTB memory node → Slot boundary |
| D25 | 2 | ACTIVE | dev://uart0 device file |
| D26 | 2 | ACTIVE | Phase 1 Sv39 page tables (deferred) |
| D27 | 2 | ACTIVE | DTB magic 0xd00dfeed validation |
| D28 | 2 | ACTIVE | 5-step degradation (Phase 1 runtime) |

## R10-R14: Topology + ABI

| # | Class | Status | Decision |
|---|-------|--------|----------|
| D29 | 2 | ACTIVE | Two-tier static pool (NodePool + BlockPool) |
| D30 | 2 | ACTIVE | Static pool is contiguous physical (Phase 0) |
| D31 | 2 | ACTIVE | No PMP isolation (Phase 0 soft boundaries) |
| D32 | 1 | ACTIVE | AIA/IMSIC target (Phase 1+) |
| D33 | 2 | ACTIVE | kmain first-step: DTB dump |
| D34 | 2 | ACTIVE | QEMU virt as Phase 0 dev target |
| D35 | 2 | ACTIVE | OpenSBI standard services only |
| D36 | 2 | ACTIVE | Flat File Table (MAX_FILES=50) |
| D37 | 2 | ACTIVE | 4KB physical page buffer (Phase 1+) |
| D38 | 2 | ACTIVE | SBI ecall fallback when AIA absent |
| D39 | 2 | ACTIVE | Co-resident Shell (Phase 0) |
| D40 | 2 | ACTIVE | Pool exhaustion → 5-step degradation (Phase 1) |
| D41 | 2 | ACTIVE | Page tables at kernel page (4KB aligned) |
| D42 | 1 | ACTIVE | 1536B = 1500B MTU + 28B framing (initial math) |
| D43 | 2 | ACTIVE | Work-Stealing scheduler (Phase 1+ Server Profile) |
| D44 | 1 | ACTIVE | Zicboz cache zero (server profile) |
| D45 | 2 | ACTIVE | 4KB page = 2 × 1536B + 1024B padding (D42 refined) |
| D46 | 2 | ACTIVE | MAX_FILES=50 in .rodata |
| D47 | 2 | ACTIVE | Initrd placed adjacent to .text |
| D48 | 2 | ACTIVE | Cache Line Profile: 64B Embedded, 128B Server |
| D49 | 2 | ACTIVE | V2.2 topology: 644 KB total (净数据预算) |
| D50 | 2 | ACTIVE | S-Mode co-residency for Phase 0 isolation |
| D51 | 2 | ACTIVE | No PMP 强隔离 (D31 elaboration) |
| D52 | 2 | ACTIVE | .bss shrink to 8KB (V2.2) |
| D53 | 2 | ACTIVE | D36 flat-only (no CoW alternative) |

## R15-R19: Call Gate + network + SMP

| # | Class | Status | Decision |
|---|-------|--------|----------|
| D54 | 2 | ACTIVE | Phase 0 has no syscall6 ecall |
| D55 | 2 | ACTIVE | Phase 0/1 user-facing API unchanged |
| D56 | 1 | ACTIVE | Phase 0 Call Gate (no ecall) |
| D57 | 1 | ACTIVE | 1536B three-layer same-structure |
| D58 | 1 | ACTIVE | D57 = 12 × 128B cache line |
| D59 | 1 | ACTIVE | No-MMU ELF forbidden in Phase 0 |
| D60 | 2 | ACTIVE | 14B MAC external to 1536B (D42 fix) |
| D61 | 2 | ACTIVE | 132KB NodePool NOLOAD placeholder |
| D62 | 1 | **DEPRECATED** | `csrrw sp, sscratch, sp` Call Gate (R17) — **SUPERSEDED by D73 (R21)** |
| D63 | 2 | ACTIVE | DTB physical decoupling from .boot_meta |
| D64 | 2 | ACTIVE | sscratch Hart-Local abstraction |
| D65 | 2 | ACTIVE | D28/D40 5-step: comptime assert only Phase 0 |
| D66 | 2 | ACTIVE | Phase 0 fence.i = 1 global |
| D67 | 1 | ACTIVE | PLIC minimal stub retirement (R19) |
| D68 | 2 | ACTIVE | Secondary Hart spin-wait sync |
| D69 | 2 | ACTIVE | Phase 0 pure software isolation (D31) |

## R20-R24: Trap + Linker + HAL

| # | Class | Status | Decision |
|---|-------|--------|----------|
| D70 | 1 | ACTIVE | `csrc sstatus, SIE` before csrrw (R20) |
| D71 | 2 | ACTIVE | RpcUnit align(64) unified |
| D72 | 2 | ACTIVE | Open path ≤ 60 chars |
| D73 | 1 | ACTIVE | **Call Gate does NOT touch sscratch (R21) — 现行真相, D62 取代者** |
| D74 | 1 | ACTIVE | SSOT for ABI (build.zig translate-abi) |
| D75 | 2 | ACTIVE | 4KB physical page alignment (SPI Flash) |
| D76 | 1 | ACTIVE | cosmo_panic_abort C HAL single panic |
| D77 | 2 | ACTIVE | Primary Hart DTB release deferred (Phase B) |
| D78 | 2 | ACTIVE | FILE_TABLE in .rodata (not NodePool) |
| D79 | 1 | ACTIVE | 14B MAC DMA pool (not .bss) |
| D80 | 1 | ACTIVE | Sstc detection + SBI fallback |
| D81 | 1 | ACTIVE | PIE dynamic kernel_phys_start |
| D82 | 1 | ACTIVE | HLCB in_kernel_space AtomicBool (R24) |
| D83 | 2 | ACTIVE | AIA interface placeholder (trigger_msi) |
| D84 | 2 | ACTIVE | BlockPool Phase 1 SATP VMA dynamic |
| D85 | 1 | ACTIVE | Three-end offsetof field offset |

## R25: ABI 16B red line + Q22 closure

| # | Class | Status | Decision |
|---|-------|--------|----------|
| D86 | 1 | ACTIVE | C ABI 16B red line (sys_result_t MUST be 16) |
| D87 | 1 | ACTIVE | A extension soft fallback (RV64IMAC) |
| D88 | 1 | ACTIVE | Early Console SBI Stub (DTB-less) |
| D89 | 1 | ACTIVE | sys_result_payload_t 8B three-segment (Q22 closed) |

## R26-R30: Polish rounds

| # | Class | Status | Decision |
|---|-------|--------|----------|
| D90 | 1 | ACTIVE | All-primitive-int cross-language red line |
| D91 | 1 | **SUPERSEDED** | Bit 31 adaptive error code — **SUPERSEDED by D110 (R32 Bit 30 重定位)** |
| D92 | 1 | ACTIVE | Early Boot Stack (Step 0 紧急栈 → Step 1+ Hart-Local) |
| D93 | 1 | ACTIVE | Phase 0 fixed link base 0x80200000 |
| D94 | 1 | ACTIVE | Cross-Hart Coherence 3-tier fallback |
| D95 | 1 | ACTIVE | entry.S Anti-Trampling (DTB before .bss) |
| D96 | 1 | **SUPERSEDED** | Network Shim Layer (1536B ↔ 1500B MTU) — **SUPERSEDED by D108 (R31 -Dip_family 派生)** |
| D97 | 1 | ACTIVE | Phase 0 Shell = containerized kernel-mode shell |
| D98 | 1 | ACTIVE | DTB dump buffer max size (Embedded 64KB / Server 8MB) |
| D99 | 1 | ACTIVE | S-Mode Hart ID via OpenSBI FFI (no `csrr mhartid`) |
| D100 | 1 | ACTIVE | UKI Loader ELF Program Header scan (~2KB) |
| D101 | 1 | **SUPERSEDED** | Post-build ELF physical-size melt-down (5 struct gate) — **SUPERSEDED by D113 (R32 jq + --json)** |
| D102 | 1 | ACTIVE | Page-Aggregation (Server compact + U-Mode sparse) |
| D103 | 1 | ACTIVE | FFI ownership red line (Pin static pool, no stack ptr) |
| D104 | 1 | **SUPERSEDED** | sstatus.FS/VS Lazy Save — **SUPERSEDED by D118 (R34 FS=Off 题面错误纠正)** |
| D105 | 1 | ACTIVE | build.zig initrd file count ≤ 50 (D46 gate) |
| D106 | 1 | **SUPERSEDED** | Trap entry sscratch 二次交换 防御 — **SUPERSEDED by D107 (R31 per-Hart HLCB)** |

## R31: Multi-core + multi-protocol audit (3 GAP reopen) — RATIFIED

| # | Class | Status | Decision |
|---|-------|--------|----------|
| D107 | 1 | ACTIVE | Trap entry sscratch range check 锚定 HLCB per-Hart 区间 (Q23 选项 A — **R31 裁定 RATIFIED**) |
| D108 | 1 | ACTIVE | Shim Layer `SHIM_PAYLOAD_MAX` 按 `-Dip_family=v4\|v6` 编译期派生 (Q24 选项 A — **R31 裁定 RATIFIED**) |
| D109 | 2 | ACTIVE | Sparse 模式 "PTE alignment" 语义降级 + D31/D84 SATP/PMP 二级隔离 (Q25 选项 B — **R31 裁定 RATIFIED**, rename from "PTE isolation" to "PTE alignment" codified) |

## R31 prior: Work-Stealing compile-time guard (D111,补漏 — 13-build-pipeline.md 已引用)

| # | Class | Status | Decision |
|---|-------|--------|----------|
| D111 | 1 | ACTIVE | Work-Stealing scheduler 必须 `num_harts > 1` AND `has_global_coherence == true`,build.zig 编译期门禁 |

## R32: Error + ex_table + ELF gate audit (3 GAP reopen) — RATIFIED

| # | Class | Status | Decision |
|---|-------|--------|----------|
| D110 | 1 | ACTIVE | D91 adaptive 标志位 Bit 31 → Bit 30 重定位 + 解码次序「符号→Bit30→普通值」钉死 (Q26 选项 A — **R32 裁定 RATIFIED**) |
| D112 | 1 | ACTIVE | D116 ex_table 二分查找统一用 `ld` (8B) 替代 `lwu` (4B),entry 16B 排序闸门 (Q27 选项 A — **R32 裁定 RATIFIED**) |
| D113 | 1 | ACTIVE | D101 check_elf_sizes.sh 改用 `llvm-readobj --syms --json` + `jq` + `set -euo pipefail` (Q28 选项 A — **R32 裁定 RATIFIED**). **R51-FIX (F-1 勘误增补)**: 旧命令 `llvm-readobj --syms --json` 在 LLVM 18 不存在 `--json` 旗标 (沙箱三实测撞过); 修正为 `llvm-readobj --syms --elf-output-style=JSON` + `jq '.[].Symbols[].Symbol'` (R51-M6). 旧脚本块 13:216 加 [OBSOLETED-by-R51-M6] 标注. |

## R33: 集成与门禁目录审计 (3 GAP reopen) — RATIFIED

| # | Class | Status | Decision |
|---|-------|--------|----------|
| D114 | 1 | ACTIVE | 15-phase0-mvp.md 同步 R31/R32: T1.11/T1.13/T1.15 升级到 D113/D108/D107,新增 T1.16-T1.20 (Q29 选项 A — **R33 裁定 RATIFIED**) |
| D115 | 1 | ACTIVE | 20-doc-gate 59 → 63 + 4 条 R31/R32 衍生禁词 + 元禁词类别 (Q30 选项 A — **R33 裁定 RATIFIED**) |
| D116 | 1 | ACTIVE | 07-shell D97 audit 改用 `cargo geiger --all-targets` + unsafe allowlist (Q31 选项 A — **R33 裁定 RATIFIED**) |

## R34: HAL 状态机 + syscall ABI 边界 (3 GAP reopen) — RATIFIED

| # | Class | Status | Decision |
|---|-------|--------|----------|
| D117 | 1 | ACTIVE | D94 Tier 2 IPI ACK 等待 1ms timeout (rdtime 派生) + panic fall-through, peer_mask + Hart ID 输出 (Q32 选项 A — **R34 裁定 RATIFIED**) |
| D118 | 1 | ACTIVE | D104 Lazy Save 后 FS=Off + trap-and-retry + 三条件消歧 (Q33 选项 A+B 合成 — **R34 裁定 RATIFIED, 题面 FS=Clean 错误已纠正**) |
| D119 | 1 | ACTIVE | syscall6 6-arg XLEN 原生整型, per-syscall arity 表 0x00-0x3F, Zig comptime + C _Static_assert 双端 (Q34 选项 A — **R34 裁定 RATIFIED**) |

## R35: 顶层摘要与历史决策收敛 (3 GAP reopen) — RATIFIED

| # | Class | Status | Decision |
|---|-------|--------|----------|
| D120 | 1 | ACTIVE | SPEC.md / 01-system-overview.md 全量重写 Headline/Plan/Success 同步 D1-D119 (Q35 选项 A — **R35 裁定 RATIFIED**) |
| D121 | 1 | ACTIVE | D74 SSOT 白名单 5 struct + 白名单外类型必须手写 + 内嵌三端编译期断言块, 手写 + 无断言 = 熔断 (Q36 选项 A+补强 — **R35 裁定 RATIFIED**) |
| D122 | 1 | ACTIVE | D62 标 DEPRECATED superseded by D73, ledger 全表 status 列回填 (Q37 选项 A — **R35 裁定 RATIFIED**) |

## R36: 端到端数学 + 4 Pillars 完整 Spec (3 GAP reopen) — RATIFIED

| # | Class | Status | Decision |
|---|-------|--------|----------|
| D123 | 1 | ACTIVE | BlockPool 净/物理双口径分立, V2.2 图双列标注, 量纲标签 net/physical/NOLOAD, doc-gate 恒等式机检 (Q38 选项 A 台账前置 — **R36 裁定 RATIFIED**) |
| D124 | 1 | ACTIVE | D101 size 闸门补 stride 维度, 期望值编译期派生 (block_count × page_size), 类型身份问题归 D121 断言网 (Q39 选项 A 派生常量 — **R36 裁定 RATIFIED**) |
| D125 | 1 | ACTIVE | 00-ffi-pillars.md 聚合红线非内容, 权威方向单向化, 子系统复述必须回链 00 锚点 (Q40 选项 A 红线聚合 — **R36 裁定 RATIFIED**) |

## R37: Stride gate / AtomicBool / Trap 判据审计 (3 GAP reopen) — RATIFIED

| # | Class | Status | Decision |
|---|-------|--------|----------|
| D126 | 2 | ACTIVE | D124 stride gate 期望值按 build profile × layout 编译期派生 (embedded_sparse=512 KB / server_compact=384 KB), 与 D123 台账同源 (Q41 选项 A — **R37 裁定 RATIFIED**) |
| D127 | 1 | ACTIVE | HLCB `in_kernel_space` 与 `sscratch_initialized` 定义为 load/store-only 原子字段, 终身禁 RMW, CI riscv64imc target + `__atomic_*` libcall grep 闸门 (Q42 修正版 — **R37 裁定 RATIFIED**) |
| D128 | 1 | ACTIVE | trap_entry 区间判据回归 sp (D106 原意), D107 标 refinement (区间来源 per-Hart HLCB 不变, 仅判据操作数回正), D82 `in_kernel_space` 不进 trap 热路径 (Q43 根因重裁 — **R37 裁定 RATIFIED**) |

## R38: FFI 红线 / CSR 解码 / 物理数学边界审计 (3 GAP reopen) — RATIFIED

| # | Class | Status | Decision |
|---|-------|--------|----------|
| D129 | 1 | ACTIVE | D119 syscall 号 a7 由 stub 的同一 asm! 块写入, 防 clobber; cosmo_call_gate 全局符号 nm 属性必须 T, 编译期 objdump 校验 a7 写入 (Q44 选项 A — **R38 裁定 RATIFIED**) |
| D130 | 1 | ACTIVE | D118 三条件闸条件 ③ `is_fp_or_vv_opcode` 解码器补全 (主码全集 0x07/0x27/0x43-0x4F), 主码判定即充分, godbolt 实测 ~5 指令无 libcall 无 RMW (Q45 选项 A — **R38 裁定 RATIFIED**) |
| D131 | 2 | ACTIVE | D108 SHIM_PAYLOAD_MAX 扩展为 per-(L3,L4) 二维查表, 5 种常见组合 IPv4×{UDP,TCP,ICMP} + IPv6×{UDP,TCP} 预定义, network_frame_t 增 `l4_proto: u8 @ offset 9` 冻结字段 (Q46 选项 A — **R38 裁定 RATIFIED**) |

## R39: 硬件对齐 / 数学恒等 / 工具机制审计 (3 GAP reopen) — RATIFIED

| # | Class | Status | Decision |
|---|-------|--------|----------|
| D132 | 1 | ACTIVE | D116.2 `.balign 4` 改 `.balign 3` 强制 8B 自然对齐, 兼容 D112 ld 8B 二分查找; 二分查找对齐掩码 `~0xF` 16B entry 起点 (Q47 选项 A — **R39 裁定 RATIFIED**) |
| D133 | 2 | ACTIVE | D49 ledger 双轨制: ceiling (644 KB 立法上限) + measured (实测 ELF json 管线), 行项目 Σ 内部 comptime 一致, 不假装等于 ceiling, 严禁 `(估)` 字面量喂断言 (Q48 选项 A+双轨制 — **R39 裁定 RATIFIED**) |
| D134 | 1 | ACTIVE | D100 UKI Loader ELF Program Header scan 策略: 取最后一个含 `__boot_meta_start` 的 PT_LOAD, BOOT_META 头布局 `magic(8B) + slot_id(4B) + reserved(4B) = 16B`, `find_boot_meta_phdr` 实现定型 (Q49 选项 A — **R39 裁定 RATIFIED**) |

## R40: Pillar 3+4 集成约束补强审计 (3 GAP reopen) — RATIFIED

| # | Class | Status | Decision |
|---|-------|--------|----------|
| D135 | 2 | ACTIVE | D109 PTE alignment per-region 解耦 (embedded sparse / compact 分立), Auto 模式默认 compact, 与 D102 自洽; Auto 行 "mixed / Yes" 自相矛盾文本消除 (Q50 选项 A — **R40 裁定 RATIFIED**) |
| D136 | 1 | ACTIVE | HLCB `sscratch_initialized: AtomicBool` (D82 复用) Step 0 trap 防线, 未初始化时直接 SBI SRST halt, 与 D95 不可恢复路径同款 (Q51 选项 A — **R40 裁定 RATIFIED**) |
| D137 | 1 | ACTIVE | D67 PLIC minimal stub 缺席 → panic, 给明确失败信号; QEMU 注入 PLIC IRQ 单测验证 catch 路径 (Q52 选项 A — **R40 裁定 RATIFIED**) |

## R41: 编译期闸门 / Panic 路径 / 退化树审计 (3 GAP reopen) — RATIFIED

| # | Class | Status | Decision |
|---|-------|--------|----------|
| D138 | 1 | ACTIVE | 删 `-mno-f` 伪 flag, arch = `rv64imac` + `feat`-disable + build.zig comptime 三件套校验 RVV/FP, 编译期 + 链接期双层防御 (Q53 选项 A — **R41 裁定 RATIFIED**) |
| D139 | 1 | ACTIVE | Panic 路径多通道冗余 SBI putchar → UART0 MMIO → SRST system reset; 递归检测用 D127 load/store-only `__panic_in_progress`, 与 D95 DTB collision 同款 reset (Q54 选项 A — **R41 裁定 RATIFIED**) |
| D140 | 2 | ACTIVE | D28/D40 5 步退化 BlockPool-only (Reclaim → Compact → Spill → Reduce FS window → Panic), MacDmaPool/IPC/PMP 各走 short-form; Phase 0 D65 仅 comptime assert (Q55 选项 A — **R41 裁定 RATIFIED**) |

## R42: Hart ID 来源 / FS 状态机 / NodePool 提交时机审计 (3 GAP reopen) — RATIFIED

| # | Class | Status | Decision |
|---|-------|--------|----------|
| D141 | 1 | ACTIVE | D99 Hart ID 来源: a0 寄存器权威 (OpenSBI 预校验), SBI HSM `hart_get_id` 杜撰 (HSM 无此函数, 高危) 禁, DTB `num_harts` 断言兜底, park 循环路由 (Q56 选项 A 方向 + 机制重写 — **R42 裁定 RATIFIED, R46 反杜撰纪律一并生效**) |
| D142 | 1 | ACTIVE | D118 三条件扩四条件: 加 `build_options.has_fp_extension` 与 `has_v_extension` 编译期检查, `is_fp_or_vv_opcode` 拆 `is_fp_opcode` + `is_vv_opcode` 各自检查 (Q57 选项 A — **R42 裁定 RATIFIED**) |
| D143 | 2 | ACTIVE | D61 NodePool Phase 0 NOLOAD 不变 (D5), Phase 1+ 启动时显式 commit 132 KB 物理连续页, 严禁 lazy commit (避免零碎物理页); commit 失败走功能降级非 panic (Q58 选项 A — **R42 裁定 RATIFIED**) |

## R43: 多核拓扑 / Pin-Binding / Cache Line Profile 审计 (3 GAP reopen) — RATIFIED

| # | Class | Status | Decision |
|---|-------|--------|----------|
| D144 | 1 | ACTIVE | D94 Tier 3 `num_harts > 1` 走 SBI IPI 自旋锁 (rfence 异步路径), peer 侧 quiescent spin 契约, 禁进调度热路径 (Q59 选项 A — **R43 裁定 RATIFIED**) |
| D145 | 1 | ACTIVE | D43 Pin-Binding Phase 0 实现: per-Hart 任务表 + `task_affinity` 显式绑定, 禁运行时随机 Hart 绑定, 跨 Hart 调度禁用 (Hart 故障走 D139 panic) (Q60 选项 A — **R43 裁定 RATIFIED**) |
| D146 | 1 | ACTIVE | D71 RpcUnit 缓存行对齐按 profile 派生 `align(64)` Embedded / `align(128)` Server, 池基址 cache line 对齐防 false sharing (Q61 选项 A — **R43 裁定 RATIFIED**) |

## R44: 链接期 W^X / fixup 嵌套 / CPIO 计数审计 (3 GAP reopen) — RATIFIED

| # | Class | Status | Decision |
|---|-------|--------|----------|
| D147 | 1 | ACTIVE | D66 立法明确化为 entry.S Step 0 顶部 `fence.i` 单条, 闸门改**链接期 W^X 校验** (page table/segment flags), `fence.i` 非特权指令表述纠错 (Q62 选项 A — **R44 裁定 RATIFIED**) |
| D148 | 1 | ACTIVE | D116 fixup 嵌套路径泛化为 `S-Mode fault + SUM=0 ⇒ 致命`, `cosmo_do_user_fault_fixup` 增 SUM 状态机检测, 触发直接 panic, 与 D139 fail-safe 一致 (Q63 选项 A — **R44 裁定 RATIFIED**) |
| D149 | 2 | ACTIVE | D36/CPIO `parse_cpio` 只计 regular file (mode bit `S_ISREG`), 目录/symlink 不计入 FILE_TABLE; 矩阵与文本矛盾以文本为准 (Q64 选项 A — **R44 裁定 RATIFIED**) |

## R45: 负向证据末轮 (3 GAP reopen) — RATIFIED

| # | Class | Status | Decision |
|---|-------|--------|----------|
| D150 | 1 | ACTIVE | D94 跨 Hart 读 `in_kernel_space` 走 `sbi_remote_fence_vma` 控制面同步, 数据 cache 一致性由 IPI+CMO (Zicbom) 保障 (SBI RFENCE 无数据一致性语义); 场景被 D145 预闭 (Q65 修正版 — **R45 裁定 RATIFIED**) |
| D151 | 2 | ACTIVE | file_entry_t **自然布局 80B** (inode@0 / block_index@8 / flags@16 / name@17, char name[60] 对齐 1, 隐式尾对齐 80), `_Static_assert(sizeof == 80)`; D46 FILE_TABLE .rodata 台账 **4 KB** (50 × 80B = 4000B ≤ 4096B). **R47 勘误增补 (P1-5)**: R46 临时裁定 84B / D46 4.2KB 经 ctypes 实测反驳 (char name[60] 对齐为 1, `pad@17–23` 不存在; 显式 padding 后实际为 88B), 本轮回滚 D151 至 80B / D46 4 KB; R46 `.rodata + .bss mutable_table` 双结构维持 (Q66 R46 A 选 — **R45 裁定 RATIFIED**, R47 勘误纠正 R46) |
| D152 | 1 | ACTIVE | D130 decoder 收窄 0x73 主码 (FP CSR 访问): `funct3 ≠ 0` **且** CSR 编号 ∈ `{0x001 fflags, 0x002 frm, 0x003 fcsr}` 才返回 true, 其余 0x73 走真异常路径; FS=Off 阶段读 FP CSR 自动置 FS=Initial (Q67 — **R45 裁定 RATIFIED**) |

## R50: ISA/ABI profile 矩阵立法 (1 锚) — RATIFIED

| # | Class | Status | Decision |
|---|-------|--------|----------|
| D160 | 2 | ACTIVE | **ISA/ABI profile 矩阵**: 三档 profile 五元组 (ISA / mabi / RpcUnit 粒度 / BlockPool 池 / cache line) 立法; `embedded` 走 `rv64imac / lp64 / 1536B / 精简池 / 64B`, `qemu_virt` 走 `rv64imac / lp64 / 1536B / 全量池 / 64B` (rv64gc/lp64d 为 FPU 需求时特许变体), `server_compact` 走 `rv64gc / lp64d / 1536B / 96 页 compact 池 / 128B`; 粒度列当前一律 1536B, `endpoint_compact=256B` 记 PROVISIONAL 候选 (触及 frozen 门 `rpc_unit_t=1536`, 需独立 Q 研究, 不激活). 矩阵为索引, 语义细节在 02/08/13 各源 D#. 回追批准: 沙箱二 lp64d 构建追认为 qemu_virt 特许变体合规; 沙箱三 imac 构建追认为 qemu_virt 基线合规 (与 R51-F2 一致). 详见 `docs/16-profile-matrix.md` (Q78 OPEN: endpoint_compact 256B 粒度研究). 收口传染面: `08-risc-v-hal.md` D138 / `13-build-pipeline.md` D126 / `02-memory-topology.md` D45/D49 / `04-abi-contract.md` D71/D146 各自加"见 16-profile-matrix.md"索引注. **R51-FIX-F-1 勘误增补 (反向锁)**: D138 原文 `-mno-f/-mno-d/-mno-v` 伪 flag 已勘误 (march 字符串天然不含 f/d/v + feature disable + comptime 三件套, 见 R51 收口 R50 行 R50-1)

| # | Class | Status | Decision |
|---|-------|--------|----------|
| D153 | 2 | ACTIVE | **Dispatcher 命名锚定**: Rust 侧 `cosmo_core_syscall_dispatcher.rs` 重命名为 `syscall_stubs.rs` (D129 stub 角色明示); Zig 侧 `syscall_dispatch.zig` 为 call gate 落点唯一合法名, **不改名** (D56 Call Gate 入口不变). forbidden-word: 文档中出现裸名 `dispatcher` (无角色前缀) 即视为未锚命名. Back-link: 05-call-gate.md:40-41 + 15-phase0-mvp.md:180-181 + 07-shell-architecture.md dispatcher 段. 沙箱三 D-04 收口 (Q69-Q75 议程同源 fd 语义不立)|
| D154 | 2 | ACTIVE | `SYS_SHUTDOWN = 0x28` 14 号表登记 (Phase 0 不实现; Phase 1 立法 typed-syscall 路径). Phase 0 power-off 走 **HAL FFI 不占 a7** 的 `cosmo_hal_shutdown()` 直接 SBI SRST (a0 reset_type=0, a1 reason=system_failure). 沙箱三 D-05 收口. |
| D155 | 2 | ACTIVE | 锚点变量 `.bss` 零初始化 — Zig 形态 `var shim_state: ShimState = .{}` 显式零构造; 不允许 `.rodata const`. spec_lab 双轨断言 `R51-M2-bss-anchor.{sh,_negative.sh}` (text-grep; compile-gate pending, Q77). 沙箱三 D-07 收口. |
| D156 | 2 | ACTIVE | `error_pack` 打印字面量冻结 — 唯一合法格式 `error: code=%d  sub=0x%04X node=0x%04X` 三字段必齐. spec_lab 双轨断言 `R51-M3-errorprint.{sh,_negative.sh}` (text-grep; QEMU log 三字段正则). 沙箱三 D-08 收口. |
| D157 | 2 | ACTIVE | Phase 0 ledger 上限固化 — `text ≤ 81920B` (80KB), `rodata ≤ 10240B` (10KB), `data ≤ 4096B` (4KB), `bss ≤ 8192B` (8KB). 越界 `build.zig @compileError` 熔断. spec_lab 双轨断言 `R51-M4-ledger-cap.{sh,_negative.sh}` (text-grep; compile-gate pending, Q77). 沙箱三 D-11 收口. **量测口径 (本轮钉死)**: 四段实测取链接脚本符号 (`.bss_size` 等), 非 `llvm-size` 段列 — 后者把 NOLOAD 的 Hart-Local 栈 (D107) 计入 bss 必误报; 分层: 池维度走编译期 `@compileError`, 四段实测走链接后 verify-elf (详见 30 号 Q77). |
| D158 | 2 | ACTIVE | HLCB 删除 `in_kernel_space` 字段 (R47 P1-1 extern struct 64B 严守); 托管方案: `.bss` 单独 8B Hart-Local Control 用于 RR 调度. 同步 D107 + D150. spec_lab 双轨断言 `R51-M5-hlcb-bss.{sh,_negative.sh}` (text-grep; compile-gate pending, Q77). 沙箱三 D-16 收口. |
| D159 | 2 | ACTIVE | `ReleaseSmall` 默认 `-Dstrip` 让 nm/readobj 输空表, 闸门空真过; 必须显式 `-Dstrip=false -Doptimize=ReleaseSafe`. spec_lab 双轨断言 `R51-M7-strip-mode.{sh,_negative.sh}` (text-grep; compile-gate pending, Q77). 沙箱三 D-21 收口 (从大桶提到 M 桶, 变体). |

## R47: P1-5 勘误增补挂靠

| 挂靠 D# | 修正内容 |
|---------|----------|
| D151 | R46 84B/4.2KB 临时裁定被 ctypes 实测反驳; R47 撤销 84B 断言, D151 回到 80B 形式, D46 FILE_TABLE 台账回滚为 4 KB; R45 § D151 行已 inline 此勘误增补。**传染面**: 09-memory-subsystem.md § D151 显式 padding 块标 OBSOLETED-by-R47; 02-memory-topology.md § V2.2 ledger D46 行恢复 "4 KB" 数字并附 `// R47 勘误增补: R46 84B/4.2KB 已撤销` 注记 |

## 元规则: RATIFIED 传染面清单 (D-tag Propagation)

R31-R33 九问揭示两类失效模式:
1. 局部假设冒充全局不变量 (R31/R32)
2. 裁决不传染 (R33 全部)

**新元规则**: 任何决策 RATIFIED 时必须附「传染面清单」(受影响文档 + 任务编号 + 禁词条目), 清单未闭环前该决策不得标记为 closed。Q30 Option C 在流程层的手工版, Phase 1 D-tag 索引上线后自动化。

**R36 元规则四扩展**: 所有 spec 中出现的派生数字必须带权威源 + 量纲标签 (R35/D120 + R36/D123 联合)。数字失同步 = 构建错误, 不是文档瑕疵。

## Class distribution

| Class | Count | Definition |
|-------|-------|------------|
| 1 evidence | ~80 | Verified with RISC-V spec, git, or version check |
| 2 coherence | ~30 | Follows spec thesis (16KB stack, 1536B, zero-heap) |
| 3 taste | ~6 | See Decisions Log in SPEC.md |
| DEPRECATED | 1 | D62 superseded by D73 |
| SUPERSEDED | 6 | D91→D110, D96→D108, D101→D113, D104→D118, D106→D107, D116→D112 |

## Cross-references

- **SPEC.md** top-level summary — full rewrite per D120, anchor to `00-ffi-pillars.md`
- **00-ffi-pillars.md** — 4 pillars aggregation, single source of red lines (D125)
- Per-subsystem docs (04, 05, 06, 07, 08, 09, 10, 11, 12, 13, 14, 15)
- Plan file: R1-R46 audit rounds (含 R47 勘误增补 P1-5 D151 回滚)
