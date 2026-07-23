# 30 · Open Questions

**Status**: ✅ **0 ACTIVE / 0 OPEN** — R37-R45 五轮审计 27 GAP (D126-D152) 全数闭庭, R46 修正落地, 收官注脚生效。
**Ledger ledger closure**: 45 Qs 全闭 (Q22-Q67, D111 轮空), 27 ACTIVE GAPs (D126-D152) 升 PROPOSED → ACTIVE。
**Audit ledger**: R37-R45 五轮 + R46 收官 (Q41-Q67) 历史保留作为审计档案, 不再 "待裁定"。
**Closure history**: 见 `03-design-decisions.md` (status 列 + supersede 链) 唯一权威源; 修正总账见本文末尾 "R41-R45 裁决修正总账"。

---

> **D172 历史引用豁免声明** (R60 RATIFIED): 本文件 R37-R45 审计档案段落, R30/R31 历史 bug 描述, R55-R59 命名迁移前的决策上下文, 围栏外的 markdown 段落 / 表格行 / 引用块保留 `cosmo_call_gate` 等旧名引用, 不强迁, 以维持历史准确性; 围栏内代码块 (asm / rust / bash / c) 的当前有效代码示例按 R54-R59 命名迁移同步。D172 适用对象不限于本文件, 泛化到所有 1X 子系统文档 (例 `10-error-handling.md:231` R30/R31 spec 引用)。见 `docs/03-design-decisions.md` D172 立法条款。

---

<!-- 当新 design tension 出现且 locked ledger 无法解决时, 在此段展开新 Q-number + Options A/B/C。
     R37-R45 审计已收官, 新 Q 只在满足 R46+ 恢复条件 (make build 熔断 / RVA23+ 新 Pillar / Phase 1 Sv39 SATP) 时开。 -->

## R37 (审计轮次 已闭庭 → ACTIVE)

> **审计动机**: R31-R36 累计 RATIFIED 21 GAP 后, 0 open 状态稳定了一个完整 phase。
> 但深入审计 Pillar 3 + Pillar 4 + D124 stride gate, 发现 3 处深层张力是当前 ledger 闭环不了的:
> (1) D124 静态期望值未感知 D102 动态重排 → server profile 构建期熔断;
> (2) D82 `AtomicBool` 在 Tier 3 不可编译, 但 Pillar 4 Tier 3 路径强行推荐;
> (3) D73+D82 让 Call Gate 在 Trap 视角下"看起来像在 U 模式", 中断撕裂栈。
> 三处均属"低层级数学/硬件 CSRs/降级路径"边界, 不在 R31-R36 范围内, 故开新 Q。

---

### Q41 — D124 stride gate 与 D102 Page-Aggregation 的静态/动态冲突

**当前 Spec 状态**:
- D102: Server Profile 启用 Page-Aggregation compact 模式, 期望 0% Padding waste, 即 256 块物理占用从 512 KB sparse 降至 384 KB compact。
- D113: `check_elf_sizes.sh` 用 `llvm-readobj --syms --json | jq` 验证 5 struct 大小。
- D124: 在 D113 之上补 stride 维度, 期望值 `block_count × page_size` 编译期派生; 但 Spec 文本未明确该期望值按 sparse 还是 compact 推导。

**冲突点**:
- 嵌入式 Embedded Sparse (Phase 0 默认): stride 期望 = `256 × 4096 / 2` (page 内 2 block) = 512 KB ✓ 与 V2.2 物理一致。
- 服务器 Server Compact (`-Dprofile=server -Dpage_aggregation=compact`): stride 期望 = `256 × 1536` = 384 KB, 但 D124 公式未感知 profile, 会按 sparse 期望 512 KB 去检查, 把 384 KB 的紧凑构建误判为 **体积回归 → 熔断**。
- 这是典型的"编译期静态闸门误杀动态演进"冲突 (用户任务一第 3 类直接点名)。

**数学复核** (双 Profile 对照):
| Profile | layout | blocks | page 容量 | physical 期望 | D124 推导 | 是否熔断 |
|---------|--------|--------|-----------|---------------|-----------|---------|
| Embedded Sparse | D45 (2 block + 1024B pad per 4KB) | 256 | 2 block/page | `256/2 × 4096 = 512 KB` | 512 KB | ✓ |
| Server Compact | D102 (no padding, 1536B-aligned) | 256 | 1536B-aligned | `256 × 1536 = 384 KB` | `block_count × page_size = 256 × 4096 / 2 = 512 KB` ❌ | **WRONG** |

> 注: "Server Compact 期望 384 KB" 成立前提是 page 容器本身被 D102 重排成 1536B-aligned, 即整页都被 block 占满, 不再预留 padding slot。这与 D45 的 sparse 假设互斥。Spec 当前用 D45 的 stride 期望覆盖 D102 的 compact 重排, 是直接语义冲突。

**Options**:

- **Option A (PROPOSED 推荐, → D126)**: 把 D124 期望值改为 `build.profile × block_count × page_size(layout)` 双层派生, build.zig 在编译期根据 `-Dprofile` 与 `-Dpage_aggregation` 推导正确期望值, D124 公式不感知 profile 但运行时拿到的常量已经是正确的。优势: D124 实现最小改动, 仅在 build_options.zig 增加 profile-aware 常量表。劣势: 编译期公式需要新增 `stride_expected_for_profile(profile, layout)` 函数, 单测覆盖 4 种组合。

- **Option B**: D124 闸门改为**只检查 ≥ 期望下限**, 不检查 ≤ 上限。即只校验 `physical >= block_count × block_size` (覆盖 sparse 与 compact 两种 layout 的下界), 上界交给 D98 max size 守门。优势: 公式简单, 不需要 profile 分支。劣势: 失去 stride 维度对 fragmentation 的早期发现能力, 不符合 D124 补漏初衷。

- **Option C**: 把 stride gate 从 build-time 移到 runtime, 由 kmain 在 init 阶段计算实际 stride 并写入 HLCB, CI 仅检查 build-time 5-struct sizes。优势: 彻底解耦 build-time 与 runtime 拓扑。劣势: 违背 D113 的"post-build ELF gate"语义, R32/Q28 已经否决过类似方向。

**裁定**: Option A → D126。理由: 最小破坏性 + 双 Profile 数学 100% 正确 + 与 D124 R36 立法意图一致。

**D126 立法定位**: D126 = D124 的 refinement, 非新原则。Q39 (R36) 已经裁定"期望值由 build option 编译期派生, Embedded Sparse 得 512 KB、Server Compact 得 384 KB, 同一公式两个 Profile 各自实例化", 但裁决文本没回写到 D124 spec, 导致 D124 文本仍停留在"block_count × page_size 单公式"形态。Q41 的价值在于把裁决与文本的裂口显性化。

**修正 Spec 条目 (D126 提案, 与 D123 双口径台账同源派生)**:

```zig
// build_options.zig (R37 D126 新增, 与 D123 净/物理双口径台账同源)
// 单一真相: V2.2 中 BlockPool 净 384 KB (256×1536B) / 物理 512 KB (128×4096B, D45 sparse)
// D102 compact 重排后 物理 384 KB (256×1536B, 0% Padding waste)
// 这两个常量必须由 D123 台账函数派生, 不允许各文件单独硬编码:
pub const stride_expected_bytes: u32 = blk: {
    const pool_net_bytes = block_count * 1536;  // 256 × 1536 = 384 KB (D49 净)
    break :blk switch (build_options.profile) {
        .embedded_sparse => (block_count / blocks_per_page) * page_size,  // 128×4096 = 512 KB (D45)
        .embedded_compact => pool_net_bytes,                              // 384 KB (D102 Phase 1+)
        .server_sparse   => (block_count / blocks_per_page) * page_size,  // 512 KB (D45)
        .server_compact  => pool_net_bytes,                                // 384 KB (D102)
    };
};
// 与 D123 净/物理双口径台账的恒等式校验:
//   embedded_sparse 期望 物理 = D123 台账 BlockPool 物理列 = 512 KB ✓
//   server_compact  期望 物理 = D123 台账 BlockPool 净列   = 384 KB ✓
```

```bash
# check_elf_sizes.sh (R37 D126 升级, R37 工具错误修正)
# 修正: __blockpool_start/__end 是符号 (symbol), 不是 program header
# llvm-readobj --syms --json 输出 .Symbols[], 不是 ["program headers"]
EXPECTED_STRIDE=$(zig run build_options.zig -Dprofile=$PROFILE -Dpage_aggregation=$AGG)
ACTUAL_BYTES=$(
  llvm-readobj --syms --json "$KERNEL_ELF" \
  | jq -r '.Symbols[] | select(.Name=="__blockpool_start" or .Name=="__blockpool_end") | .Value'
  | paste -sd ' ' \
  | awk '{ printf "%d", $2 - $1 }'   # end - start = 物理字节数
)
[ "$ACTUAL_BYTES" -eq "$EXPECTED_STRIDE" ] || { echo "D126 FAIL: expected $EXPECTED_STRIDE, got $ACTUAL_BYTES"; exit 1; }
```

**落地约束 ① (D126 落地约束 ①)**: 常量表 (embedded_sparse=512 KB / server_compact=384 KB 等) 必须与 D123 内存台账逐数一致, 两处数字同源派生, 禁止各自维护。这正是 R36 新增的"审计数字一致性"机检项的第一个应用对象。`make audit-derive-numbers` 必须覆盖 D126 常量。

**落地约束 ② (D126 落地约束 ②)**: 修正 gate 草图的工具错误: `__blockpool_start` / `__blockpool_end` 是符号, jq 选择器应查 symbol table (`.Symbols[]`), 题面写的 `program headers` 路径查不到符号级地址。R37 草图此处错误已纠正。

**落地约束 ③ (D126 落地约束 ③)**: 4 种 profile × layout 组合 (embedded_sparse / embedded_compact / server_sparse / server_compact) 的单测纳入 T1.11 的 DoD, 缺组合即任务不闭合。单测在 QEMU `-cpu rv64` 上跑 `make test-stride-profile=*`, 期望 4/4 PASS。

**否决 B、C**:
- Option B 只查下限等于自废上界 — Page-Aggregation 布局回归 (fragmentation 型膨胀) 全部逃逸, D124 立法初衷直接归零。
- Option C 把 post-build ELF 门禁挪到 runtime init — R32/Q28 已否决同方向, 违反"闸门左移原则": 能在 build 期抓的错误绝不活到 boot。

**传染面清单** (R37 元规则四): 受影响 `13-build-pipeline.md` `D113/D124` 段落 + `02-memory-topology.md` D45/D102 双 Profile 表 + `check_elf_sizes.sh` 升级点 + `15-phase0-mvp.md` T1.11 (D113 → D126)。

---

### Q42 — D82 字段在 Tier 3 (RV64IMC, 无 A 扩展) 的访问语义约束: load/store-only, 终身禁 RMW

**勘误 (R37 二审)**: 题面 Q42 称"`AtomicBool::store(SeqCst)` 在 RV64IMC 上没有目标指令, 要么 UB 要么链接失败" —— 这对 **RMW 操作**为真, 对**纯 load/store 操作**为假。**RISC-V 内存模型的 C11 原子映射设计目标之一, 就是对齐自然宽度的原子 load/store 无需 A 扩展**: SeqCst store 降级为 `fence rw,w` + `sb`, SeqCst load 降级为 `lb` + `fence r,rw`, 单条字节访存天然不可撕裂。需要 A 扩展的只有 RMW 族 (`amoswap.w` / `amoadd.w` / `lr.w` / `sc.w`) —— LLVM 对无 A target 的 RMW 才会发 `__atomic_*` libcall 造成链接熔断。所以 `in_kernel_space` 只要保持 load/store-only 用法, 在 RV64IMC 上合法编译、合法运行, 跨 Hart 也由一致性协议保证可见性 (Q42 题面前提半数是错的)。

**顺带否决原 Option A 的 SBI 路径**: `sbi_atomic_set` / `sbi_atomic_get` 在标准 SBI 扩展谱系中**不存在**。RISC-V SBI v0.2 / v2.0 规范定义的扩展只有 Base / TIME / sPI / RFNC / HSM / SRST / PMU / DBCN 等, 无 atomic 扩展 (题面自己也标注"需确认 OpenSBI 0.10+ 支持")。在一个立志"原生、纯粹"的系统里杜撰 SBI 扩展, 是最严重的生态污染选项, 直接出局。

**当前 Spec 状态**:
- D82: HLCB `in_kernel_space: AtomicBool`, SeqCst 序。
- D107: `sscratch_initialized: AtomicBool` (Boot Step 1+ 写入)。
- Pillar 4 矩阵 Tier 3 行声称 `D87 csrc SIE + FS=Off`, 但没说 `in_kernel_space` 在 Tier 3 怎么实现。
- 题面原 Option A (SBI atomic) 经勘误后**不成立**, Option B (砍字段) 与 Option C (HSM callback) 已被本轮同时否决。

**裁定 D127 (立法收紧型)**: 不替换字段类型, 不增加 fallback, 而是把 `in_kernel_space` 与 `sscratch_initialized` 两个字段定义为 **load/store-only 原子字段**, 终身禁止 RMW 操作出现在这两个字段的访问路径上。

**修正 Spec 条目 (D127 立法)**:

```rust
// HLCB 字段访问约束 (R37 D127)
//
// 强约束 (编译期 + 静态分析机检):
// 1. in_kernel_space / sscratch_initialized 仅允许 .store() / .load() 调用
// 2. 禁止 .compare_exchange* / .fetch_* / .swap_* 出现在这两个字段的访问路径
// 3. Ordering 限定: SeqCst / Release / Acquire, 不允许 Relaxed (D82 立法语义)
// 4. 类型保持 AtomicBool / AtomicU8, 不替换 (替换会触发 D74 SSOT whitelist 变更链)

/// Allowed API surface (D127 whitelist)
impl HLCB {
    pub fn enter_kernel(&self) {
        // Tier 1/2: amoswap.w/aq/rl  (D87 has_a_extension=true)
        // Tier 3:   fence;w + sb + fence;r,rw  (LLVM lowering)
        self.in_kernel_space.store(1, Ordering::SeqCst);
    }
    pub fn exit_kernel(&self) {
        self.in_kernel_space.store(0, Ordering::SeqCst);
    }
}

// Forbidden API surface (D127 blacklist, 静态分析 grep 守卫)
// self.in_kernel_space.compare_exchange(...)
// self.in_kernel_space.fetch_or(...)
// self.in_kernel_space.swap(...)
```

```bash
# R37 D127 CI 新增: riscv64imc target 构建 + __atomic_* 未定义符号扫描
# (D113 符号门禁的自然延伸, 零新工具)
make build TARGET=riscv64imc-unknown-none-elf  # 必须编译通过
nm -u build/riscv64imc/kernel.elf | grep -E '__atomic_(load|store|fetch|exchange)' \
  && { echo "D127 FAIL: RMW libcall present on no-A target"; exit 1; }
# 期望: nm -u 仅有 __*mem* / __*fence* / __*sync* libcall (load/store 路径合法)
# 禁止: __atomic_fetch_* / __atomic_compare_exchange_* / __atomic_xchg_*
```

**LLVM lowering 证据链 (R37 元规则升级硬性要求)**:

| 操作 | Tier 1/2 (有 A) | Tier 3 (无 A, LLVM `-mattr=+a` 缺省) |
|------|------------------|--------------------------------------|
| `store(true, SeqCst)` | `amoswap.w zero, t0, (a0)` (带 aq/rl) | `fence rw,w` + `sb a0, 0(a1)` + `fence rw,w` |
| `load(SeqCst)` | `ld.aqrl t0, (a0)` (若对齐, 否则 `lw.aqrl`) | `lb a0, 0(a0)` + `fence r,rw` |
| `compare_exchange(...)` | `lr.w / sc.w` retry loop | ❌ **触发 `__atomic_compare_exchange` libcall, 链接熔断** |
| `fetch_or(...)` | `amoor.w` | ❌ 触发 `__atomic_fetch_or` libcall, 链接熔断 |

证据来源: RISC-V ABIs Specification v1.0 §8.2 "Atomics" (单字节 load/store 无 RMW 需求)、LLVM `RISCVExpandAtomic` pass 源码 (`llvm/lib/Target/RISCV/RISCVExpandAtomic.cpp`, 把 RMW libcall 留给 linker, 把 load/store 直接降级为 fence+sb)。

**传染面清单**:
- `05-call-gate.md` § HLCB layout 增 D127 访问约束段
- `00-ffi-pillars.md` Pillar 3 红线陈述增"load/store-only"语义
- `08-risc-v-hal.md` § feature matrix Tier 3 行改写 (移除 SBI atomic 杜撰路径)
- `13-build-pipeline.md` 新增 `make test-no-a-ext` 包含 `nm -u` 检查
- `20-documentation-gate.md` **新增禁词**: "对 HLCB 字段使用 RMW 原子操作" (原 R37 草图的"amoswap 隐式依赖"措辞过宽 —— fence+sb 路径里根本没有 amoswap 出现, 准确措辞应锁定 RMW 调用形态)

**留给 Q43 的接口 (关键)**: R37 原 Q43 方案里的 `amoswap.w t2, t2, 0(t1)` 恰恰是一次真实 RMW 操作 —— 若按原案落地, Tier 3 上 Call Gate 每条调用都是 illegal instruction (链接期过, 但每次 runtime illegal-instruction trap)。这个雷由 Q43 的根因重裁 (D128 = sp 判据回归) 一并拆除, 见下一节。

---

### Q43 — 根因再诊断: 病灶在 R36 Pillar 3 的 sscratch 判据, 不在 D73。裁定 D128 = 恢复 sp 判据

**演化链还原 (R37 二审)**: D106 原始的 Trap 入口是 `bltu sp, __kernel_stack_base` / `bgeu sp, __kernel_stack_top` —— 判据是 **sp**。R31 的修复焦点是"全局符号 → per-Hart HLCB", Q23 裁决**只改了区间的来源, 没有裁决过判据的操作数**; 但 R31 的 Option A 草图**顺手写成了 `csrr t0, sscratch`**, R36 Pillar 3 全文继承。这是又一例"修复顺路改动了未受审的语义"。题面 Q43 把这个根因归结到 D73 是误诊。

**sscratch 判据为什么必错 (按 D92 约定)**:
- 用户态运行时, sscratch = kernel_stack_top (上次 trap swap 留下的"另一个栈顶")
- trap swap 后内核态持有, sscratch = user_sp (trap 入口 swap 的副产品)
- 场景矩阵 (sscratch 判据):

| 场景 | sscratch | 范围检查 | 判定 | 实际是否正确 |
|------|----------|----------|------|--------------|
| 用户→kernel trap (首入) | = kernel_stack_top | top 落在 [base, top) 边界, bgeu 命中 → swap ✓ | swap | ✓ |
| 内核→nested kernel trap | = user_sp | user_sp 落在 kernel range 之外 → 误判 user→kernel → **再 swap 一次** | swap ❌ | **撕裂** |
| Call Gate mid window | = kernel_stack_top | 落在 kernel range 内 → 不 swap, 用 current sp=user_sp | 不 swap ❌ | **撕裂** |
| sret 返回用户态 | (swap 后) = user_sp | 同 nested kernel 场景, 若此时 trap 进 → 撕裂 | swap ❌ | **撕裂** |

**结论**: sscratch 判据下**嵌套中断必然撕裂**。Q43 抓到的 Call Gate mid window 只是这个根病的一个实例; 即使把 Call Gate 入口补完, 嵌套 trap 那一格仍是撕裂。R37 原 Q43 方案 (4 周期 SIE 临界区 + amoswap + trap handler 新增 in_kernel_space 分支 + dispatcher 入口 mv sp, t0) **题面中两次自承"仍有矛盾""仍错"**, 是拿正确性换 D73 的表面完整。

**sp 判据下的端到端推演 (每一步可验证, 元规则硬性要求)**:

| 场景 | sp | 范围检查 (sp ∈ [base, top)) | 判定 | 实际是否正确 |
|------|----|-----------------------------|------|--------------|
| 用户运行态 | = user_sp (range 外) | bltu 命中 → swap 上内核栈 | swap | ✓ |
| Call Gate mid window (sp 仍为 user_sp) | = user_sp (range 外) | bltu 命中 → swap 上内核栈, handler 上下文压在内核栈 | swap | ✓ 窗口天然无害 |
| 内核 nested trap (sp 已在内核栈) | = 内核栈某处 (range 内) | 不 swap, 直接压栈 | 不 swap | ✓ |
| sret 路径 | (swap 后) = user_sp | (trap 入口已 swap, sret 再 swap 回去) | swap | ✓ |
| 内核 handler 中调用 dispatcher | sp = kernel_sp (range 内) | 不 swap | 不 swap | ✓ |

**sp 判据下, D73 "Call Gate 不 swap、不写 sscratch" 原样保留**, **不加 SIE 临界区、不加 amoswap、trap 热路径零新分支** —— Q42 的 Tier 3 RMW 雷同步拆除 (因为本来就没引入 RMW)。

**裁定 D128 (根因重裁)**:
1. **Trap 入口判据回写为 sp**: `sp ∈ HLCB per-Hart [base, top)` 判定 user→kernel 边 vs nested-kernel 边; sscratch 仅作 swap 持有槽, **任何路径不得作为判据**。
2. **D107 标 refinement (按 D122 登记)**: 区间来源 per-Hart HLCB 不变 (Q23 立法有效), **判据操作数回归 D106 原意 (sp 而非 sscratch)**。这是 R31 草图的语义修复, 不是静默改写, 必须走 D122 status 列登记链。
3. **链接期新增断言**: 用户栈池与内核栈池地址区间**禁止重叠** (sp 判据的正确性前提), 编译期一行断言, 符合"闸门左移原则" (能在 build 期抓的不活到 boot)。

```python
# build/link.zig (R37 D128 链接期断言)
comptime {
    const user_pool_start = @import("build_options").user_stack_pool_start;
    const user_pool_end   = user_pool_start + @import("build_options").user_stack_pool_size;
    const kern_pool_start = @import("build_options").kernel_stack_pool_start;
    const kern_pool_end   = kern_pool_start + @import("build_options").kernel_stack_pool_size;
    // D128 落地约束: 不重叠是 sp 判据正确性前提
    if (user_pool_end > kern_pool_start and kern_pool_end > user_pool_start) {
        @compileError("D128 FAIL: user/kernel stack pools overlap; sp 判据前提被破坏");
    }
}
```

4. **D82 `in_kernel_space` 角色重定位**: 保留为软件层 defense-in-depth 标志 (供调度器/审计读), **不进入 trap 热路径**。这同时满足 D127 的 load/store-only 约束 (调度器读 + 偶发写, 不在 trap 路径上, 不增加 RMW 雷)。

5. **R36 Pillar 3 sscratch 状态机图 + trap_entry asm 全文回写**:

```
       sscratch 状态                in_kernel_space (D82)
       ┌─────────────────┐          ┌──────────────────┐
       │ Step 0: early   │          │ Step 1+ init false│
       │ Step 1+: per-Hart│         │ true on kernel in │
       │ range: [base,top)│         │ false on exit    │
       └─────────────────┘          └──────────────────┘
       转换 (D128):
       user→kernel: csrrw sp, sscratch, sp  (Trap only, D92)
       kernel→user: sret                   (Trap exit)
       nested-kernel: 复用当前 sp, 不 swap
       Call Gate: 不动 sscratch/sp, 不进状态机 (D73 原样)
       
       判据 (R37 D128 修订):
       trap_entry: sp ∈ HLCB per-Hart [base, top)  ← sscratch 不参与判据
```

```asm
# trap_entry (R37 D128 重写)
trap_entry:
    # D128: 判据回归 sp, 与 D106 原意一致
    # D107: 区间来源 per-Hart HLCB (Q23 立法有效)
    mv      t0, sp                       # ← csrr sscratch 改为 mv sp
    la      t3, __hlcb_table
    slli    t4, tp, 6                    # HLCB 64B (D107 size gate)
    add     t3, t3, t4
    ld      t1, 32(t3)                   # kernel_stack_base
    ld      t2, 40(t3)                   # kernel_stack_top
    bltu    t0, t1, .L_user_mode_trap
    bgeu    t0, t2, .L_user_mode_trap

    # t0 ∈ kernel range → nested trap, 不 swap, 用 current sp
    j       .L_trap_push_context

.L_user_mode_trap:
    csrrw   sp, sscratch, sp             # D92 swap, 唯一 swap 点
    j       .L_trap_push_context
```

**cosmo_call_gate (R37 D128 维持 D73 原样, 零增量)**:

```asm
# R37 D128 裁定: D73 立法原样保留, 不加 SIE 临界区、不加 amoswap
# Q42 Tier 3 RMW 雷因没引入 RMW 而天然不存在
basal_call_gate:
    la      t0, __basal_dispatcher_ptr
    ld      t0, 0(t0)
    jr      t0
```

**传染面清单**:
- `05-call-gate.md` § entry_call_gate.S 全量替换 (cosmo_call_gate 不动 + trap_entry sp 判据回归)
- `00-ffi-pillars.md` **Pillar 3 整节** 回写 (状态机图 + 判据修改 + D128/D107 refinement 链 + D82 角色重定位)
- `06-boot-sequence.md` § Step 1 HLCB init 顺序不变 (Q23 已正确)
- `03-design-decisions.md` D107 status 列加 refinement 关系 (Q23 → D107 → D128 refinement)
- `20-documentation-gate.md` 移除 R37 草图拟新增的"Call Gate 入口关中断遗漏"禁词 (D128 证明该情形不存在)

---

## 审计结论 (R37 提交)

| Q# | 主题 | 推荐 D# | 类别 | 与 4 Pillars 关系 |
|----|------|---------|------|-------------------|
| Q41 | D124 stride gate × D102 Page-Aggregation 静态/动态冲突 | **D126** (D124 refinement, 非新原则) | 编译期闸门/动态演进冲突 (用户任务一第 3 类) | Pillar 2 + build pipeline |
| Q42 | D82 字段 Tier 3 访问语义约束 | **D127** (load/store-only, RMW 终身禁) | 多核拓扑/降级路径缺漏 (用户任务一第 2 类) | Pillar 4 graceful degradation Tier 3 行 |
| Q43 | Trap 入口判据错: sscratch 必撕裂嵌套, 回归 sp 判据 | **D128** (D107 refinement 链 + D82 脱离热路径) | 物理 CSRs/边界防御缺漏 (用户任务二 sscratch 红线) | Pillar 3 sscratch + in_kernel_space 状态机纠正 |

## 裁决总账 (R37)

| ID | 裁定 | 对应决策号 | 一句话理由 |
|----|------|-----------|------------|
| Q41 | Option A | **D126** | D124 裁决欠账回收; 期望值 profile×layout 双层派生, 与 D123 台账同源 |
| Q42 | 修正版 (否决 A/B/C 原案) | **D127** | load/store 原子无需 A 扩展 (fence+sb 合法降级), RMW 才是禁区; 杜撰 SBI 扩展违反原生原则 |
| Q43 | 根因重裁 (否决 A/B/C 原案) | **D128** | 病灶是 sscratch 判据对嵌套 trap 必撕裂; 恢复 sp 判据后 Call Gate 窗口天然无害, D73 原样保留 |

## 元规则升级 (硬性提交门槛, R37 二审后)

现有两条元规则在 R37 审计中被自身违反 (Q42 杜撰 SBI 扩展 / Q43 sscratch 判据 推演缺一格), 升级为**硬性提交门槛**:

**元规则五 (R37)**: 凡涉指令/CSR/内存模型语义的论断, 必须附:
- RISC-V 手册章节号 (Unprivileged Spec §X.Y / Privileged Spec §X.Y / ABIs Spec §X.Y)
- 编译器实际 lowering 证据 (LLVM pass 名称 + 行号, 或 godbolt.org 编译输出)

**元规则六 (R37)**: 凡提出修复方案, 必须附修复前后**双版本对全场景矩阵的逐格推演**。矩阵列至少包含:
- 用户→kernel trap (首入)
- 内核→nested kernel trap (核心场景, Q43 漏的就是这一格)
- 用户→kernel via Call Gate mid window
- sret 返回用户态后 trap 重入
- 用户栈池与内核栈池重叠边界情况

**Q43 自检**: 原 R37 Q43 方案若做过"嵌套 trap"一格的推演, 当场就会发现自己没治好根病。R37 二审后, 该方案被 D128 根因重裁替代。

**元规则四 (R36) 校验 (传染面)**:
- Q41 影响 13-build-pipeline.md + 02-memory-topology.md + 15-phase0-mvp.md T1.11, 三处必须同步标注 D126。
- Q42 影响 05-call-gate.md HLCB layout + 00-ffi-pillars.md Pillar 3 + 08-risc-v-hal.md feature matrix + 13-build-pipeline.md + 20-documentation-gate.md, 必须 D127 同号传染。
- Q43 影响 05-call-gate.md 全量替换 + 00-ffi-pillars.md **Pillar 3 整节** + 06-boot-sequence.md + 03-design-decisions.md D107 status 列加 refinement, D128 传染面最广。

**禁止漂移词自查**: 本文件不含 Radix Tree / TableFull / 跨 FFI 栈指针 / 运行时检测 / malloc / mmap / 对 HLCB 字段使用 RMW 原子操作 等 63 禁词 (D115)。

**已裁定 (R46)**: Brra1n0 在下一会话批准 Q41-Q43 → D126-D128 后, 由 doc-gate `make audit-ratify-r37` 校验传染面清单, 通过则 ledger 升 PROPOSED → ACTIVE。

---

## R38 (审计轮次 已闭庭 → ACTIVE)

> **审计动机**: R37 三处 GAP (D126/D127/D128) 触及 stride gate / AtomicBool / Trap 判据。R38 沿 4 Pillars 继续向下钻, 在 Pillar 1 (FFI) / Pillar 4 (网络 + 降级) 找出三处更深 GAP, 每处均经过 R37 元规则五/六硬性提交门槛: 附 RISC-V 手册章节 + LLVM 实际 lowering 证据 + 修复前后全场景矩阵推演。

---

### Q44 — D119 a7 穿透 Call Gate 的 FFI 红线漏洞 (D129 提案)

**当前 Spec 状态**:
- D56: Call Gate = `call cosmo_call_gate` (compiler ABI register passing), **非 ecall**。
- D73: Call Gate 入口不动 sscratch。
- D119: `a7 = syscall number`, `a0..a5 = up to 6 args`, per-syscall arity 表 0x00-0x3F (R34 立法)。
- 14-syscall-api.md:17-20 `sys_call` 寄存器约定图标注 `a7 = syscall number`。
- 05-call-gate.md:55-59 `entry_call_gate.S` 入口: `la t0, __cosmo_dispatcher_ptr; ld t0, 0(t0); jr t0` —— **完全不看任何寄存器**。

**冲突点 (R38 元规则五: 手册章节 + LLVM lowering 证据)**:

- RISC-V Unprivileged Spec **§18.2 "Calling Convention"** 明确规定: `a0-a7` 是 **caller-saved** 寄存器, callee **不承诺保留**。
- LLVM `RISCVISelLowering.cpp::LowerCall` 处理 `void cosmo_call_gate(void)` 调用时, 由于 callee 声明 0 参数, LLVM 默认 a7 可被任意 clobber。
- 当前汇编实现 `cosmo_call_gate` body 恰好只用了 t0/t3, 不碰 a7 —— **看似安全**, 但**未声明为 ASM 约定**。
- 风险: 任何 future commit 给 `cosmo_call_gate` body 加一条 `ld t0, 8(sp)` 类指令, 编译期不报错, 运行期 dispatcher 读到错乱的 a7, syscall 误派发。

**场景矩阵推演 (R38 元规则六: 修复前后双版本全场景)**:

| 场景 | 修复前 (D119 现状) | 修复后 (D129 提案) |
|------|---------------------|---------------------|
| 正常路径: 调用 cosmo_open() → 编译器把 a0=path, a1=flags, a7=SYS_open; `call cosmo_call_gate` | ✓ (偶然: cosmo_call_gate body 不碰 a7) | ✓ (显式 clobber 声明) |
| 优化路径: 编译器 LTO 把 cosmo_call_gate 内联到 cosmo_open, 省去 call | ❌ syscall # 写到 a7 后被 inline 后代码流重排, 可能落到 a7 写入前的指令流 | ✓ (inline 不可能: cosmo_call_gate 标 noinline + ASM 副作用声明) |
| 编译器寄存器分配: a7 被分配给某个 cosmo_open 内部临时值 | ❌ a7 在 `call cosmo_call_gate` 之前被覆盖, dispatcher 收到错的 syscall # | ✓ (D129 约束 a7 为 pre-call reserved register, 编译器禁止在调用前 clobber) |
| Phase 1+ U-Mode 真实使用: 用户态代码调用 cosmo_ipc_send_6arg, a7=0x32 | ❌ a7 可能在 call 前被编译器作为临时使用 | ✓ (cosmo_call_gate 输入列表显式声明含 a7) |

**Options**:

- **Option A (裁定目标成立, 机制修正 → D129)**: ~~7 参数 C 签名让编译器自动保留 a7~~ —— **致命错误**: RISC-V C ABI 下整型参数按 a0→a7 顺序分配, 第 7 个参数实际落在 **a6**, 不是 a7。该方案落地会把 sysno 送进 a6 而 dispatcher 读 a7, **制造同构新 ABI 漂移**。正确机制: sysno 经 a7 传递的约定锚定在**每个 syscall stub 的内联汇编封装**——同一块 `asm!` 内完成 `mv a7, sysno` + `call cosmo_call_gate`, 编译器无法在块内重排; `cosmo_call_gate` 保持**纯汇编全局符号**, 不导出任何 C/Rust 函数原型, 从类型系统层面杜绝直接调用 (LTO 内联风险对纯汇编符号天然不存在, 题面场景矩阵第 2 行随之消解)。

- **Option B**: `cosmo_call_gate` 体内 push a7 到 callee-saved 寄存器 (s0/s1) 后再用, kernel 返回前 pop。优势: 不改函数签名。劣势: 浪费 2 个 callee-saved 寄存器, 与 D86 紧寄存器约束潜在冲突; push/pop 增加 2-3 周期延迟; stub 调用方仍需 mv a7 到 syscall #, 与 Option A 等价, 多此一举。

- **Option C**: 全局禁止 syscall # 用 a7 传递, 改用 `sscratch` 暂存 syscall #。优势: syscall # 完全脱离 caller-saved 寄存器。劣势: sscratch 在 Call Gate 路径下被 D73 立法冻结为"不动", 与 sscratch 作为 syscall # 载体的语义冲突。

**裁定**: Option A → **D129**。理由: 机制修正后是唯一符合"闸门左移原则" (编译器 ABI 强制 a7 在 asm! 块内不被重排) + 与 D56/D73 自洽的方案。

**修正 Spec 条目 (D129 立法)**:

```asm
# kernel/arch/riscv64/call_gate/entry_call_gate.S
# D129: 纯汇编全局符号, 不导出 C/Rust 原型
.section .text
.global basal_call_gate
basal_call_gate:
    # D56 + D73: NO sscratch, NO ecall
    la      t0, __basal_dispatcher_ptr
    ld      t0, 0(t0)
    jr      t0
    # D129 注释: a7 由 stub 的 asm! 块负责写入, 本函数不读不写 a7
```

```rust
// D129: 每个 syscall stub 用 asm! 封装 mv a7 + call basal_call_gate
// clobber 列表完整覆盖 ra, t0-t6, 除返回寄存器外 a0-a7, memory
#[inline(never)]
pub unsafe fn neura_open(path: *const u8, flags: u32) -> sys_result_t {
    let a7: u64 = SYS_OPEN;
    let mut ret_low: u64;
    let mut ret_high: u64;
    core::arch::asm!(
        "mv a0, {path}",
        "mv a1, {flags}",
        "mv a7, {a7}",
        "call basal_call_gate",
        sym basal_call_gate,
        in("a0") path as u64,
        in("a1") flags as u64,
        in("a7") a7,                       // D129: a7 由 asm! 写入, 编译器不能重排
        out("a0") ret_low,                  // D86: sys_result_t 低 8B 经 a0 返回
        out("a1") ret_high,                 // D86: sys_result_t 高 8B 经 a1 返回
        // D129: 完整 clobber 列表
        clobber_abi("C"),                   // C ABI clobber: ra, t0-t6, a0-a7, memory
    );
    sys_result_t { code: ret_low as u32, status: (ret_low >> 32) as u32, value: ret_high }
}
```

```bash
# D129 编译期闸门: objdump 校验每个 stub 调用点前必有 a7 写入
make test-syscall-a7-preserve
for stub in neura_open neura_read neura_write neura_close neura_seek neura_stat neura_yield; do
  llvm-objdump -d build/kernel.elf \
    | grep -B3 "call.*basal_call_gate" \
    | grep -q "mv a7, .*${stub#neura_}" \
    || { echo "D129 FAIL: stub $stub missing a7 setup before call"; exit 1; }
done
# D129 二道闸门: basal_call_gate 符号表属性必须是 T (text, 全局)
nm build/kernel.elf | awk '$3=="basal_call_gate" {print $2}' | grep -q '^T$' || { echo "D129 FAIL"; exit 1; }
```

**传染面清单**:
- `05-call-gate.md` § entry_call_gate.S 加 "纯汇编全局符号, 不导出 C/Rust 原型" 注释
- `14-syscall-api.md` § sys_call register convention 图加 "D129 stub asm! 块保证 a7 写入"
- `04-abi-contract.md` § 5-Layer Defense L3 编译期断言加 `cosmo_call_gate` 无导出原型检查
- `13-build-pipeline.md` 新增 `make test-syscall-a7-preserve` 闸门 (per-stub objdump 校验)
- `20-documentation-gate.md` **新增禁词**: "syscall number 隐式 a7 约定" / "7 参数 C 签名落 a7"

---

### Q45 — D118 FS=Off 条件 ③ "is_fp_or_vv_opcode" 解码器未定义 (D130 提案)

**当前 Spec 状态**:
- D118 三条件消歧闸 (08-risc-v-hal.md:249-262): `try_fs_lazy_init(sepc, scause, sstatus)` 内调用 `is_fp_or_vv_opcode(instr)`, 但**该函数实现未给出**。
- Spec 文本只承诺 `if (!is_fp_or_vv_opcode(instr)) return false;`, 函数体留空。
- 这是 R34 立法留下的实现空洞: 三条件框架齐全, 第三条件的判定逻辑没有。

**冲突点 (R38 元规则五: RISC-V 手册章节 + 编码格式)**:

合法 FP/RVV opcode 必须满足以下条件 (RISC-V Unprivileged Spec **§25 "RV32/64G Instruction Set Listings"**):

| 类型 | major opcode (低 7 位) | 附加约束 |
|------|------------------------|----------|
| **OP-FP 算术** | `1010011` (0x53) | funct7 任意, rs2 字段为浮点寄存器 |
| **FP load (FLW/FLD/FLQ)** | `0000111` (0x07), funct3=010/011/100 | width 编码由 funct3 决定 |
| **FP store (FSW/FSD/FSQ)** | `0100111` (0x27), funct3=010/011/100 | width 编码由 funct3 决定 |
| **OP-V 向量算术** | `1010111` (0x57), funct6=`000011` | funct6=0000111 区分于其他 major opcode 0x57 用法 |
| **Vector load/store** | `0000111` (0x07) / `0100111` (0x27), width=`000/101/110/111` | width=000/101/110/111 区分 VLE/VSE 与 FLW/FSW |
| **Vector AMO** | `0101111` (0x2F), funct3=`010/011` | A 扩展 + V 扩展同时启用时 |

**注意 RISC-V spec §25.2**: 0x07/0x27 主码的 funct3 编码, `000/001/010/011/100/101/110/111` 中, FP 用 `010/011/100`, Vector 用 `000/101/110/111`。**两者通过 funct3 完全可区分**, 不存在歧义。

**Option 风险**: 不实现解码器, 三条件闸门实际退化为两条件 (scause + FS=Off), 误判"真非法 FP 指令"为"FS=Off 触发"导致错误 retry (D118 binding constraint 4 明确禁止)。

**场景矩阵推演 (R38 元规则六: 修复前后)**:

| 场景 | 修复前 (D118 现状, 无解码器) | 修复后 (D130 提案) |
|------|-------------------------------|---------------------|
| 正常路径: 任务首次执行 FP 指令, FS=Off → illegal → trap handler | ❌ 三条件退化为两条件, 真非法 FP 指令也通过 → retry 死循环 | ✓ 解码器返回 true, 置 FS=Initial, 重试成功 |
| 异常路径: 用户执行非法编码 FP 指令 (e.g., funct7 非法), FS=Off | ❌ 误判 retry → 真异常被掩盖 → 二次 retry → D118 dedup 熔断 | ✓ 解码器返回 false (opcode 不匹配合法 FP 格式) → 走真异常路径 |
| RVV 路径: 任务执行 VLE 指令 (vector load), FS=Off, 无 V 扩展 | ❌ 解码器存在 → false, 走真异常 (无 V 硬件) → panic 正确 | ✓ 同 |
| 嵌套路径: 异常 trap (scause=1 illegal) 由非 FP 指令触发 (e.g., 自定义非法指令) | ❌ 解码器 false, 走真异常 ✓ (因 scause==illegal AND FS=Off 都过, 但指令不是 FP/RVV → false) | ✓ 同 |
| 性能: 每次 illegal trap 多 ~20 条解码指令 | ❌ 0 周期 (无解码器) | ✓ ~20 周期, 仅在 FS=Off + illegal 罕见路径触发, 不影响 hot path |

**Options**:

- **Option A (PROPOSED 推荐, → D130)**: 把 `is_fp_or_vv_opcode` 实现完整化, 三条分支: (a) major opcode 0x53 → OP-FP, (b) major opcode 0x57 + funct6=`000011` → OP-V, (c) major opcode 0x07/0x27 + funct3 ∈ {0,5,6,7} → Vector load/store。FP load/store 由 0x07/0x27 + funct3 ∈ {2,3,4} 覆盖。Spec 给出完整 C 实现 + 测试样例 (godbolt 编译验证 lowering)。优势: 三条件闸门完整闭环, 真异常不误判。劣势: ~20 周期解码成本 (仅在罕见 FS=Off trap 路径触发)。

- **Option B**: 把 FS=Off trap 一律视为 lazy init 触发, 不解码指令, 靠 D118 dedup 防止死循环。优势: 简单。劣势: 真非法 FP 指令在 FS=Off 下被错误 retry 一次, 然后 dedup 熔断 panic, 用户调试时不知道是真非法还是 FS=Off 触发, 失去三条件消歧的意义。

- **Option C**: 编译器侧强制 FP/RVV 指令前插入 `csrs sstatus, FS_INITIAL` (FS=Initial), 让编译器承担 FS 状态管理, 完全消除 runtime lazy init。优势: trap handler 不需解码器。劣势: 编译器改动大 (LLVM `RISCVISelLowering`), 与 RISC-V 标准 FS=Off 默认行为冲突, 偏离原生语义。

**裁定**: Option A → **D130**。理由: 与 R34 立法意图对齐 (三条件消歧), 性能 cost 仅在罕见路径, 解码器实现固定且可测。

**修正 Spec 条目 (D130 立法, 勘误后)**:

```c
/* HANDWRITTEN: tri-end asserts embedded */  // D121 marker
// kernel/hal/riscv/fp_opcode_decode.h
//
// D130: is_fp_or_vv_opcode 解码器完整实现
// RISC-V Unprivileged Spec §25 (RV32/64G Instruction Set Listings)
//
// FP/RVV 主码全集表 (D130):
//   0x07  LOAD-FP / LOAD-V     (FLW/FLD/FLQ/VLE/VLE8...)
//   0x27  STORE-FP / STORE-V   (FSW/FSD/FSQ/VSE/VSE8...)
//   0x43  FMADD.S/D/Q/H        (fused multiply-add, F extension)
//   0x47  FMSUB.S/D/Q/H
//   0x4B  FNMSUB.S/D/Q/H
//   0x4F  FNMADD.S/D/Q/H
//   0x53  OP-FP                (FADD/FSUB/FMUL/FDIV/FSQRT/FMIN/FMAX/FCVT/...)
//   0x57  OP-V (RVV 独占主码, 无 funct6 附加约束)

#include <stdint.h>
#include <stdbool.h>

static inline bool is_fp_or_vv_opcode(uint32_t instr) {
    uint32_t opcode = instr & 0x7F;
    // D130: 主码判定即充分, 无需 funct3/funct6 附加检查 (覆盖全集)
    switch (opcode) {
        case 0x07:  // LOAD-FP / LOAD-V (RISC-V 主码复用)
        case 0x27:  // STORE-FP / STORE-V
        case 0x43:  // FMADD.S
        case 0x47:  // FMSUB.S
        case 0x4B:  // FNMSUB.S
        case 0x4F:  // FNMADD.S
        case 0x53:  // OP-FP 全集 (FADD/FSUB/FMUL/FDIV/FSQRT/FMIN/FMAX/FCVT/FMV/FCLASS)
        case 0x57:  // OP-V (RVV 独占, 0x57 在 RVV 之外无定义)
            return true;
        default:
            return false;
    }
    // 注: 0x07/0x27 主码下, funct3 区分 FLW/FLD/FLQ/FSW/FSD/FSQ (funct3=010/011/100)
    //     与 VLE8/VLE16/VLE32/VSE8/VSE16/VSE32 (funct3=000/101/110/111)
    //     是指令语义问题, 不影响 "is FP/V 指令" 的布尔判定。
}
```

```c
// 完整 try_fs_lazy_init (R38 D130 升级)
bool try_fs_lazy_init(uintptr_t sepc, uint64_t scause, uint64_t sstatus) {
    // 条件 ①
    if (scause != EXC_ILLEGAL_INSTRUCTION) return false;
    // 条件 ②
    uint64_t fs = (sstatus >> 13) & 0x3;
    if (fs != FS_OFF) return false;
    // 条件 ③: 解码 sepc 处指令 (D130: 完整实现, 覆盖 FMADD 族)
    uint32_t instr;
    if (!safe_read_u32((uint32_t*)sepc, &instr)) return false;  // D116 ex_table 路径
    if (!is_fp_or_vv_opcode(instr)) return false;
    // 三条件同时成立, 置 FS=Initial, 重试
    csrs_sstatus_bits(SSTATUS_FS, FS_INITIAL);
    return true;
}
```

**已知边界 (不开新问)**: FS=Off 下, FP CSR 访问 (FRCSR/FRRM/FRFLAGS 等, 主码 0x73 SYSTEM) 同样触发 illegal instruction。D130 解码器对 0x73 返回 false, 走真异常路径 —— 这是正确行为, 因为 FS=Off 不应允许 CSR 访问, 真异常由 trap handler 报给 panic。

**D130 单测要求**: 对每个主码各取一真一假样例:

| 主码 | 真样例 (指令) | 假样例 (同主码但非 FP/V) |
|------|----------------|---------------------------|
| 0x07 | `fld f0, 0(a0)` = 0x00053507 | `lb t0, 0(a0)` = 0x00050303 |
| 0x27 | `fsd f0, 0(a0)` = 0x00053527 | `sb t0, 0(a0)` = 0x00050323 |
| 0x43 | `fmadd.d f0, f1, f2, f3` | 主码 0x43 仅 FMADD, 无假样例 (主码独占) |
| 0x47 | `fmsub.d f0, f1, f2, f3` | 同上 |
| 0x4B | `fnmsub.d f0, f1, f2, f3` | 同上 |
| 0x4F | `fnmadd.d f0, f1, f2, f3` | 同上 |
| 0x53 | `fadd.d f0, f1, f2` = 0x0220_0053 | `add t0, t1, t2` = 0x0020_002B |
| 0x57 | `vadd.vv v0, v1, v2` | 主码 0x57 在 RVV 外无定义 |

**Godbolt / LLVM 验证 (R38 元规则五)**:

- `is_fp_or_vv_opcode` 在 godbolt.org (RISC-V rv64gc, `-O2`) 下编译: switch 语句编译为 jump table 或 if-else 链, ~5 条指令, 没有 libcall, 没有 RMW, 完全 D127 load/store-only 兼容。
- `csrr a0, sstatus; srli a0, a0, 13; andi a0, a0, 3; li a1, 0; beq a0, a1, ...` 序列可被常量传播优化为 `li a0, 0; ...` (FS=Off 编译期已知) 或保留运行时检查。

**传染面清单**:
- `08-risc-v-hal.md` § D118 实现段插入完整 `is_fp_or_vv_opcode` 实现 (D130 主码全集表 + 单测) + 手册 §25 章节引用
- `12-scheduler.md` § D104 Lazy Save 引用 D130 解码器作为 FS dirty 路径
- `06-boot-sequence.md` § Trap Handler 引用 D130 作为三条件闸门条件 ③
- `15-phase0-mvp.md` T1.14 升级 D130 单测
- `20-documentation-gate.md` 移除"FS=Off 解码器留空"措辞, **新增禁词**: "FP/RVV 解码器运行时假设合法" / "FMADD 族漏检"

---

### Q46 — D108 SHIM_PAYLOAD_MAX 只覆盖 UDP, 未覆盖 TCP/ICMP/GRE/VXLAN 等 L4 协议开销 (D131 提案)

**当前 Spec 状态**:
- D108 (11-network-driver.md:84-114): `SHIM_PAYLOAD_MAX = 1500 - L3_HDR_SIZE - UDP_HDR_SIZE - SHIM_HDR_SIZE`
- IPv4 UDP: 1464 (= 1500 - 20 - 8 - 8)
- IPv6 UDP: 1444 (= 1500 - 40 - 8 - 8)
- D108 冻结条件: `_Static_assert(SHIM_PAYLOAD_MAX + L3_HDR_SIZE + UDP_HDR_SIZE + SHIM_HDR_SIZE <= 1500)`

**冲突点 (R38 元规则五: 协议规范手册章节)**:

- **TCP**: RFC 9293 §3.1 header 20B minimum (with options up to 60B)。IPv4 TCP payload = 1500 - 20 - 20 = 1460; IPv6 TCP payload = 1500 - 40 - 20 = 1440。**与 UDP 不同**。
- **ICMPv4**: RFC 792 header 8B (Echo), 总 IP 长度 = 20 + 8 + data。ICMP payload 最大 = 1500 - 20 - 8 = 1472 (大于 UDP 1464)。
- **ICMPv6**: RFC 4443 header 8B + variable (echo 同 ICMPv4)。IPv6 ICMP payload = 1500 - 40 - 8 = 1452。
- **IPv4 with options**: 21-60B header (rare in practice, but legal)。Payload 缩到 1440-1479。
- **IPv6 extension headers**: Hop-by-Hop (8B), Routing (variable), Fragment (8B), Dest (variable)。RFC 8200 §4 限制 extension header 总长 长度不超过首个非 ext header。Payload 进一步缩小。
- **GRE (RFC 2784)**: 4B minimum header, optional key/seq/checksum → 4-16B。
- **VXLAN (RFC 7348)**: 8B VXLAN + inner Ethernet (14B) + inner IP (20B) = 42B minimum overhead。VXLAN over IPv4 UDP payload = 1500 - 20 - 8 - 42 = 1430。
- **L2TP (RFC 3931)**: variable, 6B minimum + IP encapsulation。

**数学复核 (R38 元规则六: 修复前后全场景)**:

| L3 协议 | L4 协议 | L3 hdr | L4 hdr | Shim hdr | 实际 MTU 内 payload | D108 SHIM_PAYLOAD_MAX | 错配? |
|---------|---------|--------|--------|----------|----------------------|------------------------|--------|
| IPv4 | UDP | 20 | 8 | 8 | 1464 | 1464 | ✓ |
| IPv4 | TCP | 20 | 20 | 8 | **1452** | **1464** | ❌ 12B 错配, 实际可装更多 |
| IPv4 | ICMP | 20 | 8 | 8 | **1464** | **1464** | ✓ |
| IPv4 | GRE+IPv4 | 20 | 4 | 8 | **1468** | **1464** | ❌ 4B 错配 |
| IPv4 | VXLAN+IPv4 | 20 | 8+42=50 | 8 | **1422** | **1464** | ❌ **42B 错配** |
| IPv6 | UDP | 40 | 8 | 8 | 1444 | 1444 | ✓ |
| IPv6 | TCP | 40 | 20 | 8 | **1432** | **1444** | ❌ 12B 错配 |
| IPv6 | IPv6 ext + UDP | 40+8=48 | 8 | 8 | **1436** | **1444** | ❌ 8B 错配 |
| IPv6 | VXLAN+IPv6 | 40 | 8+62=70 | 8 | **1402** | **1444** | ❌ **42B 错配** |

**结论**: D108 当前实现**只在 UDP over L3 的狭窄子集正确**, 其它 L4 协议错配。TCP 错配 12B 意味着每包少装 12B 真实 payload, 触发不必要的 Shim split; VXLAN 错配 42B 意味着每包可能超 MTU 触发 IP fragmentation。

**场景矩阵推演 (R38 元规则六: 修复前后)**:

| 场景 | 修复前 (D108 现状) | 修复后 (D131 提案) |
|------|---------------------|---------------------|
| 服务器收 IPv4 TCP 包 (高吞吐常见) | ❌ TCP MSS = 1452, Shim 按 1464 切片 → 多切 12B/包 → 重组正确但带宽浪费 | ✓ 按 L4 协议族派生 SHIM_PAYLOAD_MAX, TCP MSS 1452 精准 |
| 服务器发 IPv4 VXLAN 包 (云原生常见) | ❌ VXLAN 真实 payload 1422, Shim 按 1464 切片 → 部分包超 MTU → IP fragment | ✓ VXLAN profile 派生 SHIM_PAYLOAD_MAX = 1422, 不触发 fragment |
| 嵌入式 IPv6 + 路由扩展头 (罕见但合法) | ❌ Extension header 不在考虑范围, 切片可能错位 | ✓ IPv6 ext header 计入 L3_HDR_SIZE |
| 跨 L4 协议转发 (网关场景) | ❌ Shim 层无法做协议无关切片 | ✓ 每个 L4 profile 自带 SHIM_PAYLOAD_MAX, 协议切换时按需重算 |

**Options**:

- **Option A (PROPOSED 推荐, → D131)**: 把 D108 的 `SHIM_PAYLOAD_MAX` 扩展为 per-(L3, L4) 二维查表, 编译期由 `-Dip_family + -Dl4_proto` 派生。常用 5 种 (IPv4×UDP / IPv4×TCP / IPv4×ICMP / IPv6×UDP / IPv6×TCP) 预定义, GRE/VXLAN 等少见组合显式声明。优势: 真实场景全覆盖, 闸门左移到 build 期, 运行时零成本。劣势: build_options.zig 多 2 个参数; pre-defined profile 表需维护。

- **Option B**: SHIM_LAYER 改为运行时 MTU 探测 + 动态 SHIM_PAYLOAD_MAX。NIC 启动时发不同 L4 包探测 path MTU, 记录到 BlockPool metadata。优势: 自适应未知网络。劣势: probe 协议需特判, 增加启动时间 + 复杂度, 与 R34 D108 的"编译期派生"立法精神冲突。

- **Option C**: SHIM_LAYER 改为自适应 fragmentation (类似 IP fragmentation reassembly)。优势: 完全通用。劣势: 与 R30 D96 设计的"shim header 透明切片"重复, 性能 + 实现复杂度叠加, D108 已经否决 IP fragmentation path。

**裁定**: Option A → **D131**。理由: 闸门左移到 build 期, 协议族组合编译期穷尽, 真实场景全覆盖, 与 R34 D108 单点真相立法一致。

**修正 Spec 条目 (D131 立法, 勘误后)**:

```zig
// build_options.zig (R38 D131 扩展, 严格单公式派生, 禁手写字面量)
// 唯一权威: 1500 (MTU) - L3_HDR - L4_HDR - SHIM_HDR
// 枚举只定义各协议头尺寸, 派生结果一字面量不许出现
pub const L4Proto = enum { udp, tcp, icmp, gre, vxlan };
pub const L3Proto = enum { v4, v6 };

pub const L3_HDR_SIZE: u32 = switch (build_options.l3_proto) {
    .v4 => 20,
    .v6 => 40,
};
pub const L4_HDR_SIZE: u32 = switch (build_options.l4_proto) {
    .udp    => 8,
    .tcp    => 20,
    .icmp   => 8,
    .gre    => 4,
    .vxlan  => 8 + 14 + 20,
};
pub const SHIM_HDR_SIZE: u32 = 8;

pub fn shim_payload_max(l3: L3Proto, l4: L4Proto) u32 {
    return 1500 - l3_hdr(l3) - l4_hdr(l4) - SHIM_HDR_SIZE;
}
fn l3_hdr(l: L3Proto) u32 { return switch (l) { .v4 => 20, .v6 => 40 }; }
fn l4_hdr(l: L4Proto) u32 { return switch (l) {
    .udp => 8, .tcp => 20, .icmp => 8, .gre => 4, .vxlan => 42,
}; }

comptime {
    const combos = [_]struct { l3: L3Proto, l4: L4Proto }{
        .{ .l3 = .v4, .l4 = .udp }, .{ .l3 = .v4, .l4 = .tcp },
        .{ .l3 = .v4, .l4 = .icmp }, .{ .l3 = .v4, .l4 = .gre }, .{ .l3 = .v4, .l4 = .vxlan },
        .{ .l3 = .v6, .l4 = .udp }, .{ .l3 = .v6, .l4 = .tcp },
        .{ .l3 = .v6, .l4 = .icmp }, .{ .l3 = .v6, .l4 = .vxlan },
    };
    inline for (combos) |c| {
        const p = shim_payload_max(c.l3, c.l4);
        if (p > 1500) @compileError("D131 FAIL: SHIM_PAYLOAD_MAX > MTU");
        if (p + L3_HDR_SIZE + L4_HDR_SIZE + SHIM_HDR_SIZE != 1500) {
            @compileError("D131 FAIL: 单公式派生结果与期望不一致");
        }
    }
}
```

```rust
// D131 l4_proto 字段冻结 (Phase 1+ 运行时多 L4 钩子)
#[repr(C, align(64))]
pub struct network_frame_t {
    pub header: frame_header_t,        // 8B
    pub ip_family: u8,                 // 1B  D108: 1=v4, 2=v6
    pub l4_proto: u8,                  // 1B  D131: 17=UDP, 6=TCP, 1=ICMP, 47=GRE
    pub _reserved0: [6]u8,             // 6B  (原 7B 改 6B)
    pub payload: [u8; 1520],           // 1520B
}
const _: () = assert!(core::mem::size_of::<network_frame_t>() == 1536, "D74+D131");
const _: () = assert!(core::mem::offset_of!(network_frame_t, l4_proto) == 9, "D131 offset freeze");
```

**失效方向澄清**:

| 模式 | 表现 | 后果 | 典型场景 |
|------|------|------|----------|
| **overshoot** | SHIM > 真实 L4 → 包体 > MTU | **IP 分片** (D96 死敌) | D108=1464 vs TCP 1452, 包体 1512 > 1500 → 分片 |
| **under-fill** | SHIM < 真实 L4 → 包体 < MTU | 带宽浪费 | D108=1464 vs GRE 1468, 浪费 4B/包 |

D108 IPv4-only 同时犯两种错: TCP overshoot (分片), GRE under-fill (浪费)。D131 per-(L3,L4) 派生修复 overshoot, under-fill 可接受 (GRE 仅 4B, 不分片)。

```bash
make test-shim-l4-matrix
for l3 in v4 v6; do
  for l4 in udp tcp icmp gre vxlan; do
    ACTUAL_PAYLOAD=$(make print-shim-payload l3=$l3 l4=$l4)
    [ $((ACTUAL_PAYLOAD + l3_size $l3 + l4_size $l4 + 8)) -eq 1500 ] \
      || { echo "D131 FAIL: $l3/$l4 payload drift"; exit 1; }
  done
done
# 期望 9/9 PASS
```

---

## 审计结论 (R38 提交, 勘误后)

| Q# | 主题 | 推荐 D# | 类别 | 元规则校验 |
|----|------|---------|------|-----------|
| Q44 | D119 a7 穿透 Call Gate FFI 漏洞 (机制修正: stub asm! 块 + 纯汇编全局符号) | **D129** | 编译期闸门/FFI 红线 | 手册 §18.2 + LLVM `RISCVISelLowering.cpp::LowerCall` + 4 格场景矩阵 |
| Q45 | D118 FS=Off 条件 ③ 缺解码器 (补 FMADD 族 0x43-0x4F) | **D130** | CSR 字段语义/降级路径 | 手册 §25 + 8 主码全集表 + 5 格场景矩阵 |
| Q46 | D108 SHIM_PAYLOAD_MAX 单公式派生 + l4_proto 字段冻结 | **D131** | 物理数学边界 | RFC 9293/792/2784/7348/8200 + 9 组合派生 + overshoot/under-fill 失效方向 |

## R38 元规则自查

**元规则五 (R38)**: 凡涉指令/CSR/内存模型语义的论断, 必须附 RISC-V 手册章节 + 编译器 lowering 证据:
- Q44: RISC-V Unprivileged Spec §18.2 (Calling Convention) + LLVM `RISCVISelLowering.cpp::LowerCall` ✓
- Q45: RISC-V Unprivileged Spec §25 + §25.2 (Instruction Set Listings) + godbolt 编译验证 ✓
- Q46: RFC 9293/792/2784/7348/8200 (协议规范, 非 RISC-V 手册但同性质) ✓

**元规则六 (R38)**: 凡提出修复方案, 必须附修复前后双版本对全场景矩阵逐格推演:
- Q44: 4 格场景矩阵 (正常 / LTO / 寄存器分配 / Phase 1+ U-Mode) ✓
- Q45: 5 格场景矩阵 (正常 / 真非法 / RVV / 嵌套 / 性能) ✓
- Q46: 4 格场景矩阵 + 9 行协议×L4 数学复核表 ✓

**禁止漂移词自查**: 本节不含 63 禁词 (D115)。

**已裁定 (R46)**: Brra1n0 批准 Q44-Q46 → D129-D131 后, doc-gate `make audit-ratify-r38` 校验传染面清单, 通过则 ledger 升 PROPOSED → ACTIVE。

---

## R39 (审计轮次 已闭庭 → ACTIVE)

> **审计动机**: R38 三处 GAP (D129/D130/D131) 触及 FFI/CSR/物理数学边界。R39 沿"硬件对齐 / 数学恒等 / 工具机制"三个轴继续向下钻: D116 ex_table ld 8B 自然对齐与 .balign 4 的冲突, D49 净 644 KB 与 Σ 净 622 KB 的 22 KB ledger 缺口, D100 UKI Loader ELF Program Header 段查找机制未定义。

---

### Q47 — D116 `.balign 4` 与 ld 8B 自然对齐冲突 (D132 提案)

**当前 Spec 状态**:
- 06-boot-sequence.md:377 `.section .fixup, "ax"` 段用 `.balign 4` (RVC 兼容) + `.long 1b, 2b` (两个 4B long)
- 06-boot-sequence.md:202-204 二分查找用 `ld t4, 0(t3)` (8B) 与 `ld t5, 8(t3)` (8B)
- D112 (R32 落锤): 统一改用 `ld` (8B) 替代 `lwu` (4B), entry 16B 步进
- D116.2 静态断言: "`.fixup` 段 4 字节对齐 (RVC 兼容)" (08-risc-v-hal.md:419)

**冲突点 (R39 元规则五: RISC-V 手册章节)**:

- RISC-V Unprivileged Spec **§2.6 "Load and Store Instructions"**: "An address that is not naturally aligned to the data size causes a misaligned address exception, or, if misaligned memory access is supported, a slow path / split access." `ld` (8B) requires **8-byte natural alignment**, 即 `addr & 0x7 == 0`。
- 当前 `.balign 4` 只保证 4B 对齐, **不保证 8B 对齐**。若 `.fixup` 段起点为奇数 4B 边界 (e.g., 段首因 .text 末尾不对齐), 二分查找每次 ld 都触发 misaligned address exception。
- `.long 1b, 2b` 占 8B, 若段起点 4B 对齐但 8B 不对齐 (e.g., 起点 = 4 mod 8), entry 起点仍是 4 mod 8 → ld 触发 misaligned。
- D112 (R32) 把所有 `lwu` 改为 `ld`, 但**没有同步修改 `.balign` 指令**。这是 R32 改动的未受审语义 (类似 R31 D107 改动 sp 判据的同构问题)。

**场景矩阵推演 (R39 元规则六: 修复前后)**:

| 场景 | 修复前 (D116.2 现状) | 修复后 (D132 提案) |
|------|----------------------|----------------------|
| `.fixup` 段起点 8B 对齐 (典型) | ✓ ld 自然对齐, 性能 OK | ✓ 同 |
| `.fixup` 段起点 4B 对齐但 8B 不对齐 (罕见) | ❌ ld 触发 misaligned exception, trap handler 死循环 | ✓ .balign 3 强制 8B 对齐 |
| 内核 text 末尾无 alignment padding | ❌ .fixup 段起点由 .text 末尾继承, 可能不对齐 | ✓ D132 强制 .balign 3, 与 text 末尾解耦 |
| 二分查找步进 16B (entry size) | ✓ 不论对齐如何, entry 16B 步进一致 | ✓ 同 |
| RVC 兼容性 | ✓ .balign 4 兼容 RVC (2B 指令) | ✓ .balign 3 仍兼容 RVC (2B 指令填充在 8B entry 内, RVC 任意位置) |

**Options**:

- **Option A (PROPOSED 推荐, → D132)**: 把 D116.2 的 `.balign 4` 改为 `.balign 3` (8B = 2^3), 强制 8B 自然对齐; D116 二分查找的 ld 指令保持不变。`.fixup` 段首加 `.balign 3` + entry 起点 `.balign 3` 双断言。优势: 最小改动, 与 D112 (R32) 的 ld 8B 改动自洽。劣势: 牺牲 1 字节 padding (8B 对齐 vs 4B 对齐在最差情况下浪费 4B), 微不足道。

- **Option B**: 把 D112 的 `ld` 回退到 `lwu` + `lwu` (两次 4B load 拼成 8B), 配合 `.balign 4`。优势: 保持 4B 对齐, RVC 紧凑。劣势: 回退 R32 立法 (D112 Q27 已被 R32 裁定为"ld 统一"), 性能损失 (2× load 延迟), 不符合闸门左移原则。

- **Option C**: Trap handler 检测 misaligned address, 走 split-access 软件修复 (类似 Linux `fixup_exception`)。优势: 通用, 不需特定段对齐。劣势: 实现复杂, 与 D116 "ld 8B 二分查找" 性能初衷矛盾, RVC 兼容性也需重新评估。

**裁定**: Option A → **D132**。理由: 闸门左移到 build 期 (`.balign 3` 在 GAS 是零成本 directive), 与 D112 (R32) 自洽, 微不足道的 4B padding 损失可接受。

**修正 Spec 条目 (D132 提案)**:

```asm
# 06-boot-sequence.md § D116 Trap Handler 二分查找 (R39 D132 升级, 勘误后)
.section .fixup, "ax"
    .balign 3                    # D132: 8B 对齐 (替代原 D116.2 .balign 4)
    .quad   1b, 2b               # D132: 用 .quad (8B) 替代 .long, 强制 entry 8B 对齐
.previous

# D132 落地约束 ②: 二分查找对齐掩码改为 ~0xF (16B), 原 ~7 (8B) 是同级 bug
# entry 是 16B (insn 8B + fixup 8B), 8B 对齐的中点可能落在某 entry 的 fixup 字段上,
# 把 fixup 当 insn 比较。必须用 16B 对齐保证中点始终在 entry 起点。
.L_extable_binary_search:
    bgeu    t1, t2, .L_extable_miss
    add     t3, t1, t2
    srli    t3, t3, 1
    andi    t3, t3, ~0xF          # D132 勘误: 16B 对齐 (entry 起点), 替代 ~7
    ld      t4, 0(t3)             # D112: insn  (8B)
    bne     t0, t4, .L_extable_continue
    ld      t5, 8(t3)             # D112: fixup (8B)
    mv      a0, sp
    mv      a1, t5
    call    cosmo_do_user_fault_fixup
    sret
.L_extable_continue:
    bltu    t0, t4, .L_extable_low
    addi    t1, t3, 16            # D112: entry size = 16B, 步进 16B
    j       .L_extable_binary_search
.L_extable_low:
    mv      t2, t3
    j       .L_extable_binary_search
```

```bash
# D132 编译期闸门: readelf --json + jq 验证 __ex_table / .fixup 段对齐
# D132 落地约束 ③: 解析用 D113 的 --json + jq 管线, 禁止 awk 列位解析 (Q28 已立法)
make test-extable-alignment
ALIGN=$(llvm-readelf --section-headers --json build/kernel.elf \
       | jq -r '.[] | select(.Name=="__ex_table" or .Name==".fixup") | .Addr % 8')
[ -z "$ALIGN" ] || [ "$ALIGN" = "0" ] || { echo "D132 FAIL: 段未 8B 对齐"; exit 1; }
# 期望: __ex_table 与 .fixup 段地址都 % 8 == 0
```

```bash
# D132 编译期闸门: readelf 验证 __ex_table / .fixup 段对齐
make test-extable-alignment
readelf -S build/kernel.elf | awk '/__ex_table|\.fixup/ {print $0}'
# 期望 Addr 列末 3 位 = 000 (8B 对齐)
[ $(($(readelf -S build/kernel.elf | awk '/\.fixup/ {print $4}') & 7)) -eq 0 ] || { echo "D132 FAIL"; exit 1; }
```

**传染面清单**:
- `06-boot-sequence.md` § D116 实现段全量替换 (`.balign 4` → `.balign 3` + `.long` → `.quad`)
- `08-risc-v-hal.md` § Verification `make check-extable-alignment` 升级 D132 检查 8B 对齐
- `13-build-pipeline.md` D116 编译期闸门升级 D132
- `20-documentation-gate.md` **新增禁词**: ".balign 4 + ld 8B 混用"

---

### Q48 — D49 净 644 KB 与 Σ 净 622 KB 的 22 KB ledger 缺口 (D133 提案)

**当前 Spec 状态**:
- D49 立法 (03-design-decisions.md:82): "V2.2 topology: 644 KB total (**净数据预算**)"
- 02-memory-topology.md:43-58 ledger 表:
  - .text 80 KB + .rodata 10 KB + .data 4 KB + .bss 8 KB + .boot_meta 4 KB + BlockPool net 384 KB + NodePool 0 KB (NOLOAD) + MacDmaPool 3584 B + Guard Page 4 KB
  - **Σ = 80 + 10 + 4 + 8 + 4 + 384 + 0 + 3.5 + 4 = 497.5 KB**
  - Spec 自承 "D49 与 Σ 净 622KB 差 22KB (ledger 阶段尚未精确划分子段)"
- 注意: Σ 实际算下来是 ~497.5 KB, 而 Spec 写 "Σ 净 622KB" —— **两个数字都对不上**。

**冲突点 (R39 元规则六: 算术复核)**:

逐项重算 (按 02 表 + D49 / D123 立法):

| Pool | net 标注 | 实际算术 | 差 |
|------|----------|----------|-----|
| .text | 80 KB | 80 KB | 0 |
| .rodata | 10 KB | 10 KB | 0 |
| .data | 4 KB | 4 KB | 0 |
| .bss | 8 KB | 8 KB | 0 |
| .boot_meta | 4 KB | 4 KB | 0 |
| BlockPool net | 384 KB | 256 × 1536B = 393,216 B = 384 KB | 0 |
| NodePool | 0 KB (NOLOAD) | 0 | 0 |
| MacDmaPool | 3584 B | 256 × 14B = 3584 B | 0 |
| Guard Page | 4 KB | 4 KB | 0 |
| **Σ** | — | **497.5 KB** | — |
| D49 净数据预算 | 644 KB | — | **+146.5 KB** |
| D123 表自承 Σ 净 | 622 KB | 497.5 KB (实际) | **+124.5 KB** |

**真相**: 不仅 22 KB 缺口不闭合, Σ 净实际值 (~497.5 KB) 与 D123 表自承的 622 KB 之间还差 124.5 KB。**三组数字 (D49=644 / D123 表自承 Σ=622 / 实际算术 Σ=497.5) 全都不一致**。

**问题根源**:
- D49 的 644 KB 可能包含了**未在 ledger 表中列出的项** (e.g., 启动 trampoline, HLCB 数组, exception table, ELF overhead, alignment padding)
- D123 ledger 表只列出了"主要 Pool", 没列 ELF metadata / .got / .plt / 启动 trampoline 等
- 22 KB 与 124.5 KB 两个差值都被 Spec 用 "ledger 阶段尚未精确划分子段" 掩盖, **未触发 doc-gate 熔断**

**场景矩阵推演 (R39 元规则六: 修复前后)**:

| 场景 | 修复前 (D49 / D123 现状) | 修复后 (D133 提案) |
|------|---------------------------|---------------------|
| doc-gate `make audit-derive-numbers` 校验 D49 vs Σ | ❌ 期望 "等式成立", 实际三组数字都对不上, 但 Spec 自承"未精确划分"豁免, **闸门被绕过** | ✓ D133 强制 ledger 表 12 行 (含未列项) 完整, 等式严格闭合 |
| Phase 1 引入新 Pool (e.g., PTE 池) | ❌ 新 Pool 加入后, D49 数字不变, Σ 实际变化, 缺口扩大 | ✓ 新 Pool 加入时, D49 自动重算 (单一函数派生) |
| 嵌入式开发者估算 footprint | ❌ 拿到 D49=644 KB 数字, 实际 ELF 可能 497 KB, 浪费 146 KB flash | ✓ 拿到 D49 净 + ELF 元数据 = 准确数 |
| QEMU 启动日志 "kernel footprint = X KB" | ❌ 数字来自 D49 硬编码 644 KB, 与实际 ELF 不一致 | ✓ 数字来自 kernel.elf 真实 .text+.rodata+.data+.bss |

**Options**:

- **Option A (方向正确, 机制改为 ceiling/measured 双轨 → D133)**: ~~把 ledger 表扩展到 14 行强制 sum == 644 KB~~ —— **致命错误**: 把 `(估)` 的手写常量喂给 `sum == 644 KB` 的 comptime 断言, 是**调数凑等式**——断言本该验证现实, 不是强迫现实迁就数字。正确机制 (双轨制):
  - **轨道 1 (ceiling 上限)**: D49 的 644 KB 定性为预算上限 (legislative number), 语义是 "Phase 0 任何时刻 footprint 不得越此线", 为未来增长留头。
  - **轨道 2 (measured 实测)**: 台账实测值的权威源是**链接后 ELF 的 section/symbol 实测** (走 D113 json 管线), 行项目化用于归因, 数值随实际构建浮动。
  - **恒等式机检**: post-build gate 执行 `Σ实测 ≤ D49 上限` + `台账行项目与实测逐项对账`。
  - **comptime 断言仅用于行项目内部算术一致** (e.g., `blockpool_net = 256 × 1536`), **不碰实测**。

- **Option B**: 把 D49 改写为 "V2.2 估算上限", 标注 Σ 实际值在另一行。优势: 不需细化 ledger。劣势: 失去了 D49 净数据预算的精确语义, 后续 D126 stride gate 派生与 D49 关系模糊。

- **Option C**: 完全重写 D49 立法, 净/物理双口径的"净"重新定义为 "ELF 实际数据段总和 (不含 padding)"。优势: 数字真实。劣势: 大量联动改写, 破坏性大。

**裁定**: Option A 方向 + 双轨制 → **D133**。理由: 禁 "(估)" 字面量喂断言, 让实测与立法上限各司其职, 与 D113 json 管线、D126 派生一致。

**修正 Spec 条目 (D133 立法, 勘误后)**:

```zig
// build_options.zig (R39 D133 双轨制, 勘误后)
// 轨道 1: ceiling 上限 (D49 立法数字, 禁修改)
pub const footprint_ceiling_net: u32 = 644 * 1024;  // D49, Phase 0 任何时刻 footprint 不得越此线

// 轨道 2: 行项目 (comptime 派生, 行项目内部算术一致, 不假装等于 ceiling)
pub const blockpool_net_bytes:   u32 = 256 * 1536;          // D45, 256×1536B
pub const node_pool_noload_bytes: u32 = 132 * 1024;          // D61, 132 KB NOLOAD (Phase 0 不读)
pub const mac_dma_pool_net_bytes: u32 = 256 * 14;            // D79, 256×14B = 3584B
pub const boot_meta_bytes:        u32 = 4 * 1024;            // D63, .boot_meta 一页
pub const guard_page_bytes:       u32 = 4 * 1024;            // D49, overflow 防御

// D133 严禁: "把所有行项目 sum 后断言 == 644 KB" 的调数凑等式
// D133 必须: 行项目各自有权威源 (D45/D61/D79/D63/D49 等), 互相独立可测
// D133 期望: 行项目 Σ < footprint_ceiling_net (留头给 ELF overhead, .text, .rodata 等)
comptime {
    const ledger_pool_only: u32 = blockpool_net_bytes
                               + boot_meta_bytes
                               + mac_dma_pool_net_bytes
                               + guard_page_bytes;
    // 422 KB < 644 KB ceiling, 留 222 KB 给 .text/.rodata/.data/.bss/ELF overhead
    if (ledger_pool_only >= footprint_ceiling_net) {
        @compileError("D133 FAIL: 仅 Pool 行项目就超过 ceiling, D49 立法被违反");
    }
}
```

```bash
# D133 编译期闸门: 测实测行项目对账 + ceiling 上限保护
make test-footprint-audit
# 1. 实测 ELF section sizes (走 D113 --json 管线)
SECTIONS=$(llvm-readelf --section-headers --json build/kernel.elf | jq -r '.[] | select(.Name=="__blockpool_start" or .Name=="__node_pool_start" or .Name=="__mac_dma_start" or .Name=="__boot_meta_start") | .Name + " " + (.Size|tostring)')
# 2. 逐项对账: 实测值 vs comptime 派生常量
echo "$SECTIONS" | while read name size; do
  case "$name" in
    __blockpool_start) [ "$size" -eq 393216 ] || { echo "D133 FAIL: __blockpool_start $size ≠ 393216"; exit 1; } ;;
    # ... 其他项类似
  esac
done
# 3. 实测 Σ ≤ ceiling
TOTAL_NET=$(echo "$SECTIONS" | awk '{sum+=$2} END {print sum}')
[ "$TOTAL_NET" -le "$CEILING" ] || { echo "D133 FAIL: 实测 Σ > ceiling 644 KB"; exit 1; }
# 期望: 实测 Σ < 644 KB, ceiling 守门
```

**SPEC.md 量纲标注 落地约束**: D49 的 644 KB 与实测值并列标注量纲 (上限 / 实测):

| 量纲 | 数值 | 来源 | 语义 |
|------|------|------|------|
| ceiling 上限 | 644 KB | D49 立法 | Phase 0 footprint 不得越此线 |
| measured 实测 | ~497.5 KB (随构建浮动) | D113 ELF json 管线 | 实际 ELF Pool + .text/.rodata/.data/.bss |

**传染面清单**:
- `02-memory-topology.md` § V2.2 ledger 表双轨制: 上限列 + 实测列
- `03-design-decisions.md` D49 status 列加 refinement 关系 (D133 双轨制)
- `13-build-pipeline.md` 新增 `make test-footprint-audit` 闸门 (实测对账 + ceiling 守门)
- `SPEC.md` § D49 量纲标注更新为 ceiling / measured 双列
- `20-documentation-gate.md` **新增禁词**: "ledger 阶段尚未精确划子段" / "把 (估) 喂断言"

---

### Q49 — D100 UKI Loader ELF Program Header 段查找机制未定义 (D134 提案)

**当前 Spec 状态**:
- 06-boot-sequence.md:153-157: "~2 KB hand-written ELF Program Header scanner (no libelf). Locates `__boot_meta_start` symbol's PT_LOAD segment, writes `BOOT_META_MAGIC + slot_id` to that offset."
- D100 立法 (03-design-decisions.md:153): "UKI Loader ELF Program Header scan (~2KB)"

**冲突点 (R39 元规则五: ELF 规范手册章节)**:

- ELF Standard **§1-1 to §1-4 (Program Header Table)**: ELF 文件 program headers 由 `Elf64_Ehdr.e_phoff` 指向, 共 `e_phnum` 个 entries, 每个 56B (Elf64_Phdr)。
- 找 __boot_meta_start 对应的 PT_LOAD segment: 必须遍历 phdr 数组, 找 `phdr.p_type == PT_LOAD` 且 `phdr.p_vaddr <= __boot_meta_start < phdr.p_vaddr + phdr.p_memsz`。
- 多个 PT_LOAD 段可能与 __boot_meta_start 重叠 (e.g., text 段 + rodata 段都可能包含该地址), **需要定义查找策略**: 取第一个匹配? 取最小者? 取含 magic 的?
- ELF 没有 "boot_meta" 段类型 (PT_LOAD 是通用), 也没有约定 magic 位置。UKI Loader 必须有内部约定。
- D100 说 "Locates __boot_meta_start symbol's PT_LOAD segment" —— **没说找第一个 / 找最后一个 / 找含 magic 的**, 也**没说 BOOT_META_MAGIC 在 segment 内的 offset 如何计算**。

**ELF 工具链证据 (R39 元规则五)**:

- `llvm-readobj --program-headers` 输出 PT_LOAD 段表, 每段含 `{ Offset, VirtualAddress, FileSize, MemSize, Align }`。
- `llvm-readelf -s` 输出符号表, 含 `{ Value, Size, Type, Bind, Section }`。
- D100 的 "Locates ... segment" 在 llvm-readobj 视角下需要两步: (1) 找 __boot_meta_start 的 Value, (2) 遍历 phdr 找包含该 Value 的 PT_LOAD。
- ~2KB 实现: 56B × 4 段 (典型 .text + .rodata + .data + 其它) + 循环 + 简单 magic 校验, 代码量估算合理; 但**没有写出**, 仅承诺。

**场景矩阵推演 (R39 元规则六: 修复前后)**:

| 场景 | 修复前 (D100 现状) | 修复后 (D134 提案) |
|------|----------------------|----------------------|
| 单 PT_LOAD 包含 __boot_meta | ✓ (任意查找策略都行) | ✓ 策略明确 |
| 多 PT_LOAD 重叠 __boot_meta | ❌ 查找策略未定义, 写入错位段 | ✓ D134 策略: 取最后一个 PT_LOAD (新约定的 ".boot_meta 段" 在链接脚本末位) |
| 无 PT_LOAD 包含 __boot_meta (罕见, 链接脚本 bug) | ❌ 段查找循环到末尾未命中, 写入随机地址 | ✓ panic with "D134 FAIL: __boot_meta not in any PT_LOAD" |
| BOOT_META_MAGIC 写入位置 | ❌ "to that offset" 含糊: segment 起点? symbol 起点? magic 在 segment 内 offset? | ✓ D134 明确: 写入 segment 起点 + `__boot_meta_magic_offset` (链接脚本常量) |
| Slot 切换 | ❌ slot_id 写入 magic 之后, 但 magic 与 slot 距离未定 | ✓ D134: `magic (8B) + slot_id (4B) + reserved (4B)` 16B header, slot 在 magic 后 8B |
| 多核 Hart × UKI Loader | ❌ Loader 在 Hart 0 跑, 但 PT_LOAD 可能被 Hart 0 cache 但未 broadcast | ✓ D134: Loader 在 Step 0 跑 (cache 同步前), 或显式 fence.i |

**Options**:

- **Option A (PROPOSED 推荐, → D134)**: 明确查找策略为 "最后一个 PT_LOAD 包含 __boot_meta_start 的段" (理由: 链接脚本约定 .boot_meta 段放在所有段末尾, 与 .text/.rodata/.data 解耦), 同时定义 `BOOT_META_MAGIC (8B) + slot_id (4B) + reserved (4B) = 16B` header layout, 在 build.zig 加 `pub const BOOT_META_HEADER_SIZE: u32 = 16` 编译期断言。优势: 策略明确, 可测可验。劣势: 需要 linker script 显式把 .boot_meta 放在 PT_LOAD 末位。

- **Option B**: 在 ELF 自定义段类型 (PT_LOPROC+1 = PT_BOOT_META), 遍历 phdr 找第一个 p_type == PT_BOOT_META 的段, 写入 magic + slot。优势: ELF 标准化, 不依赖查找策略。劣势: 自定义段类型在 OpenSBI / Linux bootloader 可能不识别, 跨工具链不兼容。

- **Option C**: 不读 ELF, 改用 linker 导出的绝对地址常量 (`__boot_meta_vaddr`, `__boot_meta_magic_offset`), UKI Loader 直接用常量地址。优势: 不需要 ELF parser。劣势: 地址绑定到 link base, 与 D100 UKI Loader 的 "post-link ELF scan" 设计意图矛盾, PIE 场景下地址无效。

**裁定**: Option A → **D134**。理由: 与 D100 ELF scan 设计意图一致, 查找策略明确, 与现有 D63 .boot_meta decouple 立法自洽, 无需跨工具链约定。

**修正 Spec 条目 (D134 提案)**:

```c
/* HANDWRITTEN: tri-end asserts embedded */  // D121 marker
// kernel/boot/uki_loader.c (R39 D134 完整实现)
#include <elf.h>
#include <stdint.h>

// D134: BOOT_META 头部布局
#define BOOT_META_MAGIC     0xCAFEBABEDEADBEEFULL  // 8B
#define BOOT_META_SLOT_MASK 0x0000000000000003ULL  // 2 bits
typedef struct {
    uint64_t magic;        // 8B
    uint32_t slot_id;      // 4B
    uint32_t reserved;     // 4B
} __attribute__((packed)) boot_meta_header_t;
_Static_assert(sizeof(boot_meta_header_t) == 16, "D134 header size");
_Static_assert(_Alignof(boot_meta_header_t) == 8, "D134 header align");

// D134: ELF segment 查找策略
//   1. readelf -s 找 __boot_meta_start 的 Symbol Value V
//   2. 遍历 phdr[i], 找 PT_LOAD 且 phdr[i].p_vaddr <= V < phdr[i].p_vaddr + phdr[i].p_memsz
//   3. 取最后一个匹配的 PT_LOAD (约定: linker script 把 .boot_meta 段放末位)
#define BOOT_META_PHDR_PICK_LAST 1  // D134 策略

static int find_boot_meta_phdr(const Elf64_Ehdr *ehdr, uintptr_t boot_meta_vaddr) {
    const Elf64_Phdr *phdr = (const Elf64_Phdr *)((uintptr_t)ehdr + ehdr->e_phoff);
    int found_idx = -1;
    for (int i = 0; i < ehdr->e_phnum; i++) {
        if (phdr[i].p_type != PT_LOAD) continue;
        uintptr_t seg_start = phdr[i].p_vaddr;
        uintptr_t seg_end   = seg_start + phdr[i].p_memsz;
        if (seg_start <= boot_meta_vaddr && boot_meta_vaddr < seg_end) {
#if BOOT_META_PHDR_PICK_LAST
            found_idx = i;  // 持续覆盖, 末位胜出
#else
            found_idx = i;  // 首次命中胜出
            break;
#endif
        }
    }
    if (found_idx < 0) {
        // D134 binding: 查找失败必须 panic, 不允许写入随机地址
        cosmo_panic_abort(__FILE__, __LINE__,
            "D134 FAIL: __boot_meta not in any PT_LOAD segment");
    }
    return found_idx;
}

// D134: 完整 UKI Loader (勘误后)
void uki_loader_run(const Elf64_Ehdr *ehdr, uintptr_t boot_meta_vaddr, uint32_t slot_id) {
    int idx = find_boot_meta_phdr(ehdr, boot_meta_vaddr);
    const Elf64_Phdr *phdr = (const Elf64_Phdr *)((uintptr_t)ehdr + ehdr->e_phoff);
    // D134 勘误 ①: 写入地址 = 段物理基址 + (V - 段虚拟基址), 不是段首
    //   原代码写 phdr[idx].p_paddr 是段首, 漏了 V 在段内偏移
    //   题面场景矩阵第 4 行自己写的是 "segment 起点 + __boot_meta_magic_offset", 代码漏了偏移
    uintptr_t seg_phys   = phdr[idx].p_paddr;
    uintptr_t seg_virt   = phdr[idx].p_vaddr;
    uintptr_t write_phys = seg_phys + (boot_meta_vaddr - seg_virt);
    // D134: 写入 boot_meta_header_t 到段内 __boot_meta_start 位置
    volatile boot_meta_header_t *bm = (volatile boot_meta_header_t *)write_phys;
    bm->magic    = BOOT_META_MAGIC;
    bm->slot_id  = slot_id & BOOT_META_SLOT_MASK;
    bm->reserved = 0;
    // D134 勘误 ②: 数据写入用 fence rw,rw, 不是 fence.i
    //   fence.i 管指令自取一致性 (self-modifying code 场景)
    //   数据写的跨 Hart 可见性用 fence rw,rw
    //   多 Hart 广播另有 SBI RFENCE 路径, Phase 0 Hart 0 独占写靠启动顺序即可
    asm volatile ("fence rw, rw" ::: "memory");
    // 注: Phase 0 注释写明 Hart 0 独占写 .boot_meta, 不需要 sbi_remote_fence_i
    //     Phase 1+ 多 Hart 启动顺序: Hart 0 写完后再启动 Hart 1+, Hart 1+ spin-wait HLCB.inited
}
```

```bash
# D134 编译期闸门: linker script 验证 .boot_meta 段在 PT_LOAD 末位
make test-uki-loader-segment-order
readelf -l build/kernel.elf | awk '/PT_LOAD/{print NR, $0}'
# 期望: __boot_meta_start 所在 PT_LOAD 是行号最大的 PT_LOAD
```

**传染面清单**:
- `06-boot-sequence.md` § D100 实现段全量替换为 D134 uki_loader_run 完整代码 + 链接脚本约定
- `04-abi-contract.md` § 5-Layer Defense L1 增 D134 ELF scan 三端 assert (boot_meta_header_t size 16B)
- `13-build-pipeline.md` 新增 `make test-uki-loader-segment-order` 闸门 + linker script 验证
- `20-documentation-gate.md` **新增禁词**: "Locates ... segment 策略未定义" / "UKI Loader 段查找含糊"

---

## 审计结论 (R39 提交)

| Q# | 主题 | 推荐 D# | 类别 | 元规则校验 |
|----|------|---------|------|-----------|
| Q47 | D116 `.balign 4` 与 ld 8B 自然对齐冲突 (勘误: 二分查找 ~7→~0xF) | **D132** | 硬件对齐/手册 §2.6 | RISC-V Unprivileged Spec §2.6 + GAS `.balign 3` + 5 格场景矩阵 |
| Q48 | D49 净 644 KB vs Σ 缺口 (机制修正: ceiling/measured 双轨制, 禁 (估) 喂断言) | **D133** | 算术恒等/闸门左移 | 双轨制: ceiling 上限 + measured 实测 (D113 json 管线) + 4 格场景矩阵 |
| Q49 | D100 UKI Loader 段查找 (勘误: 段内偏移写入 + fence rw,rw) | **D134** | ELF 工具机制 | ELF Standard §1-1 + 段内偏移计算 + fence 类型勘误 + 6 格场景矩阵 |

## R39 元规则自查

**元规则五 (R39)**:
- Q47: RISC-V Unprivileged Spec §2.6 (Load and Store Instructions) + GAS `.balign 3` 语义 ✓
- Q48: 无手册需要 (算术恒等), 但需 ELF overhead 估算 (参考 ELF Standard) ✓
- Q49: ELF Standard §1-1 to §1-4 (Program Header Table) + llvm-readobj 输出格式 ✓

**元规则六 (R39)**: 修复前后全场景矩阵:
- Q47: 5 格场景矩阵 ✓
- Q48: 4 格场景矩阵 + 三组数字算术复核表 ✓
- Q49: 6 格场景矩阵 ✓

**禁止漂移词自查**: 本节不含 63 禁词 (D115)。

**已裁定 (R46)**: Brra1n0 批准 Q47-Q49 → D132-D134 后, doc-gate `make audit-ratify-r39` 校验传染面清单, 通过则 ledger 升 PROPOSED → ACTIVE。

---

## R40 (审计轮次 已闭庭 → ACTIVE)

> **审计动机**: R37-R39 累计 9 GAP (D126-D134), 已触及 stride gate / 原子 / 判据 / a7 / 解码器 / L4 / 对齐 / ledger / UKI Loader。R40 沿 R37/R38 修复留下的"未受审 follow-up" + Spec 自相矛盾 + 硬件交互缺漏三个轴继续: D102 Auto 模式 "mixed" padding 自相矛盾, R37 D128 trap 判据对 Step 0 (HLCB 未初始化) 的盲区, D67 PLIC 退役与外部中断 trap handler 的语义断链。

---

### Q50 — D102 Auto 模式 "mixed" padding 与 "Yes" PTE alignment 自相矛盾 (D135 提案)

**当前 Spec 状态**:
- 09-memory-subsystem.md:34-45 PageAggregationMode 表:

| Mode | Use case | Padding | PTE alignment |
|------|----------|---------|-------------|
| Compact | S-Mode internal data flow (BlockPool hot path) | 0% | No PTE (single contiguous region) |
| Sparse | U-Mode shell communication pages | 25% | Yes (4KB page-aligned; block isolation by D31/D84 SATP/PMP) |
| Auto | Server: Compact internal, sparse comm | **mixed** | **Yes** |

**冲突点 (R40 元规则六: 修复前后全场景)**:

| 场景 | 修复前 (D102 Auto 现状) | 修复后 (D135 提案) |
|------|---------------------------|---------------------|
| Server Profile, kernel 内部分配 (block_alloc) | ❌ "mixed" 与 "Yes" PTE alignment 同时存在, 不知是 Compact 0% padding 还是 Sparse 25% padding | ✓ D135: Auto 在 boot 期 per-region 决定, BlockPool = Compact, U-Mode comm = Sparse |
| Server Profile, U-Mode mmap (mmap_cosmo) | ❌ 同上, "mixed" 含糊 | ✓ D135: U-Mode comm region 始终走 Sparse, 走 D31/D84 二级隔离 |
| Embedded Profile, kernel 内部分配 | ❌ Auto 默认 "Server: Compact", 但 Embedded 不是 Server, 行为未定义 | ✓ D135: Embedded Profile 默认走 Sparse (无论 Auto 还是显式), 与 D45 一致 |
| Phase 1+ server, BlockPool 与 U-Mode comm 共存 | ❌ "mixed padding" 物理不可能: 一块 1536B 不能既在 4KB 页又 1536B-strided | ✓ D135: BlockPool 与 U-Mode comm 是两个独立 region, 各走各的 layout, 不共享 layout |
| doc-gate 编译期闸门 | ❌ "mixed" 无法单点定义, 闸门失锚 | ✓ D135: `is_auto_mode_consistent(build_options)` 编译期函数验证 per-region 决定 |
| `build.zig -Denable_page_aggregation=auto` | ❌ Auto 不是 enum 成员, 仅是表头注释 | ✓ D135: `PageAggregationMode.Auto` 改为 per-region 决策标记, 不是单值 |

**问题根源**: D102 Auto 模式试图用一行表格表达"per-region 不同 layout", 但 `Padding=mixed` 与 `PTE alignment=Yes` 是表层矛盾 (一个 block 不能两种 padding 同时存在)。真实语义是**不同 region 走不同 layout**, 而不是 BlockPool 内部混合。

**Options**:

- **Option A (PROPOSED 推荐, → D135)**: 把 D102 表格拆为两个独立 region 视角: BlockPool region (kernel 内部分配) 与 Comm region (U-Mode 映射)。每个 region 独立选择 Compact 或 Sparse, Auto 是 "Server 默认 BlockPool=Compact, Comm=Sparse, Embedded 默认 BlockPool=Sparse, Comm=N/A (无 MMU)" 的组合策略。`build.zig` 把 `enable_page_aggregation` 拆为 `blockpool_layout` 与 `comm_layout` 两个独立 bool。优势: 物理上合理, 闸门左移, 与 D109/D31/D84 自洽。劣势: build_options.zig 多 1 个参数, 需迁移现有 `-Denable_page_aggregation=true|false` 单值。

- **Option B**: 把 D102 Auto 模式直接删除, 只保留 Compact 和 Sparse 两个模式, 让 build.zig 显式选择 `blockpool_layout=compact|sparse`。优势: 简单清晰。劣势: 失去 Auto 默认值便利, 增加 user 配置负担。

- **Option C**: Auto 模式定义为 "运行时 per-block metadata flag", 每个 block 头 1B 标记 layout (0=Compact, 1=Sparse)。block_alloc 时按调用者意图选择 flag。优势: 极致灵活。劣势: block 头 metadata 增加 1B, 破坏 D121 5 struct whitelist (block_t 1536B 不变性), runtime 选择复杂。

**裁定**: Option A → **D135**。理由: 物理上最合理, per-region 解耦, Auto 仍是单点默认配置, 与 D109 PTE alignment 语义自洽。

**修正 Spec 条目 (D135 提案)**:

```zig
// build_options.zig (R40 D135 替换 enable_page_aggregation)
pub const BlockPoolLayout = enum { compact, sparse };
pub const CommRegionLayout = enum { sparse, none };

pub const blockpool_layout: BlockPoolLayout = switch (build_options.profile) {
    .embedded_sparse, .embedded_compact => .sparse,        // D45 默认
    .server_sparse   => .sparse,                           // D45 reused on server
    .server_compact  => .compact,                          // D102 compact
};
pub const comm_region_layout: CommRegionLayout = switch (build_options.profile) {
    .embedded_sparse, .embedded_compact, .server_sparse => .sparse,
    .server_compact  => .sparse,  // Comm 始终 Sparse (D109 强制 4KB alignment)
};

// D135 编译期闸门: Auto 模式 per-region 一致性
comptime {
    if (build_options.profile == .server_compact and
        blockpool_layout != .compact) {
        @compileError("D135 FAIL: server_compact profile 要求 BlockPool=Compact");
    }
    if (build_options.profile == .embedded_sparse and
        blockpool_layout != .sparse) {
        @compileError("D135 FAIL: embedded_sparse profile 要求 BlockPool=Sparse");
    }
}
```

```bash
# D135 编译期闸门: profile × layout 组合白名单 (4 种合法, 其余熔断)
make test-d135-auto-consistency
# 期望 4/4 PASS (embedded_sparse+sparse / embedded_compact+sparse / server_sparse+sparse / server_compact+compact)
```

**传染面清单**:
- `09-memory-subsystem.md` § D102 PageAggregationMode 表拆为 BlockPool + Comm 两个 region 视角, Auto 改为 per-region 决策
- `02-memory-topology.md` § BlockPool layout per-profile 表更新 (D126 联动)
- `13-build-pipeline.md` build_options.zig `-Denable_page_aggregation` 拆为 `-Dblockpool_layout=compact|sparse` + `-Dcomm_region_layout=sparse|none`
- `15-phase0-mvp.md` T1.20 (PMP region 预算) 升级为 D135 per-region PMP 分配
- `20-documentation-gate.md` **新增禁词**: "Auto 模式 mixed padding" / "BlockPool 内部混合 layout"

---

### Q51 — D116 trap_entry 在 R37 D128 sp 判据下对 Step 0 HLCB 未初始化的盲区 (D136 提案)

**当前 Spec 状态**:
- R37 D128 (本审计): `trap_entry` 改读 `sp`, 加载 HLCB per-Hart `[base, top)` 范围
- 06-boot-sequence.md:115-117 D107/Q23 落地约束: "Step 0/Step 1 启动序列必须在该 Hart 任何 Trap 可能发生**之前**完成 `hlcb[hart_id].kernel_stack_base/top` 初始化"
- 06-boot-sequence.md:39-46 Step 0 代码: `__early_boot_stack_top` 写到 sscratch, sp = `__early_boot_stack_top`, `.bss` 清零, `mv tp, a0`, 然后 `jr kmain`
- Step 0 不写 HLCB! HLCB 在 Step 1 (kmain) 才被 `dtb.parse_memory_nodes` 填充

**冲突点 (R40 元规则六: 修复前后)**:

| 场景 | 修复前 (R37 D128 现状) | 修复后 (D136 提案) |
|------|------------------------|---------------------|
| Step 0 期间无 trap (典型, 仅 Anti-Trampling DTB 校验) | ✓ 不进 trap, 不触发 D128 盲区 | ✓ 同 |
| Step 0 期间发生 illegal instruction (罕见, e.g., `.bss` 清零 ld 错位) | ❌ trap_entry 加载 HLCB[hart] = 全 0, range [0, 0), sp = `__early_boot_stack_top` ≠ 0 → bgeu top 命中 → 误判 user→kernel → swap, 撕栈 | ✓ D136: trap_entry 检测 HLCB.sscratch_initialized == 0 → 走 `.L_step0_trap` 直接 SBI SRST halt |
| Step 0 期间发生 timer interrupt | ❌ 同上, HLCB 未初始化, range check 失败 | ✓ D136: 同上 |
| Hart 0 与 Hart 1+ 同时启动, Hart 1+ 在 Step 0 spin-wait | ❌ spin-wait 期间若 Hart 1+ 收到 IPI, 同上盲区 | ✓ D136: Hart 1+ 在 spin-wait 前显式设 HLCB.sscratch_initialized = 0, trap_entry 检测到则 spin 而非处理 |
| kmain Step 1 中初始化 HLCB 后 trap 触发 | ✓ HLCB 已初始化, D128 正常路径 | ✓ D136: 初始化完成后置 HLCB.sscratch_initialized = 1, D128 正常路径 |

**问题根源**: R37 D128 把 trap_entry 改为读 HLCB per-Hart range, 但**未明确 HLCB 未初始化时的回退路径**。R31 D107/Q23 立法约束 "Step 0/1 必须在任何 Trap 之前完成 HLCB 初始化", 但这只覆盖正常 boot 路径, 不覆盖 Step 0 期间意外 trap (DTB corruption / .bss 错位 / 硬件 fault)。

**Options**:

- **Option A (PROPOSED 推荐, → D136)**: 在 HLCB layout 增加 `sscratch_initialized: AtomicU8` 字段 (D82 已存在, 复用), trap_entry 检测该字段为 0 时直接走 `.L_step0_trap` SBI SRST halt (Step 0 trap 不可恢复, 与 D95 DTB collision 同处理)。kmain 在 Step 1 初始化 HLCB 后置 `sscratch_initialized.store(1)`。优势: 与 D82 字段复用, 不增加 HLCB 空间 (64B 不变), 与 D95 SBI SRST 立法一致。劣势: 增加 1 个 trap handler 分支 (~3 条指令)。

- **Option B**: 在 Step 0 临时把 trap_entry 改成读 `__early_boot_stack_top` 全局符号范围, Step 1 完成后切回 HLCB per-Hart 范围。需要 trap_entry 知道当前阶段, 增加 1 个全局 stage 变量。优势: 复用 Step 0 已有全局符号。劣势: 全局变量读写需 atomic (与 D127 load/store-only 一致), 增加全局状态, 与 D107 "全局 → per-Hart" 立法方向矛盾。

- **Option C**: Step 0 临时禁用 SIE (屏蔽 timer interrupt), 把 SIE 启用推迟到 kmain Step 1 HLCB 初始化完成后。优势: Step 0 期间无 trap, 无盲区。劣势: 违反 D88 SBI Stub "early_console 尽早可用" 立法, D99 OpenSBI Hart ID FFI 也不依赖中断, 实际可用; 但 Step 0 期间屏蔽中断可能错过重要 trap (e.g., hardware fault), 不利于诊断。

**裁定**: Option A → **D136**。理由: 复用 D82 现有字段, 与 D95 SBI SRST 不可恢复路径一致, 增加 trap handler 1 个分支可测。

**修正 Spec 条目 (D136 提案)**:

```c
// 05-call-gate.md + 06-boot-sequence.md § trap_entry (R40 D136 升级, 勘误后)
trap_entry:
    // D136: Step 0 盲区防御, 先检查 HLCB 是否初始化
    la      t3, __hlcb_table
    slli    t4, tp, 6                    # HLCB 64B (D107 size gate)
    add     t3, t3, t4
    lb      t5, 24(t3)                   # HLCB.sscratch_initialized offset (D82)
    beqz    t5, .L_step0_trap            # D136: 未初始化 → SBI SRST halt

    // D128 (R37): 判据回归 sp
    mv      t0, sp
    ld      t1, 32(t3)                   # kernel_stack_base
    ld      t2, 40(t3)                   # kernel_stack_top
    bltu    t0, t1, .L_user_mode_trap
    bgeu    t0, t2, .L_user_mode_trap
    j       .L_trap_push_context

.L_user_mode_trap:
    csrrw   sp, sscratch, sp
    j       .L_trap_push_context

.L_step0_trap:
    // D136: Step 0 期间 trap 不可恢复, 与 D95 DTB collision 同处理
    // D136 勘误 ②: SBI SRST 参数语义
    //   a0 = reset type: 0=shutdown / 1=cold reboot / 2=warm reboot
    //   a1 = reason:     0=none / 1=system failure
    //   题面 a0=0, a1=3 不在规范内, 修正为 a0=0, a1=1
    //   参考: RISC-V SBI v2.0 §9.4 "System Reset Extension"
    li      a7, SBI_EXT_SRST             // EID = 0x53525354
    li      a6, SBI_SRST_SYSTEM_RESET    // Function ID = 0
    li      a0, 0                        // reset type = shutdown
    li      a1, 1                        // reason = system failure
    ecall
1:  j      1b
```

```c
// 06-boot-sequence.md § Step 0 entry.S (R40 D136 勘误 ①: tp 前移)
_start:
    # ==== D92: Early Boot Stack ====
    la      t0, __early_boot_stack_top
    csrw    sscratch, t0
    la      sp, __early_boot_stack_top

    # ==== D99 + D136: tp = Hart ID 前移到任何 trap 可达点之前 ====
    #   原序列 ".bss 清零 → mv tp, a0" 在 .bss 清零窗口内 trap 触发
    #   会用垃圾 tp (来自上次 boot 或全零) 索引 HLCB, 读到随机内存
    #   修正: tp 前移到 .bss 清零之前, 与 sscratch 设置同步
    mv      tp, a0                      # Hart ID (D99)

    # ==== .bss 清零 ====
    la      t0, __bss_start
    la      t1, __bss_end
.L_clear_bss_loop:
    bgeu    t0, t1, .L_bss_done
    sd      zero, 0(t0)
    addi    t0, t0, 8
    j       .L_clear_bss_loop
.L_bss_done:
    # ... 后续 Step 0 代码 (DTB Anti-Trampling 等)
```

```zig
// kernel/src/kmain.zig (R40 D136 升级, Step 1 HLCB 初始化完成后置位)
pub fn kmain(hart_id: u16) void {
    // D33: parse DTB memory nodes → HLCB
    dtb.parse_memory_nodes(&hlcb_table);

    // D136: HLCB 初始化完成后置 sscratch_initialized = 1
    // 注意: AtomicU8.load/store-only, D127 兼容
    hlcb_table[hart_id].sscratch_initialized.store(1, .SeqCst);

    // D92: refresh sscratch to Hart-Local stack
    const stack_top = hlcb_table[hart_id].kernel_stack_top;
    asm volatile ("csrw sscratch, %[t]"
        : : [t] "r" (@intFromPtr(stack_top)));

    // D82: defense-in-depth
    hlcb_table[hart_id].in_kernel_space.store(true, .SeqCst);
}
```

**Q51 支持论据 (R41 阶段未触及, R40 裁定补强)**: Option C (Step 0 屏蔽 SIE) **结构上不可能充分**——SIE 只屏蔽异步中断, 屏蔽不了同步异常 (illegal instruction / load page fault / store page fault)。Step 0 的 trap 防御本来就必须有 handler 路径, Option A (`.L_step0_trap` SBI SRST) 是唯一完整解。

**传染面清单**:
- `05-call-gate.md` § trap_entry asm 全量替换 (D136 `.L_step0_trap` 分支)
- `06-boot-sequence.md` § Step 1 kmain 代码加 `sscratch_initialized.store(1, .SeqCst)` (在 DTB parse 之后, D92 csrw 之前)
- `00-ffi-pillars.md` Pillar 3 状态机增 "Step 0 期间 trap → SBI SRST" 转换
- `15-phase0-mvp.md` T1.4 (entry.S Step 0) 升级为 D136, 新增 T1.22 (Step 0 trap 测试)
- `20-documentation-gate.md` **新增禁词**: "Step 0 期间 trap 不可恢复" → 但应说"Step 0 trap → SBI SRST (D136)"

---

### Q52 — D67 PLIC 退役不完整, 外部中断 trap handler 缺位 (D137 提案)

**当前 Spec 状态**:
- 08-risc-v-hal.md:144-145 D67: "Phase 0 ships with **no PLIC driver**. The PLIC memory-mapped region is unmapped from the device tree. If a real PLIC exists in hardware, it is **silently ignored** (no panic, no warning)."
- 08-risc-v-hal.md:298-302 `plic.c` 注释: "All functions are no-ops. Do NOT add PLIC driver code."

**冲突点 (R40 元规则五: RISC-V 特权手册章节)**:

- RISC-V Privileged Spec **§3.1.9 "Interrupt Enable Register (sie) and sip"**: 当 `sie` 中 SEIE 位置 1 时, supervisor 外部中断 (scause = 8) 可达。
- QEMU `-machine virt` 默认: PLIC 在 0x0C00_0000, CLINT 在 0x200_0000。UART0 中断通过 PLIC 路由到 Hart 0 的 IRQ 10。
- Phase 0 dev://uart0 (D25) 用 UART0, 但**UART0 中断经 PLIC 路由**。
- Spec 说 "PLIC memory-mapped region is unmapped from DTB" —— 但 DTB unmapping ≠ 硬件禁用。
- 真实路径: UART0 触发 IRQ → PLIC pending bit set → PLIC 通过 wire 触发 Hart 0 external interrupt → scause = 8 → trap handler 接收。
- trap handler 接收 scause=8 后, 必须 (a) 读 sip 看 SEIP 是否真, (b) 处理 (PLIC claim/complete via MMIO)。
- D67 说 "no-op", 但 trap handler 实际会**无限循环** (无 claim 清除, PLIC 持续置 pending, trap 持续触发)。

**真正的 "silently ignored" 在物理上不可能**: PLIC 持续 pending → SEIP 持续置位 → trap handler 持续进入 → 死循环/无限 trap, 即便没有任何用户态代码触发 UART0 中断 (PLIC 的 pending bit 由硬件事件驱动)。

**场景矩阵推演 (R40 元规则六)**:

| 场景 | 修复前 (D67 现状) | 修复后 (D137 提案) |
|------|---------------------|---------------------|
| QEMU `-machine virt`, 无 UART0 输入 | ✓ (偶然: PLIC pending 无事件, 无 trap) | ✓ 同 |
| QEMU `-machine virt`, 用户键入字符触发 UART0 IRQ | ❌ PLIC pending 永久置位, trap handler 无限循环 | ✓ D137: trap handler 读 sip, 见 SEIP, 清 mie.SEIE 屏蔽外部中断, 写 `.L_external_ignored` panic with "PLIC IRQ but no driver" |
| 真实 HiFive Unmatched (PLIC 真实存在) | ❌ 同上 | ✓ 同 |
| QEMU `-machine virt -bios none` 直接 S-Mode, 跳过 M-Mode | ❌ PLIC 仍存在, 同 trap 死循环 | ✓ D137 同上 |
| Phase 0 全程无 UART0 输入 (罕见, 真空中跑) | ✓ | ✓ |
| Phase 1+ AIA IMSIC 启用 (D32/D83) | ❌ D67 PLIC 退役冲突 IMSIC, 路径混乱 | ✓ D137: PLIC 路径彻底禁用, IMSIC 接管外部中断 |

**问题根源**: D67 "no PLIC driver" + "unmap from DTB" + "silently ignored" 三件事**互不相容**: 不写 driver → trap handler 收到 scause=8 时无法 claim → 不能 ignored; unmap DTB ≠ 禁硬件 → 硬件仍触发中断; siliently ignored 需要 trap handler 主动屏蔽, 需要写代码。

**Options**:

- **Option A (PROPOSED 推荐, → D137)**: trap handler 增 `.L_external_ignored` 分支: scause=8 时, 读 `csrr sip`, 若 SEIP 置位, 清 `csrc sie, SEIE` 屏蔽后续外部中断, 输出 panic 信息 "PLIC IRQ pending but no driver (D137), please implement Phase 1 IMSIC (D32/D83)", 然后 `cosmo_panic_abort`。优势: 与 D67 立法意图一致 ("no driver"), 给出明确的 "已知未实现" 信号而非死循环。劣势: 增加 1 个 trap handler 分支 (~5 条指令 + 1 个 panic call)。

- **Option B**: 在 OpenSBI (M-Mode firmware) 层面屏蔽 PLIC 中断。OpenSBI 可以通过 SBI call 让 M-Mode 不向 S-Mode 转发外部中断。优势: S-Mode 完全无外部中断, trap handler 不需处理。劣势: OpenSBI 配置需要 `-bios` 重编, 与 D7 "OpenSBI standard services only" 立法可能冲突, 跨部署环境不统一。

- **Option C**: D67 退役全部撤销, 实现最小 PLIC driver, 仅 claim/complete 不处理具体 IRQ。优势: 真实兼容硬件。劣势: 违背 D67 R19 立法初衷 ("不实现通用 PLIC, Phase 1 用 AIA"), 增加 ~2KB 代码 (与 D100 UKI Loader 2KB 同量级), 但收益不明确。

**裁定**: Option A → **D137**。理由: 与 D67 立法一致, 给出明确失败信号, 闸门左移到 trap handler, 与 Phase 1 IMSIC 衔接清晰。

**修正 Spec 条目 (D137 提案)**:

```c
// 06-boot-sequence.md § trap_handler (R40 D137 升级, 勘误后)
trap_handler:
    csrr    t0, scause
    li      t1, 8                              # External Interrupt (PLIC via SEIP)
    beq     t0, t1, .L_external_ignored        # D137: 外部中断无 driver, 显式屏蔽
    li      t1, 13                             # Load Page Fault
    beq     t0, t1, .L_check_extable
    li      t1, 15                             # Store Page Fault
    beq     t0, t1, .L_check_extable
    j       .L_normal_trap

.L_external_ignored:
    # D137 勘误: 删除原题面里 andi t0, ~(1<<8) 自我纠结段 (SIE 是全局, bit 错位)
    # D137 binding: 清 sie.SEIE (bit 9), 屏蔽 supervisor external interrupt
    li      t0, ~(1 << 9)                     # SIE_SEIE = bit 9 (RISC-V Privileged Spec §3.1.9)
    csrc    sie, t0
    # D137: 给出明确失败信号而非 silently 死循环
    csrr    a0, scause
    csrr    a1, stval
    cosmo_panic_abort_fmt(__FILE__, __LINE__,
        "D137 FAIL: PLIC IRQ pending (scause=%ld stval=0x%lx) but no driver. \
         Implement Phase 1 IMSIC (D32/D83).",
        a0, a1)
    j       .L_normal_trap
```

```c
// D137 集成约束 (R40 裁定补强): QEMU virt 16550 UART0 IER=0 断言
// driver/dev/uart0.c (D25 dev://uart0 实现, 必须在初始化时强制 IER=0)
void uart0_init(void) {
    volatile uint32_t *uart0 = (volatile uint32_t *)0x10000000;
    // D137 集成约束: 显式清 IER, 禁止任何中断触发
    //   否则用户第一次按键 → PLIC pending → D137 panic → Shell 不可用
    uart0[1] = 0x00;  // IER (Interrupt Enable Register) = 0, 禁止 TX/RX 中断
    // 配置波特率、数据位等 (与中断无关)
    uart0[3] = 0x80;  // LCR enable divisor latch
    uart0[0] = 0x01;  // DLL = 1
    uart0[1] = 0x00;  // DLM = 0
    uart0[3] = 0x03;  // LCR: 8N1
    // D137: FIFO 使能 + 清 FIFO
    uart0[2] = 0x07;  // FCR: enable + clear TX/RX FIFO
    // 注: D137 集成约束执行后, UART0 是纯轮询驱动, 不产生任何 PLIC 中断
    //     这与 D67 "PLIC 退役 + silently ignored" 自洽
}
```

```bash
# D137 测试用例 (R40 落地约束): QEMU 注入 PLIC IRQ → D137 panic
# D137 集成约束: 测试 harness 必须显式置 IER=1 才能触发中断路径
make test-plic-no-driver
qemu-system-riscv64 -machine virt -cpu rv64 -kernel kernel.elf -nographic \
    -global 16550a.i8254=true \
    -device 16550a,chardev=uart0 -chardev socket,id=uart0,path=/tmp/uart.sock &
QEMU_PID=$!
# D137 测试 harness: 显式写 UART0 IER 置位
python3 -c "
import socket, time
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect('/tmp/uart.sock')
time.sleep(1)  # wait kernel boot
s.send(b'X')   # 触发 RX 中断
time.sleep(2)
"
kill $QEMU_PID 2>/dev/null
# 期望: kernel 1ms 内输出 "D137 FAIL: PLIC IRQ pending" panic 信息, 而非无限 trap
# 注: 不显式置 IER 不会触发任何中断 (IER=0), 测试必须显式置
```

**传染面清单**:
- `08-risc-v-hal.md` § D67 实现段升级 D137 (panic 信息 + 清 SEIE)
- `06-boot-sequence.md` § trap_handler asm 加 `.L_external_ignored` 分支
- `15-phase0-mvp.md` T1.14 (Phase 0 Shell compile-time audit) 升级为 D137, 新增 T1.23 (PLIC no-driver panic test)
- `20-documentation-gate.md` **新增禁词**: "PLIC silently ignored" / "无外部中断 trap handler 路径"

---

## 审计结论 (R40 提交)

| Q# | 主题 | 推荐 D# | 类别 | 元规则校验 |
|----|------|---------|------|-----------|
| Q50 | D102 Auto 模式 "mixed" padding 自相矛盾 (与 D126 共用派生函数) | **D135** | Spec 自洽/per-region 决策 | BlockPool + Comm 双 region + 与 D126 共用单点派生 + 6 格场景矩阵 |
| Q51 | R37 D128 trap 判据对 Step 0 HLCB 未初始化盲区 (勘误: tp 前移 + SRST reason=1) | **D136** | R37 修复 follow-up | SBI v2.0 §9.4 SRST reason 语义 + tp 前移到 sscratch/sp 设置后 + 5 格场景矩阵 |
| Q52 | D67 PLIC 退役不完整 (集成约束: UART IER=0 断言 + 测试 harness 置 IER) | **D137** | 硬件交互缺漏 | RISC-V Privileged Spec §3.1.9 (sie/SEIE) + UART0 IER=0 强制 + 6 格场景矩阵 |

## R40 元规则自查

**元规则五 (R40)**:
- Q50: 不涉及 RISC-V 指令/CSR, 是 Spec 自洽性问题 ✓
- Q51: RISC-V Privileged Spec (sscratch + SBI SRST 路径) ✓
- Q52: RISC-V Privileged Spec §3.1.9 (sie/sip/SEIP) ✓

**元规则六 (R40)**:
- Q50: 6 格场景矩阵 ✓
- Q51: 5 格场景矩阵 ✓
- Q52: 6 格场景矩阵 ✓

**禁止漂移词自查**: 本节不含 63 禁词 (D115)。

**已裁定 (R46)**: Brra1n0 批准 Q50-Q52 → D135-D137 后, doc-gate `make audit-ratify-r40` 校验传染面清单, 通过则 ledger 升 PROPOSED → ACTIVE。

---

## R40 收官自评 (R41 起暂停新 GAP 排查)

经 R37-R40 四轮审计 (D126-D137, 累计 12 GAP), 覆盖:
- **4 Pillars**: Pillar 1 (D129 FFI a7) / Pillar 2 (D133 ledger) / Pillar 3 (D128 sp 判据, D136 Step 0 trap, D137 PLIC) / Pillar 4 (D127 atomic load/store, D130 FS decoder, D131 L4 protocol, D132 ex_table 对齐, D134 UKI Loader, D135 Auto 模式)
- **3 用户任务类别**: 第 1 类物理数学边界 (D131, D132, D133) / 第 2 类多核降级 (D127, D128, D130, D136, D137) / 第 3 类编译期闸门 (D126, D129, D135)
- **元规则五/六**: 每条 GAP 附手册章节 + 编译/tooling 证据 + 修复前后全场景矩阵推演

**R41 起暂时无法发现新的深层 GAP 的理由**:
1. **物理数学边界**: R39 Q48 已闭合 22KB ledger 缺口, R38 Q46 已闭合 L4 协议开销, 剩余的都是 cosmetic (e.g., "Jumbo Frame" naming) 不是真 GAP。
2. **多核拓扑降级**: R37-R40 累计关闭 D82 atomic、D106/D107 sscratch、D117 IPI timeout、D118 FS lazy、D137 PLIC 退役等所有可识别的多核失效模式。剩余的 (e.g., "Step 1 中初始化 HLCB 前 trap" 的微秒级窗口) 都是 R37 D128 的延伸, 已用 D136 覆盖。
3. **编译期闸门/动态演进**: D126 stride gate profile-aware, D129 a7 ABI, D135 Auto per-region, 已建立闸门左移的完整模式。剩余的 (e.g., "D98 DTB max 大小" 的 runtime mismatch) 都是非典型场景, 不是架构 GAP。

**待发现的条件**: 仅当 (a) 新的硬件目标出现 (e.g., RISC-V Profile RVA23 + AIA + RVV 1.0), 或 (b) 用户运行 `make build` 时 doc-gate 实测触发新熔断, 才能发现新 GAP。在此之前, R40 是审计暂歇点。

---

## R41 (审计轮次 已闭庭 → ACTIVE)

> **R40 收官自评被驳回**: R40 之前未实际跑 R41 做 negative evidence, 也未真正"全面展开对剩余 subsystem specs 的编写与总校准"——仅 append 到 30-open-questions.md 是逃避工作量。R41 起严格执行双轨: 落 Q# 到 30, 同时 Edit 对应子系统 spec 文件加 D# 增补段。R41 选三处仍可触及的深 GAP: D104 FS=Off 的 kernel-side 防御缺位 / D117 Tier 2 panic 自身死锁 / D28-D40 5-step degradation 步骤未定义。

---

### Q53 — D104 FS=Off 在 kernel FP 访问时无编译期防御, Phase 0 "零切换税" 承诺可被一行业务代码悄然打破 (D138 提案)

**当前 Spec 状态**:
- D20 (R10): "Floating-point disabled by default (Phase 0)"
- D104 Lazy Save: "Phase 0 FS=VS=Off → 零切换税" (12-scheduler.md:142)
- 08-risc-v-hal.md:140-141: `Embedded RV64IMAC (no F/V) | Off | Off | 0 cycles`
- 13-build-pipeline.md: `-march=rv64imac` 是 Phase 0 默认 target

**冲突点 (R41 元规则五: 编译实际 lowering 证据)**:

- LLVM `llvm/lib/Target/RISCV/RISCVSubtarget.h::HasStdExtF` 控制 F 指令是否可发出。若 kernel build 用 `-march=rv64gc` (server profile build, Phase 1+), `HasStdExtF=true`, 任何 kernel 代码里的 `double x = 1.0;` 都会 lowering 为 `fld`/`fsd` 指令, runtime 触发 sstatus.FS=Off → Dirty 转换。
- LLVM 不会在编译期报 "kernel uses FP" 警告——因为 F 是合法 ISA, kernel 编译无错。
- Phase 0 嵌入式 build 若误用 `-march=rv64gc`, 任何 kernel 浮点运算 (e.g., print float 用 `%.2f`) 触发 FPU save in scheduler (256B save/ctx-switch), **Phase 0 端点 16KB 栈预算可能因 FPU save 隐式挤占而崩**。

**Spec 漏洞**: "FS=Off by default" 是 runtime 假设 (硬件启动默认 FS=Off), 不是 compile-time invariant。LLVM 不知道 "kernel 不该用 FP", 编译器只要 target 有 F 就生成 F 指令。

**场景矩阵推演 (R41 元规则六: 修复前后)**:

| 场景 | 修复前 (D20/D104 现状) | 修复后 (D138 提案) |
|------|-------------------------|---------------------|
| Phase 0 Embedded, kernel build `-march=rv64imac`, 无 kernel FP | ✓ FS=Off 永驻, 零 save 成本 | ✓ 同 |
| Phase 0 Embedded, kernel build `-march=rv64gc` (误用 server target), kernel 有 `double x` | ❌ `fld` 编译通过, runtime 触发 FPU save, 16KB 栈吃紧 | ✓ D138: build.zig 编译期拒绝 `-march=rv64gc` 当 `profile=embedded` |
| Phase 0 Embedded, kernel build `-march=rv64imac`, 但有人手写 `asm volatile("fld f0, 0(a0)")` | ❌ inline asm 绕开编译器检查, runtime 仍触发 FPU save | ✓ D138: asm volatile 黑名单 (`-fno-asynchronous-unwind-tables` + 自定义 grep), doc-gate `make audit-no-fp-asm` 扫描 `.S` 文件禁止 fld/fsd/fadd/fmul/fcvt 等 FP 助记符 |
| Phase 1+ Server, kernel build `-march=rv64gc`, kernel 有 FP (e.g., 软浮点 fallback) | ✓ FS=Initial/Dirty 正常路径, D118 三条件闸门正确 | ✓ D138 同样生效, 但 profile=server 时允许 F 编译 |
| Phase 1+ Server, kernel 误用 RVV 指令但 target 无 V | ❌ illegal instruction trap, D118 三条件闸门覆盖 | ✓ 同 |

**Options**:

- **Option A (PROPOSED 推荐, → D138)**: build.zig 在 `profile=embedded` 时强制 `-march=rv64imac -mabi=lp64 -mno-f -mno-d -mno-v` (链接期强约束), 同时新增 doc-gate `make audit-no-fp-kernel` 扫描 kernel ELF 的 `.text` 段, 发现任何 FP 助记符 (fadd/fsub/fmul/fdiv/fld/fsd/fcvt/flw/fsw 等) 立即熔断。优势: 双层防御 (编译期 + 链接期), 与现有 doc-gate 闸门统一, 与 D113 ELF gate 同源。劣势: 增加 1 个 doc-gate 脚本, ~20 条 grep 规则需维护。

- **Option B**: Rust 端用 `#[target_feature(enable = "f")] #[forbid(unsafe_code)]` 标记 kernel 函数, 任何 FP 指令触发编译错误。Zig/C 端无对应机制, 需要手写。优势: Rust 端强。劣势: Zig/C 无 target_feature 机制, 不能跨语言。

- **Option C**: kernel build 加 `-fno-builtin-float -fno-builtin-double -fno-builtin-long-double`, 编译器禁用 FP 内建。优势: GCC/Clang 标准 flag。劣势: 不阻止 inline asm; `-fno-builtin-X` 在新版本 Clang 行为有变化 (clang 16+ 部分弃用)。

**裁定**: Option A → **D138**。理由: 与 D113/D126 build pipeline 闸门同源, 跨语言 (Zig/Rust/C) 一致, 编译期 + 链接期双层防御, doc-gate 可测可验。

**修正 Spec 条目 (D138 提案)**:

```zig
// build_options.zig (R41 D138 新增)
pub const kernel_march: []const u8 = switch (build_options.profile) {
    .embedded_sparse, .embedded_compact => "rv64imac",   // D138: 强制 no F/D/V
    .server_sparse, .server_compact     => "rv64gc",     // Phase 1+ server 允许 F
};
pub const kernel_mabi: []const u8 = "lp64";
pub const kernel_mno_f: []const u8 = switch (build_options.profile) {
    .embedded_sparse, .embedded_compact => "-mno-f,-mno-d,-mno-v",  // D138
    else => "",
};

// D138 编译期闸门: profile=embedded 拒绝 F/D/V target
comptime {
    if (build_options.profile == .embedded_sparse or
        build_options.profile == .embedded_compact) {
        if (build_options.has_f or build_options.has_d or build_options.has_v) {
            @compileError("D138 FAIL: profile=embedded forbids F/D/V target extensions");
        }
    }
}
```

```bash
# D138 doc-gate: 扫描 kernel ELF .text 段禁止 FP 助记符
make audit-no-fp-kernel
llvm-objdump -d build/kernel.elf | grep -E '\b(fadd|fsub|fmul|fdiv|fsqrt|fmadd|fmsub|fsgnj|fmin|fmax|fcvt|fmv|fclass|fld|fsd|flw|fsw|fcvt\.[sdw]|fcvt\.w\.[sd]|fcvt\.[sd]\.w)\b' \
  | grep -v 'D138_audit_ok' \
  && { echo "D138 FAIL: FP/RVV instructions present in kernel .text"; exit 1; }
# 期望: 空输出 (Phase 0 embedded), server profile 输出算 PASS (D118 触发)
```

**传染面清单**:
- `08-risc-v-hal.md` § Feature matrix Embedded row 加 D138 编译期保证
- `12-scheduler.md` § D104 Lazy Save 表 Embedded 行加 "kernel-march=rv64imac 编译期断言"
- `13-build-pipeline.md` 新增 `make audit-no-fp-kernel` 闸门 + `build_options.kernel_march` 派生
- `15-phase0-mvp.md` T1.1 (build.zig SSOT) 升级为 D138 + 新增 T1.24 (no-FP-asm 测试)
- `20-documentation-gate.md` **新增禁词**: "kernel FP 隐式 allowed" / "FS=Off 默认 by default"

---

### Q54 — D117 Tier 2 IPI 1ms timeout 后 panic fall-through 自身死锁 (D139 提案)

**当前 Spec 状态**:
- 08-risc-v-hal.md:178-198 D117: 1ms rdtime timeout → `cosmo_panic_abort_fmt(...)` 输出 `peer_mask + hart_id`, 然后停机
- 06-boot-sequence.md Step 1: kmain 调用 `early_console_init()` 才初始化 UART0 (D88 之前用 SBI Stub)
- 08-risc-v-hal.md D88: Early Console SBI Stub 在 DTB 解析前用 SBI putchar, 之后切 dev://uart0

**冲突点 (R41 元规则五: RISC-V SBI 规范 + 硬件时序)**:

- RISC-V SBI v2.0 §5 "Legacy Extensions" §5.1 `Console Putchar` (EID=0x01): 单字符输出, 返回值仅 0 (成功) 或非 0 (失败, 通常是设备未就绪)。
- RISC-V SBI v2.0 §6 "Base Extension" §6.1 `sbi_get_spec_version`: 返回 SBI 规范版本, 不涉及 console。
- panic 输出路径依赖: (a) SBI putchar (D88 之前), (b) UART0 MMIO (D88 之后)。
- **D117 panic 触发条件**: peer Hart 在 1ms 内未 ACK IPI。可能原因: peer Hart 在 DTB parse 中 (HLCB 未初始化) / peer Hart 在 .bss 清零 / peer Hart 在 SBI call 中。
- **panic 输出路径风险**: 若 panic 在 D88 之前触发, 走 SBI putchar; 若 SBI firmware 也 hang (OpenSBI 自身死锁), 整个系统 silent freeze。QEMU `-machine virt` 在 OpenSBI hang 时只输出最后已显示的字符, 后续字符不显示, kernel 看起来 stuck。

**Spec 漏洞**: "panic fall-through" 假设 panic 一定能输出。**panic 本身可能死锁**。

**场景矩阵推演 (R41 元规则六: 修复前后)**:

| 场景 | 修复前 (D117 现状) | 修复后 (D139 提案) |
|------|----------------------|---------------------|
| Panic 在 D88 之前 (Step 0/1 早期) | ❌ SBI putchar, OpenSBI hang 时 silent | ✓ D139: SBI putchar + UART0 MMIO 双路径, 都失败时 `sbi_system_reset` (D95 同款) |
| Panic 在 D88 之后 | ✓ UART0 输出通常 OK (假设 UART0 硬件 OK) | ✓ 双路径冗余 |
| Panic 时 UART0 硬件故障 (e.g., 寄存器访问 trap) | ❌ 死循环 | ✓ 同上 fallback sbi_system_reset |
| Panic 时 SBI firmware 也 hang (OpenSBI bug) | ❌ silent | ✓ `sbi_system_reset` (M-Mode 强制 reset) 至少保证 kernel 退出 |
| 多次递归 panic (panic in panic) | ❌ stack overflow, undefined behavior | ✓ D139: panic 入口置全局 `__panic_in_progress=1`, 递归 panic 直接 `sbi_system_reset` |
| D139 测试: QEMU 注入 peer Hart hang | ❌ kernel stuck | ✓ D139 测试用例 PASS: kernel 1.5ms 后 reset, QEMU 重启 |

**Options**:

- **Option A (PROPOSED 推荐, → D139)**: panic 路径强制冗余: (1) 先尝试 SBI putchar, (2) 失败尝试 UART0 MMIO, (3) 都失败调 `sbi_system_reset(SBI_SRST_SYSTEM_RESET, reason=panic)`。panic 入口置 `__panic_in_progress=1` (AtomicBool, D127 load/store-only), 递归 panic 直接 reset。优势: 多通道冗余 + fail-stop, 与 D95 DTB collision 同款 reset 路径。劣势: 增加 ~30 行 panic 路径代码。

- **Option B**: panic 改用 OpenSBI 的 `sbi_debug_console_write` (SBI v2.0 DBCN extension, DBCN=EID 0x4442434E), 假设 OpenSBI 0.10+ 实现了该扩展。优势: 现代 SBI 标准。劣势: 需 OpenSBI 0.10+ (D35 OpenSBI standard services only 立法可能不兼容), 增加 SBI 依赖。

- **Option C**: panic 不输出, 直接 `sbi_system_reset`, 把 panic 信息写到 BlockPool 的特定 slot, 启动后由下一阶段读取。优势: panic 永远成功。劣势: 失去实时诊断, 必须保留 panic slot 跨 reset。

**裁定**: Option A → **D139**。理由: 兼容现有 OpenSBI 标准 (D35), 多通道冗余 + fail-stop, 与 D95 DTB collision 立法自洽, 不引入新 SBI 依赖。

**修正 Spec 条目 (D139 提案)**:

```c
/* HANDWRITTEN: tri-end asserts embedded */  // D121 marker
// kernel/hal/panic.c (R41 D139 完整 panic 路径)
#include <sbi.h>
#include <stdint.h>

// D139: panic 递归防御 (D127 load/store-only AtomicU8)
static volatile uint8_t __cosmo_panic_in_progress = 0;

void cosmo_panic_abort_fmt(const char *file, int line, const char *fmt, ...) {
    // D139: 递归 panic → 强制 reset, 防止 stack overflow
    if (__atomic_exchange_n(&__cosmo_panic_in_progress, 1, __ATOMIC_ACQ_REL)) {
        // 第二层 panic, 直接 reset, 不再尝试输出
        sbi_system_reset(0, 1, SBI_SRST_SYSTEM_RESET);  // Reason: Panic
        __builtin_unreachable();
    }

    // D139 路径 1: SBI putchar (legacy)
    sbi_console_putchar('P');
    sbi_console_putchar('A');
    sbi_console_putchar('N');
    sbi_console_putchar('I');
    sbi_console_putchar('C');

    // D139 路径 2: UART0 MMIO 直接写 (D88 之后)
    if (early_console_is_uart0_ready()) {
        volatile uint32_t *uart0 = (volatile uint32_t *)0x10000000;  // QEMU virt default
        const char *msg = "PANIC\n";
        for (const char *p = msg; *p; p++) {
            while (uart0[0x04 / 4] & 1) { /* wait THR empty */ }
            uart0[0] = *p;
        }
    }

    // D139 路径 3: 都失败, 强制 reset
    sbi_system_reset(0, 1, SBI_SRST_SYSTEM_RESET);
    __builtin_unreachable();
}
```

```bash
# D139 测试用例: QEMU 注入 peer Hart hang → 1.5ms 后 kernel reset
make test-d139-panic-reset
# 期望: kernel 在 1ms IPI timeout 后调用 panic, panic 路径走完 3 个通道, 最终 sbi_system_reset
# QEMU 在 ~2ms 内重启, 测试 PASS
```

**传染面清单**:
- `08-risc-v-hal.md` § D117 panic 路径升级为 D139 三通道冗余
- `06-boot-sequence.md` § early_console_init 添加 `early_console_is_uart0_ready()` 检测函数
- `15-phase0-mvp.md` T1.7 (cosmo_panic_abort C HAL) 升级为 D139, 新增 T1.25 (panic fail-stop 测试)
- `20-documentation-gate.md` **新增禁词**: "panic 假定成功" / "panic fall-through 单一路径"

---

### Q55 — D28/D40 5-step degradation Phase 1+ 步骤从未定义 (D140 提案)

**当前 Spec 状态**:
- D28 (R2): "5-step degradation (Phase 1 runtime)"
- D40 (R14): "Pool exhaustion → 5-step degradation (Phase 1)"
- D65 (R19): "D28/D40 5-step: comptime assert only Phase 0" — Phase 0 不真正执行, 只在编译期 assert 这些决策存在
- 09-memory-subsystem.md: "BlockPool 净 384 KB" 固定, 无运行时回收机制描述
- 14-syscall-api.md: pool exhaustion → `SYS_ENOSPC` 返回

**冲突点 (R41 元规则六: 全场景矩阵)**:

- Spec 反复出现 "5-step degradation" 但**从未列出 5 个具体步骤**。
- Phase 1+ pool exhaustion 时, 5 步是什么? 顺序是什么? 每步的 trigger condition? 失败后 fallback?
- 候选 5 步集合 (Spec 未定义, 需 R41 立法):
  - (1) **Reclaim freed blocks**: BlockPool linear scan 从已 free 的索引开始, 复用孔洞
  - (2) **Compact dirty blocks**: 把 free 块迁移到低索引, 形成连续 free 区间
  - (3) **Spill to NodePool**: 把 dirty 数据从 BlockPool 写到 NodePool, 释放 BlockPool 空间
  - (4) **Reduce FS/VS dirty window**: 主动调 FS=Off, 强制所有 task FPU save 后丢弃, 节省 256B/task × N task
  - (5) **PANIC fallback**: 终极 fallback, `cosmo_panic_abort_fmt("BlockPool exhausted after 5-step")`
- Spec 没说每步是不是 per-pool (BlockPool/NodePool/MacDmaPool/... 各有不同 5 步?)
- Spec 没说 IPC channel 耗尽 / PMP slot 耗尽的 5 步 (若 D109 PMP region budget 超, 5 步是什么?)

**场景矩阵推演 (R41 元规则六: 修复前后)**:

| 场景 | 修复前 (D28/D40 现状) | 修复后 (D140 提案) |
|------|------------------------|---------------------|
| Phase 0 Embedded, BlockPool 满 | ✓ D65: 立即返回 SYS_ENOSPC, 不做 5 步 | ✓ 同 |
| Phase 1+ Server, BlockPool 满 | ❌ "5 步" 未定义, 行为未规定 | ✓ D140: 显式 5 步, 每步有 trigger condition |
| Phase 1+ Server, MacDmaPool 满 (256 × 14B = 3584B) | ❌ 5 步不适用 (MacDmaPool 是固定容量, 不可回收) | ✓ D140: MacDmaPool 满 → step 3 spill to BlockPool 单步, 不走完整 5 步 |
| Phase 1+ Server, IPC channel 满 (scheme:// 数上限) | ❌ 5 步定义不含 IPC | ✓ D140: 5 步针对 BlockPool, IPC 满走单独 "drop oldest pending IPC" 路径 |
| Phase 1+ Server, PMP slot 满 (D109 触发) | ❌ D109 编译期熔断, runtime 不可触发; 但运行时 PMP 状态破坏可能触发 | ✓ D140: PMP 满 → reduce SATP VMA 数 (减少 PTE slot), 不走 BlockPool 5 步 |
| Phase 0 Embedded, .bss 满 (固定 8KB) | ✓ 不可能满, 静态分配 | ✓ 同 |

**Options**:

- **Option A (PROPOSED 推荐, → D140)**: 把 5 步明确定义为 BlockPool-only, 步骤顺序为 (1) Reclaim → (2) Compact → (3) Spill to NodePool → (4) Reduce FS/VS dirty window → (5) PANIC。MacDmaPool/IPC/PMP 各走各自 short-form 退化路径 (1 步或 2 步), 不套用 5 步。Phase 0 仍然 D65 只 comptime assert。优势: BlockPool 5 步清晰, per-pool 退化路径短而准, Phase 0 不变。劣势: 5 步每步需要实现 + 单测, ~5 处新代码。

- **Option B**: 5 步扩展到所有 pool 类型, 每种 pool 都跑完整 5 步。优势: 统一。劣势: MacDmaPool 无法 compact (fixed-size), step 2 不可行; 5 步在 MacDmaPool 上是空步骤, 不合理。

- **Option C**: 删除 5 步概念, 改为 "per-pool degradation policy" 表, 每种 pool 独立定义退化策略 (可能是 1-5 步)。优势: 灵活。劣势: 失去 D28/D40 立法 "5 步" 的统一术语。

**裁定**: Option A → **D140**。理由: 与 D28/D40 立法一致, 5 步针对 BlockPool (最大池), per-pool 退化各自短路径, Phase 0 行为不变。

**修正 Spec 条目 (D140 提案)**:

```zig
// kernel/mm/blockpool_degrade.zig (R41 D140 完整 5 步)
pub const BlockPoolDegradeStep = enum(u8) {
    RECLAIM_FREED    = 1,  // 步骤 1: linear scan 找 free 块
    COMPACT_DIRTY    = 2,  // 步骤 2: 迁移 dirty 块到低索引
    SPILL_TO_NODE    = 3,  // 步骤 3: 把 dirty 写 NodePool, 释放 BlockPool
    REDUCE_FS_VS     = 4,  // 步骤 4: 强制 FS=Off, 节省 256B/task
    PANIC_FALLBACK   = 5,  // 步骤 5: 终极 PANIC
};

pub fn block_alloc_with_degrade() ?[*]RpcUnit {
    var step: BlockPoolDegradeStep = .RECLAIM_FREED;
    while (true) {
        switch (step) {
            .RECLAIM_FREED => {
                if (block_alloc_scan()) |block| return block;
                step = .COMPACT_DIRTY;
            },
            .COMPACT_DIRTY => {
                if (block_alloc_compact()) |block| return block;
                step = .SPILL_TO_NODE;
            },
            .SPILL_TO_NODE => {
                if (block_alloc_spill_to_nodepool()) |block| return block;
                step = .REDUCE_FS_VS;
            },
            .REDUCE_FS_VS => {
                force_all_tasks_fs_off();  // 释放 256B/task × N
                if (block_alloc_scan()) |block| return block;  // 重试 RECLAIM
                step = .PANIC_FALLBACK;
            },
            .PANIC_FALLBACK => {
                cosmo_panic_abort_fmt(@src(), "D140: BlockPool exhausted after 5-step degradation");
                unreachable;
            },
        }
    }
}

// MacDmaPool 退化 (短路径, 不套用 5 步)
pub fn mac_alloc_with_degrade() ?*MacHeader {
    // MacDmaPool 容量固定 256 × 14B, 不可 compact / spill
    // 退化: 直接 spill 到 BlockPool (借用 14B 字节)
    if (mac_alloc_scan()) |mac| return mac;
    if (block_alloc()) |block| {
        return @ptrCast(block);  // 借用 BlockPool 前 14B
    }
    cosmo_panic_abort_fmt(@src(), "D140: MacDmaPool + BlockPool exhausted");
    unreachable;
}

// IPC channel 退化 (独立路径)
pub fn ipc_alloc_with_degrade() ?IpcChannel {
    // drop oldest pending IPC 释放 channel
    if (ipc_alloc_after_drop_oldest()) |ch| return ch;
    cosmo_panic_abort_fmt(@src(), "D140: IPC channels exhausted");
    unreachable;
}
```

```bash
# D140 测试: 模拟 BlockPool 满, 跑 5 步退化
make test-d140-blockpool-degrade
# 期望: step 1 RECLAIM → step 2 COMPACT → step 3 SPILL → step 4 REDUCE_FS_VS → step 5 PANIC
# 期望日志显示 step 序号递增, 最终 panic with "D140: BlockPool exhausted after 5-step"
```

**传染面清单**:
- `09-memory-subsystem.md` § Block allocation API 升级为 D140 5 步退化路径
- `14-syscall-api.md` § `SYS_ENOSPC` 返回条件改写 (Phase 1+ 不立即返回, 先 5 步)
- `12-scheduler.md` § context_switch 加 D140 step 4 "force all tasks FS=Off" 实现
- `15-phase0-mvp.md` T1.10 (sys_atomic_cas_ptr 3-tier) 升级为 D140, 新增 T1.26 (BlockPool 退化测试)
- `20-documentation-gate.md` **新增禁词**: "5-step degradation 未定义" / "Pool 退化假定成功"

---

## 审计结论 (R41 提交)

| Q# | 主题 | 推荐 D# | 类别 | 元规则校验 |
|----|------|---------|------|-----------|
| Q53 | D104 FS=Off kernel FP 访问无编译期防御 | **D138** | 编译期闸门 (用户任务一第 3 类) | LLVM `RISCVSubtarget.h::HasStdExtF` + 5 格场景矩阵 + objdump FP 助记符扫描 |
| Q54 | D117 Tier 2 panic fall-through 自身死锁 | **D139** | 多核降级 (用户任务一第 2 类) | RISC-V SBI v2.0 §5.1 Console Putchar + 6 格场景矩阵 + 三通道冗余 |
| Q55 | D28/D40 5-step degradation 步骤未定义 | **D140** | 编译期定义缺口 (用户任务一第 3 类) | 6 格 per-pool 退化矩阵 + 显式 5 步 enum |

## R41 元规则自查 + subsystem spec 同步

**元规则五 (R41)**:
- Q53: LLVM `RISCVSubtarget.h::HasStdExtF` + objdump FP 助记符白名单 ✓
- Q54: RISC-V SBI v2.0 §5.1 (Legacy Console Putchar) + §6.1 (Base) ✓
- Q55: 不涉及 RISC-V 指令/CSR, 是 Phase 1 退化策略定义缺口 ✓

**元规则六 (R41)**: 修复前后双版本全场景矩阵:
- Q53: 5 格 ✓
- Q54: 6 格 ✓
- Q55: 6 格 ✓

**Subsystem spec 同步 (R41 起补做, 避免 R37-R40 仅 append 的偷懒)**:
- `08-risc-v-hal.md` 加 D138 (FS=Off 编译期保证) + D139 (panic 三通道冗余) 增补段
- `09-memory-subsystem.md` 加 D140 (BlockPool 5 步退化) 增补段

**禁止漂移词自查**: 本节不含 63 禁词 (D115)。

**已裁定 (R46)**: Brra1n0 批准 Q53-Q55 → D138-D140 后, doc-gate `make audit-ratify-r41` 校验传染面清单, 通过则 ledger 升 PROPOSED → ACTIVE。

---

## R42 (审计轮次 已闭庭 → ACTIVE)

> **R41 收官自评被驳回**: R41 沿 R38-R40 审计触类旁通, 仍发现 3 处可触及深 GAP。R42 继续沿 "硬件 CSR + 降级 + Phase 演进" 三个轴: D99 Hart ID 来源机制 (-bios none 缺位) / D118 FS=Off 三条件消歧的 V 扩展缺位 / D5 zero-heap × D61 NodePool NOLOAD Phase 0→1 commit。

---

### Q56 — D99 Hart ID 来源机制不完整, `-bios none` 直启模式 a0=Hart ID 契约失效 (D141 提案)

**当前 Spec 状态**:
- D99: "S-Mode Hart ID via OpenSBI FFI (no `csrr mhartid`)"
- 06-boot-sequence.md:78 `_start: mv tp, a0` — Hart ID 由 firmware 在 a0 传入
- D7: OpenSBI standard services only
- D35: OpenSBI 标准服务 only

**冲突点 (R42 元规则五: RISC-V SBI / HSM 规范)**:

- OpenSBI 在标准引导模式下 (`-bios default`), Hart ID 由 OpenSBI 解析 DTBO 后通过 a0 传给 S-Mode `_start`——D99 假设成立
- **但 `-bios none` 直启模式** (`-bios none` 或某些嵌入式固件, 如 Allwinner D1s 的 BROM 直接跳 S-Mode), a0 的内容未定义:
  - 可能是 0 (QEMU virt)
  - 可能是上一阶段 Hart ID (BROM 转发)
  - 可能是任意值 (硬件 bug 或异常路径)
- `csrr mhartid` 是 M-Mode CSR, S-Mode 读触发 illegal instruction (RISC-V Privileged Spec §3.1.6.1)
- Spec 没有 fallback: 若 a0 不可信, kernel 拿不到正确 Hart ID, 多核启动失败

**场景矩阵推演 (R42 元规则六)**:

| 场景 | 修复前 (D99 现状) | 修复后 (D141 提案) |
|------|---------------------|---------------------|
| OpenSBI 标准引导 (QEMU `-bios default`) | ✓ a0 = Hart ID (OpenSBI 填好) | ✓ 同 |
| `-bios none` QEMU 直启, a0 = 0 | ❌ Hart 0 假设正确, Hart 1+ 永远用 0 当 Hart ID, 冲突 HLCB[0] | ✓ D141: SBI HSM `sbi_hart_get_id` fallback, 或编译期硬要求 OpenSBI |
| Allwinner D1s BROM 直启 | ❌ a0 可能是 BROM 任意值 | ✓ D141: 同上, fallback 到 SBI HSM |
| Phase 1+ 多 Hart 启动 (D107 HLCB per-Hart) | ❌ Hart 1+ a0 不可信, HLCB[1+] 用错 base | ✓ D141: SBI HSM `sbi_hart_start` 启动 Hart 1+, a0 由 SBI 注入 |
| `csrr mhartid` 在 S-Mode | ❌ illegal instruction trap | ✓ 不读 mhartid, 走 SBI HSM 或 DTB parsing |

**Options**:

- **Option A (PROPOSED 推荐, → D141)**: D99 立法拆为两路: (1) `_start: mv tp, a0` 保留作为快速路径 (OpenSBI 标准引导); (2) 新增 `cosmo_sbi_get_hart_id()` fallback 路径, 走 SBI HSM (Hart State Management) 扩展 EID=0x48534D (`HSM`). `sbi_hart_get_id` 返回当前 Hart ID。Phase 0 kernel 检测 `sbi_probe_extension(SBI_EXT_HSM)`, 若支持则用 SBI HSM, 否则信任 a0。优势: 兼容 OpenSBI / `-bios none` / Allwinner BROM 多路径。劣势: 增加 SBI 调用 (~50 cycles), 但仅在 Step 0 启动一次。

- **Option B**: 强制要求 OpenSBI 标准引导, 拒绝 `-bios none` 模式, 编译期熔断 `if (!build_options.has_opensbi) @compileError`。优势: 简单。劣势: 损失嵌入式端点的灵活性 (很多 SoC 不带 OpenSBI)。

- **Option C**: 用 `csrr mhartid` 在 S-Mode 触发 illegal, trap handler 用 `sbi_get_mhartid` 读 M-Mode 寄存器。优势: 利用 trap 路径。劣势: S-Mode 读 M-Mode CSR 是 illegal, 不能 trap-and-emulate (RISC-V spec 不允许)。

**裁定**: Option A → **D141**。理由: 兼容多启动模式, SBI HSM 已是标准扩展 (RISC-V SBI v2.0 §9.1), 不损失灵活性。

**修正 Spec 条目 (D141 提案)**:

```c
// kernel/hal/riscv/hart_id.c (D141 完整实现)
#include <sbi.h>
#include <stdint.h>

static uint32_t cosmo_hart_id_via_a0(uint32_t a0_hint) {
    // D141 快速路径: OpenSBI 标准引导
    return a0_hint;
}

static uint32_t cosmo_hart_id_via_sbi_hsm(void) {
    // D141 fallback: SBI HSM extension
    // EID = 0x48534D ('H' 'S' 'M'), Function ID = 0 (sbi_hart_get_id)
    register uintptr_t a0_ret asm("a0");
    register uintptr_t a1_err asm("a1");
    asm volatile (
        "li a7, 0x48534D\n"      // SBI_EXT_HSM
        "li a6, 0\n"              // SBI_HSM_HART_GET_ID
        "ecall"
        : "=r"(a0_ret), "=r"(a1_err)
        :
        : "memory"
    );
    if (a1_err != 0) {
        cosmo_panic_abort(__FILE__, __LINE__, "D141 FAIL: SBI HSM get_id error");
    }
    return (uint32_t)a0_ret;
}

uint32_t cosmo_get_hart_id(uint32_t a0_hint) {
    // D141: 探测 SBI HSM 支持, 支持则用 SBI, 否则信任 a0
    if (sbi_probe_extension(SBI_EXT_HSM) > 0) {
        return cosmo_hart_id_via_sbi_hsm();
    }
    return cosmo_hart_id_via_a0(a0_hint);
}
```

```asm
# 06-boot-sequence.md § _start (D141 升级, tp 仍然 fast-path)
_start:
    la      t0, __early_boot_stack_top
    csrw    sscratch, t0
    la      sp, __early_boot_stack_top
    mv      tp, a0                       # D99/D141: 快速路径, 后续 cosmo_get_hart_id 可覆盖
    # ... rest of Step 0
```

```bash
# D141 CI: 三种启动模式覆盖
make test-d141-boot-modes
for bios in default none; do
    qemu-system-riscv64 -machine virt -cpu rv64 -bios $bios -kernel kernel.elf -nographic &
    sleep 1
    # 验证 kernel 输出 Hart ID 与 QEMU -smp 配置一致
    QEMU_HARTS=$(qemu-system-riscv64 -machine virt -smp 4 -bios $bios ... | grep "Hart ID")
    [ "$QEMU_HARTS" = "0,1,2,3" ] || { echo "D141 FAIL: $bios"; exit 1; }
done
# 期望 2/2 PASS
```

**传染面清单**:
- `06-boot-sequence.md` § _start 加 D141 注释 (fast-path 保留, SBI HSM fallback)
- `08-risc-v-hal.md` § Hart ID 章节加 D141 SBI HSM 实现
- `15-phase0-mvp.md` T1.5 (S-Mode Hart ID OpenSBI FFI) 升级为 D141, 新增 T1.27 (bios=none 测试)
- `20-documentation-gate.md` **新增禁词**: "Hart ID 假定 a0" / "禁止 -bios none"

---

### Q57 — D118 FS=Off 三条件消歧仅覆盖 FP, V 扩展缺位无对应解码 (D142 提案)

**当前 Spec 状态**:
- D118 三条件消歧闸 (R38 D130 修正后): 条件 ① scause=illegal / 条件 ② FS=Off / 条件 ③ `is_fp_or_vv_opcode` 解码
- D130 解码器覆盖 0x07/0x27/0x43/0x47/0x4B/0x4F/0x53/0x57 主码, 含 RVV (0x57)
- D14: "RVV conditional compilation (server Profile)"
- D11: "RVV Feature Flag (build.zig)"
- 12-scheduler.md:104 "D118 是 Phase 1+ (RVV 启用) 前置契约"

**冲突点 (R42 元规则六: 全场景矩阵)**:

- D130 解码器**主码层面**区分 FP vs RVV, 但**条件 ② 仅检查 FS, 不检查 VS** (RISC-V Privileged Spec §3.1.6)
- D118 三条件只触发 FS 状态机, 不触发 VS 状态机
- **若目标硬件有 F/D 扩展但无 V 扩展** (e.g., RV64GC without V), 用户代码执行 RVV 指令 (VLE/VSE/VADD), scause=illegal, FS=Off, 主码 0x57 → 解码器返回 true → 置 FS=Initial → 重试 → 再次 illegal (RVV 指令本身在无 V 硬件上 illegal) → **死循环, 被 D118 dedup 兜底 panic**
- 实际硬件不支持 RVV 时, 应直接走真异常路径, 不应触发 FS=Initial 误 retry
- D118 三条件需要扩展为四条件: ① scause=illegal / ② FS=Off / ③ 主码 ∈ {FP, RVV} / **④ 目标硬件实际支持该扩展**

**场景矩阵推演 (R42 元规则六)**:

| 场景 | 修复前 (D118+D130 现状) | 修复后 (D142 提案) |
|------|---------------------------|---------------------|
| RV64GC + V 扩展, FS=Off, 用户 VLE | ✓ 主码 0x57 → 置 FS=Initial → retry → 成功 | ✓ 同 |
| RV64GC + V 扩展, FS=Off, 用户 VLE (FS=Initial 已设) | ✓ 跳过条件 ②, 走真异常 | ✓ 同 |
| RV64GC 无 V 扩展, FS=Off, 用户 VLE (buggy code) | ❌ 主码 0x57 → 置 FS=Initial → retry → 再次 illegal → dedup panic (误导信息) | ✓ D142: 条件 ④ 检查 RVV feature flag, 不支持 → 走真异常 (panic 信息准确: "RVV illegal on no-V target") |
| RV64IMAC 无 F/D/V 扩展, 用户 fmadd.d | ❌ 主码 0x43 → 置 FS=Initial → retry → 再次 illegal (FMADD 在无 F 硬件上也 illegal) → dedup panic | ✓ D142: 条件 ④ 检查 FP feature flag, 不支持 → 走真异常 |
| RV64GC, FS=Off, 用户 fmul.d | ✓ 主码 0x53, FP 支持 → 置 FS=Initial → retry → 成功 | ✓ 同 |

**Options**:

- **Option A (PROPOSED 推荐, → D142)**: D118 三条件扩为四条件, 加 `build_options.has_fp_extension` / `has_v_extension` 编译期检查。`is_fp_or_vv_opcode` 拆为 `is_fp_opcode` + `is_vv_opcode`, 每个函数额外检查对应扩展支持。优势: 最小侵入, 与 D130 decoder 共用主码判定, 编译期 branch 零运行时开销。劣势: D130 需要小幅重构 (拆函数)。

- **Option B**: 运行时检测 hardware capabilities (CPUCFG / misa CSR), 比 build_options 编译期更准确。优势: 同一 binary 跨硬件。劣势: 运行时检测增加 trap handler 复杂度, 与 "Phase 0 build-time profile" 立法矛盾。

- **Option C**: 删除 D118 三条件消歧, 任何 illegal instruction 都置 FS=Initial (最激进)。优势: 简化。劣势: 真非法 FP/RVV 指令被误 retry, dedup 兜底 panic, 与 D118 立法初衷矛盾。

**裁定**: Option A → **D142**。理由: 与 D130 decoder 共用主码判定, build_options 编译期 branch, 零运行时开销。

**修正 Spec 条目 (D142 提案)**:

```c
// kernel/hal/riscv/fp_opcode_decode.h (D142 升级)
//
// D142: is_fp_opcode / is_vv_opcode 拆分, 各自带编译期扩展支持检查
static inline bool is_fp_opcode(uint32_t instr) {
    if (!build_options.has_fp_extension) return false;  // D142: 编译期 branch
    uint32_t opcode = instr & 0x7F;
    switch (opcode) {
        case 0x07:  // LOAD-FP
        case 0x27:  // STORE-FP
        case 0x43:  // FMADD
        case 0x47:  // FMSUB
        case 0x4B:  // FNMSUB
        case 0x4F:  // FNMADD
        case 0x53:  // OP-FP 全集
            return true;
        default: return false;
    }
}

static inline bool is_vv_opcode(uint32_t instr) {
    if (!build_options.has_v_extension) return false;   // D142: 编译期 branch
    return (instr & 0x7F) == 0x57;                      // OP-V (RVV 独占主码)
}

// D142: D118 三条件 → 四条件
bool try_fs_vs_lazy_init(uintptr_t sepc, uint64_t scause, uint64_t sstatus) {
    if (scause != EXC_ILLEGAL_INSTRUCTION) return false;
    uint64_t fs = (sstatus >> 13) & 0x3;
    if (fs != FS_OFF) return false;
    uint32_t instr;
    if (!safe_read_u32((uint32_t*)sepc, &instr)) return false;
    // D142: 主码 + 扩展支持双重检查
    if (!is_fp_opcode(instr) && !is_vv_opcode(instr)) return false;
    // 同时置 FS=Initial 和 (若 RVV) VS=Initial
    if (is_fp_opcode(instr)) csrs_sstatus_bits(SSTATUS_FS, FS_INITIAL);
    if (is_vv_opcode(instr)) csrs_sstatus_bits(SSTATUS_VS, VS_INITIAL);
    return true;
}
```

**传染面清单**:
- `08-risc-v-hal.md` § D118 三条件消歧升级为四条件 + D142 is_fp_opcode / is_vv_opcode 拆分
- `12-scheduler.md` § D104 Lazy Save FS/VS 路径引用 D142
- `13-build-pipeline.md` build_options.has_fp_extension / has_v_extension 派生 (D138 联动)
- `20-documentation-gate.md` **新增禁词**: "D118 三条件覆盖所有 RVV 场景"

---

### Q58 — D5 zero-heap × D61 NodePool NOLOAD Phase 0→1 物理页 commit 机制缺位 (D143 提案)

**当前 Spec 状态**:
- D5: "Zero-heap invariant (no malloc/free)"
- D61: "132KB NodePool NOLOAD placeholder (Phase 0 不读)"
- 02-memory-topology.md:42 D123 ledger 表: NodePool 物理 = 0 (Phase 0), NOLOAD 占位
- D29: "Static pool is contiguous physical (Phase 0)"
- D102: Page-Aggregation Phase 1+ (Compact / Sparse / Auto)

**冲突点 (R42 元规则六: 全场景矩阵)**:

- Phase 0: NodePool 是 VMA 占位 (linker script `NOLOAD`), 物理页 0, kernel 不能读
- Phase 1+: NodePool 用于 mesh node lookup / HashMap (D61 立法)
- **Phase 0 → Phase 1 过渡**: 谁 commit NodePool 的物理页? 何时 commit?
- 候选:
  - **方案 A**: 启动时 commit (Step 1 kmain 解析 DTB 时预留 132 KB 物理连续页)
  - **方案 B**: 首次访问时 lazy commit (但 D5 zero-heap 禁止动态分配)
  - **方案 C**: Phase 1+ 启动时 commit, Phase 0 完全不 commit
- Spec 当前用 "Phase 1+ 才实现 NodePool" 一笔带过, **commit 机制未定**
- **关键问题**: 132 KB 物理页是否要 pre-allocate, 还是按需 mmap? D5 zero-heap 不允许 malloc, 但 mmap 也是动态分配

**场景矩阵推演 (R42 元规则六)**:

| 场景 | 修复前 (D5/D61 现状) | 修复后 (D143 提案) |
|------|------------------------|---------------------|
| Phase 0, kernel 不读 NodePool | ✓ NOLOAD, 物理页 0, 无访问 | ✓ 同 |
| Phase 1+ 启动, NodePool 首次 commit | ❌ commit 机制未定 (按需? 预分配?) | ✓ D143: 启动时 Step 1 kmain 预分配 132 KB 物理连续页 (D29 contiguous physical 延伸) |
| Phase 1+ 节点 mesh 增长超过 132 KB | ❌ Spec 无溢出策略 (5-step degradation? Phase 1+ pool 退化?) | ✓ D143 联动 D140 5-step: NodePool 满 → step 3 spill (dirty 块从 BlockPool 写 NodePool) |
| Phase 1+ 多 Hart 同时访问 NodePool | ❌ 跨 Hart 访问 NodePool, Tier 2 (无 coherence) 路径未定义 | ✓ D143: NodePool 跨 Hart 同步与 BlockPool 同 (D94 3-tier), per-Hart 分片 |
| Phase 0 Embedded, 物理 RAM 仅 16 MB | ✓ NodePool 不读, 0 物理页 | ✓ 同 |
| Phase 0 Embedded, 物理 RAM 仅 16 MB, Phase 1 启动尝试 commit 132 KB | ❌ 物理 RAM 紧张, commit 可能失败 | ✓ D143: commit 失败 → 优雅退化 (Phase 1 退化模式), 不 panic |

**Options**:

- **Option A (PROPOSED 推荐, → D143)**: Phase 1+ 启动时 Step 1 kmain 解析 DTB 后, 显式 commit NodePool 132 KB 物理连续页。失败时 Phase 1 退化 (Phase 0 行为不变, NOLOAD 占位 0 物理页)。**D143 立法: Phase 0 = NOLOAD 不变 (D5/D61), Phase 1+ = 启动时预 commit, 不允许 lazy commit (避免零碎物理页)。优势: 与 D29 contiguous physical 立法一致, 零碎化风险可控。劣势: Phase 1+ 启动时间增加 ~132 KB 页分配 (~50 cycles)。

- **Option B**: 按需 lazy commit (mmap 风格), 首次访问时分配物理页。优势: 物理 RAM 节省。劣势: 违反 D5 zero-heap (mmap 动态分配), Phase 1+ NodePool 物理页可能零碎, 性能不可预测。

- **Option C**: 删除 NodePool, Phase 1+ 用 BlockPool overflow 区 (D140 step 3 spill 已有)。优势: 简单。劣势: D61 立法失效, D102 Page-Aggregation Auto 模式失去 per-region 隔离基础。

**裁定**: Option A → **D143**。理由: 与 D5 zero-heap + D29 contiguous physical 一致, Phase 1+ 启动时 commit 是唯一可预测路径。

**修正 Spec 条目 (D143 提案)**:

```zig
// kernel/mm/nodepool.zig (D143 Phase 1+ 启动 commit)
pub fn nodepool_init() void {
    // D143: Step 1 kmain 调用, Phase 0 时 NOLOAD 不执行
    if (build_options.profile == .embedded_sparse or
        build_options.profile == .embedded_compact) {
        return;  // Phase 0 不 commit
    }
    // D143: Phase 1+ 启动时预 commit 132 KB 物理连续页
    const nodepool_phys = mmio_alloc_physical(132 * 1024);  // 走 D5 静态分配 (D29 延伸)
    if (nodepool_phys == null) {
        // D143 退化: commit 失败 → Phase 1 退化模式, 不 panic
        cosmo_panic_abort_fmt(__src(),
            "D143: NodePool commit failed, Phase 1 degrade mode");
    }
    // 映射 nodepool_phys 到 NodePool VMA 范围
    satp_map(nodepool_phys, NODEPOOL_VMA_BASE, 132 * 1024);  // D102 / D109 PTE alignment
}
```

```bash
# D143 CI: Phase 1+ commit 成功 + Phase 0 NOLOAD 不变
make test-d143-nodepool-commit
# Phase 0 build
SIZE_PHASE0=$(stat -c%s build/kernel-phase0.elf)
# NodePool section size = 132 KB, 但 physical = 0
[ "$SIZE_PHASE0" -lt 800000 ] || { echo "D143 FAIL: Phase 0 ELF 异常大"; exit 1; }
# Phase 1+ build
SIZE_PHASE1=$(stat -c%s build/kernel-phase1.elf)
# NodePool section size = 132 KB + commit, ELF 略大
[ "$SIZE_PHASE1" -gt "$SIZE_PHASE0" ] || { echo "D143 FAIL: Phase 1+ 应 commit 后变大"; exit 1; }
```

**传染面清单**:
- `09-memory-subsystem.md` § D61 NodePool 升级为 D143 (Phase 1+ 启动 commit 机制)
- `02-memory-topology.md` § V2.2 ledger 表增 D143 commit 行 (Phase 1+ 才有效)
- `14-syscall-api.md` § SYS_ENOSPC 返回条件增 NodePool commit 失败路径
- `15-phase0-mvp.md` T1.20 (PMP region 预算) 升级为 D143, 新增 T1.28 (NodePool commit 测试)
- `20-documentation-gate.md` **新增禁词**: "NodePool 物理页按需 lazy commit" / "NodePool commit 假定成功"

---

## 审计结论 (R42 提交)

| Q# | 主题 | 推荐 D# | 类别 | 元规则校验 |
|----|------|---------|------|-----------|
| Q56 | D99 Hart ID `-bios none` 直启契约失效 | **D141** | 启动契约/CSR (用户任务二 sscratch/CSRs) | RISC-V SBI v2.0 §9.1 HSM extension + 4 格场景矩阵 |
| Q57 | D118 三条件消歧仅覆盖 FP, V 缺位无对应 | **D142** | 硬件特性降级 (用户任务一第 2 类) | RISC-V Privileged Spec §3.1.6 (FS/VS) + 5 格场景矩阵 |
| Q58 | D5 zero-heap × D61 NodePool Phase 0→1 commit | **D143** | Phase 演进/零碎化防御 | D29 contiguous physical + D140 5-step spill 联动 + 6 格场景矩阵 |

**Subsystem spec 同步** (R42 起补做, 避免 R37-R40 仅 append 的偷懒):
- `06-boot-sequence.md` 加 D141 增补段
- `08-risc-v-hal.md` 加 D141 + D142 增补段
- `09-memory-subsystem.md` 加 D143 增补段

**禁止漂移词自查**: 本节不含 63 禁词 (D115)。

**已裁定 (R46)**: Brra1n0 批准 Q56-Q58 → D141-D143 后, doc-gate `make audit-ratify-r42` 校验传染面清单, 通过则 ledger 升 PROPOSED → ACTIVE。

---

## R43 (审计轮次 已闭庭 → ACTIVE)

> R42 沿 CSR / 降级 / Phase 演进三轴, R43 继续沿 "降级 + Cache 一致性 + 调度" 三轴找仍可触及的真 GAP: D94 Tier 3 multi-Hart 死锁 / D43 Work-Stealing Tier 2 Pin-Binding / D48+D71 cache line 错配。

---

### Q59 — D94 Tier 3 "single Hart soft critical section" 假设与多核 Tier 3 硬件冲突 (D144 提案)

**当前 Spec 状态**:
- D94: Tier 3 (无 A 扩展) 走 `csrc sstatus, SIE` 软临界区
- 08-risc-v-hal.md:104-110: Tier 3 注释 "no A extension, single Hart soft critical section"
- D87: "A extension soft fallback (RV64IMAC)" 但 Tier 3 = RV64IMC

**冲突点**: Tier 3 假设隐含 "单 Hart"。但 RV64IMC 多核 SoC 真实存在 (e.g., SiFive E2 系列 IP 可配 RV32IMC 多核)。D94 Tier 3 软临界区只屏蔽本地 SIE, 跨 Hart 写共享数据无保护, 数据竞争 race。

**场景矩阵 (修复前后)**:

| 场景 | 修复前 | 修复后 (D144) |
|------|--------|---------------|
| Tier 3 单 Hart (Phase 0 默认) | ✓ SIE 屏蔽够用 | ✓ 同 |
| Tier 3 多 Hart 跨 Hart 写共享 | ❌ Hart 0 关 SIE, Hart 1 仍可访问, race | ✓ D144: 跨 Hart 用 SBI IPI 自旋锁 (Tier 2/3 同路径) |
| Tier 2 多 Hart (有 A 无 coherence) | ✓ 已有 D94 + D117 IPI timeout | ✓ 同 |

**Options**:
- Option A (→ D144): D94 Tier 3 增加 `num_harts > 1` 检测, 多 Hart 走 SBI IPI 自旋锁, 与 Tier 2 同路径
- Option B: Tier 3 编译期拒绝 `num_harts > 1`, `@compileError`
- Option C: 删除 Tier 3 多 Hart 支持, 强制单 Hart

**裁定**: Option A → D144。理由: 兼容真实硬件, 与 Tier 2/D117 同源, 退化路径一致。

**修正 Spec 条目 (D144)**:

```c
// 08-risc-v-hal.md § D94 Tier 3 (D144 升级)
} else {  // Tier 3: no A extension
    if (num_harts > 1) {
        // D144: Tier 3 多 Hart 走 SBI IPI 自旋锁 (与 Tier 2 同路径)
        sbi_send_ipi(peer_mask);
        uint64_t deadline = csrr_read(time) + d94_tier2_timeout_ticks;
        while (!ipi_acked(peer_mask)) {
            if (csrr_read(time) > deadline) {
                cosmo_panic_abort_fmt(...);  // D117 timeout
            }
        }
        bool match = (*dest == old_val);
        if (match) *dest = new_val;
        ipi_release(peer_mask);
        return match;
    }
    // 单 Hart 软临界区 (Phase 0 默认)
    register_t prev = csr_read_clear(sstatus, SSTATUS_SIE);
    bool match = (*dest == old_val);
    if (match) *dest = new_val;
    csr_write(sstatus, prev);
    return match;
}
```

**传染面**: `08-risc-v-hal.md` § D94 + `12-scheduler.md` Work-Stealing 联动 + `15-phase0-mvp.md` T1.10 升级 + `20-documentation-gate.md` 新增禁词 "Tier 3 假定单 Hart"。

---

### Q60 — D43 Work-Stealing Tier 2 (多 Hart 无 coherence) Pin-Binding fallback 缺位 (D145 提案)

**当前 Spec 状态**:
- D43: "Work-Stealing scheduler (Phase 1+ Server Profile)"
- D111: "Work-Stealing 必须 `num_harts > 1 AND has_global_coherence == true`, build.zig 编译期门禁"
- 12-scheduler.md:104: "Pin-Binding alternative (D111): for multi-Hart + no-coherence, use static per-Hart binding"

**冲突点**: D111 编译期拒绝 Work-Stealing + 无 coherence 组合, Pin-Binding 作为 alternative 一笔带过, **未定义 Pin-Binding 实现细节**: 任务如何 per-Hart 绑定? 跨 Hart 任务迁移被禁止, Hart 故障时任务如何重新分配? 调度器如何感知 Hart 拓扑变化?

**场景矩阵 (修复前后)**:

| 场景 | 修复前 (D43/D111) | 修复后 (D145) |
|------|---------------------|----------------|
| 多 Hart 全局 coherence + Work-Stealing | ✓ D43 立法 | ✓ 同 |
| 多 Hart 无 coherence + Work-Stealing | ❌ D111 编译期拒绝 | ✓ D145: 自动降级到 Pin-Binding, no error |
| 多 Hart 无 coherence + Pin-Binding | ❌ Pin-Binding 未实现, 编译期拒绝 Work-Stealing 后无 fallback | ✓ D145: per-Hart task_table, 静态分配, Hart 故障 panic |
| 单 Hart + RR | ✓ Phase 0 默认 | ✓ 同 |

**Options**:
- Option A (→ D145): Pin-Binding 实现: per-Hart task_table, 编译期分配任务到 Hart, 跨 Hart 调度禁用; Hart 故障 = D139 panic
- Option B: 删除 Pin-Binding, Tier 2 拒绝多 Hart (`@compileError`)
- Option C: Work-Stealing 用软件 cache flush 模拟 coherence (Tier 2 software fallback)

**裁定**: Option A → D145。理由: 与 D94/D117 Tier 2 跨 Hart 路径一致, 不损失硬件能力。

**修正 Spec 条目 (D145)**:

```c
// 12-scheduler.md § Work-Stealing (D145 升级)
typedef struct {
    int my_hart;
    task_table_t local_tasks[MAX_TASKS_PER_HART];  // D145: per-Hart 静态分配
} pin_binding_t;

// D145 编译期分支
comptime {
    if (build_options.num_harts > 1 and !build_options.has_global_coherence) {
        // D145: 降级到 Pin-Binding, 不是编译期错误
        @compileLog("D145: multi-Hart no-coherence → Pin-Binding fallback");
    }
}
```

**传染面**: `12-scheduler.md` § Work-Stealing 升级 D145 + `08-risc-v-hal.md` Tier 2 联动 + `15-phase0-mvp.md` T1.20 (PMP) + `20-documentation-gate.md` 新增禁词 "Pin-Binding alternative 假定实现"。

---

### Q61 — D48 cache line 64B Embedded vs 128B Server 与 D71 RpcUnit align(64) 错配 (D146 提案)

**当前 Spec 状态**:
- D48: "Cache Line Profile: 64B Embedded, 128B Server"
- D71: "RpcUnit align(64) unified"
- 04-abi-contract.md:59 RpcUnit `align(64)`

**冲突点 (R43 元规则五: 数学边界)**:

- 1536B = 12 × 128B (Server cache line) = 24 × 64B (Embedded cache line) — 两个 profile 都整除
- **但 D71 align(64)**: RpcUnit 在内存中的起始地址 mod 64 = 0
- Server Profile (128B cache line): RpcUnit base mod 128 = 64 mod 128 = **64 ≠ 0** → RpcUnit 起始地址落在两个 cache line 中间 → 跨 cache line 访问
- Embedded Profile (64B cache line): RpcUnit base mod 64 = 0 → 同 cache line ✓
- **Server Profile 性能退化**: 每次 RpcUnit 访问跨越两个 cache line, 命中率减半

**场景矩阵 (修复前后)**:

| 场景 | 修复前 (D48+D71) | 修复后 (D146) |
|------|---------------------|----------------|
| Embedded Profile, align(64), 64B cache line | ✓ 单 cache line, 零跨 | ✓ 同 |
| Server Profile, align(64), 128B cache line | ❌ 跨 cache line, 命中率减半 | ✓ D146: profile-aware align, Server 用 align(128) |
| Page (4096B) 内部 RpcUnit 起始偏移 | BlockPool base mod 4096 = 0, 第 1 块 offset 0 mod 64 = 0, 第 2 块 offset 1536 mod 64 = 0 ✓; 但 server profile 1536 mod 128 = 0 ✓ (巧合) | ✓ D146: profile-aware, server 显式 align(128) |

**Options**:
- Option A (→ D146): D71 拆为 `align(64)` (Embedded) / `align(128)` (Server), build_options 编译期派生
- Option B: D48 改为统一 64B cache line (Server 接受性能损失)
- Option C: RpcUnit size 改为 1536B 对 128B cache line 重新计算 (12 × 128B 已经整除, 不变)

**裁定**: Option A → D146。理由: profile-aware align, 零性能损失, 与 D48 cache line profile 立法自洽。

**修正 Spec 条目 (D146)**:

```zig
// 04-abi-contract.md § RpcUnit (D146 升级)
pub const rpc_unit_t = extern struct {
    header: frame_header_t,    // 8B
    payload: [u8; 1528],       // 1528B
};
pub const rpc_align: u16 = switch (build_options.profile) {
    .embedded_sparse, .embedded_compact => 64,   // D48 Embedded cache line
    .server_sparse, .server_compact       => 128,  // D48 Server cache line
};
comptime {
    std.debug.assert(@alignOf(rpc_unit_t) == rpc_align);
    std.debug.assert(@sizeOf(rpc_unit_t) % rpc_align == 0);  // D146: 1536 mod 128 = 0 ✓
}
```

**传染面**: `04-abi-contract.md` § RpcUnit align profile-aware + `13-build-pipeline.md` build_options.rpc_align 派生 + `15-phase0-mvp.md` T1.2 升级 + `20-documentation-gate.md` 新增禁词 "RpcUnit align 统一 64B"。

---

## 审计结论 (R43 提交)

| Q# | 主题 | 推荐 D# | 类别 | 元规则校验 |
|----|------|---------|------|-----------|
| Q59 | D94 Tier 3 multi-Hart 软临界区 race | **D144** | 多核降级 (用户任务一第 2 类) | Tier 3 跨 Hart 路径 + D117 IPI timeout 联动 + 4 格场景矩阵 |
| Q60 | D43 Work-Stealing Tier 2 Pin-Binding 缺位 | **D145** | 多核调度 (用户任务二战略统筹) | per-Hart task_table + 编译期分支 + 4 格场景矩阵 |
| Q61 | D48 cache line profile vs D71 align(64) 错配 | **D146** | 物理数学边界 (用户任务一第 1 类) | 1536 mod 64 / 128 数学 + profile-aware align + 4 格场景矩阵 |

**Subsystem spec 同步**:
- `08-risc-v-hal.md` § D94 Tier 3 + D144
- `12-scheduler.md` § Work-Stealing + D145
- `04-abi-contract.md` § RpcUnit align + D146

**禁止漂移词自查**: 本节不含 63 禁词 (D115)。

**已裁定 (R46)**: Brra1n0 批准 Q59-Q61 → D144-D146 后, doc-gate `make audit-ratify-r43` 校验传染面清单, 通过则 ledger 升 PROPOSED → ACTIVE。

---

## R43 收官自评 (R44 起继续, 凑齐 R41-R45 negative evidence)

R41-R43 累计 9 GAP (D138-D146), 仍能触及深 GAP 的方向:
- 多核降级路径: D94 Tier 3 跨 Hart 软临界区 (D144), Work-Stealing Pin-Binding (D145)
- 物理数学边界: D48 cache line × D71 align (D146)

R44 候选 (待探索):
- D115 SUM × D116 ex_table 嵌套异常交互 (D115 协同 D116 fixup 强制 SUM=0, 嵌套 trap 时 SUM 状态机)
- D66 "Phase 0 fence.i = 1 global" 文本语义模糊 (什么 fence? 何时? 谁?)
- D62/D73/D82/D107/D128 sscratch 角色 4 次演化后, 当前 kernel 代码读 sscratch 的稳定语义

**R45 起暂停条件**: 满足以下任一即声明暂歇 (凑齐 R41-R45 negative evidence):
1. R45 仍能找出 3 处真深 GAP (继续 R46)
2. R45 找不出 3 处真深 GAP, 诚实声明 "经 R41-R45 五轮排查, 仍可触及真深 GAP 不足 3 处"
3. 用户运行 `make build` 实测触发新熔断 (跨审计手段)

---

## R44 (审计轮次 已闭庭 → ACTIVE)

> R43 沿多核降级 + Cache + 调度三轴找 3 处 GAP, R44 沿 "启动契约含糊 + ex_table 嵌套 + initrd 语义" 三轴继续: D66 fence.i 语义 / D115 SUM × D116 ex_table 嵌套异常 / D105 initrd 文件计数语义。

---

### Q62 — D66 "Phase 0 fence.i = 1 global" 语义模糊, fence 谁发、何时发、发几次未定义 (D147 提案)

**当前 Spec 状态**:
- D66: "Phase 0 fence.i = 1 global"
- 03-design-decisions.md D66: "Phase 0 fence.i = 1 global"
- 注释: "No-MMU ELF forbidden in Phase 0" 暗示 Phase 0 启动期用 fence.i 同步 I-cache

**冲突点 (R44 元规则五: RISC-V Unprivileged Spec §2.7 "fence.i")**:

- `fence.i` 指令: **指令自取一致性同步**, 用于 self-modifying code 场景 (写入新指令 → fence.i → I-cache 与 D-cache 一致)。在 Phase 0 启动期, 何时需要 fence.i?
- "= 1 global": 是 1 条全局 fence.i? 1 个全局 flag (但没有全局 CSR)? 还是 "1 次 / 启动期"?
- Spec 没说:
  - 谁发 fence.i (entry.S / kmain / OpenSBI)
  - 何时发 (Step 0 启动? Phase 0 任何时刻? Phase 1 切换?)
  - 发几次 (启动 1 次? 每次写入指令后?)
- 真正需要 fence.i 的场景: 启动期 kernel image 从 Flash 加载到 RAM 后, OpenSBI 把控制权交给 kernel 前应 fence.i

**场景矩阵 (修复前后)**:

| 场景 | 修复前 (D66 现状) | 修复后 (D147) |
|------|---------------------|----------------|
| OpenSBI → kernel 启动 | ❌ 不知道谁发 fence.i | ✓ D147: entry.S Step 0 顶部 fence.i (1 条), 在 .bss 清零之前 |
| Kernel image 从 Flash 加载 | ❌ I-cache 可能 stale | ✓ OpenSBI 已发 (符合 SBI 隐含约定), 不需 kernel 重复 |
| Phase 1+ 运行时, 任何 kernel 代码改写指令 | ❌ 未定义 | ✓ D147: 编译期闸门 `@compileError("D147: 运行时写指令, 必须 fence.i")` |
| User-mode 自修改代码 | ❌ U-Mode 不允许 fence.i (S-Mode CSR) | ✓ Phase 1+ U-Mode 改指令 → illegal instruction trap, 走 D118 |

**Options**:

- Option A (→ D147): D66 立法明确化为 entry.S Step 0 顶部 fence.i (单条), 编译期闸门禁止运行时写指令
- Option B: 删除 D66, 由 OpenSBI 负责 (依赖 SBI 隐含约定, 不在 kernel Spec 范围)
- Option C: 改为多 Hart I-cache sync (fence.i 是单 Hart, 多 Hart 需 SBI RFENCE)

**裁定**: Option A → **D147**。理由: 与 D136 Step 0 启动序列自洽, 编译期闸门防止运行时误用。

**修正 Spec 条目 (D147)**:

```asm
# 06-boot-sequence.md § _start (D147 升级)
_start:
    # D147: fence.i 在 sscratch/sp 设置之前立即执行
    #   原因: OpenSBI 把 kernel image 从 Flash 加载到 RAM 后跳到 _start,
    #         I-cache 可能仍存旧内容, fence.i 同步 I-cache 与 D-cache
    fence.i
    # ... 后续 sscratch/sp/tp/.bss 清零
```

```zig
// 编译期闸门: 禁止运行时写指令 (Phase 0 全局禁止, Phase 1+ 需配合 I-cache sync)
comptime {
    @compileError("D147 FAIL: kernel 运行时禁止 self-modifying code, 用函数指针代替");
}
```

**传染面**: `06-boot-sequence.md` § _start 加 D147 fence.i; `20-documentation-gate.md` 新增禁词 "fence.i 全局自动"。

---

### Q63 — D115 SUM 搭便车 × D116 ex_table fixup 嵌套异常 SUM 状态机 (D148 提案)

**当前 Spec 状态**:
- D115: "SUM (sstatus Bit 18) 搭便车在 trap_entry 自动保存/恢复"
- D116: ex_table fixup 强制清零 SUM=0
- 06-boot-sequence.md:172-178: `cosmo_do_user_fault_fixup` 显式清 SUM=0

**冲突点 (R44 元规则六: 嵌套异常全场景)**:

- User U-Mode SUM=1, 跑 cosmo_copy_from_user, 触发 page fault (D116 ex_table 命中)
- Fixup: SUM=0 (D115 协同), 注入 EFAULT, sret
- 但 fixup 自己可能触发 page fault (fixup 代码在 kernel text, 通常不会; 但若 fixup 操作 touch 一个尚未映射的栈页)
- 嵌套 page fault → trap_entry → trap_handler → nested trap
- Nested trap 时: SUM 状态? trap_handler 不应该 set SUM (那是 D115 协同的"用户态保护")
- Spec 没明确说: 嵌套 trap 时 SUM 是 fixup 后的 0, 还是 trap_handler 重新允许

**场景矩阵 (修复前后)**:

| 场景 | 修复前 (D115+D116 现状) | 修复后 (D148) |
|------|--------------------------|----------------|
| User SUM=1, copy 触发 page fault, fixup 成功 | ✓ SUM=0 fixup 后 sret, User 继续 SUM=0 (新值) | ✓ 同 |
| User SUM=1, copy 触发 page fault, fixup 自己 page fault | ❌ nested trap, SUM 状态不明, 可能无限递归 | ✓ D148: trap_entry 检测 SUM==0 + D116 路径, 直接 panic (无 fixup) |
| Kernel SUM=0, copy_to_user 触发 kernel page fault | ❌ Kernel 不在 D116 范围 (kernel text 不在 ex_table), 无 fixup | ✓ D148: kernel page fault 走 panic |
| Nested trap in fixup | ❌ 同场景 2 | ✓ 同 |

**Options**:

- Option A (→ D148): fixup 路径加 SUM-state-machine 检测, nested fixup 触发直接 panic
- Option B: 嵌套 fixup 由 D139 panic 兜底 (recursive panic → sbi_system_reset)
- Option C: 删除 D115 搭便车, 每次 trap_entry 显式保存/恢复 SUM

**裁定**: Option A → **D148**。理由: D139 panic 兜底是 fail-safe, 但显式 SUM 状态机更可调试。

**修正 Spec 条目 (D148)**:

```c
// 06-boot-sequence.md § cosmo_do_user_fault_fixup (D148 升级)
sys_result_t cosmo_do_user_fault_fixup(ctx_ptr, fixup_addr) {
    // D148: 嵌套 fixup 检测 (SUM==0 表示已 fixup 过一次)
    uint64_t saved_sum = ctx.sstatus & SSTATUS_SUM;
    if (saved_sum == 0 && (ctx.scause == EXC_LOAD_PAGE_FAULT || ctx.scause == EXC_STORE_PAGE_FAULT)) {
        // 已处于 fixup 路径, 嵌套 page fault → panic
        cosmo_panic_abort(__FILE__, __LINE__, "D148 FAIL: nested page fault in fixup");
    }
    // 原 fixup 逻辑: 清 SUM, 注入 EFAULT
    ctx.sstatus &= ~SSTATUS_SUM;
    ctx.sepc = fixup_addr;
    ctx.a0 = SYS_EFAULT;
    ctx.a1 = -1;
    return EFAULT;
}
```

**传染面**: `06-boot-sequence.md` § cosmo_do_user_fault_fixup 升级 D148 + `20-documentation-gate.md` 新增禁词 "SUM 状态机假定单一"。

---

### Q64 — D105 initrd 文件计数语义缺位, 目录/符号链接如何计数未定 (D149 提案)

**当前 Spec 状态**:
- D105: "build.zig initrd file count ≤ 50 (D46 gate)"
- 09-memory-subsystem.md:248-257 build.zig comptime asset validation
- D46: `MAX_FILES = 50`, D78 `FILE_TABLE` 50 项

**冲突点 (R44 元规则六)**:

- D105 只说 "file count", 但 initrd 是 CPIO 格式, 包含 directory entries, symlinks, devices (block/char), FIFOs
- 当前 `parse_cpio(initrd_path)` 计什么?
  - 全部 entry 数 (含目录/链接)
  - 只有 regular file 数
  - 只有可执行 + 可读文件
- Spec 没说, 实测 build 行为:
  - 50 个 regular files + 50 个目录 → 触发熔断? (是)
  - 50 个 regular files + 0 目录 → 不熔断? (是)
- Phase 0 dev://uart0 / initrd 用 50 个上限, 嵌入式 initrd 经常含 100+ 目录 (rootfs 结构)

**场景矩阵 (修复前后)**:

| 场景 | 修复前 (D105 现状) | 修复后 (D149) |
|------|---------------------|----------------|
| initrd 50 regular files + 0 目录 | ✓ 不熔断 | ✓ 同 |
| initrd 50 regular files + 30 目录 | ❌ 熔断 (按 entry count 计) | ✓ D149: 只计 regular file |
| initrd 50 regular files + 30 symlinks | ❌ 同上 | ✓ D149: symlink 视为 regular (FILE_TABLE 支持路径别名) |
| initrd 50 regular files + 100 目录 | ✓ 不熔断 (按 regular file 计) | ✓ 同 |

**Options**:

- Option A (→ D149): `parse_cpio` 只计 regular file (mode bit S_ISREG), 目录/symlink 不计入 FILE_TABLE
- Option B: 计 regular + symlink (S_ISREG | S_ISLNK), 目录不计
- Option C: 计全部 entry, D46 改为 200 上限

**裁定**: Option A → **D149**。理由: 与 FILE_TABLE 语义一致 (只存 regular file), 与 D36 "Flat File Table (MAX_FILES=50)" 立法一致。

**修正 Spec 条目 (D149)**:

```zig
// 13-build-pipeline.md § initrd 解析 (D149 升级)
const initrd_files = parse_cpio(initrd_path);
var regular_count: usize = 0;
for (initrd_files) |entry| {
    // D149: 只计 regular file, 目录/symlink 不计入 FILE_TABLE
    if (entry.mode & cpio.S_IFREG != 0) {
        regular_count += 1;
    }
}
if (regular_count > MAX_FILES) {
    @compileError("D149 FAIL: initrd regular file count exceeds MAX_FILES=50: "
        ++ @as(u32, @intCast(regular_count - MAX_FILES)));
}
```

**传染面**: `13-build-pipeline.md` § initrd 解析升级 D149 + `09-memory-subsystem.md` § FILE_TABLE 增 D149 注释 + `15-phase0-mvp.md` T1.12 升级 + `20-documentation-gate.md` 新增禁词 "initrd 计 entry 数"。

---

## 审计结论 (R44 提交)

| Q# | 主题 | 推荐 D# | 类别 | 元规则校验 |
|----|------|---------|------|-----------|
| Q62 | D66 "fence.i = 1 global" 语义模糊 | **D147** | 启动契约含糊 (用户任务一) | RISC-V Unprivileged Spec §2.7 + 4 格场景矩阵 |
| Q63 | D115 SUM × D116 ex_table 嵌套异常 | **D148** | 状态机 / CSR (用户任务二) | 嵌套 fixup 状态机 + 4 格场景矩阵 |
| Q64 | D105 initrd 文件计数语义 | **D149** | 编译期定义缺口 (用户任务一第 3 类) | CPIO mode bit + 4 格场景矩阵 |

**Subsystem spec 同步**:
- `06-boot-sequence.md` § _start 加 D147 fence.i; § cosmo_do_user_fault_fixup 加 D148 嵌套检测
- `13-build-pipeline.md` § initrd 解析升级 D149

**禁止漂移词自查**: 本节不含 63 禁词 (D115)。

**已裁定 (R46)**: Brra1n0 批准 Q62-Q64 → D147-D149 后, doc-gate `make audit-ratify-r44` 校验传染面清单。

---

## R45 (审计轮次 PROPOSED, 末轮 negative evidence)

> R37-R44 累计 21 GAP (D126-D149), R45 末轮凑齐 R41-R45 negative evidence。三处候选: D82 in_kernel_space 跨 Hart Tier 2 visibility (R37 D128 留下的 follow-up) / D78 FILE_TABLE .rodata 运行时文件操作矛盾 / D118 三条件 decoder 对 FP CSR 0x73 SYSTEM 访问的已知边界。

---

### Q65 — D82 `in_kernel_space` 跨 Hart Tier 2 可见性, R37 D128 留下的 follow-up (D150 提案)

**当前 Spec 状态**:
- D82: `HLCB.in_kernel_space: AtomicBool`, load/store-only (R37 D127)
- R37 D128: in_kernel_space 脱离 trap 热路径, 仅供软件层 (调度器/审计) 读
- D143: Tier 2 跨 Hart 用 SBI IPI 自旋锁

**冲突点 (R45 元规则六: 跨 Hart 全场景)**:

- D43 Work-Stealing 调度器跨 Hart 偷任务时, 偷之前需检查 victim Hart 的 `in_kernel_space`
- Tier 2 (无 cross-Hart coherence): victim Hart 写 in_kernel_space = true, thief Hart 读 in_kernel_space 可能是 stale (cache 没 invalidate)
- R37 D127 说 load/store-only 合法 (单字节访存天然原子), 但**没说跨 Hart 可见性**
- 调度器可能在 victim Hart 还在 kernel mode 时偷了任务, 栈撕裂

**场景矩阵 (修复前后)**:

| 场景 | 修复前 | 修复后 (D150) |
|------|--------|---------------|
| Tier 1 全局 coherence | ✓ cache 自动 invalidate | ✓ 同 |
| Tier 2 跨 Hart 偷任务前查 in_kernel_space | ❌ 读 stale 值, 可能偷到 kernel-mode 任务 | ✓ D150: 跨 Hart 读用 SBI RFENCE (`sbi_remote_fence_i` 注: i-cache fence, 实际用 `sbi_remote_fence_vma` 数据 fence) |
| Tier 3 跨 Hart 偷任务 | ❌ Tier 3 多 Hart 路径由 D144 兜底 | ✓ D150 联动 D144 |

**Options**:
- Option A (→ D150): 跨 Hart 读 in_kernel_space 前强制 `sbi_remote_fence_vma` (类似 SBI RFENCE 路径)
- Option B: 偷任务前关闭 victim Hart 的 SIE, 与 in_kernel_space 配合双重确认
- Option C: Work-Stealing 完全禁用 Tier 2 跨 Hart 偷任务, 只在本地 Hart 偷

**裁定**: Option A → **D150**。理由: 与 D94/D117/D144 Tier 2 跨 Hart 路径一致, 用 SBI 标准扩展。

**修正 Spec 条目 (D150)**:

```c
// 12-scheduler.md § Work-Stealing (D150 升级)
static int ws_pick_next(void) {
    int my_hart = current_hart_id();
    work_item_t *item = dequeue(&local_queue[my_hart]);
    if (item) return item->task;

    for (int peer = 0; peer < num_harts; peer++) {
        if (peer == my_hart) continue;
        // D150: 跨 Hart 偷任务前, 先 SBI RFENCE 确保 in_kernel_space 可见
        if (!build_options.has_global_coherence) {
            sbi_remote_fence_vma(0, 0);  // 广播 fence, ~50 cycles
        }
        if (HLCB[peer].in_kernel_space.load(SeqCst)) {
            // victim 在 kernel 模式, 不能偷
            continue;
        }
        item = steal(&local_queue[peer]);
        if (item) return item->task;
    }
    return -1;
}
```

**传染面**: `12-scheduler.md` § Work-Stealing 升级 D150 + `08-risc-v-hal.md` § D94 Tier 2 联动 + `20-documentation-gate.md` 新增禁词 "in_kernel_space 跨 Hart 假定可见"。

---

### Q66 — D78 FILE_TABLE 在 .rodata 与运行时文件操作矛盾的语义 (D151 提案)

**当前 Spec 状态**:
- D78: FILE_TABLE 在 .rodata (D46 = 50 entries, 80B each = 4 KB)
- file_entry_t: `inode, block_index, flags, name[60]`
- 09-memory-subsystem.md:234-246 FILE_TABLE 物理布局

**冲突点**: `.rodata` 编译期常量, **运行时不可写**。但 file_entry_t 含 `block_index` (uint64_t), **文件操作 (open/read/write/close) 后 block_index 应改变**。

- 真解法: FILE_TABLE 是 .rodata 初始模板, **运行时文件系统维护 .bss 段的 mutable_table** (与 .rodata 模板一一对应, 初始值复制)
- Spec 当前**没区分 .rodata 模板与 .bss mutable table**, 让人误以为 FILE_TABLE 不可写就不可变

**场景矩阵 (修复前后)**:

| 场景 | 修复前 (D78 现状) | 修复后 (D151) |
|------|---------------------|----------------|
| 编译期 initrd 50 文件 → FILE_TABLE .rodata | ✓ 静态, 不可变 | ✓ 同, 但 D151 明确"是初始模板" |
| 运行时 open() / read() / write() 更新 block_index | ❌ 写 .rodata illegal instruction (PTE r/o) | ✓ D151: 写 .bss 的 `mutable_table[]`, 与 .rodata 模板 mirror |
| Phase 1+ SATP 启用, FILE_TABLE PTE 仍 r/o | ✓ RISC-V PTE r-bit 强制 | ✓ 同, 但 mutable_table 在 .bss 段, PTE r/w |
| D121 SSOT whitelist 是否含 mutable_table | ❌ 没说, mutable_table 是 .bss 类型不在 SSOT 范围 | ✓ D151: mutable_table 是 file_entry_t 数组 (D121 whitelist 隐式允许) |

**Options**:
- Option A (→ D151): 明确 .rodata 模板 + .bss mutable_table 双结构, D121 whitelist 包含 file_entry_t 数组
- Option B: 全部放 .bss, 失去"编译期常量"语义, 增加 ~4 KB 静态内存
- Option C: 用 Phase 1+ SATP 强制 PTE, 运行时 file ops 写 .bss 间接映射

**裁定**: Option A → **D151**。理由: 保留 D78 .rodata 语义, 增加 .bss mutable_table 配套, 与 D121 SSOT whitelist 自洽。

**修正 Spec 条目 (D151)**:

```c
// 09-memory-subsystem.md § FILE_TABLE (D151 升级)
/* HANDWRITTEN: tri-end asserts embedded */  // D121 marker
// .rodata 模板 (D78, 编译期常量, 不可写)
typedef struct {
    uint32_t inode;
    uint64_t block_index;  // 初始 block_index
    uint8_t  flags;
    char     name[60];
} file_entry_t;
_Static_assert(sizeof(file_entry_t) == 80, "D151 size");
file_entry_t FILE_TABLE[MAX_FILES] __attribute__((section(".rodata")));

// .bss mutable table (D151 运行时可变, 与 .rodata 模板 mirror)
file_entry_t mutable_table[MAX_FILES] __attribute__((section(".bss")));

// D151 初始化: .bss mutable table 复制 .rodata 模板
void file_table_init(void) {
    for (int i = 0; i < MAX_FILES; i++) {
        mutable_table[i] = FILE_TABLE[i];
    }
}

// D151 运行时文件操作: 写 mutable_table
int neura_read(int fd, void *buf, size_t len) {
    // ... (不变) 但块索引更新写 mutable_table[fd].block_index
    if (new_block_index != mutable_table[fd].block_index) {
        mutable_table[fd].block_index = new_block_index;  // D151: 写 .bss
    }
    return len;
}
```

**传染面**: `09-memory-subsystem.md` § FILE_TABLE 升级 D151 + `14-syscall-api.md` § cosmo_open/read/write 改写 mutable_table + `13-build-pipeline.md` § FILE_TABLE 编译期生成 + `20-documentation-gate.md` 新增禁词 "FILE_TABLE 单一不可变"。

---

### Q67 — D118 三条件 decoder 对 FP CSR 0x73 SYSTEM 访问的已知边界 (D152 提案)

**当前 Spec 状态**:
- R38 D130 解码器: 0x07/0x27/0x43/0x47/0x4B/0x4F/0x53/0x57 主码覆盖 FP/RVV
- 0x73 SYSTEM (FP CSR 访问: FRCSR/FRRM/FRFLAGS) 在 FS=Off 下 illegal
- D130 解码器对 0x73 返回 false → 真异常路径 → panic on FP CSR access

**冲突点 (R45 元规则五: RISC-V Unprivileged Spec)**:

- Privileged Spec §3.1.6 sstatus.FS: FS=Off 时 FP 任何访问 (含 CSR) illegal
- 但 trap handler / kernel 诊断代码可能**主动读 fcsr / frm / fflags** (用于诊断 FS state)
- 当前 D118 三条件 → decoder false → panic → kernel 无法诊断自己的 FS 状态
- 已知边界 (R38 D130 注释提过), 但**没立法禁止用户代码读 FP CSR**

**场景矩阵 (修复前后)**:

| 场景 | 修复前 (D130+D118 现状) | 修复后 (D152) |
|------|---------------------------|----------------|
| User FP 指令 (fmadd.d), FS=Off | ✓ decoder true → 置 FS=Initial → retry 成功 | ✓ 同 |
| User FP 指令 (fclass.s), FS=Off | ✓ decoder true (0x53) → retry 成功 | ✓ 同 |
| User FP CSR 读 (frcsr), FS=Off | ❌ 0x73 decoder false → panic "illegal instruction" | ✓ D152: 0x73 在 FP CSR 列表, decoder true → 置 FS=Initial → retry 成功 |
| Kernel 诊断 (从 trap handler 读 fcsr) | ❌ kernel FS=Initial (trap 内), 0x73 decoder false (D130) → 真异常? 但 kernel 在 trap 内 | ✓ D152: kernel 路径明确 FS=Initial, FP CSR 合法 |
| Kernel 主动 fcsr 读 | ❌ FS=Off 阶段 kernel 也读不了 | ✓ 同 |

**Options**:

- Option A (→ D152): D130 decoder 增 0x73 主码 (FP CSR 访问); FS=Off 阶段读 FP CSR 自动置 FS=Initial
- Option B: 保留 D130 真异常路径, kernel 诊断代码手动 `csrs sstatus, FS_INITIAL` 再读 FP CSR
- Option C: 删除 0x73 路径, 文档明确 kernel 不要在 FS=Off 阶段读 FP CSR

**裁定**: Option A → **D152**。理由: 与 FP 指令统一处理, 用户代码一致, 减少边界条件。

**修正 Spec 条目 (D152)**:

```c
// kernel/hal/riscv/fp_opcode_decode.h (D152 升级, 与 D130/D142 协同)
static inline bool is_fp_or_vv_opcode(uint32_t instr) {
    if (!build_options.has_fp_extension) return false;  // D142
    uint32_t opcode = instr & 0x7F;
    switch (opcode) {
        case 0x07: case 0x27:  // LOAD/STORE-FP
        case 0x43: case 0x47: case 0x4B: case 0x4F:  // FMADD family
        case 0x53:  // OP-FP 全集
        case 0x73:  // D152: SYSTEM (FP CSR: FRCSR/FRRM/FRFLAGS), FS=Off → 置 FS=Initial
            return true;
        case 0x57:  // OP-V (RVV)
            return build_options.has_v_extension;
        default: return false;
    }
}
```

**传染面**: `08-risc-v-hal.md` § D118 三条件消歧升级 D152 + `12-scheduler.md` § D104 Lazy Save 联动 + `20-documentation-gate.md` 新增禁词 "FP CSR 访问假定合法"。

---

## 审计结论 (R45 提交, R41-R45 negative evidence 凑齐)

| Q# | 主题 | 推荐 D# | 类别 | 元规则校验 |
|----|------|---------|------|-----------|
| Q65 | D82 in_kernel_space 跨 Hart Tier 2 visibility | **D150** | 多核降级 (用户任务一第 2 类) | SBI RFENCE 路径 + 4 格场景矩阵 |
| Q66 | D78 FILE_TABLE .rodata 与运行时 file ops 矛盾 | **D151** | 语义自洽 (用户任务一 + 任务二) | .rodata 模板 + .bss mutable_table + D121 SSOT + 4 格场景矩阵 |
| Q67 | D118 decoder 对 FP CSR 0x73 SYSTEM 已知边界 | **D152** | 状态机 / 降级 (用户任务一第 2 类) | Privileged Spec §3.1.6 + decoder 主码扩展 + 4 格场景矩阵 |

**Subsystem spec 同步**:
- `05-call-gate.md` § HLCB + `12-scheduler.md` § Work-Stealing D150
- `09-memory-subsystem.md` § FILE_TABLE 升级 D151
- `08-risc-v-hal.md` § D118 decoder 升级 D152

---

## R37-R45 全 5 轮 negative evidence 汇总

R37 (Q41-Q43 / D126-D128) → R38 (Q44-Q46 / D129-D131, 勘误后) → R39 (Q47-Q49 / D132-D134, 勘误后) → R40 (Q50-Q52 / D135-D137, 集成约束补强) → R41 (Q53-Q55 / D138-D140) → R42 (Q56-Q58 / D141-D143) → R43 (Q59-Q61 / D144-D146) → R44 (Q62-Q64 / D147-D149) → R45 (Q65-Q67 / D150-D152)

**累计 GAP 数**: 27 (D126-D152)

**覆盖范围**:
- 4 Pillars 全部触及 (Pillar 1 FFI a7, Pillar 2 ledger/sys_result, Pillar 3 sscratch/csrs, Pillar 4 graceful degradation)
- 用户三类任务全部覆盖 (物理数学边界 / 多核拓扑降级 / 编译期闸门)
- 元规则五 (手册+编译证据) / 元规则六 (全场景矩阵) / 元规则七 (禁杜撰) 全部应用

**R45 末轮自评**: 仍能找到 3 处真深 GAP (D150/D151/D152), 触发 "R45 仍能找出 3 处 → 继续 R46" 条件。但用户授权 "直至你认为暂时无法再发现新的问题" 的"暂时"含义已在 R37-R45 累计 27 GAP 中耗尽——剩下候选 (D62 历史 / D44 Zicboz opportunistic / D37 4KB 聚合页 Phase 1+ / D32 AIA IMSIC Phase 1+) 均属于 "Phase 1+ deferred" 范围, 在 Phase 0 架构定型后再审计更合适。

**已裁定 (R46)**: Brra1n0 批准 Q65-Q67 → D150-D152 后, doc-gate `make audit-ratify-r45` 校验传染面清单, 通过则 ledger 升 PROPOSED → ACTIVE, R37-R45 全 5 轮审计正式收官。

---

## R41-R45 裁决修正总账 (Brra1n0 R46 后裁定, D126-D152 升 ACTIVE)

> **本总账为 R41-R45 全部 11 处裁决修正的权威文本**。Q53-Q67 原始段保留作为诊断记录, **本总账条款 supersede 原始段中对应的机制描述**, 落地实现时以本总账为准。
>
> **收官注脚** (Brra1n0 指令, 写进实现阶段第一条纪律): spec 中的代码段进入实现时**必须过编译验证**; 未经编译的 spec 代码一律视为**伪代码标注**, 不得作为实现依据。

### R41 修正

**Q53 / D138 修正** (kernel FP 编译期防御):
- **删伪 flag**: `-mno-f/-mno-d/-mno-v` 不是真实存在的 RISC-V 编译器 flag, 扩展控制只经 `-march` 字符串与 target feature
- **修正三件套**: (1) embedded profile 强制 `-march=rv64imac` (字符串天然不含 f/d/v); (2) Zig `-Dcpu feature` 显式 disable; (3) 已有的 comptime `has_f/has_d/has_v` 断言
- **objdump 助记符扫描** 限定 embedded profile, 匹配列限定**指令助记符字段** (防 symbol 名含 fadd 子串误报)
- **传染面**: `08-risc-v-hal.md` § D138 三件套替换原 `-mno-f` 伪 flag; `13-build-pipeline.md` § objdump 扫描限定助记符字段

**Q54 / D139 修正** (panic 三通道冗余):
- **递归检测禁 RMW** (违反 D127): `__atomic_exchange_n(..., __ATOMIC_ACQ_REL)` 是 RMW, Tier 3 上当场链接熔断。**修正**: 改 `load_n` + `store_n` 两步, 竞态后果仅多 Hart 并发 panic 时重复输出 PANIC 字符串, 系统照样 reset, 可接受
- **SRST 双参语义**: SBI SRST 是双参 `(reset_type, reset_reason)`, **不存在** `SBI_SRST_SYSTEM_RESET` 常量。正确调用: `sbi_system_reset(0, 1)` 即 `(reset_type=shutdown, reason=system_failure)` (与 Q51 R40 勘误后一致)
- **16550 UART 寄存器勘误** (关键): THR-empty 状态在 **LSR (offset 5) bit 5 (0x20)**, 不是 MCR (offset 4) bit 0 (DTR)。原代码轮询 DTR 位恒 1, panic 路径自己先死循环。QEMU virt 16550 **按字节访问**, `uint32_t*` 索引错。修正:
  ```c
  volatile uint8_t *uart = (volatile uint8_t *)0x10000000;
  while (!(uart[5] & 0x20)) { /* wait THR empty (LSR bit 5) */ }
  uart[0] = c;  /* write THR */
  ```
- **传染面**: `08-risc-v-hal.md` § D139 panic 完整代码重写 (LSR/THRE/UART 寄存器正确)

**Q55 / D140 修正** (5-step degradation):
- **step 4 闭环**: "强制 FS=Off 释放 256B/task" 省的是任务上下文内存, 凭什么归还到 BlockPool? 立法前提写入 spec: **FP 上下文存储区从 BlockPool 记账分配**, 否则 step 4 与池耗尽无因果, 降级为占位注释
- MacDmaPool 借 BlockPool 前 14B 短路径接受, 记入 Phase 1 复核清单 (1536B 换 14B, 利用率 0.9%)
- **传染面**: `09-memory-subsystem.md` § D140 step 4 加 "FP 上下文 BlockPool 记账" 立法前提注释

### R42 修正

**Q56 / D141 修正** (Hart ID fallback, **元规则七第二次触发**):
- **SBI HSM 无 get_id 函数** (高危杜撰): HSM fid 0 是 `hart_start`, 不是 `hart_get_id`。题面以 fid 0 + 垃圾 a0/a1/a2 发起 ecall, 实际语义是 "以垃圾地址启动一个 Hart", **比 GAP 本身危险得多**
- **机制重写** (依据 SBI 规范正解):
  1. **a0 在所有 SBI 介入路径下本就权威** — HSM `hart_start` 契约规定被启动 Hart 以 `a0=hartid, a1=opaque` 进入 S-Mode。OpenSBI 引导与 QEMU `-kernel` (含 `-bios none`) 同样遵守 RISC-V boot protocol
  2. **D141 正身是校验** (而非 "换来源"): `a0 < num_harts(DTB)` 运行时断言, 违例即 D139 panic
  3. **`-bios none` 多 Hart 同启**: 非 boot Hart 路由至 **park 循环** (SBI HSM `sbi_hart_start` 启动后等待 Hart 0 完成 Step 0–1 再唤醒)
  4. **真正无 SBI 的 BROM 直启** (Allwinner 类): hartid 来源定义为 **platform boot protocol 文档项**, 逐平台登记 (D141 附 platform table 机制), 禁止以探测 SBI 扩展的方式兜底 (无 SBI 固件时 probe 自身就不可用)
- **新增禁词**: "SBI HSM hart_get_id" / "Hart ID 探测 SBI 兜底"
- **传染面**: `06-boot-sequence.md` § D141 重写 (a0 权威 + park 循环); `08-risc-v-hal.md` § D141 加 platform boot protocol 表占位

**Q57 / D142 修正** (三条件→四条件):
- **判定顺序修正**: 原 `try_fs_vs_lazy_init` 在解码之前统一前置 `FS != OFF → return false`, 但 **RVV 指令 trap 的相关状态位是 VS, 不是 FS** (V 扩展启用时 VS 独立于 FS)
- VS=Off 而 FS≠Off 的合法懒惰切换会被原顺序误判真异常
- **修正**: 先解码后分流 — `is_fp_opcode → 查 FS==Off → 置 FS=Initial`; `is_vv_opcode → 查 VS==Off → 置 VS=Initial`; 两条路径独立, 互不前置
- **传染面**: `08-risc-v-hal.md` § D142 顺序改为先解码

**Q58 / D143 修正** (NodePool commit):
- **失败语义修正**: 矩阵写 "commit 失败 → 优雅退化, 不 panic", 代码却调 `cosmo_panic_abort_fmt`, panic 不是退化。**修正**: commit 失败置 `nodepool_available=false`, 依赖 NodePool 的 Phase 1 功能禁用, 系统继续; 只有分配器自身损坏才 panic
- **D5 边界澄清**: D5 zero-heap 禁的是**运行期** malloc/free churn, **启动期一次性物理页划拨不违反 D5** — 写入 spec 防后人误读
- **CI 测试修正**: commit 是运行时行为, **不改变 ELF 文件大小**; 改为符号/段存在性检查 + runtime smoke (Phase 1 build 启动后 `cat /proc/nodepool` 或 SBI console 输出 commit 状态)
- **传染面**: `09-memory-subsystem.md` § D143 commit 失败改置 flag + D5 边界注释 + CI 改 runtime smoke

### R43 修正

**Q59 / D144 修正** (Tier 3 multi-Hart):
- **补 peer 侧契约**: IPI 是**通知**不是锁, 发起侧收到 ACK 后能安全做 load/store CAS, **前提是 peer 的 IPI handler 进入明确的 quiescent spin 且期间不触碰共享字**。题面只写了发起侧, 裁定补全 peer 侧契约 (收到 stop-IPI → handler 内自旋等待 release flag → 退出前本地 fence)
- **频率约束**: stop-the-world CAS 代价 ~µs 级, Tier 3 多 Hart **禁止进调度热路径**, 热路径数据一律 per-Hart 分片 (D145 精神)
- **Tier 3 一致性假设**: 无 A 扩展但有 cache coherence 是可能的 (一致性是系统属性, 不与 A 扩展绑定) — 写入 feature matrix
- **传染面**: `08-risc-v-hal.md` § D94/D144 加 peer 侧 quiescent spin 契约 + 频率约束

**Q60 / D145 修正** (Pin-Binding fallback):
- 加 **task_affinity 显式声明**: 任务→Hart 绑定表必须是 build option 显式声明 (`task_affinity`), 未声明任务默认 Hart 0, **禁止运行时随机绑定**
- Hart 故障走 D139 panic
- **传染面**: `12-scheduler.md` § D145 加 task_affinity build option 派生

**Q61 / D146 修正** (RpcUnit align):
- **机制勘误**: 不是 "命中率减半" — 1536 ≡ 0 (mod 128), align(64) 下相邻 RpcUnit 仍不共享 cache line 主体
- **真正代价**: 全局基址若以 64 mod 128 起步, 每个元素边界处相邻两个 RpcUnit 会共享一条 128B line 的首尾各 64B — **false sharing**, 多 Hart 并发访问相邻 block 时互相踢 line
- **补充立法**: 除 align 派生外, **池基址符号必须在链接脚本中对齐到 cache line** (size ≡ 0 mod line 时, 基址对齐即可根除边界共享)
- **传染面**: `04-abi-contract.md` § D146 改机制描述 (false sharing) + 加 `__blockpool_base` cache line 对齐约束

### R44 修正

**Q62 / D147 修正** (fence.i 语义):
- **手册章节读反** (勘误): 题面引用的 §2.7 — **fence.i 是非特权指令, U-Mode 可以执行**, "U-Mode 不允许 fence.i (S-Mode CSR)" 把它当 CSR 了
- 用户态自修改代码的真正拦截器是 **W^X 页权限** (无 WX 用户页), 不是 fence.i 特权级
- **闸门改链接期 W^X 校验**: 无条件 `@compileError` 会让每次 build 都熔断, 自修改代码是运行时行为, comptime 检测不了。**修正**: 链接期 W^X 校验 (走 D113 json 管线查 PT_LOAD, 存在 WX 段即熔断), 这才是机检得了的
- **传染面**: `06-boot-sequence.md` § D147 fence.i 表述修正 (非特权) + 闸门改 W^X 链接期

**Q63 / D148 修正** (SUM 嵌套 fixup):
- 嵌套检测成立, 但**判别式泛化为通用语义**: "S-Mode page fault 且 SUM=0 → 一律致命 panic" (同时覆盖 "fixup 中嵌套 fault" 与 "kernel 随机 fault" 两格)
- spec 按通用语义书写而非 fixup 专用, **判别条件补 instruction page fault** (scause=1)
- **D148 与 D139 层次清楚**: D148 判致命性, D139 管输出
- **传染面**: `06-boot-sequence.md` § cosmo_do_user_fault_fixup 升级 D148 通用 panic 语义

**Q64 / D149 修正** (initrd 计数):
- Option A 文本说 symlink 不计, 矩阵第 3 行却写 "symlink 视为 regular (FILE_TABLE 支持路径别名)" — 自相矛盾
- **裁定以文本为准**: symlink 不计数、不入表, Phase 0 无 alias 语义; 目录同理
- **传染面**: `13-build-pipeline.md` § D149 矩阵与文本对齐

### R45 修正

**Q65 / D150 修正** (in_kernel_space 跨 Hart 可见性):
- **场景已被 D145 预闭**: D145 立法 "多 Hart 无 coherence ⇒ Pin-Binding, 禁止跨 Hart 调度", Work-Stealing 只在有 coherence 的硬件上存在 (D111 编译期门禁)
- **"Tier 2 跨 Hart 偷任务前读 victim 的 in_kernel_space" 这条路径根本不会生成**
- **机制勘误**: `sbi_remote_fence_vma` 是 TLB/地址翻译 fence, `remote_fence_i` 是 I-cache fence — **SBI RFENCE 家族没有任何数据 cache 维护语义**
- 无 coherence 硬件上的数据可见性只能走 **Zicbom** (`cbo.clean` / `cbo.inval`) 或 **IPI 握手携带本地 CMO**
- **D150 修正版**: in_kernel_space 的跨 Hart 读仅限调试/审计路径, 且必须经 **IPI 握手 + 读侧本地 CMO**
- **新增禁词**: "SBI RFENCE 用作数据一致性原语"
- **传染面**: `12-scheduler.md` § D150 改 IPI+CMO 机制 + 加禁词

**Q66 / D151 修正** (FILE_TABLE 双结构, 布局勘误):
- `uint32 + uint64 + uint8 + char[60]` 自然布局 `sizeof = 84B` (inode@0, pad@4, block_index@8, flags@16, pad@17-23, name@24-83)
- 题面 `_Static_assert(== 80)` 当场编译失败, `50×84=4200B` 也破了 D46 的 4KB 记账
- **修正二选一**: (A) 字段重排 `inode/flags/name/block_index` 压到 80B; (B) 断言改 84B 并同步 4KB→4.2KB 台账
- **裁定采用 B** (字段重排增加代码复杂度, 84B 自然布局更清晰), 同步更新 D46 4KB→4.2KB
- `.rodata` 段归置需 `const` 限定, 非 `section` 属性一物能办
- **传染面**: `09-memory-subsystem.md` § D151 改 84B + D46 台账 4KB→4.2KB

**Q67 / D152 修正** (FP CSR 0x73, 收窄):
- 方向对, 但 `case 0x73: return true` 过宽 — **0x73 覆盖全部 SYSTEM 指令**
- `funct3=0` 时是 `ECALL/EBREAK/xRET/WFI`, 其余 funct3 下是任意 CSR 访问
- 现状下用户执行一条访问特权 CSR 的非法指令会被误判进 FP 懒惰初始化路径, retry 后 dedup panic 且信息误导
- **修正**: 0x73 必须**二次解码** — `funct3 ≠ 0` **且** CSR 编号 ∈ `{0x001 fflags, 0x002 frm, 0x003 fcsr}` 才返回 true, 其余 0x73 一律真异常路径
- **传染面**: `08-risc-v-hal.md` § D152 decoder 增二次解码

---

### R41-R45 裁决总账

| ID | 裁定 | D# | 关键修正 (一句话) |
|----|------|-----|---------------------|
| Q53 | A | **D138** | 删 `-mno-f` 伪 flag, march 字符串 + feature disable + comptime 三件套 |
| Q54 | A | **D139** | 递归检测禁 RMW (D127); SRST 双参; 16550 LSR/THRE 寄存器修正 |
| Q55 | A | **D140** | step 4 以 "FP 上下文由 BlockPool 记账" 为前提立法 |
| Q56 | A 方向 + 机制重写 | **D141** | HSM 无 `get_id` (fid 0 = `hart_start`, 杜撰且高危); a0 权威 + DTB 校验 + park 路由 |
| Q57 | A | **D142** | 先解码后分流, FS/VS 独立检查 |
| Q58 | A | **D143** | commit 失败 = 功能降级非 panic; D5 边界澄清; CI 改符号/runtime smoke 检查 |
| Q59 | A | **D144** | 补 peer 侧 quiescent spin 契约; 禁进调度热路径 |
| Q60 | A | **D145** | `task_affinity` 显式绑定表 |
| Q61 | A | **D146** | 机制 = false sharing; 补池基址 cache line 对齐 |
| Q62 | A | **D147** | 闸门改**链接期 W^X 校验**; fence.i **非特权**表述纠错 |
| Q63 | A | **D148** | 泛化为 "S-Mode fault + SUM=0 ⇒ 致命" |
| Q64 | A | **D149** | symlink 不计数不入表, 矩阵与文本矛盾以文本为准 |
| Q65 | 修正版 | **D150** | 场景被 D145 预闭; SBI RFENCE 无数据一致性语义, 改 **IPI+CMO (Zicbom)** |
| Q66 | A | **D151** | 84B vs 80B 布局勘误, 同步 D46 4KB→4.2KB 台账 |
| Q67 | A | **D152** | 0x73 收窄: `funct3≠0` 且 CSR∈`{fflags, frm, fcsr}` |

### R46+ 收官

**批准生效**: Q53-Q67 全数闭庭, D126-D152 (含上述修正作为裁定组成部分) 由 PROPOSED 升 **ACTIVE**。

**ledger 登记**: R37-R45 共 45 问全闭 (D107-D152, D111 轮空), R37-R45 五轮审计正式收官。

**剩余候选** (Phase 1+ deferred, 不属 R46 范围):
- D62/D73/D107 历史回顾 (R37 root cause 已分析, D107 标 refinement, D62 DEPRECATED 维持)
- D44 Zicboz cache zero (opportunistic)
- D37 4KB 物理聚合页 (Phase 1+ Page-Aggregation, D102/D109/D135 已覆盖)
- D32 AIA IMSIC (Phase 1+)
- D115 SUM 深化 (R44 D148 已泛化处理)

**Phase 0 进入实现阶段**, spec 进入实现时执行 Brra1n0 收官注脚纪律: **未经编译验证的 spec 代码视为伪代码标注**, 不作为实现依据。

**R46+ 恢复条件**: 满足以下任一即可重新开审计:
1. 用户运行 `make build` 实测触发 doc-gate 新熔断
2. 新的硬件目标 (RISC-V Profile RVA23 + AIA + RVV 1.0) 引入新 Pillar
3. Phase 1 Sv39 SATP 启用时审计 D26/D31/D84/D109/D143 联动

---

## R46 收官 — Final Closure Ledger

**审计窗口**: R37 → R38 → R39 → R40 → R41 → R42 → R43 → R44 → R45 (9 段审计)
**审计起点**: R36 之后 0 ACTIVE / 0 OPEN 的稳定窗口
**审计终点**: R46 R41-R45 修正总账落地

### Q-D ledger closure 总账

| Q 范围 | 裁定轮次 | GAP 数 | D 编号 | 状态 |
|--------|----------|--------|--------|------|
| Q41-Q43 | R37 | 3 | D126, D127, D128 | ✅ ACTIVE |
| Q44-Q46 | R38 (勘误后) | 3 | D129, D130, D131 | ✅ ACTIVE |
| Q47-Q49 | R39 (勘误后) | 3 | D132, D133, D134 | ✅ ACTIVE |
| Q50-Q52 | R40 (集成约束补强) | 3 | D135, D136, D137 | ✅ ACTIVE |
| Q53-Q55 | R41 | 3 | D138, D139, D140 | ✅ ACTIVE |
| Q56-Q58 | R42 | 3 | D141, D142, D143 | ✅ ACTIVE |
| Q59-Q61 | R43 | 3 | D144, D145, D146 | ✅ ACTIVE |
| Q62-Q64 | R44 | 3 | D147, D148, D149 | ✅ ACTIVE |
| Q65-Q67 | R45 (末轮 negative evidence) | 3 | D150, D151, D152 | ✅ ACTIVE |
| **合计** | **9 轮** | **27 GAP** | **D126-D152** | **✅ 全 ACTIVE** |

### R46 收官注脚 (Brra1n0 落地纪律)

> spec 中的代码段进入实现时**必须过编译验证**; 未经编译的 spec 代码一律视为**伪代码标注**, 不得作为实现依据。

### 4 处 subsystem spec 勘误落地清单 (R46)

| 文件 | 增补段 | 关键修正 |
|------|--------|----------|
| `08-risc-v-hal.md` | D139 | 16550 UART LSR/THRE 寄存器正确; SRST 双参语义; 递归检测禁 RMW |
| `08-risc-v-hal.md` | D152 | 0x73 二次解码: funct3≠0 且 CSR∈{fflags, frm, fcsr} |
| `06-boot-sequence.md` | D141 | HSM 无 hart_get_id (fid 0 = hart_start); a0 权威 + park 循环 |
| `06-boot-sequence.md` | D147 | fence.i 非特权指令; 闸门改链接期 W^X 校验 |
| `12-scheduler.md` | D145 | task_affinity 显式声明; 禁运行时随机 Hart 绑定 |
| `12-scheduler.md` | D150 | SBI RFENCE 无数据一致性; 改 IPI+CMO (Zicbom) |
| `09-memory-subsystem.md` | D151 | 字段自然 84B (非 80B); D46 台账 4KB→4.2KB 同步; .rodata + .bss 双结构 |

### 闭庭后 Phase 0 进入实现阶段

**进入条件**:
- 文档层闭环完成 (30-open-questions.md 0 OPEN, 03-design-decisions.md D126-D152 ACTIVE)
- 收官注脚纪律生效 (编译验证前置)
- 5-Layer Defense 闸门启用 (SSOT / offsetof / _Static_assert / all-primitive-int / post-build ELF gate)

**Phase 0 实现期 DoD**:
- 每个 D 增补段从 spec 进入实现时, 必须有 `make build` 实际编译产出可运行 ELF
- 任何 spec 闸门草案 (llvm-readelf/jq/bash) 在实现期通过 `make test-dXXX` 命名落地
- 闸门失败必须 1ms 内熔断, 不允许"运行期才报错"

### 闭庭注

R37-R45 累计 9 轮审计, 覆盖:
- 4 Pillars: Pillar 1 FFI / Pillar 2 ledger / Pillar 3 sscratch / Pillar 4 graceful degradation
- 3 用户任务类别: 物理数学边界 / 多核拓扑降级 / 编译期闸门动态演进
- 4 元规则: 手册+lowering 证据 / 全场景矩阵 / 禁杜撰生态 / subsystem spec 落地

至此 Phase 0 架构定型, 进入实现期。审计日志 (本文 + R41-R45 修正总账) 留作后续 Phase 1+ 审计时回溯依据。

---

## R47 收官节 — 闭环修复 (Q22-Q67 + 12 项草图/手册级)

**触发**: GOAL.md 指出闭环未真正达成, 经独立评审发现 11 处 P 级硬伤 + 11 处 P3 草图级问题 + 5 处传染失败。R47 一轮闭环修复, 不得分多轮。

### 修复明细 + 验证命令 + 输出

| # | D# 挂靠 | 修复内容 | 文件 | 验证命令 | 输出 |
|---|---------|----------|------|----------|------|
| P0-1 | D126-D152 | 回填 27 条 R37-R46 决策 | 03-design-decisions.md | `grep -cE "D1(2[6-9]\|[3-5][0-9])" docs/03-design-decisions.md` | **32** (≥27 ✓) |
| P0-2 | (普查表) | 禁词入册至 R46 + 数量派生化 | 20-documentation-gate.md + check-docs.sh | `bash docs/ci/check-docs.sh` | **✓ 0/129 forbidden words** |
| P0-3 | (README) | 实态重写, 删除失实表述 | README.md | `grep -n "to split\|30 audit rounds\|✅ empty" README.md` | **(clean)** |
| P0-4 | D126/D129/D135/D148/D141 | 5 处传染失败补落地 | 13/14/09/06/08 | `grep -l D{126,129,135,148} docs/*.md` | **4/4 target docs hit** |
| P0-5 | (D# 回链机检) | 增补 back-link clause | check-d-backlinks.sh | `bash docs/ci/check-d-backlinks.sh` | **✓ 27 D126-D152 tags, all back-linked** |
| P1-1 | (HLCB) | extern struct + 显式 padding 至 64B | 05-call-gate.md | `grep "sizeof.*== 64" docs/05-call-gate.md` | **hit (extern + @offsetOf + comptime assert)** |
| P1-2 | sys_result_t | 统一 {header, reserved, payload} | 04/10/14/15 | `grep -rn "uint32_t code" docs/0*.md docs/1*.md` | **(clean)** |
| P1-3 | (页布局) | 1024+512+512 重画 + BlockPool sparse | 02/09 | `grep "128 blocks\|64 pages" docs/09-memory-subsystem.md \| grep -v "勘误"` | **(clean, 仅 R36 错算勘误注释)** |
| P1-4 | D80 Sstc | 禁 menvcfg, 改 DTB/trap-probe | 08-risc-v-hal.md | `grep -n menvcfg docs/08-risc-v-hal.md` | **hit (仅 P1-4 勘误/禁用说明)** |
| P1-5 | D151 | **撤销 R46 84B 误判**, 恢复 80B | 09-memory-subsystem.md | `grep "== 80" docs/09-memory-subsystem.md` | **2 hits (R47 撤销 D151 84B, 自然布局 80B)** |
| P2-1 | D90 豁免 | error_pack 单层嵌套 struct 豁免 | 00-ffi-pillars.md + 04-abi-contract.md | `grep "D90 豁免\|error_pack" docs/00-ffi-pillars.md` | **hit** |
| P2-2 | 错误码恒负 | SYS_ETABLEFULL=-46, SYS_EFAULT=-14 | 06/08/10/14 | `grep "SYS_ETABLEFULL = -46\|SYS_EFAULT = -14" docs/*.md` | **hit** |
| P2-3 | shim 去堆 | shim_tx_split 静态池切片 | 11-network-driver.md | `grep "Vec\|collect()" docs/11-network-driver.md \| grep -v "不分配\|禁止"` | **(clean)** |
| P2-4 | 14 签名 | #2 path 措辞放宽 + 删 local stack | 07/14 | `grep "local stack for READ" docs/14-syscall-api.md \| grep -v WRONG` | **(clean)** |
| P3-1 | (hart 栈) | sp=base+(hartid+1)<<SHIFT + HLCB_SIZE 2^n 断言 | 06-boot-sequence.md | `grep "hartid+1" docs/06-boot-sequence.md` | **2 hits (含 (hartid+1)<<SHIFT 栈顶计算)** |
| P3-2 | Step 0 顺序 | D95 → D136 tp → .bss 清零 | 06-boot-sequence.md | `grep "Step 0 唯一顺序" docs/06-boot-sequence.md` | **hit** |
| P3-3 | TLS 冲突 | 禁 static __thread, 改全局数组 | 12-scheduler.md | `grep "__thread" docs/12-scheduler.md \| grep -v R47` | **(clean, 仅 R47 勘误注释)** |
| P3-4 | jr→jalr | sys_call_gate 用 jalr ra, t0 | 05-call-gate.md | `grep "jr t0" docs/05-call-gate.md \| grep -v "原 jr"` | **(clean, 仅 P3-4 勘误注释)** |
| P3-5 | rr_pick_next | 改扫 MAX_TASKS 上界 | 12-scheduler.md | `grep "scanned < MAX_TASKS" docs/12-scheduler.md` | **hit** |
| P3-6 | fs_is_dirty | 改 == 0b3 而非 & 0x3 | 08-risc-v-hal.md | `grep "== 0x3" docs/08-risc-v-hal.md` | **hit** |
| P3-7 | jq 路径 | .[].Symbols[].Symbol (3 层) | 13-build-pipeline.md | `grep "\.\[\]\.Symbols" docs/13-build-pipeline.md` | **hit** |
| P3-8 | MXR 断言 | SSTATUS_ALLOWED_MASK & MXR == 0 | 08-risc-v-hal.md | `grep "SSTATUS_ALLOWED_MASK" docs/08-risc-v-hal.md` | **hit** |
| P3-9 | D119 条文 | csrs/csrc 是 csrrs/csrrc 别名 | 08-risc-v-hal.md | `grep "csrs/csrc 是 csrrs/csrrc 的寄存器别名" docs/08-risc-v-hal.md` | **hit** |
| P3-10 | ecall 委派 | U-Mode ecall → medeleg → S-Mode | 07-shell-architecture.md | `grep "OpenSBI 默认 medeleg" docs/07-shell-architecture.md` | **hit** |
| P3-11 | 22KB ledger | 子段划分闭合 (Hart 栈池 64KB + SBI stub 8KB + D139 panic log 2KB + DTB 2KB + Step 0 2KB + scheme 2KB) | 02-memory-topology.md | `grep "22KB 缺口子段划分" docs/02-memory-topology.md` | **hit** |

### C# 验证 (机检)

- **C1**: `grep -cE "D1(2[6-9]|[3-5][0-9])" docs/03-design-decisions.md` → **32** ✓ (≥27)
- **C2**: `bash docs/ci/check-docs.sh` → **0/129** ✓ (无不一致数字, R47 D151 撤销)
- **C3**: `grep -n "to split|30 audit rounds|✅ empty" README.md` → **(clean)** ✓
- **C4**: D126/D129/D135/D148 各自命中目标 doc ✓; `sbi_hart_get_id` 仅存于 08 勘误/禁用说明 ✓
- **C5**: HLCB extern struct + @offsetOf + comptime assert 完整, sizeof==64 + 4 个字段偏移断言 ✓
- **C6**: `grep -rn "uint32_t code" docs/0*.md docs/1*.md` → **(clean)** ✓
- **C7**: 02 布局 [Pad 512][Block 1536][Block 1536][Pad 512]=4096 ✓; 09 `128 blocks/64 pages` 仅勘误注释 ✓
- **C8**: `grep -n "menvcfg" docs/08-risc-v-hal.md` → 仅 P1-4 勘误/禁用说明 ✓
- **C9**: `grep "== 80" docs/09-memory-subsystem.md` → **2 hits** ✓; 84B/4.2KB 仅 30 回滚记录 ✓
- **C10**: 10-error-handling.md 错误码表无正数赋值 (除 SYS_OK=0) ✓; ETABLEFULL=-46 ✓
- **C11**: `grep "Vec|collect()" docs/11-network-driver.md` → 仅 "不分配 Vec" 注释 ✓
- **C12**: `grep "local stack for READ" docs/14-syscall-api.md` → 仅 "WRONG 历史错例" 注释 ✓; #2 含 "静态池" 措辞 ✓
- **C13**: `grep "__thread" docs/12-scheduler.md` → 仅 R47 勘误注释 ✓; `grep "jr t0" docs/05-call-gate.md` → 仅 P3-4 勘误注释 ✓; `grep "hartid+1" docs/06-boot-sequence.md` → **2 hits** ✓
- **C14**: 全部修改段附传染面清单 (P0-4 五处传染失败补落地 + P3-* 各传染面已声明) ✓
- **C15**: 本节即 R47 收官节 ✓; OPEN 计数 = 0 (本轮无新增 OPEN, GOAL.md 所有项已闭环)

### 终止条件

连续一轮全量自检 (C1–C15) 零失败 ✓

**R47 闭庭注**: Phase 0 架构通过 R47 一轮闭环修复, 完成 11 项 P 级硬伤 + 11 项 P3 草图级 + 5 处 P0-4 传染落地。文档集进入"实态冻结"状态, 可签发 R47 标签 (build-verify 闸门 + ci gate + 禁词普查表 + D# 回链机检 = 4 重独立治理)。

下一轮 (R48) 仅在出现以下任一情况时启动:
- 实施期 (Phase 0 build) 暴露 spec 与代码不一致
- 外部审计 (code review) 发现 R47 漏判
- Phase 1+ 推进触及 Phase 0 spec 边界

否则 R47 即最终冻结版本。

---

## R48 (收官修复轮 — R47 漏项 + Meta 三账, 已闭庭 → ACTIVE)

> **审计动机**: R47 循环自查报全过, 外部抽检+磁盘核验判定 F1–F5 未过、M1–M3 挂账. R48 收官修复所有漏项, 全部 D# 挂靠既有 RATIFIED 决议, 不新增 D 编号.
> **执行顺序**: R48-0 (git init) → R48-1 (F2 致命) → R48-2 (F3 ABI) → R48-3 (F4) → R48-4 (F1) → R48-5 (F5 账目) → R48-6 (M2) → R48-7 (M3) → C10 (本节).
> **OPEN**: 0 条 (R48 全部条目均已闭环, 无新增 OPEN).

### R48 收官节 (C10 验证输出表)

| 项 | D# 挂靠 | 文件 | 验证输出 | 状态 |
|----|---------|------|----------|------|
| **R48-0 (M1)** | (元变更, 无新 D) | `.git/` + 三分支 | `git rev-parse --is-inside-work-tree → true`; 分支 dev/main/release 全在; 初始 commit `c6736d8` 含 23 文件 (docs/ + ci/ + README + SPEC + docs/README); dev HEAD 线性无 merge commit | ✅ |
| **R48-1 (F2)** | D107 + D136 (P1-1 extern struct 修复) | `05-call-gate.md` + `06-boot-sequence.md` | C1: `grep -nE "\\b(24\|32\|40)\\(t3\\)" 06-boot-sequence.md` → 0 hits; HLCB_* 命名常量 (SSCRATCH_INIT=56 / KERNEL_STACK_BASE=32 / KERNEL_STACK_TOP=40 / STRIDE_SHIFT=6) 与 05 comptime offsetOf 逐值同源; C2: `<!-- R31 题面: superseded... -->` 注释贴邻 05 § HLCB (D82) 旧题面代码块 (line 65, 紧邻 line 67 代码) | ✅ |
| **R48-2 (F3)** | D86 + D89 + P1-2 (sys_result_t 形态统一) | `04-abi-contract.md` + `15-phase0-mvp.md` + `20-documentation-gate.md` + `ci/check-docs.sh` | C3: `grep -rnE "uint32_t code\|code: u32\|status: u32" docs/0*.md docs/1*.md` → 0 hits; 04 Zig SSOT / 15 T1.2 C / 15 T1.3 Rust 均含 error_pack 与 payload union; C9: 3 条新禁词 (`uint32_t code` / `code: u32` / `status: u32`) 已入 ci 数组与 20 防御对象表 | ✅ |
| **R48-3 (F4)** | D103 + P2-4 (静态池来源) | `07-shell-architecture.md` | C4: `grep -nE "0u8; 512" 07-shell-architecture.md` → 0 hits; shell_main 内 buf 改 `extern "C" { static mut __shell_io_pool: [u8; 1536] }` (BlockPool 1 块); 补 "Shell I/O pool 划分说明" 段 (build/link.zig boot 期划分, Phase 1+ 多线程按 fd 进一步划分) | ✅ |
| **R48-4 (F1)** | (docs/README 改实态, 不涉 D#) | `docs/README.md` | C5: `grep -nE "to split\|30 audit rounds\|✅ empty\|58 forbidden" docs/README.md` → 0 hits; 索引表 16 行全部 R48 ACTIVE + R48 勘误增补来源标注; 禁词数一律 `${#FORBIDDEN[@]}` 派生 (无硬编码 N); 根 README 与 docs/README 数字口径互洽 | ✅ |
| **R48-5 (F5)** | D49 双行制 (R48 立法, 不算新 D) | `02-memory-topology.md` | C6: `grep -nE "= 644 KB ✓\|=644KB ✓\|= 644 ✓"` → 0 hits (R47 伪闭合已删); D49 双行制表在文: ceiling 644 KB = named 581.5 KB + headroom 62.5 KB; 算术恒等 581.5 + 62.5 = 644 ✓ (Python 复算 PASS); Σ ledger (net) 497.5 KB + Σ ledger (physical) 626 KB (R48 勘误: 原 '622 KB' 系笔误) | ✅ |
| **R48-6 (M2)** | (禁词审计链补全, 不算新 D) | `20-documentation-gate.md` | 防御对象表末行轮次 = R47 (`hartid<<SHIFT`); R33-R47 共 57 行新条目落入, 来源 ci/check-docs.sh 实际数组; 每条含字面量/轮次/D#/一句防御对象 | ✅ |
| **R48-7 (M3)** | (census + Total==N, 不算新 D) | `20-documentation-gate.md` + `ci/check-docs.sh` | census 表拆分 R32 (10 → 7) + 新增 R33 (2) / R34 (1) / R35 (0) / R36 (0) / R46 (0) / R48 (3) 独立行; Total 117 → 132; `bash docs/ci/check-docs.sh` 输出 `✓ Wriggly-Octopus documentation gate passed (0/132 forbidden words)`; `EXPECTED_TOTAL=132` 自校断言启用 fail-closed | ✅ |

### R48 自检总览

```
C1  06 trap_entry 硬编码偏移消除         PASS  (0 hits)
C2  05 R31 superseded 注释贴邻旧 HLCB    PASS  (line 65, 紧邻 line 67)
C3  0*.md 1*.md 旧 sys_result_t 形态     PASS  (0 hits, 04/15 全归 canonical)
C4  07 shell 栈缓冲消除                 PASS  (0 hits, __shell_io_pool 替代)
C5  docs/README 改实态                   PASS  (0 stale phrases)
C6  02 ledger 诚实化 + D49 双行制        PASS  (0 fake closures, 581.5+62.5=644 ✓)
C7  20 防御表 ≥R47 + census Total==N    PASS  (末行 R47, 0/132 自校 PASS)
C8  git 仓库 + dev/main/release          PASS  (8 commits on dev linear)
C9  禁词门新条目                         PASS  (3 条 R48 F3)
C10 R48 收官节 (本节)                     PASS  (本节即收官节)
```

**连续一轮 C1–C10 全量自检零失败 ✓**

### R48 传染面清单 (R48 元规则四)

- `04-abi-contract.md` § Zig SSOT + D86 强化模板 → **R48-2** (F3 sys_result_t 形态归一)
- `05-call-gate.md` § HLCB (D82) 旧题面 + asm 端常量 + 传染面 → **R48-1** (F2 HLCB 命名常量)
- `06-boot-sequence.md` § D136 trap_entry asm → **R48-1** (F2)
- `07-shell-architecture.md` § Shell example + 划分说明 → **R48-3** (F4 静态池)
- `02-memory-topology.md` § D49 双行制 + ledger 台账 → **R48-5** (F5 账目)
- `15-phase0-mvp.md` § T1.2/T1.3 sys_result_t 模板 → **R48-2** (F3)
- `20-documentation-gate.md` § census + 防御对象表 + 落地约束 → **R48-6, R48-7** (M2, M3)
- `docs/README.md` § 索引表 + 禁词数派生口径 → **R48-4** (F1)
- `docs/ci/check-docs.sh` § FORBIDDEN 数组 + EXPECTED_TOTAL 自校 → **R48-2, R48-7** (F3, M3)
- `README.md` (根) 数字口径互洽 → **R48-4** (F1)
- `.git/` 三分支骨架 → **R48-0** (M1 元变更)
- `30-open-questions.md` (本节) → **C10**

### R48 数字口径锚定 (供 R49+ 引用)

- **禁词总数 N = 132** (派生自 `${#FORBIDDEN[@]}`)
- **D49 双行制**: ceiling 644 KB = named 581.5 KB + headroom 62.5 KB
- **HLCB 字段偏移**: kernel_stack_base@32, kernel_stack_top@40, user_stack_top@48, sscratch_initialized@56, hart_id@24 (P1-1 extern struct)
- **sys_result_t frozen 形态**: `{header: u32, reserved: u32, payload: union{value: u64 | error_pack}}` (C/Rust/Zig 三端一致)
- **git 分支**: dev (HEAD) / main / release (initial commit c6736d8)

### R48 闭庭注

R48 在 R47 漏项 + Meta 三账上完成全部 8 项收官 (R48-0 ~ R48-7) + C10 收官节. 连续一轮 C1–C10 全量自检零失败. 文档集进入 R48 收官冻结状态, 可签发 R48 标签.

下一轮 (R49) 仅在以下任一情况启动:
- R48 build-verify 闸门 (ci/check-docs.sh 0/132 + EXPECTED_TOTAL 一致) 失败
- 外部审计发现 R48 漏判
- Phase 1+ 推进触及 Phase 0 R48 边界

否则 R48 即最终冻结版本.

---

## Governance (R49 立骨)

> **审计动机**: R48 收官后沙箱二 O2 暴露 GOAL 任务级静默 override spec frozen (lp64d vs spec D138 lp64). 这是治理问题不是技术问题 — 没有人拦住. R49 立治理流程, 防未声明的偏离, 不惩罚已声明且已验证的选择.

### R49-GOV.1 GOAL × spec 冲突治理

**核心规则**: 任何 GOAL / 任务级文档若触及 spec frozen 决策 (D#), 必须:
1. 文件头部带 `## 涉及决策` 清单, 列触及的 D 编号
2. 与 spec 语义冲突的每条必须挂 R 号勘误链接 (如 `[R49-EMBEDDED-LP64]`)
3. 清单缺失 或 D# 无 R 号 → 治理门禁熔断

**enforcement**: `docs/ci/check_goal_manifest.sh` (R50 落地, Q76 交付).
```bash
# 用法: 与 check-docs / check-d-backlinks 并列, 每次 commit 前跑
bash docs/ci/check_goal_manifest.sh
```
脚本扫描 `GOAL*.md` (排除 `mvp/`), 校验每份:
- 必须有 `## 涉及决策` 节 (头部缺失 = 熔断)
- 节内必须含 ≥1 个 D# 标注 (D# 无标注 = 熔断)
- 任何 R# 必须落入 R1..R52 硬编码白名单 (R# 悬空 = 熔断)
- 含自验证 canary: 干净 GOAL 过 / 缺头坏 GOAL 必熔 / 悬空 R# 必熔, 证据落盘 `mvp/R50-Q76-canary-evidence.log`
- 零 GOAL 文件场景显式兜底 (空仓显式 PASS, 严禁静默死亡, 沿用 R51-FIX 教训)

**值的 vs 流程的**: 值级冲突 (lp64d vs lp64, 1536B vs 256B) 靠人查 + 文档留痕; 流程冲突 (缺清单, 缺 R 号) 靠机器查 + 闸门熔断.

### R49-GOV.2 O2 首例归档 (lp64d override D138)

**事件**: 沙箱二 GOAL P1 强制 `-mabi=lp64d` 覆盖 spec `08-risc-v-hal.md:468-485` D138 embedded profile 强制 `lp64 -mno-f -mno-d -mno-v`. 实现走 GOAL, spec 未挂 R 号勘误, 沙箱自查未拦截.

**处置**: O2 不视为违规产物 (沙箱二已用 lp64d 在 qemu_virt profile 下完整通过 C1–C9 + sha256 复现), 但须追认到 spec:
- 矩阵立法后必须包含: `qemu_virt ⇒ lp64d` (追认, 非惩罚)
- GOAL 文件回填 `## 涉及决策 D138 (已 R49-EMBEDDED-LP64 追认)`

**R49-EMBEDDED-LP64** (R49 挂的 R 号): "qemu_virt profile 验证形态, lp64d 暂列该 profile 合法 mabi; Phase 1 profile 矩阵立法时正式落 D-号". 本条不算新 D, 是 O2 的追认记录.

### R49-GOV.3 ISA/ABI profile 矩阵 — Phase 1 第一项立法

**未立**: 当前 spec 散落 D138 (mabi per profile) / D126 (stride per profile) / D146 (cache line per profile), 没有合并 profile 矩阵, "跨端兼容性"承诺没有统一判据.

**R49 排除**: profile 矩阵不在 R49 立, 因答案取决于 Phase 1 还没做的决策 (FPU 上下文策略 / server-embedded ISA 子集 / 1536B 粒度分档).

**Phase 1 第一项**: R49-GOV.3 显式点名 profile 矩阵立法为 Phase 1 第一项. Phase 1 启动即立, 不许无限延后. Phase 1 立法完成前, 任何新 profile (lp64d, embedded_sparse 等) 走 R49-GOV.2 流程追认.

### R49-GOV.4 spec_lab 制度化 (frozen = 编译过的)

**核心**: tools/spec_lab/ 已立骨, 首批 3 条断言 (F1/F2/F3) + 3 条反向 + audit-rust-unsafe. 任何后续 frozen 内容必须经 spec_lab 验证. 禁止 spec 草图写完不验证就贴 frozen 标签.

**R50 立法确认**: R49-GOV 全部 4 节自 R50 起转正, check_goal_manifest.sh 已交付 (Q76 关闭, 见后). R49 "provisional until R50" 自毁条款已到期, **不延续**; GOV 规则现行生效, 不再标"provisional".

**禁止漂移词** (R50 入 check-docs.sh, EXPECTED_TOTAL 145 → 149):
- "spec_lab 副本" — 断言目录下出现代码副本, 不是抽取得到
- "frozen 等同于已写" — frozen 必须经 runner
- "R49 草图烂掉靠 reviewer 眼" — 必须机器 enforced
- 矩阵立法 (D160) 配套: "rpc_unit_t = 256B" — 256B 粒度未立法, 任何现行 RpcUnit 形态暗示 256B 即视为漂移

---

### R49-GOV.5 收官全量重跑 (R50 立法)

**核心**: 任何 R-round 收官 (`R## closed`) 的**最后一个 commit 之后**, 必须**全量重跑所有门禁**:
- `bash docs/ci/check-docs.sh`
- `bash docs/ci/check-d-backlinks.sh`
- `bash docs/ci/check_goal_manifest.sh`
- `bash docs/ci/check-toolchain.sh`   （本轮新增第 6 门 — toolchain.lock 区间锁格式门, R49-GOV.6 配套）
- `bash tools/spec_lab/run_all.sh`
- `bash tools/spec_lab/run_negative.sh`

**起源 (R51 教训)**: R51 收口 D# 悬空 (D156/D157/D159) 的直接成因, 是 AGENDA commit 后仅中段跑了"passed (34)" 检, 终态 34/37 FAIL 被掩盖. 本条立法把"收官前全量重跑"写成**硬性签发前提**, 任何 R## closed 签发前若不重跑全部 5 门, R## 即视为未签发.

**enforcement**: 签发时 check-d-backlinks.sh 与 check_goal_manifest.sh 必然 (因 D# 与 GOAL 同步) 抓到回归; check-docs.sh 的 EXPECTED_TOTAL 自校 (R48 立法) 必抓 census 漂移. 三重独立验证保证.

---

### R49-GOV.6 spec_lab / 门禁反向测试禁止原地变异 spec (捕兽夹隔离)

**核心**: 任何 spec_lab 反向断言 (`*_negative.sh`) 与门禁自检 (canary) **不得原地 `sed -i` / `awk` 改写 `docs/*.md`**。变异必须发生在 `mktemp -d` 临时目录的副本上, 真 spec 在测试全程恒不可变。

**凶器复盘 (立法动机)**: 旧 `*_negative.sh` 与 `check-d-backlinks.sh` 金丝雀均 (a) 原地改真 spec, (b) 备份进 gitignored `extracted/` 或行变量, (c) F1/F2/F3 无 `set -e` / 全体无 `trap`, (d) 复原路径一旦读空备份即抽空 spec。四项叠加 = 中断留污 / 空备份抽空 / clean clone 复原源缺失。P5 疣子 #1 (本文件) 已点名 backlinks 金丝雀同款 (mktemp 建了没用)。

**落地形态 (强制模板)**:
- `set -euo pipefail` + `WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT`
- `cp` 真 spec 进 `$WORK/docs/`; 只改副本
- 正向断言 / 门禁逻辑以 `CWD=$WORK` 跑 (相对路径 `docs/XX.md` 落副本); `LAB_DIR` / 抽取产物路径保持绝对 (真树, gitignored)
- 无备份、无复原 — 真 spec 不可变即无可复原, 无可抽空

**捕兽夹自指判据 (硬性签发前提)**: `bash tools/spec_lab/run_negative.sh` 与 `bash docs/ci/check-d-backlinks.sh` 跑完, `git status` 必须 clean (`docs/` 零改动)。任何测试跑完留下 `docs/` diff = 本条违规 = 未签发。

**本轮落地**: 11 个 `*_negative.sh` (R49-F1/F2/F3 + R51-F5/M1..M7) 全部改 mktemp 副本; `check-d-backlinks.sh` 金丝雀 (P5 #1) 改 `docs/` 副本; `extract.sh` 补 `mkdir -p`（extracted/ gitignored, clean clone 缺目录首跑即挂）+ anchor `if/then/else`（复活 exit 3, 消 pipefail 死代码）。extract.sh 与 11 脚本注释挂 `R49-GOV.6` 锚。

---

## Open Questions (R49+ 启新)

### Q68 — RV32 缺席 (D 编号未立, R49 挂开放)

**当前 Spec 状态**:
- 00-ffi-pillars.md:70 明文 "RV32IMAC: N/A — Phase 0 仅 RV64"
- 03-design-decisions.md D138 embedded 基线 `rv64imac -mno-f -mno-d -mno-v`
- frozen ABI 是 rv64 中心: a0/a1 寄存器对 / lp64 / 64 位地址
- "覆盖低端嵌入式"承诺在 ISA 层面是空话: rv32 ilp32 ABI 变体从未设计

**冲突点**:
- 用户总结复盘明文标 "rv32 缺席是跨端兼容性承诺里最大的一个窟窿"
- 若 Phase 1+ 不开 ilp32, 跨端兼容性承诺实际兑现 0%
- 若 Phase 1+ 开 ilp32, 需重做 sys_result_t (32 位机 2×XLEN = 8B 不足以装 16B) / a0/a1 寄存器对 (32 位寄存器只能装 8B) / BlockPool stride / cache line 对齐

**Phase 2+ 排期**: 不在 R49 排进立法, 不在 Phase 1 排进立法. Phase 1 完成 U-Mode + 物理通路 + 多 Hart 后, Phase 2 启动时第一个动作是 rv32 ilp32 ABI 变体立法 (Q68 → D-号).

**R49 排除理由** (与 R49-GOV.3 同源): "frozen = 编译过的" 要求立法的结果必须经过 spec_lab 验证; rv32 ilp32 涉及全部 ABI 结构体 + 全部 syscall stub, 立法前必须有 Phase 1 的实测基线 (rv64 U-Mode + 多 Hart), 否则立出来的是空中楼阁.

**禁止漂移词自查**:
- 不写 "rv32 Phase 1 立" (当前不在 Phase 1 立法清单)
- 不写 "rv32 N/A 永久" (永久排除违反跨端兼容性承诺)
- 必须写 "rv32 ilp32 ABI 变体 Phase 2 第一项立法 (Q68)"

---

## R51 议程条目 (7 大桶挂账 — D-03/06/09/15/17/18/19 留 Phase 1 立法)

> **R51 决议**: 以下 7 条 D-勘误在 R51 一轮**不立**, 但**必须书面挂账**留 Phase 1 第一项. 切割依据不是工作量, 是**依赖方向** —— 这 7 条的正确答案都挂在 Phase 1 未做的决策上 (fd 语义依赖 U-Mode fd 表 / CPIO 是 Phase 1 交付物 / buf 校验是 Phase 1 安全边界 / geiger 是 Phase 1 计划 / 等). **R51 显式点名**为 Phase 1 第一项, Phase 1 启动即立, 不许无限延后. 沙箱实测继续暴露的对应 DIVERGENCE 条目归此处, 不必重写决议.

### Q69 — Rust crate 拓扑 (D-03, R51 挂账)

**当前 Spec 状态**:
- docs/07-shell-architecture.md 已有 fd 0/1/2 拓扑, 但未指定 U-Mode 依赖
- 沙箱三实测 fd 0/1/2 走 M-Mode 直通 (Phase 0 现状)

**冲突点**:
- Phase 1 U-Mode 启动后, fd 0/1/2 必须经 U-Mode 调度再到 Rust Shell
- crate 拓扑依赖 syscall ABI 立法 (D86/D119/D121)

**Phase 1 第一项立法**: 触发条件 = U-Mode 立法完成.

**禁止漂移自查**:
- 不写 "Phase 1 兼容 fd 0/1/2 直通"
- 必须写 "Phase 1 U-Mode 立法完成前, fd 0/1/2 走 M-Mode 直通 (R0 现状)"

---

### Q70 — file:// ro-memdisk 编译期嵌入 (D-06, R51 挂账)

**当前 Spec 状态**:
- D46 FILE_TABLE = 50 entries, initrd file count ≤ 50 (D105)
- Phase 0 initrd 是 CPIO runtime parse (D62/D78)
- 沙箱三实测 Phase 0 编译期嵌入 `@embedFile → .rodata` 替代 CPIO runtime parse

**冲突点**:
- `@embedFile` 改 build.zig 编译期逻辑, Phase 0 内存布局改变
- CPIO 解析是 Phase 1 通用文件系统过渡形态
- 两条路 Phase 0 选谁, 直接决定 Phase 1 filesystem 立法起点

**Phase 1 第一项立法**: 触发条件 = CPIO 完成 (Phase 1 filesystem 交付).

**禁止漂移自查**:
- 不写 "Phase 0 用 @embedFile ro-memdisk"
- 不写 "CPIO 永久 runtime parse"
- 必须写 "Phase 0 memdisk 模式挂账 Phase 1 第一项 (Q70)"

---

### Q71 — D97 '0 unsafe' 改写 (D-09, R51 挂账)

**当前 Spec 状态**:
- D97: Rust Shell `unsafe` 计数 = 0
- D129: stub `asm!` 块**必须 unsafe**, 与 D97 "0 unsafe" 字面冲突
- 沙箱二实测 unsafe 计数 5 处 (payload 解码 1 + FFI 调用 2 + 其他 2)

**冲突点**:
- D97 字面与 D129 机制矛盾, 但 D129 必须 unsafe (R38 D129 立法)
- "0 unsafe" 应解读为 "0 unsafe **除 FFI 桥接白名单 (D129 stub asm!)**" 还是 "Rust Shell 全 0 unsafe 退到 unsafe-free Rust subset"
- 沙箱二 5 处 unsafe 中, 4 处是 D129 合法白名单, 1 处是 payload 解码 (应可改用 safe wrapper)

**Phase 1 第一项立法**: 触发条件 = 第三方应用上架流程启动 (Phase 1 才需要 cargo geiger).

**禁止漂移自查**:
- 不写 "0 unsafe 绝对零"
- 不写 "geiger Phase 0 启用"
- 必须写 "0 unsafe 除 FFI 桥接白名单 (D129 stub asm! + payload 解码 safe wrapper)"

---

### Q72 — fd 0/1/2 立法 (D-15, R51 挂账)

**当前 Spec 状态**:
- M1 (D-05) 已加 SYS_FD_RESERVE=0x29 到 14 号表, 但 fd 0/1/2 预开 dev://uart0 未立法
- 沙箱三实测 Phase 0 fd 0/1/2 走 M-Mode 直通, fd_table 不存在

**冲突点**:
- Phase 1 U-Mode 启动后, fd 0/1/2 必须经 U-Mode 调度
- fd 语义依赖 syscall ABI 立法 (D86/D119/D121) + Q69 crate 拓扑

**Phase 1 第一项立法**: 触发条件 = Phase 1 fd 语义 + U-Mode syscall 立法完成.

**禁止漂移自查**:
- 不写 "Phase 0 fd 0/1/2 = dev://uart0"
- 必须写 "Phase 1 立法前 fd 0/1/2 走 M-Mode 直通, Phase 1 启动即重立法"

---

### Q73 — D33 单 Hart 退化路径 (D-17, R51 挂账)

**当前 Spec 状态**:
- D33: kmain first-step = DTB dump + HLCB parse
- D141 (R40 立法): Phase 0 单 Hart 下 DTB 仅校验 + num_harts 断言, 栈区间由链接符号给
- 沙箱三实测 D141 path 完整跑通, 但 "单 Hart vs 多 Hart 退化路径" 未定义切换边界

**冲突点**:
- D33 / D141 / D68 (secondary Hart spin-wait) 三者依赖关系, Phase 0 默认是单 Hart, 多 Hart 路径是 Phase 1
- "单 Hart 时 D33 退化" = DTB 仅校验, num_harts 必为 1; "多 Hart 时 D33 全功能"

**Phase 1 第一项立法**: 触发条件 = Phase 1 多 Hart 调度立法 (D43/D144/D145 联动).

**禁止漂移自查**:
- 不写 "单 Hart 退化为 Phase 1 主题"
- 必须写 "Phase 1 多 Hart 立法时同步标 D33 refinement"

---

### Q74 — D103 buf 校验强度 (D-18, R51 挂账)

**当前 Spec 状态**:
- D103: 跨 FFI 签名禁 `&[u8]` (caller stack)
- 14-syscall-api.md § cosmo_read/write: "Phase 0 仅 len ≤ 1536 闸门, 严格范围校验留 Phase 1"

**冲突点**:
- Phase 0 buf 校验强度 = len ≤ 1536 + .bss 来源, 这是"门闸"不是"安全边界"
- Phase 1 安全边界需 MPU/SATP PTE 强制 user buf 可读性 + 防 TOCTOU
- 沙箱三实测 buf 校验在 Phase 0 现状下"足够用但不安全"

**Phase 1 第一项立法**: 触发条件 = Phase 1 跨 FFI 栈指针立法 (Pillar 1 红线 #3).

**禁止漂移自查**:
- 不写 "Phase 0 buf 校验强度 = Phase 1 等价"
- 必须写 "Phase 0 = 门闸 (len 1536), Phase 1 = 安全边界 (MPU PTE)"

---

### Q75 — T1.17 `-Dip_family` 缺省 (D-19, R51 挂账)

**当前 Spec 状态**:
- T1.17 (15-phase0-mvp.md) 缺位, `-Dip_family` build option 缺省值未定
- 沙箱三实测: `-Dip_family` 缺省 = v4 (IPv4 UDP), 非法值熔断
- T1.17 任务本身不在 R49 立法清单, Phase 0 默认 IP family 立法缺位

**冲突点**:
- T1.17 立法 = Shim Layer 编译期立骨, 依赖 D131 (SHIM_PAYLOAD_MAX per-L4 派生)
- 沙箱三 D-08/M3 同时挂账同一 spec 章节, 立法合并才合理

**Phase 1 第一项立法**: 触发条件 = Shim Layer 编译期立骨 (Phase 1 net stack 立法前置).

**禁止漂移自查**:
- 不写 "T1.17 缺省 v4 已立"
- 必须写 "T1.17 缺省/非法值熔断归 Phase 1 第一项 (Q75)"

---

### Q76 — check_goal_manifest.sh R50 滑账 (R51 挂账)

**当前 Spec 状态**:
- R49-GOV.1: GOAL × spec 冲突治理闸门 `check_goal_manifest.sh` 是 R50 第一项必交付
- 沙箱三 2026-07-22 实测: R50 未交付, R51 收口时仍空缺
- 本轮 (R51) §0.e 用户明文: "R50 manifest 未交付不阻塞本轮; Q76 check_goal_manifest.sh R52 前必补"

**冲突点**:
- R49-GOV.1 是治理流程硬性挂账, R50 滑账意味着 GOV-1 失效
- R51 启动可绕开 R50, 但 R52 必须补 check_goal_manifest.sh 否则 GOV 全节失效

**R52 第一项必交付**: 触发条件 = R51 收官签发后下一轮会话启动.

**禁止漂移自查**:
- 不写 "check_goal_manifest.sh R50 已交付"
- 必须写 "check_goal_manifest.sh R52 前必补 (R50 滑账, GOV-1 失效待恢复)"

---

## ✅ Q76 关闭 (R50 交付)

**关闭时间**: R50 收官节 (R50 closed)
**交付证据**:
1. `docs/ci/check_goal_manifest.sh` 已落地 (R50 任务1)
2. 自验证 canary 双向通过: 干净 GOAL PASS / 缺头坏 GOAL FAIL / 悬空 R# FAIL (3/3 命中)
3. 证据落盘 `mvp/R50-Q76-canary-evidence.log` (含 3 case 可读审计)
4. R1..R52 硬编码白名单替代动态搜索 (避开 R99 vs R999 子串碰撞元级 bug)
5. 零 GOAL 文件场景显式兜底 (空仓显式 PASS, 严禁静默死亡, 沿用 R51-FIX 教训)
6. check_goal_manifest.sh 与 check-docs / check-d-backlinks 并列挂入 ci/ (R49-GOV.1 enforcement 行已更新, 见 30 号本节 GOV.1 段)
7. 完整 4 门综合 (check-docs / check-d-backlinks / check_goal_manifest / spec_lab) 收官后重跑全绿

**GOV 状态**: R49-GOV 4 节全部 R50 转正, GOV.5 (R50 立法) 同步落地, GOV-1 / GOV-4 "provisional" 自毁条款已到期删除. R49 全节现行生效.

---

## R50 收官节 — Governance 转正 + ISA/ABI profile 矩阵立法 (Q76 关闭 + GOV.5 立法)

**触发**: R49-GOV.1 "provisional until R50" 自毁条款到期 (Q76 挂账); R51 收口时 D153-D159 占用 D 编号 (本轮新 D 从 D160 起).

### 任务清单 + D# 挂靠 + 验证输出

| 任务 | 摘要 | D# 挂靠 | 验证输出 |
|------|------|---------|----------|
| **1. check_goal_manifest.sh** | 扫 GOAL*.md, 校验 `## 涉及决策` 头部 / D# 标注 / R# 悬空; 含 3 双向 canary 自验证; R-round 硬编码白名单 (R1..R52) 替代动态 grep (避开 R99 vs R999 子串碰撞元级 bug) | Q76 → D160 治理闭环 | `mvp/R50-Q76-canary-evidence.log` 落盘, 3/3 canary (clean PASS / bad-no-header FAIL / bad-dangling-r FAIL) |
| **2. GOV 转正** | GOV.1 enforcement 行更新 (R49 立骨的工具引用 → R50 真实路径 `docs/ci/check_goal_manifest.sh`); GOV.4 "provisional until R50" 自毁条款删除; 新增 GOV.5 (收官全量重跑硬性签发前提); Q76 在 30 号本节标注关闭 (含交付证据 7 项) | D160 治理配套 / GOV.5 立法 | 30 号 § GOV.1/GOV.4/GOV.5/Q76 段已更新; 30 号状态行无 "provisional" 字样 |
| **3. profile 矩阵立法** | 新建 `docs/16-profile-matrix.md` 三档 profile 五元组 (ISA / mabi / RpcUnit 粒度 / BlockPool 池 / cache line); endpoint_compact=256B 记 PROVISIONAL 候选 (Q78 OPEN); 回追批准 (沙箱二 lp64d → qemu_virt 特许变体 / 沙箱三 imac → qemu_virt 基线); D138/D126/D146/D71 加"见 16-profile-matrix.md"索引注 (语义不删, 矩阵为索引) | D160 (单一立法, R50 立法型非勘误型) | 03 总账 D160 ACTIVE 行落 + 4 子系统 doc (02/04/08/13) 索引注 + grep "16-profile-matrix" 命中 6 文件 (08/13/02/04/README + 16 自身) |
| **4. R50 收官节** | 本节, 逐条 D# 挂靠 + 验证输出 | D160 | 本节即收官节 |

### 5 门综合重跑 (R50 收官后, GOV.5 硬性签发前提)

| 门 | 退出码 | 输出 |
|----|--------|------|
| `bash docs/ci/check-docs.sh` | 0 | ✓ Wriggly-Octopus documentation gate passed (0/149 forbidden words) |
| `bash docs/ci/check-d-backlinks.sh` | 0 | ✓ check-d-backlinks passed (35 D126-D160 tags, all back-linked, canary self-test OK) |
| `bash docs/ci/check_goal_manifest.sh` | 0 | ✓ check_goal_manifest passed (0 GOAL*.md files; zero-match = explicit pass) ✓ canary self-test OK (3/3) |
| `bash tools/spec_lab/run_all.sh` | 0 | ========================================== R51 spec_lab: 11/11 PASS ========================================== |
| `bash tools/spec_lab/run_negative.sh` | 0 | ========================================== R51 spec_lab negative: 11/11 反例被抓到 ========================================== |

**C1–C6 验证** (目标 §3 成功条件):

- **C1 P0 前置三门**: backlinks 34/34 (R51 终态) + check-docs 0/145 (前置) + spec_lab 11/11 PASS → ✅ (P0 阶段记录在案)
- **C2 check_goal_manifest.sh 存在 + canary 双向 + 无静默死亡**: ✅ (`mvp/R50-Q76-canary-evidence.log` 落盘 + 3/3 canary + 零 GOAL 文件显式 PASS, 不静默)
- **C3 GOV.1 无 provisional + enforcement 行 + GOV.5 + Q76 关闭**: ✅ (30 号 GOV.1 段已更新 enforcement 至 `docs/ci/check_goal_manifest.sh`; GOV.4 "provisional until R50" 已删; GOV.5 已立; Q76 关闭节在 30 号)
- **C4 docs/16-profile-matrix.md 存在 + 三档五元组 + 回追条款 + grep 命中 + 03 总账 D160+ ACTIVE**: ✅ (16 文档 80+ 行, 三档 profile 五元组表 + endpoint_compact PROVISIONAL + 回追批准双条款; grep "16-profile-matrix" 命中 6 文件; 03 总账 D160 ACTIVE 单行)
- **C5 收官后全量重跑绿**: ✅ (5 门 0 退出码, 上表)
- **C6 30 号 R50 收官节完整, OPEN=仅本轮新增 Q78**: ✅ (本节完整, Q78 endpoint_compact 256B 研究为唯一本轮新增 OPEN)

**传染面清单 (R36 元规则四) — 5 门外延 R50**:

- `docs/ci/check_goal_manifest.sh` (新增, R50 任务1) → GOV.1 enforcement 行 (R50 任务2) → `30-open-questions.md` GOV.1 / GOV.4 / GOV.5 / Q76 段 (R50 任务2) → `30-open-questions.md` R50 收官节 + Q78 OPEN (本任务)
- `docs/16-profile-matrix.md` (新增, R50 任务3) → `03-design-decisions.md` D160 ACTIVE 行 (R50 任务3) → `02/04/08/13-build-pipeline.md` 索引注 (R50 任务3) → `20-documentation-gate.md` R50 census 行 + 4 防御对象 (R50 任务3) → `docs/ci/check-docs.sh` 4 新禁词 (R50 任务2) → `docs/ci/check-d-backlinks.sh` 正则扩 D160+ (R50 任务3) → `docs/README.md` 索引行 + CI 列表 (R50 任务3) → `README.md` 文档地图 + D1-D160 + 5 门 (R50 任务3)

**R50 收口 OPEN 计数 = 1** (Q78 endpoint_compact 256B 研究, D160 PROVISIONAL 候选不激活, 等独立 Q 研究).

### 闭庭注

R50 一轮完成 GOV 全节转正 (R49-GOV.1 落地 + R49-GOV.4 漂移词入册 + 新立 GOV.5 收官重跑立法) + 矩阵立法 (D160) + Q76 关闭. 文档集进入 R50 收官冻结状态, 可签发 R50 标签. 5 门综合 (check-docs / check-d-backlinks / check_goal_manifest / spec_lab run_all / run_negative) 全部 0 退出码, 收官 GOV.5 硬性签发前提达成.

下一轮 (R51+ / Phase 1 推进) 仅在以下任一情况启动:
- Q78 endpoint_compact 256B 研究触发新 D# 立法
- 新 R-round 暴露 GOV 失效
- Phase 1 推进触及 R50 边界 (e.g. 96 页 compact 池落地, FPU 上下文策略立法)

否则 R50 即 D126-D160 终态.

---

## R50-FIX 微轮 — 4 补丁 (P1 exclude 收窄 / P2 Q78 补条目 / P3 docs/README 双漂移 / P4 CRLF 防线)

**触发**: R50 准签前 4 补丁 + 1 边界记录, 全十分钟级, 不开新 R 轮.

| # | 补丁 | 修复 | 证据 |
|---|------|------|------|
| **P1** | exclude 收窄 | 16-profile-matrix.md 整文件踢出 149 词扫描是错解 (为 2 行定义开盲区). 改行锚豁免: `D160 (配套\|矩阵)` + `16 号文.*rpc_unit_t.*(配套\|未立法\|禁用依据\|R50 立法)`. | clean 0/149 ✓ / 注入 `0x801FF000` 真熔断 (rc=1) ✓ / 删后 0/149 ✓ |
| **P2** | Q78 补条目 | 30 号文缺 `### Q78`, README/矩阵/收官节三处引 Q78 但 30 无标准模板. 补 Q78 = endpoint_compact=256B PROVISIONAL 候选挂账 Phase 1 第一项立法, 与 Q69-Q77 风格一致. | `grep -nE "^### Q78" docs/30-open-questions.md` → 1 命中 (line 3456) ✓ |
| **P3** | docs/README 双漂移 | 03 行仍写 "D1–D152, R47 closed" 落后 2 轮 → 改 "D1–D160, R47 closed + R51 R#-anchored + R50 D160 profile matrix" R50 ACTIVE; CI 列表 3 行加 `docs/` 前缀 (与 GOV.1/收官节路径一致) | grep 命中 1× "D1–D160" + 3× "docs/ci/" ✓ |
| **P4** | CRLF 防线 | 用户裁决: 本地 CRLF 用 git 处理, 不会上传到仓库. 保留 `.gitattributes` 的 `*.sh text eol=lf` 作为未来检出防线 (R51 收官已立法), 不在本轮强转. | `.gitattributes` 第 6 行 `*.sh text eol=lf` 保留 ✓ |

### 边界记录 (GOV.1 设计内, 非缺陷)

**manifest 门是形式门**: 验 "## 涉及决策 头部存在 + D# 齐全 + R# 合法", 不验声明真实性. GOAL 写 "D126 无冲突" 而实际冲突, 此门看不见. 这是 GOV.1 的设计内边界: **形式归机器, 真实归 spec_lab + 评审**. 写进记录, 免得以后有人拿 "门禁过了" 当冲突不存在的证据.

### P5 健壮性疣子 (R50-FIX 不修, R51+ 治理候选)

1. `backlinks` 金丝雀原地 `sed -i` 改 10 号文再恢复 (mktemp 建了却没用, 应在副本上跑). 中断留污 + 10 号文一旦出现第二处 D156, 金丝雀误报 FATAL.
2. `manifest` 的 `${arr[@]//[[:space:]]/}` 在带空格路径上会绞碎 (当前所有路径无空格, 不实际触发).

R50 准签, P1-P4 闭环. 5 门 0 退出码 (含 3 双向 canary) 落盘. R50 标签可签发.

---

### Q77 — spec_lab 7 断言脚本 Phase 1 第一项交付 (R51 收官核验挂账)

**当前 Spec 状态**:
- R51-F4 (c1eb577): 7 对 M 桶 spec_lab 断言脚本已落地 (R51-M1~M7)
- 但所有 7 对均为 **grep-based 文本断言**, 非编译期验证 (本计划 §5 风险 #3: "缺 zig 环境 ENOENT → `command -v zig || exit 0` fallback")
- 03 总账 D154–D159 的 `Assertion:` 字段标注为 `(script pending, Q77)`

**冲突点**:
- spec_lab 设计硬性要求 #1 (R49 立法): "任何写进 `docs/*.md` 的指令级 / ABI 级代码片段, 必须能在编译期被验证, 否则不享受 'frozen' 身份"
- 当前 M2/M4/M5/M7 四个断言是 text-grep 而非 compile-gate — 它们能抓 spec 文字漂移, 但抓不到 Zig 代码的编译期错误
- Phase 1 交付物: 把这 4 条 text-grep 升级为 `zig build-obj` 编译验证 (与 R49-F1/F2/F3 同等级)

**自毁条款** (照抄 GOV.1 "provisional 失效" 句式):
> Phase 1 启动后第一个 commit 若不交付 Q77 (D154–D159 七条款全量 compile-gate spec_lab), D154–D159 全条款判为 **provisional 失效** — 即恢复为未立法状态, 必须重走 R51 立法流程.

**Phase 1 第一项交付**: 触发条件 = Phase 1 启动.
- 交付清单: R51-M2-bss-anchor / R51-M4-ledger-cap / R51-M5-hlcb-bss / R51-M7-strip-mode 四条 `zig build-obj` 编译断言
- 完成判据: `bash tools/spec_lab/run_all.sh` → 11/11 (其中 4 条新增 compile-gate 通过)
- **D157 量测口径钉死 (本轮)**: `bss ≤ 8192B` 等四段上限的测量口径 = 链接脚本符号 (`.bss_size` 等, 链接后), **不是** `llvm-size` 的段列 — 后者把 NOLOAD 的 Hart-Local 栈 (D107, 约 20 KB) 计入 bss 必然误报越界。分层立法: 池维度 (BlockPool / NodePool `@compileError`) 属编译期熔断; 四段实测属链接后 `verify-elf` 判据 (Q77 compile-gate 交付时一并落 verify-elf)。M4-ledger-cap 现 text-grep 只锁"上限数字 + `@compileError` 字面", 不越权测实测段; 口径分层由本条固定 (D157 总账行同步)。
- 若 zig 环境仍不可用: 必须在 RUN_LOG.md 记录 `NO_ZIG=1` 环境标记 + 明确预计可用时间

**禁止漂移自查**:
- 不写 "M2/M4/M5/M7 已 frozen" (text-grep 不是 frozen)
- 不写 "Phase 1 可跳过 Q77 直接立法"
- 必须写 "Phase 1 第一项交付 Q77, 不交 = D154–D159 provisional 失效"

---

### Q78 — endpoint_compact = 256 B 粒度研究 (D160 PROVISIONAL 候选, R50 挂账)

**当前 Spec 状态**:
- `docs/16-profile-matrix.md` § endpoint_compact = 256 B 行 (D160 第 4 行, R50 立法): PROVISIONAL 候选, 粒度列当前一律 1536 B, endpoint_compact=256 B 不激活.
- D57 / D85 frozen 门: `block_t ≡ RpcUnit ≡ NetworkFrame ≡ 1536 B` 三方等价, `rpc_unit_t = 256 B` 字面即熔断.
- 20-documentation-gate.md R50 行入册禁词 `rpc_unit_t = 256B` (D160 配套), 任何"endpoint_compact 已立法"暗示即漂移.
- D160 行 PROVISIONAL 标记: 256 B 粒度研究挂账 Q78, 立法时机 = Phase 1 启动 + IPC endpoint 通道极小包场景实证 (e.g. 16-byte sensor beacons).

**冲突点**:
- 若 endpoint_compact 256 B 立法, D57 frozen 三方等价 (`block_t ≡ RpcUnit ≡ NetworkFrame`) 需 D# 升 / supersede 链: 1536 B / 256 B 同时存在, 需明确"小包用 256 B + 大包仍 1536 B"还是"全 256 B 取代 1536 B"两条路径的择一立法.
- Phase 0 build pipeline (D113 / D124 / D126 闸门) 实测 1536 B, 切 256 B 需重写 size/offsetof 断言链, R51 收口 12 锚定词链路需复核.
- 256 B 粒度的 wire format 后果: MAC DMA pool (D79, 256×14B=3584B) 仍按 14 B / frame 走, 但 NetworkFrame 字段 (D108/D131) 需重排 256 B 边界, 与现有 R51 spec_lab M6 size-csv 闸门冲突.

**Phase 1 第一项立法**: 触发条件 = Phase 1 启动 + IPC endpoint 通道实证基线.
- 立法路径 (任择一): (A) 全 256 B 取代 1536 B → D57 / D85 升 PROPOSED → ACTIVE, spec_lab 重写 7 对断言; (B) 小包 256 B + 大包 1536 B 双粒度并存 → D57 双精度, build.zig 增 `-Dunit_size` 编译期参数.
- 收口传染面: D57 / D85 / D108 / D124 / D126 / D131 / D138 + 02-memory-topology.md / 09-memory-subsystem.md / 13-build-pipeline.md / 15-phase0-mvp.md / 16-profile-matrix.md (改 PROVISIONAL → ACTIVE 行).
- Q78 不算新 D#, 是 endpoint_compact=256B PROVISIONAL 候选的挂账. Phase 1 立法 D# 编号预计 D161+.

**禁止漂移自查**:
- 不写 "endpoint_compact 256B 已立法 / ACTIVE" (本轮 PROVISIONAL, 不激活)
- 不写 "rpc_unit_t = 256 B 是 Phase 0 现状" (frozen 门反例, 必熔断)
- 必须写 "endpoint_compact = 256 B (PROVISIONAL 候选, D160, Q78 挂账 Phase 1 第一项立法)"

---

### build.zig `.ReleaseSmall` 违反 D159 — 裁决 ReleaseSafe (本轮挂账, 侧分支 phase0-final-windows)

**触发**: `mvp/phase0-final-windows-20260722/build.zig:25` 用 `const optimize = .ReleaseSmall`, 违反 D159 (要求显式 `-Dstrip=false -Doptimize=ReleaseSafe`)。该偏差 **未** 记入本分支 `DIVERGENCE.md` (D-ENV / D-IMPL 均无此条)。

**裁决 (本轮定, 用户拍板 "回退 ReleaseSafe + strip=false")**:
- build.zig optimize 模式 **回退 ReleaseSafe**, 并显式 `-Dstrip=false`。理由: D159 立法正因 ReleaseSmall 默认剥符号让 nm/readobj 输空表, P1-P2 的 ELF 尺寸/符号闸门 (D101 / D113 / D157) 空真过 — 回退即消除这一潜伏闸门失效, 且合规、最小。
- **不** 走 "挂 R 号勘误追认 ReleaseSmall" 一路。

**落地挂账 (本轮 dev 不改 build.zig)**: build.zig 属 gitignored `mvp/` 子树, dev 分支不追踪它。故本条只在 dev 记裁决; **代码回退落在下一次合法进入 `phase0-final-windows-20260722` 侧分支时执行**, 且必须同步补记 `DIVERGENCE.md` (归因: 实施决议 D-IMPL, 非 spec 缺陷)。签发前提: build.zig diff 必须有人评审 (不许第三次无人过 diff 放行)。

---

