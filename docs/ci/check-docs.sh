#!/usr/bin/env bash
# =============================================================================
# Wriggly-Octopus Documentation Gate (single source of truth for forbidden words)
# =============================================================================
# Source: plan §二十.7, accumulated through R12-R46 audit rounds
# Count: derived from `${#FORBIDDEN[@]}` (no hardcoded 59/63/67/70 anywhere)
# Exit codes: 0 = pass, 1 = forbidden word found, 2 = self-validation fail
# =============================================================================
set -e

FORBIDDEN=(
  # R12 — 文字校准
  "Radix Tree"                            # D36 文字清扫
  "Sector Redirect"                       # D36
  "Delta Area"                            # D36
  "Micro-CoW"                             # D36 (Phase 0 用 Flat File Table)
  "S-Mode: None"                          # R12 文字校准 (自杀配置)
  "0x801FF000"                            # R12 D12 修正 (已迁移)

  # R13
  "516KB"                                 # R13 D49 (516 → 644KB)

  # R14
  "PMP 强隔离静态池"                      # R14 D51 闭环

  # R16
  "1544"                                  # R16 D57 (D42 旧值)
  "1500B + 44B"                           # R16 D57 (D42 旧 SG-DMA)
  "no-MMU ELF"                            # R16 D59 (Phase 0 禁止)

  # R17
  "1536B 包含 14B"                        # R17 D60 (链路层 14B 不在 1536B 内)
  "裁减 NodePool"                         # R17 D61 (132KB 必须保留)
  "tail 直接调用 dispatcher"              # R17 D62 (D56 修订为 call + sscratch)

  # R18
  "DTB 物理位置在 .boot_meta 内"        # R18 D63 (DTB 与 .boot_meta 物理解耦)
  "sscratch 全局静态"                    # R18 D64 (sscratch 必须 Hart-Local)
  "运行时检测 TableFull"                 # R18 D65 (Phase 0 仅 comptime assert)
  "Phase 0 多次 fence.i"                 # R18 D66 (Phase 0 仅 1 次全局)

  # R19
  "通用 PLIC 驱动"                       # R19 D67 (PLIC 桩退役, 严禁通用化)
  "irq_register"                         # R19 D67 (PLIC 桩严禁动态注册)
  "Secondary Hart 立即初始化 sscratch"   # R19 D68 (必须自旋等待)
  "Phase 0 硬件级隔离"                   # R19 D69 (Phase 0 纯软件防御)

  # R20
  "S-Mode 异步中断简单 csrrw"            # R20 D70 (已被 D73 替代)
  "RpcUnit align(128) 不同 Profile 切换" # R20 D71 (统一 align(64))
  "路径长度不限制"                       # R20 D72 (Phase 0 open 严格 <= 60)

  # R21
  "Call Gate 触碰 sscratch"              # R21 D73 (Call Gate 不碰 sscratch)
  "手写 abi.rs"                          # R21 D74 (SSOT 自动生成)
  "1536B 直接写入 4KB Flash"             # R21 D75 (4KB 物理页对齐伪装协议)

  # R22
  "Panic handler 各语言独立"             # R22 D76 (C HAL basal_panic_abort 唯一; D168 R54 收口, D76 SUPERSEDED)
  "Primary Hart 立即释放 DTB"            # R22 D77 (推迟到 Rendezvous Phase B)
  "FILE_TABLE 在 NodePool 槽位"          # R22 D78 (FILE_TABLE 驻留 .rodata)

  # R23
  "14B MAC 静态 .bss 扁平"               # R23 D79 (dev:// 网络 DMA 缓冲池)
  "stimecmp 无条件直写"                  # R23 D80 (Sstc 探测 + SBI 降级)
  "0x80200000 硬编码物理基址"             # R23 D81 (PIE 动态基地址)

  # R24
  "D62 旧 csrrw 栈切换"                  # R24 D82 (HLCB in_kernel_space 双重防御)
  "AIA 暂留无接口占位"                   # R24 D83 (trigger_msi + local_csr_sync 槽位)
  "BlockPool 静态基地址永久"             # R24 D84 (Phase 1 SATP VMA 动态)
  "RpcUnit 仅 size 断言"                # R24 D85 (三端 offsetof 字段偏移)

  # R25
  "sys_result_t > 16B"                   # R25 D86 (C ABI 16B 生死线)
  "A 扩展硬依赖"                          # R25 D87 (RV64IMAC 软降级)
  "DTB 损坏即静默挂死"                   # R25 D88 (Early Console SBI Stub)
  "Q22 错误码未扩展"                      # R25 D89 (sys_result_payload_t 8B 闭环)

  # R26
  "跨语言结构体允许 Option/enum"        # R26 D90 (全裸整型红线)
  "i32 error_code 单形态"                # R26 D91 (Bit 31 自适应扩展)
  "kmain 前 sscratch 默认零"             # R26 D92 (Early Boot Stack 双阶段刷新)

  # R27
  "Phase 0 全 PIE"                       # R27 D93 (锁定 0x80200000)
  "sc.d 硬依赖"                          # R27 D94 (跨 Hart Coherence 软降级)
  "DTB 与 .bss 无校验"                   # R27 D95 (Anti-Trampling 前置)

  # R28
  "Shim Layer 可选"                      # R28 D96 (默认启用, 商业生态兼容)
  "Phase 0 第三方应用直接加载"           # R28 D97 (强制编译期审计)
  "DTB 无动态上界"                       # R28 D98 (Profile 切换 64KB/8MB)

  # R29
  "S-Mode csrr mhartid"                  # R29 D99 (M-Mode 专有)
  "UKI Loader 无 ELF 解析"               # R29 D100 (无法定位动态 .boot_meta)
  "跨语言结构体仅依赖编译期断言"        # R29 D101 (必须有链接后置校验)

  # R30
  "服务器端 25% Padding 税"              # R30 D102 (Page-Aggregation 紧凑排布)
  "跨 FFI 栈指针"                         # R30 D103 (Pin 静态池红线)
  "无脑全保存向量寄存器"                  # R30 D104 (FS/VS Dirty Bit Lazy Save)
  "initrd 文件数无门禁"                  # R30 D105 (build.zig 编译期 ≤ 50)
  "Trap 入口无 sscratch 判定"            # R30 D106 (嵌套中断二次交换防御)

  # R31
  "Hart-Local 栈偏移用 time CSR"         # R31 D107 (用 hartid, 不用 time)
  "Tier 2 关 SIE 模拟原子"               # R31 D108 (D94 Tier 2 需 IPI 同步)
  "1536B 内存对象表示"                   # R31 D109 (wire format 不变, memory layout 可变)
  "SHIM_PAYLOAD_MAX = 1458"              # R31 D110 (MTU 不含 MAC, 应为 1464)
  "无 coherence 选 Work-Stealing"        # R31 D111 (build.zig 编译期熔断)
  "BlockPool 256 blocks"                 # R32 D112 (256 blocks / 128 pages Embedded Sparse)

  # R32
  "Shim 仅处理 L3"                       # R32 D113 (同时处理 L2 MAC 帧 ≤ 1518B)
  "Sv39 切换忽略 fence.vma"              # R32 D114 (严格 6 步 supervisor-paging-enable)
  "动态修补页表层 U-Mode 数据流转"       # R33 D115 (弃用, 统一 sstatus.SUM 搭便车)
  "绕过 .fixup 异常表"                   # R33 D116 (异常修复必经 ex_table)
  "PTE isolation"                         # R31 D109 (应改 PTE alignment)
  "ip_family 字段偏移可调整"             # R31 D108 (Phase 0 冻结 offset==8)
  "lwu ex_table"                          # R32 D112 (统一 ld 8B)
  "lwu fixup"                             # R32 D112 (统一 ld 8B)
  "awk.*readobj 配合 print"               # R32 D113 (改用 llvm-readobj --syms --json + jq)
  "csrs sstatus 寄存器"                   # R34 D119 (csrs/csrc 立即数, csrrs/csrrc 寄存器)

  # R37 (Q41-Q43 → D126-D128)
  "对 HLCB 字段使用 RMW 原子操作"        # R37 D127 (load/store-only 红线)
  "stride 期望值未感知 profile"           # R37 D126 (期望必须按 profile×layout 派生)

  # R38 (Q44-Q46 → D129-D131)
  "syscall number 隐式 a7 约定"           # R38 D129 (a7 必须 stub asm! 块内写入)
  "7 参数 C 签名落 a7"                    # R38 D129 (a7 防 clobber)
  "FP/RVV 解码器运行时假设合法"          # R38 D130 (解码器必须全主码覆盖)
  "FMADD 族漏检"                         # R38 D130 (0x43-0x4F 主码必须显式)

  # R39 (Q47-Q49 → D132-D134)
  ".balign 4 + ld 8B 混用"               # R39 D132 (8B ld 需 8B 对齐)
  "ledger 阶段尚未精确划子段"            # R39 D133 (双轨制 ledger 必须公开)
  "把 (估) 喂断言"                       # R39 D133 (实测与立法上限分立)
  "Locates ... segment 策略未定义"       # R39 D134 (UKI Loader 必须明确查找策略)
  "UKI Loader 段查找含糊"                # R39 D134

  # R40 (Q50-Q52 → D135-D137)
  "Auto 模式 mixed padding"               # R40 D135 (Auto 单点默认, per-region 解耦)
  "BlockPool 内部混合 layout"             # R40 D135 (pool 内部 layout 必须单值)
  "Step 0 期间 trap 不可恢复"            # R40 D136 (Step 0 trap → SBI SRST)
  "PLIC silently ignored"                 # R40 D137 (PLIC 缺席必须 panic)
  "无外部中断 trap handler 路径"          # R40 D137

  # R41 (Q53-Q55 → D138-D140)
  "kernel FP 隐式 allowed"               # R41 D138 (arch 字符串 + feat disable 显式)
  "FS=Off 默认 by default"                # R41 D138
  "panic 假定成功"                        # R41 D139 (多通道冗余 + fail-stop)
  "panic fall-through 单一路径"           # R41 D139
  "5-step degradation 未定义"             # R41 D140 (BlockPool 5 步定义定型)
  "Pool 退化假定成功"                    # R41 D140

  # R42 (Q56-Q58 → D141-D143)
  "Hart ID 假定 a0"                       # R42 D141 (a0 权威, DTB num_harts 兜底)
  "禁止 -bios none"                       # R42 D141
  "SBI HSM hart_get_id"                   # R42/R46 D141 (HSM 无此函数, R46 反杜撰纪律)
  "Hart ID 探测 SBI 兜底"                # R42/R46 D141
  "D118 三条件覆盖所有 RVV 场景"          # R42 D142 (RVV 需独立检查)
  "NodePool 物理页按需 lazy commit"       # R42 D143 (禁止 lazy commit)
  "NodePool commit 假定成功"             # R42 D143

  # R43 (Q59-Q61 → D144-D146)
  "Tier 3 假定单 Hart"                    # R43 D144 (num_harts>1 走 IPI 自旋锁)
  "Pin-Binding alternative 假定实现"     # R43 D145 (task_affinity 显式绑定)
  "RpcUnit align 统一 64B"               # R43 D146 (profile 派生 align 64/128)

  # R44 (Q62-Q64 → D147-D149)
  "fence.i 全局自动"                      # R44 D147 (Step 0 顶部单条, 链接期 W^X 校验)
  "SUM 状态机假定单一"                    # R44 D148 (S-Mode fault + SUM=0 ⇒ 致命)
  "initrd 计 entry 数"                   # R44 D149 (S_ISREG only, 目录/symlink 不计)

  # R45 (Q65-Q67 → D150-D152)
  "in_kernel_space 跨 Hart 假定可见"     # R45 D150 (IPI + CMO/Zicbom 一致性)
  "SBI RFENCE 用作数据一致性原语"         # R45/R46 D150 (SBI RFENCE 无数据一致性)
  "FILE_TABLE 单一不可变"                # R45 D151 (R46 双结构 .rodata + .bss mutable_table)
  "FP CSR 访问假定合法"                  # R45 D152 (0x73 必须二次解码: funct3≠0 且 CSR∈{fflags,frm,fcsr})

  # R47 (P1-5 勘误增补 — 撤销 R46 D151 84B/4.2KB 临时裁定)
  "FILE_TABLE 4.2KB"                     # R47 撤销 (ctypes 实测: sizeof 自然布局 80B)
  "sizeof.*file_entry.*84"               # R47 撤销
  "file_entry_t 自然 84B"                # R47 撤销

  # R47 (P3-* 勘误增补 — 反杜撰 / 闭环修补)
  "static __thread work_queue_t"         # R47 P3-3 (TLS tp 冲突, 改全局数组)
  "csrr menvcfg"                          # R47 P1-4 (S-Mode illegal, 改 DTB/trap-probe)
  "stimecmp 无条件直写"                  # R23 D80 (Sstc 探测 + SBI 降级) — R47 P1-4 保留原条目
  "jr t0                  # jump"        # R47 P3-4 (syscall 必须 jalr ra, t0)
  "task_table\[next\].active"             # R47 P3-5 (rr_pick_next 终止条件修复)
  "& 0x3  // FS == 0b11"                 # R47 P3-6 (cosmo_hal_fs_is_dirty 名实一致)
  ".\\[\\]\\?\\.\\[\\]\\?"              # R47 P3-7 (jq 3-level 路径修补)
  "SSTATUS_MXR & (1 << 19)"              # R47 P3-8 (恒假断言, 改 ALLOWED_MASK)
  "csrs/csrc 接受立即数, csrrs/csrrc 接受寄存器" # R47 P3-9 (D119 立法颠倒)
  "ecall → M-Mode → S-Mode"              # R47 P3-10 (medeleg 直委派 S-Mode)
  "22KB 缺口"                            # R47 P3-11 (子段划分后闭合)
  "hartid<<SHIFT"                        # R47 P3-1 (off-by-one, 改 (hartid+1)<<SHIFT)

  # R48 (F3 sys_result_t 形态统一, P1-2 反向禁词, R48 勘误增补)
  "uint32_t code"                        # R48 F3 (sys_result_t 旧 C 形态, P1-2 后改 header)
  "code: u32"                            # R48 F3 (sys_result_t 旧 Rust 形态)
  "status: u32"                          # R48 F3 (sys_result_t 旧 Zig 形态, P1-2 后改 reserved)
  "struct sys_result_payload_t"         # R48 F3 终验抓出 (amend bae69b1 范畴): Rust payload 必须 union 不是 struct (两个 8B 字段在 struct = 16B, size_of==8 断言永远熔断)

  # R51 (12 锚定词, F 桶 5 + M 桶 7 = 12, 见 §1 R51 收口路径)
  "host Zig 0.16"                       # R51 F1 (D-01: Zig ≥0.15 toolchain.lock)
  "rustup.*lp64d.*构建"               # R51 F2 (D-02: 审计 vs 构建 profile 分立)
  "cosmo_core_syscall_dispatcher"     # R51 F3 (D-04 / D153: 旧名被 syscall_stubs.rs 替代)
  "≤700KB 物理跨度"                   # R51 F4 (D-10: 700KB 是 ELF 文件大小)
  "rev8.*builtin"                     # R51 F5 (D-13: rv64imac 无 Zbb, 禁 rev8)
  "SYS_SHUTDOWN.*typed-syscall"        # R51 M1 (D-05 / D154: shutdown 走 HAL FFI 路径, 不占 a7; 用 "typed-syscall" 防自命中)
  "node=0x%04X\\?"                     # R51 M3 (D-08 / D156: node= 字段收尾问号? 防止缺字段)
  "ShimState.*const"                  # R51 M2 (D-07 / D155: 锚点变量禁 const, 必须 var = .{})
  "ReleaseSmall.*默认.*strip"        # R51 M7 (D-21 / D159: 必须 strip=false)
  "llvm-readobj.*--syms.*--json "    # R51 M6 (D-20: LLVM 18 必须 --elf-output-style=JSON)
  "in_kernel_space:.*AtomicBool"     # R51 M5 (D-16 / D158: HLCB 已删此字段, .bss RR 托管)
  "bss.*16384"                        # R51 M4 (D-11 / D157: bss 上限 8KB, 不可放宽到 16KB)

  # R50 (GOV.4 立法 + 矩阵立法, D160, 4 条新禁词)
  "spec_lab 副本"                     # R49-GOV.4 (R50 入册): 断言目录下出现代码副本, 不是抽取得到
  "frozen 等同于已写"                 # R49-GOV.4 (R50 入册): frozen 必须经 runner 验证
  "R49 草图烂掉靠 reviewer 眼"       # R49-GOV.4 (R50 入册): 必须机器 enforced, 不靠眼
  "rpc_unit_t = 256B"                # R50 D160 (矩阵立法): 256B 粒度未立法, 任何 RpcUnit 形态暗示 256B 即视为漂移

  # R52 (第四节血统缺口登记册收口, D161 栈保护器反向锁)
  "-fno-stack-protector"             # R52 D161: C HAL 栈保护器必启 -fstack-protector-strong, 严禁 -fno-stack-protector

  # R53 (命名法 SSOT 立法, D165 跨语言无前缀规则 4 反向锚)
  "neura_sys_result_t"                # R53 D165: D121 5 struct 不加 neura_ 前缀
  "basal_sys_result_t"                # R53 D165: D121 5 struct 不加 basal_ 前缀
  "cortix_sys_result_t"               # R53 D165: D121 5 struct 不加 cortix_ 前缀
  "synapse_sys_result_t"              # R53 D165: D121 5 struct 不加 synapse_ 前缀
)
# Self-validation: derived count, single source of truth.
# Lower bound = R12-R36 baseline (70). Floor avoids regression to old total.
# Self-validation: derived count, single source of truth.
# Self-validation: derived count, single source of truth.
# Self-validation: derived count, single source of truth.
# Self-validation: derived count, single source of truth.
# Lower bound = R12-R36 baseline (70). Floor avoids regression to old total.
FORBIDDEN_COUNT=${#FORBIDDEN[@]}
if [ "${FORBIDDEN_COUNT}" -lt 70 ]; then
  echo "[FATAL] check-docs.sh array length ${FORBIDDEN_COUNT} dropped below R12-R36 floor (70)"
  exit 2
fi
# R48 勘误增补: 自验证 census Total == N (硬性提交门槛)
#   census Total 在 20-documentation-gate.md "Forbidden word census" 表末行
#   每次新增禁词必须同步更新 census 与本 EXPECTED_TOTAL, 否则 fail-closed
EXPECTED_TOTAL=154
if [ "${FORBIDDEN_COUNT}" -ne "${EXPECTED_TOTAL}" ]; then
  echo "[FATAL] check-docs.sh array length ${FORBIDDEN_COUNT} != census Total ${EXPECTED_TOTAL}"
  echo "  (R48+: 同步更新 census 表 (20-documentation-gate.md) 与脚本 EXPECTED_TOTAL)"
  exit 2
fi

EXIT=0
# Exclude this script + the gate catalog doc + the audit history file from path-level exclude.
# Line-pattern exclude: R51-FIX (F-1 过滤器真洞修补).
# R48 老豁免规则: "勘误词出现在注释行"则放行 — 这是 F-1 漏洞根因.
# R51 新规则: R37-R45 描述行通过 "R4[0-9]+ 勘误" 等锚定模式豁免 (历史反向锁描述).
#                R51 新加反向锁必须挂 [OBSOLETED-by-...] 才能豁免 (双轨防线).
AUDIT_LINE_FILTER='grep -vE "\[OBSOLETED|rename from|审计档案|审计动机|应为|应改|诚实性|命名诚实性|was: PTE|migration|原文|R4[0-6] 勘误|R4[0-6] 修正|R36 错算|R36 D80 原案|R37 勘误|R37 修正|R37 D128|R38 勘误|R39 勘误|R40 勘误|R41 勘误|R42 勘误|R43 勘误|R44 勘误|R45 勘误|R45 默认|R45 裁定|R45 原案|D151 R46|R46 勘误|R46 修正|R46 落地|R46 同款|R46 反杜撰|R46 自然布局|R46 ledger|R46 双结构|R46 同步|R46 临时|R46 版|R46 关键|R46 形式|R46 错判|R46 臆想|R46 勘误后|R47 勘误|R47 修正|R47 落地|R47 反杜撰|R47 增补|R47 撤销|R47 立法|R47 立法注|R47 ctypes|R47 后回到|R47 默认|R48 勘误|R49 勘误|R51 note|R51 注|R51 修订|R51 自校|R51 命名锚|R51 D153|R51-F1|R51-F2|R51-F3|R51-F4|R51-F5|R51-M1|R51-M2|R51-M3|R51-M4|R51-M5|R51-M6|R51-M7|R51-AGENDA|R52 D16[123]|R52 立法|R52 收口|R52 第四节|R53 D16[4567]|R53 命名|R53 立法|R53 收口|R53 Naming Taxonomy|D165 反向锚|D165 立法|P[1-3]-[0-9]+ 修复|P[1-3]-[0-9]+ 勘误|P[1-3]-[0-9]+ 同款|P[1-3]-[0-9]+ \(R47|Step 0 trap 防御|不分配 Vec|原 char buf|原 basal_do_user_fault_fixup|勘误后|勘误前|D153 决策|Dispatcher 命名锚定|重命名裁决|新增禁词|传染面清单|D160 (配套|矩阵)|16 号文.*rpc_unit_t.*(配套|未立法|禁用依据|R50 立法)"'
for word in "${FORBIDDEN[@]}"; do
  if grep -rnF --exclude=check-docs.sh --exclude=check-d-backlinks.sh --exclude=check_goal_manifest.sh --exclude=check-toolchain.sh --exclude=20-documentation-gate.md --exclude=30-open-questions.md -- "$word" docs/ 2>/dev/null | eval "$AUDIT_LINE_FILTER"; then
    echo "[ERROR] Forbidden word found: $word"
    EXIT=1
  fi
done

if [ $EXIT -eq 0 ]; then
  echo "✓ Wriggly-Octopus documentation gate passed (0/${FORBIDDEN_COUNT} forbidden words)"
fi
exit $EXIT
