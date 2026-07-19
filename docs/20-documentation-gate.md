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
| R32 错误码 + ex_table + ELF gate | 10 | 75 | D110-D116 + R33/R34 衍生 |
| R37 stride gate / RMW / sp 判据 | 2 | 77 | D126/D127 (D128 无新禁词) |
| R38 a7 防 clobber / FP+VV 解码 | 4 | 81 | D129/D130 |
| R39 .balign 8B / ledger 双轨 / UKI ELF PHDR | 5 | 86 | D132/D133/D134 |
| R40 PTE per-region / Step0 trap / PLIC 缺席 | 5 | 91 | D135/D136/D137 |
| R41 arch 显式 / Panic 多通道 / 5 步退化 | 6 | 97 | D138/D139/D140 |
| R42 Hart ID a0 权威 / FP+V 独立 / NodePool commit | 7 | 104 | D141/D142/D143 (含 R46 反杜撰) |
| R43 Tier3 IPI / Pin-Binding / Cache line profile | 3 | 107 | D144/D145/D146 |
| R44 fence.i / SUM=0 / CPIO S_ISREG | 3 | 110 | D147/D148/D149 |
| R45 跨 Hart SBI RFENCE / FILE_TABLE / FP CSR 0x73 | 4 | 114 | D150/D151/D152 |
| R47 P1-5 撤销 D151 84B 裁定 | 3 | **117** | sizeof/file_entry 84B → 80B |
| **Total** | — | **117** | `${#FORBIDDEN[@]}` 派生 |

(*Cumulative counts in this table are best-effort documentation; the canonical count is `${#FORBIDDEN[@]}` in the script.*)

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

## How to add a new forbidden word

1. Identify the contradiction pattern (regressed decision, alternative proposal that lost, R-round outcome)
2. Add entry to `ci/check-docs.sh` FORBIDDEN array with comment `R#X D#Y (rationale)`
3. The script's sanity floor is **70** (R12-R36 baseline); do not lower it. The headline count `N = ${#FORBIDDEN[@]}` is derived live.
4. Add row to this file's census table
5. Run `bash docs/ci/check-docs.sh` to verify (it should now FAIL on existing docs that contain the word)
6. Migrate any existing docs that use the word
7. Verify gate passes again

## D# 回链机检 (P0-5 / R47)

每个 D126+ 决策号必须在其 contagion 目标文档（subsystem spec 文件）中可被 `grep` 命中；空回链 = 传染未闭环 = 闸门熔断。脚本：`docs/ci/check-d-backlinks.sh`。

```bash
$ bash docs/ci/check-d-backlinks.sh
✓ check-d-backlinks passed (27 D126-D152 tags, all back-linked)
```

规则（R47 立法）：
- D# 来源：`docs/03-design-decisions.md` status table（`| D### | class | ACTIVE|...` 行）
- 排除文件（数据载体，搜索时跳过）：`03-design-decisions.md`、`20-documentation-gate.md`、`30-open-questions.md`、`ci/check-docs.sh`、`ci/check-d-backlinks.sh`
- 词边界匹配：`(^|[^0-9])D###([^0-9]|$)` 防 D1260 等子串假阳
- 失败模式：熔断并打印缺失 D# 列表
- 自验证：`${#D_TAGS[@]} ≥ 27`（D126-D152 全集），不足即 FATAL exit 2

## Cross-references

- All 19 subsystem docs must pass this gate
- All D126+ tags must back-link per `check-d-backlinks.sh`
- CI/CD runs both gates on every push (see `SPEC.md` Success Criteria)
- The gate is the **single source of truth** for forbidden phrasing
- The D# back-link gate enforces the contagion-surface discipline (R36 元规则四)
