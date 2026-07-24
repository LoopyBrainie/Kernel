# 20 · Documentation Gate (Forbidden Words — count derived)

**Plan section**: §二十.7
**Key decisions**: D36, D51, D57, D59-D62, D64-D67, D69-D75, D77-D95, D96-D106, D107-D152
**Status**: Active CI gate; count derived from `${#FORBIDDEN[@]}` (single source of truth, no hardcoded "59/63/67/70" anywhere)

---

## Overview

A mechanical CI script (`ci/check-docs.sh`) blocks phrases that historically caused drift, regressions, or contradictions across R12-R46 audit rounds. The gate is the single source of truth for "what cannot be written" in `docs/`. New forbidden words are added only via this file.

## Gate contract

```bash
$ bash docs/ci/check-docs.sh
✓ Wriggly-Octopus documentation gate passed (0/N forbidden words)
$ echo $?
0
```

where `N` is derived live from the array length. The script enforces a **lower floor** of 70 (R12-R36 baseline) and fails closed if any forbidden word is found in `docs/`.

## Forbidden word census

| Round | New | Cumulative | Note |
|-------|-----|------------|------|
| R12 文字校准 | 6 | 6 | 基线 |
| R12 文字校准 | 6 | 6 | 基线 |
| R13 V2.2 topology | 1 | 7 | |
| R14 §十.6 文字 | 1 | 8 | |
| R16 1536B network | 3 | 11 | |
| R17 NodePool + sscratch | 3 | 14 | |
| R18 DTB + sscratch + TableFull | 4 | 18 | |
| R19 PLIC + SMP sync | 4 | 22 | |
| R20 Trap + RpcUnit + path | 3 | 25 | |
| R21 Call Gate + SSOT + Flash | 3 | 28 | |
| R22 Panic + DTB + FILE_TABLE | 3 | 31 | |
| R23 dev:// + Sstc + PIE | 3 | 34 | |
| R24 HLCB + AIA + VMA + offsetof | 4 | 38 | |
| R25 ABI red line + A ext + Early Console + Q22 | 4 | 42 | |
| R26 全裸整型 + Bit31 + Early Boot | 3 | 45 | |
| R27 PIE + Coherence + Anti-Trampling | 3 | 48 |
| R28 Shim + containerized + DTB max | 3 | 51 | |
| R29 S-Mode mhartid + UKI ELF + link-time | 3 | 54 | |
| R30 Page-Aggregation + FFI + FS/VS + initrd + Trap | 5 | 59 | |
| R31 多核 + 多协议族 + PTE alignment | 6 | 65 | D107/D108/D109 + rename/PTE 替换 |
| R32 错误码 + ex_table + ELF gate | 7 | 72 | D112/D113/D114 (BlockPool 256 + Shim L3 + Sv39 fence.vma + lwu ex_table/fixup + awk→llvm-readobj) |
| R33 D115 SUM 弃用 + D116 ex_table 必经 | 2 | 74 | D115 动态修补页表层弃用 + D116 异常修复必经 ex_table |
| R34 D119 csrs/csrc vs csrrs/csrrc | 1 | 75 | D119 (csrs/csrc 立即数, csrrs/csrrc 寄存器) |
| R35 (无新增禁词) | 0 | 75 | — |
| R36 (无新增禁词) | 0 | 75 | — |
| R37 stride gate / RMW / sp 判据 | 2 | 77 | D126/D127 (D128 无新禁词) |
| R38 a7 防 clobber / FP+VV 解码 | 4 | 81 | D129/D130 |
| R39 .balign 8B / ledger 双轨 / UKI ELF PHDR | 5 | 86 | D132/D133/D134 |
| R40 PTE per-region / Step0 trap / PLIC 缺席 | 5 | 91 | D135/D136/D137 |
| R41 arch 显式 / Panic 多通道 / 5 步退化 | 6 | 97 | D138/D139/D140 |
| R42 Hart ID a0 权威 / FP+V 独立 / NodePool commit | 7 | 104 | D141/D142/D143 (含 R46 反杜撰: SBI HSM hart_get_id 反例) |
| R43 Tier3 IPI / Pin-Binding / Cache line profile | 3 | 107 | D144/D145/D146 |
| R44 fence.i / SUM=0 / CPIO S_ISREG | 3 | 110 | D147/D148/D149 |
| R45 跨 Hart SBI RFENCE / FILE_TABLE / FP CSR 0x73 | 4 | 114 | D150/D151/D152 |
| R46 (无独立禁词) | 0 | 114 | R46 修正条目计入 R42 (R42/R46 双标) |
| R47 P1-5 撤销 + P3-* 勘误增补 | 15 | 129 | P1-5 撤销 D151 84B 裁定 (3 条) + P3-1~P3-11 勘误增补 (12 条) |
| R48 F3 sys_result_t 形态统一 | 4 | **133** | uint32_t code / code: u32 / status: u32 / struct sys_result_payload_t (终验补 1) |
| R51 F1 Zig 版本字面量 | 1 | **134** | host Zig 0.16 (D-01: Zig ≥0.15 toolchain.lock 锁定) |
| R51 F2 toolchain audit vs build profile 分立 | 1 | **135** | rustup.*lp64d.*构建 (D-02: 审计=lp64d, 构建=D138 imac lp64) |
| R51 F3 dispatcher 命名锚 (D153) | 1 | **136** | cosmo_core_syscall_dispatcher (D153: 旧名被 syscall_stubs.rs 替代) |
| R51 F4 700KB 量纲澄清 (D-10) | 1 | **137** | ≤700KB 物理跨度 (700KB 是 ELF 文件大小) |
| R51 F5 rev8 禁 Zbb 假设 (D-13) | 1 | **138** | rev8.*builtin (rv64imac 无 B/Zbb) |
| R51 M1 SYS_SHUTDOWN 路径冻结 (D154) | 1 | **139** | SYS_SHUTDOWN.*typed-syscall (shutdown 走 HAL FFI, 不占 a7) |
| R51 M2 锚点变量 .bss 零构造 (D155) | 1 | **140** | ShimState.*const (锚点变量禁 const) |
| R51 M3 error_pack 三字段冻结 (D156) | 1 | **141** | node=0x%04X\\? (三字段必齐, 缺任一字段视为漂移) |
| R51 M4 ledger 上限固化 (D157) | 1 | **142** | bss.*16384 (bss 上限 8KB, 不可放宽) |
| R51 M5 HLCB 字段托管 .bss (D158) | 1 | **143** | in_kernel_space:.*AtomicBool (字段已移 .bss) |
| R51 M6 size-csv LLVM 18 命令 (D133 扩) | 1 | **144** | llvm-readobj.*--syms.*--json (LLVM 18 必须 --elf-output-style=JSON) |
| R51 M7 ReleaseSmall strip 显式 (D159) | 1 | **145** | ReleaseSmall.*默认.*strip (必须 -Dstrip=false) |
| R50 GOV.4 三词入册 + 矩阵 D160 配套 | 4 | **149** | spec_lab 副本 / frozen 等同于已写 / R49 草图烂掉靠 reviewer 眼 (R49-GOV.4 R50 入册) + rpc_unit_t = 256B (D160 矩阵: endpoint_compact=256B 未立法) |
| R52 第四节血统缺口登记册收口 (D161/D162/D163) | 1 | **150** | -fno-stack-protector (D161: C HAL 栈保护器必启 -fstack-protector-strong, 严禁 -fno-stack-protector 出现于 docs/) |
| R53 Naming Taxonomy SSOT 立法 (D164/D165/D166/D167) | 4 | **154** | neura_sys_result_t / basal_sys_result_t / cortix_sys_result_t / synapse_sys_result_t (D165: 跨语言公共符号不加组件前缀, 4 反向锚, Linux 内核惯例; 与 D121 5 struct 白名单 + D171 neura_ syscall 前缀三向正交) |
| R59 neura_ syscall API 立法 (D171) + R60 命名迁移最终封口 (D172) | 14 | **168** | cosmo_open / cosmo_read / cosmo_write / cosmo_close / cosmo_seek / cosmo_stat / cosmo_yield / cosmo_ping / cosmo_rpc_send / cosmo_pte_map_6arg / cosmo_ipc_send_6arg / cosmo_open_stub / cosmo_pte_map_6arg_fn / cosmo_node_id (13 条 D171 派生禁词 + 1 条 D172 元规则: 历史引用豁免策略; R60 收口统一入册, EXPECTED_TOTAL 154→168; R58 因 Q69 阻塞跳过, Phase 1 待启) |
| R58 补执行 (D173 Q69 豁免) — cortix_kernel crate 名迁移 | 1 | **169** | cosmo_kernel (D173 派生禁词; Q69 Rust crate 拓扑阻塞由 D173 正交论证豁免: crate 命名空间标识 vs 运行时数据流 fd 0/1/2 路由; R58 补执行在 R60 之后追加, EXPECTED_TOTAL 168→169; 实际传染面 1 文件 1 行 `07-shell-architecture.md:92 use cosmo_kernel` → `use cortix_kernel`) |
| R61 D171 增补 — syscall 编号表 11-15 (HAL-暴露型 syscall 入口) | 5 | **174** | cosmo_copy_from_user / cosmo_copy_to_user / cosmo_atomic_cas_ptr / cosmo_hal_set_next_timer / cosmo_hal_fs_is_dirty (R59 计划文件 §1.2 漏列的 5 个 syscall 入口; R61 在 R58 补之后追加, EXPECTED_TOTAL 169→174; syscall 0x0B-0x0F 编号表 5 行 `cosmo_*` → `neura_*`; 接口层剥离 HAL 限定符 `hal_` (例 `neura_set_next_timer` 非 `neura_hal_set_next_timer`); 30-open-questions.md line 2400/2404 stale cross-ref 同步) |
| R62 D174 — mmap 后缀命名补漏 + GOV.5 收官同步状态头纪律 | 1 | **175** | mmap_cosmo (R62 收口后缀形态 `_cosmo` 漏网修补: 18 条现有禁词仅前缀 `cosmo_*` 字面匹配, 不覆盖后缀 `*_cosmo`; R62 入册 `mmap_cosmo` 同名符号, 改名 `neura_mmap` 同 D171 syscall API 命名法; 同步 D174 立 GOV.5 收官同步状态头纪律, 传染面 09:126 + 30:1144 rename, 03/SPEC/00 状态头三件套自身示范同步; EXPECTED_TOTAL 174→175) |
| R63 D175 — 门禁盲区补漏 + SPEC.md 扫描面立法 + boot banner SSOT | 1 | **176** | COSMO BOOT OK (R63 三目标收口: (a) check-d-backlinks 正则扩 D170-D199, floor 35→49, 文案三处同步; (b) SPEC.md 纳入禁词门扫描面, 触发 4 处实质改名 (SPEC.md:68/307 PTE isolation→PTE alignment, SPEC.md:147/179 cosmo_panic_abort→basal_panic_abort) + 09:122 D174 标签新增; (c) boot banner SSOT 立 `NEURA BOOT OK` 于 06-boot-sequence.md § Banner SSOT 段, 15:363 回链. GOV.5 三件套→四件套 (+README.md); EXPECTED_TOTAL 175→176) |
| **Total** | — | **176** | `${#FORBIDDEN[@]}` 派生 (R63 自校: N 必须 == 176) |

(*Cumulative counts in this table are best-effort documentation; the canonical count is `${#FORBIDDEN[@]}` in the script.*)

## GOV.5 收官同步状态头检查单 (R62-D174 派生, 硬性签发前提)

> **触发场景**: 每个 R##-FINAL commit 收口时 (硬性签发前提, R51 迭代协议扩展)。任何 R## 收口批次自身须同时满足以下"收官同步"三件套; 不闭环即视为状态头断档 (与 R50/R60 时代 README/索引断档同类), 不应标 closed。

| 子项 | 权威源 (grep 必须命中) | 触发条件 |
|------|------------------------|----------|
| ① `docs/03-design-decisions.md` 标题 + 状态行 | `^# 03 · Design Decisions \(D1-D<上限> Full Table\)` + `^\*\*Status\*\*:` 状态行 (含 R52-R<当前 R##>) | 标题 D# 上限 + 状态行 R## 终值 |
| ② `SPEC.md` 状态头 | `^\*\*Status\*\*: D1-D<上限> frozen \(R31-R<当前 R##> RATIFIED\); 0 open questions$` | D# 上限 + R## 终值 |
| ③ `docs/00-naming-taxonomy.md` status 头 | `^\*\*Status\*\*: Frozen.*R<最近 R##>` | status 头 R## 最近值 |

> **R62 自身示范**: D174 立法 + 三件套同步已写入本批次 commit。R50 era README 断档 (R50 后 03 标题停在 D1-D160) + R60 era SPEC.md 断档 (R60 后 SPEC.md 状态头停在 D1-D167 R31-R53) + R60 era 03 status 行止于 R50 — 三断档 R62 一次性补齐。
>
> **R63 升级三件套→四件套**: D175 立法后, GOV.5 检查单扩展为四件套 — ① `03-design-decisions.md` 标题 + 状态行, ② `SPEC.md` status 头 (R63 起纳入禁词门扫描面, 不能再用 README 替代), ③ `00-naming-taxonomy.md` status 头, ④ `README.md` + `docs/README.md` 标题/范围 (`Wriggly-Octopus` → `Neur-Aegis`, `D1-D160` → `D1-D174`)。理由: R62 三件套恰好漏掉 README 这条 R50 断档的老伤口; D174(b) 立法的"自身示范"commit message 自称同步, 但实际漏改 `00-naming-taxonomy.md` — 该遗漏由 R62-HOTFIX 立即补齐, 并促使 R63 立 D175 显式把 README 列入四件套。
>
> **下次收口 R## 必须**: commit message 显式列出四件套同步 (例 `R64-FINAL: ... + 03/SPEC/00/README 状态头同步`)。README 双陈旧已由 R63-HOTFIX 手动 sync, 但仍须 R##-FINAL 持续盯守 (R63 起纳入 GOV.5 检查单硬约束)。

## What each forbidden word defends against

| Forbidden phrase | Round | Defends against |
|------------------|-------|------------------|
| `Radix Tree` | R12 | D36 flat table contradiction |
| `Sector Redirect` | R12 | D36 flat table contradiction |
| `Delta Area` | R12 | D36 flat table contradiction |
| `Micro-CoW` | R12 | D36 chose flat, not CoW |
| `S-Mode: None` | R12 | 自杀配置 (no S-Mode = no kernel) |
| `0x801FF000` | R12 | Old physical address (superseded by 0x80200000) |
| `516KB` | R13 | Pre-V2.2 size; current is 644KB |
| `PMP 强隔离静态池` | R14 | D31 chose soft isolation, not PMP |
| `1544` | R16 | D42 old value; 1536 is correct |
| `1500B + 44B` | R16 | Old SG-DMA math (D42) |
| `no-MMU ELF` | R16 | D59 forbids no-MMU ELF format |
| `1536B 包含 14B` | R17 | D60 14B MAC is external to 1536B |
| `裁减 NodePool` | R17 | D61 132KB NodePool must be preserved |
| `tail 直接调用 dispatcher` | R17 | D56 revised to `call` + sscratch |
| `DTB 物理位置在 .boot_meta 内` | R18 | D63 DTB must be decoupled |
| `sscratch 全局静态` | R18 | D64 sscratch must be Hart-Local |
| `运行时检测 TableFull` | R18 | D65 Phase 0 = comptime assert only |
| `Phase 0 多次 fence.i` | R18 | D66 Phase 0 = single global fence.i |
| `通用 PLIC 驱动` | R19 | D67 PLIC stub retired |
| `irq_register` | R19 | D67 PLIC stub no dynamic registration |
| `Secondary Hart 立即初始化 sscratch` | R19 | D68 must spin-wait |
| `Phase 0 硬件级隔离` | R19 | D69 Phase 0 = pure software defense |
| `S-Mode 异步中断简单 csrrw` | R20 | D70 superseded by D73 |
| `RpcUnit align(128) 不同 Profile 切换` | R20 | D71 unified align(64) |
| `路径长度不限制` | R20 | D72 open path strictly ≤ 60 |
| `Call Gate 触碰 sscratch` | R21 | D73 Call Gate never touches sscratch |
| `手写 abi.rs` | R21 | D74 SSOT auto-generation |
| `1536B 直接写入 4KB Flash` | R21 | D75 4KB page alignment protocol |
| `Panic handler 各语言独立` | R22 | D76 C HAL = single panic entry |
| `Primary Hart 立即释放 DTB` | R22 | D77 deferred to Phase B |
| `FILE_TABLE 在 NodePool 槽位` | R22 | D78 FILE_TABLE in .rodata |
| `14B MAC 静态 .bss 扁平` | R23 | D79 dev:// DMA pool |
| `stimecmp 无条件直写` | R23 | D80 Sstc detection + SBI fallback |
| `0x80200000 硬编码物理基址` | R23 | D81 PIE dynamic base |
| `D62 旧 csrrw 栈切换` | R24 | D82 HLCB in_kernel_space |
| `AIA 暂留无接口占位` | R24 | D83 trigger_msi + local_csr_sync slot |
| `BlockPool 静态基地址永久` | R24 | D84 Phase 1 SATP VMA dynamic |
| `RpcUnit 仅 size 断言` | R24 | D85 three-end offsetof |
| `sys_result_t > 16B` | R25 | D86 C ABI 16B red line |
| `A 扩展硬依赖` | R25 | D87 RV64IMAC soft fallback |
| `DTB 损坏即静默挂死` | R25 | D88 Early Console SBI Stub |
| `Q22 错误码未扩展` | R25 | D89 sys_result_payload_t 8B closure |
| `跨语言结构体允许 Option/enum` | R26 | D90 all-primitive-int red line |
| `i32 error_code 单形态` | R26 | D91 Bit 31 adaptive extension |
| `kmain 前 sscratch 默认零` | R26 | D92 Early Boot Stack two-stage |
| `Phase 0 全 PIE` | R27 | D93 fixed link base 0x80200000 |
| `sc.d 硬依赖` | R27 | D94 cross-Hart Coherence soft fallback |
| `DTB 与 .bss 无校验` | R27 | D95 Anti-Trampling pre-zero |
| `Shim Layer 可选` | R28 | D96 default ON |
| `Phase 0 第三方应用直接加载` | R28 | D97 mandatory compile-time audit |
| `DTB 无动态上界` | R28 | D98 Profile switch 64KB/8MB |
| `S-Mode csrr mhartid` | R29 | D99 OpenSBI FFI only |
| `UKI Loader 无 ELF 解析` | R29 | D100 ~2KB ELF PH scanner |
| `跨语言结构体仅依赖编译期断言` | R29 | D101 link-time ELF gate |
| `服务器端 25% Padding 税` | R30 | D102 Page-Aggregation |
| `跨 FFI 栈指针` | R30 | D103 Pin static pool red line |
| `无脑全保存向量寄存器` | R30 | D104 FS/VS Dirty Bit Lazy |
| `initrd 文件数无门禁` | R30 | D105 build.zig ≤ 50 |
| `Trap 入口无 sscratch 判定` | R30 | D106 nested interrupt defense |
| `PTE isolation` (应改 PTE alignment) | R31 | D109 降级为 4KB alignment + D31/D84 SATP/PMP 二级隔离 |
| `ip_family 字段偏移可调整` | R31 | D108 Phase 0 冻结 network_frame_t.ip_family offset==8 |
| `lwu ex_table` / `lwu fixup` | R32 | D112 统一 ld (8B) 读 exception_table_entry |
| `awk.*readobj` 配合 `print \$5` | R32 | D113 check_elf_sizes.sh 改用 llvm-readobj --syms --json + jq |
| `uint32_t code` | R48 | F3 sys_result_t 旧 C 形态 (P1-2 后改 header/reserved/payload union) |
| `code: u32` | R48 | F3 sys_result_t 旧 Rust 形态 (P1-2 后改 header/reserved/payload union) |
| `status: u32` | R48 | F3 sys_result_t 旧 Zig 形态 (P1-2 后改 reserved) |
| `动态修补页表层 U-Mode 数据流转` | R33 | D115 弃用, 统一 sstatus.SUM 搭便车 |
| `绕过 .fixup 异常表` | R33 | D116 异常修复必经 ex_table |
| `csrs sstatus 寄存器` | R34 | D119 csrs/csrc 立即数, csrrs/csrrc 寄存器 |
| `对 HLCB 字段使用 RMW 原子操作` | R37 | D127 load/store-only 红线 (Tier 3 RV64IMC 无 A 扩展) |
| `stride 期望值未感知 profile` | R37 | D126 期望必须按 profile×layout 派生 (D49 双行制) |
| `syscall number 隐式 a7 约定` | R38 | D129 a7 必须 stub asm! 块内写入 |
| `7 参数 C 签名落 a7` | R38 | D129 a7 防 clobber (RISC-V ABI 第 7 参数落 a6, 不是 a7) |
| `FP/RVV 解码器运行时假设合法` | R38 | D130 解码器必须全主码覆盖 (RISC-V Unprivileged Spec §25) |
| `FMADD 族漏检` | R38 | D130 0x43-0x4F 主码必须显式 |
| `.balign 4 + ld 8B 混用` | R39 | D132 8B ld 需 8B 自然对齐 (.balign 3) |
| `ledger 阶段尚未精确划子段` | R39 | D133 双轨制 ledger 必须公开 (R48 已落 ceiling/named/headroom 三量纲) |
| `把 (估) 喂断言` | R39 | D133 实测与立法上限分立 |
| `Locates ... segment 策略未定义` | R39 | D134 UKI Loader 必须明确查找策略 |
| `UKI Loader 段查找含糊` | R39 | D134 取最后一个 PT_LOAD 包含 `__boot_meta_start` 的段 |
| `Auto 模式 mixed padding` | R40 | D135 Auto 单点默认, per-region 解耦 |
| `BlockPool 内部混合 layout` | R40 | D135 pool 内部 layout 必须单值 |
| `Step 0 期间 trap 不可恢复` | R40 | D136 Step 0 trap → SBI SRST halt (D139 panic 路径) |
| `PLIC silently ignored` | R40 | D137 PLIC 缺席必须 panic, 禁 silently |
| `无外部中断 trap handler 路径` | R40 | D137 trap_handler 显式 panic 路径 |
| `kernel FP 隐式 allowed` | R41 | D138 arch 字符串 + feat disable 显式 |
| `FS=Off 默认 by default` | R41 | D138 FS 状态由 sstatus 显式管理 |
| `panic 假定成功` | R41 | D139 多通道冗余 + fail-stop |
| `panic fall-through 单一路径` | R41 | D139 多通道 + 物理停机 |
| `5-step degradation 未定义` | R41 | D140 BlockPool 5 步退化定义定型 |
| `Pool 退化假定成功` | R41 | D140 退化路径必须走 panic, 不允许 silent fallback |
| `Hart ID 假定 a0` | R42 | D141 a0 权威, DTB num_harts 兜底 (R46 反杜撰) |
| `禁止 -bios none` | R42 | D141 park 路由 (Hart 1+ 等 Hart 0) |
| `SBI HSM hart_get_id` | R42/R46 | D141 HSM 无此函数 (HSM fid 0 = hart_start), R46 反杜撰纪律 |
| `Hart ID 探测 SBI 兜底` | R42/R46 | D141 a0 权威 + DTB num_harts 兜底, 禁探测 SBI |
| `D118 三条件覆盖所有 RVV 场景` | R42 | D142 RVV 需独立检查 (FP 与 RVV 各自触发条件) |
| `NodePool 物理页按需 lazy commit` | R42 | D143 禁止 lazy commit, 一次性预留 |
| `NodePool commit 假定成功` | R42 | D143 commit 走 panic 守门, 不允许假定成功 |
| `Tier 3 假定单 Hart` | R43 | D144 num_harts>1 走 IPI 自旋锁, 禁假定单 Hart |
| `Pin-Binding alternative 假定实现` | R43 | D145 task_affinity 显式绑定, 禁假定默认实现 |
| `RpcUnit align 统一 64B` | R43 | D146 profile 派生 align 64/128 (Server profile 128B) |
| `fence.i 全局自动` | R44 | D147 Step 0 顶部单条 + 链接期 W^X 校验 (R46 勘误: fence.i 非特权) |
| `SUM 状态机假定单一` | R44 | D148 S-Mode fault + SUM=0 ⇒ 致命 (二次 fixup panic) |
| `initrd 计 entry 数` | R44 | D149 S_ISREG only, 目录/symlink 不计 entry |
| `in_kernel_space 跨 Hart 假定可见` | R45 | D150 IPI + CMO/Zicbom 一致性 |
| `SBI RFENCE 用作数据一致性原语` | R45/R46 | D150 SBI RFENCE 无数据一致性 (只指令缓存) |
| `FILE_TABLE 单一不可变` | R45 | D151 R46 双结构 .rodata + .bss mutable_table |
| `FP CSR 访问假定合法` | R45 | D152 0x73 必须二次解码: funct3≠0 且 CSR∈{fflags,frm,fcsr} |
| `FILE_TABLE 4.2KB` | R47 | D151 撤销 (ctypes 实测: sizeof 自然布局 80B, 50×80B=4 KB) |
| `sizeof.*file_entry.*84` | R47 | D151 撤销 (实测 80B, 非 84B) |
| `file_entry_t 自然 84B` | R47 | D151 撤销 (实测 80B) |
| `static __thread work_queue_t` | R47 | P3-3 TLS tp 冲突, 改全局数组 |
| `csrr menvcfg` | R47 | P1-4 S-Mode illegal, 改 DTB/trap-probe (menvcfg 仅 M-Mode 合法) |
| `jr t0                  # jump` | R47 | P3-4 syscall 必须 jalr ra, t0 (jr 丢 ra) |
| `task_table\[next\].active` | R47 | P3-5 rr_pick_next 终止条件修复 |
| `& 0x3  // FS == 0b11` | R47 | P3-6 basal_hal_fs_is_dirty 名实一致 (改 ==0x3) |
| `.\[\]\?\.[]\?` | R47 | P3-7 jq 3-level 路径修补 |
| `SSTATUS_MXR & (1 << 19)` | R47 | P3-8 恒假断言 (改 ALLOWED_MASK) |
| `csrs/csrc 接受立即数, csrrs/csrrc 接受寄存器` | R47 | P3-9 D119 立法颠倒 (csrs/csrc 立即数 vs csrrs/csrrc 寄存器) |
| `ecall → M-Mode → S-Mode` | R47 | P3-10 medeleg 直委派 S-Mode (不经 M-Mode) |
| `22KB 缺口` | R47 | P3-11 R48: 改 D49 双行制, 已命名子段 581.5 KB + 余量 62.5 KB = ceiling 644 KB, 此禁词保留防 R47 伪闭合回归 |
| `hartid<<SHIFT` | R47 | P3-1 off-by-one, 改 `(hartid+1)<<SHIFT` |
| `struct sys_result_payload_t` | R48 | F3 Rust payload 必须 union 不是 struct (终验抓出: 两个 8B 字段在 struct = 16B, size_of==8 断言永远熔断) |
| `spec_lab 副本` | R49-GOV.4 (R50) | D160 矩阵: 断言目录下出现代码副本, 不是抽取得到 (frozen = 编译过的) |
| `frozen 等同于已写` | R49-GOV.4 (R50) | D160 矩阵: frozen 必须经 runner 验证, 不靠手写 |
| `R49 草图烂掉靠 reviewer 眼` | R49-GOV.4 (R50) | D160 矩阵: 必须机器 enforced, R50 check_goal_manifest.sh 落地 |
| `rpc_unit_t = 256B` | R50/D160 | 矩阵立法: endpoint_compact=256B 未立法, 任何现行 RpcUnit 形态暗示 256B 即熔断 (Q78 OPEN) |
| `-fno-stack-protector` | R52 D161 | C HAL 栈保护器必启 -fstack-protector-strong; v2.1 §3.2 防御静默消失的反向锁 |

## How to add a new forbidden word

1. Identify the contradiction pattern (regressed decision, alternative proposal that lost, R-round outcome)
2. Add entry to `ci/check-docs.sh` FORBIDDEN array with comment `R#X D#Y (rationale)`
3. The script's sanity floor is **70** (R12-R36 baseline); do not lower it. The headline count `N = ${#FORBIDDEN[@]}` is derived live.
4. Add row to this file's census table
5. Run `bash docs/ci/check-docs.sh` to verify (it should now FAIL on existing docs that contain the word)
6. Migrate any existing docs that use the word
7. Verify gate passes again

## D# 回链机检 (P0-5 / R47 / R50 扩)

每个 D126+ 决策号必须在其 contagion 目标文档（subsystem spec 文件）中可被 `grep` 命中；空回链 = 传染未闭环 = 闸门熔断。脚本：`docs/ci/check-d-backlinks.sh`。

```bash
$ bash docs/ci/check-d-backlinks.sh
✓ check-d-backlinks passed (35 D126-D160 tags, all back-linked, canary self-test OK)
```

规则（R47 立法 / R50 扩 D160+）：
- D# 来源：`docs/03-design-decisions.md` status table（`| D### | class | ACTIVE|...` 行）
- 排除文件（数据载体，搜索时跳过）：`03-design-decisions.md`、`20-documentation-gate.md`、`30-open-questions.md`、`ci/check-docs.sh`、`ci/check-d-backlinks.sh`、`ci/check_goal_manifest.sh`
- 词边界匹配：`(^|[^0-9])D###([^0-9]|$)` 防 D1260 等子串假阳
- 失败模式：熔断并打印缺失 D# 列表
- 自验证：`${#D_TAGS[@]} ≥ 35`（D126-D160 全集 = R37-R45 27 + R51 7 + R50 1），不足即 FATAL exit 2

## Cross-references

- All 19 subsystem docs must pass this gate
- All D126+ tags must back-link per `check-d-backlinks.sh`
- CI/CD runs both gates on every push (see `SPEC.md` Success Criteria)
- The gate is the **single source of truth** for forbidden phrasing
- The D# back-link gate enforces the contagion-surface discipline (R36 元规则四)
