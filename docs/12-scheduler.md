# 12 · Scheduler (Sched-Ops Pluggable + FS/VS Lazy Save)

**Plan section**: §十二
**Key decisions**: D10, D43, D48, D104
**Status**: Frozen; Phase 0 RR, Phase 1+ Work-Stealing pluggable

---

## Overview

The scheduler uses a **Sched-Ops pluggable interface** so that Round-Robin (Phase 0) and Work-Stealing (Phase 1+ Server) can be selected at build time without changing the syscall API. FS/VS vector registers use **lazy save** (D104) — only persisted when the previous task actually dirtied them. This gives embedded endpoints zero context-switch tax and server endpoints correct RVV semantics.

## Sched-Ops interface

```c
// kernel/sched/sched_ops.h
typedef struct {
    void (*init)(void);
    int  (*pick_next)(void);              // returns task id, -1 = idle
    void (*enqueue)(int task_id);
    void (*dequeue)(int task_id);
    void (*tick)(uint64_t now);           // D21: time-based tick
    const char *name;
} sched_ops_t;

extern const sched_ops_t sched_rr_ops;        // D10: Round-Robin
extern const sched_ops_t sched_worksteal_ops; // D43: Work-Stealing
```

Build-time selection (`-Dsched=rr` or `-Dsched=worksteal`):
```zig
pub const sched_ops = switch (build_options.sched) {
    .rr => &sched_rr_ops,
    .worksteal => &sched_worksteal_ops,
};
```

## Phase 0: Round-Robin (D10)

```c
static int rr_pick_next(void) {
    static int last = -1;
    // P3-5 (R47 勘误): 冷启动时 last == -1, 第一次 next = 0, 立即 next == last 假命中 → 死循环。
    // 改扫 MAX_TASKS 次上界, 退化为 O(N) 但永不死锁。
    int scanned = 0;
    int next = (last + 1) % MAX_TASKS;
    while (scanned < MAX_TASKS) {
        if (task_table[next].active) {
            last = next;
            return next;
        }
        next = (next + 1) % MAX_TASKS;
        scanned++;
    }
    return -1;  // 全表扫描完毕无 active 任务
}

static void rr_tick(uint64_t now) {
    if (now - current_task->quantum_start > TIME_SLICE) {
        enqueue(current_task->id);
        schedule();
    }
}
```

**Properties**:
- O(1) enqueue/dequeue
- O(N) pick_next where N = number of tasks
- No lock contention (Phase 0 single Hart)
- Zero-firmware tax: tick = `csrr time` (D21)

## Phase 1+: Work-Stealing (D43 + D111)

```c
typedef struct {
    int task;
    struct work_item *next;
} work_item_t;

typedef struct {
    work_item_t *head, *tail;
    AtomicBool lock;  // or csrc sstatus, SIE fallback
} work_queue_t;

// P3-3 (R47 勘误): 禁 __thread TLS — freestanding 下 __thread 编译为 tp 相对寻址,
// 与 D99 tp 征用为 hart_id 直接冲突, 多 Hart 时 per-thread-storage 会读到错误 hart 的队列。
// 改全局数组 + hart_id 索引 (.bss 内, D103 Pin static pool 白名单内, 零堆)。
static work_queue_t local_queue[MAX_HARTS];

// pick_next: try local queue first, then steal from a peer
static int ws_pick_next(void) {
    int my_hart = current_hart_id();
    work_item_t *item = dequeue(&local_queue[my_hart]);
    if (item) return item->task;

    // Steal from peer Harts
    for (int peer = 0; peer < num_harts; peer++) {
        if (peer == my_hart) continue;
        item = steal(&local_queue[peer]);
        if (item) return item->task;
    }
    return -1;
}
```

**Properties**:
- O(1) amortized pick_next (steal is rare)
- Lock-free MPSC for steal (requires cross-Hart coherence)
- Cache-friendly: tasks stay on the same Hart
- **D111 R31**: Activates only when `num_harts > 1` AND `has_global_coherence == true` AND `-Dsched=worksteal`. build.zig compile-time guard rejects multi-Hart + no-coherence combinations.

**Pin-Binding alternative** (D111): for multi-Hart + no-coherence, use static per-Hart binding (no shared queues, no cross-Hart migration).

---

## D145 增补 (R43 Q60, R46 勘误后): Pin-Binding 完整实现 — Tier 2 多核调度 fallback

> **回链**: R43 审计新增 D145, D43 Work-Stealing Tier 2 (多 Hart 无 coherence) Pin-Binding fallback 完整定义。
> **R46 勘误**: 补 `task_affinity` 显式声明 (避免运行时随机绑定)。

### 问题与动机

D111 编译期拒绝 Work-Stealing + 无 coherence 组合, Pin-Binding 作为 alternative 一笔带过, **未定义实现细节**: 任务如何 per-Hart 绑定? 跨 Hart 任务迁移被禁止, Hart 故障时任务如何重新分配? 调度器如何感知 Hart 拓扑变化?

### D145 立法 (R46 勘误后)

Pin-Binding 实现: per-Hart task_table, 编译期分配任务到 Hart, 跨 Hart 调度禁用; Hart 故障 = D139 panic。

**`task_affinity` 显式声明**: 任务→Hart 绑定表必须是 **build option 显式声明**, 未声明任务默认 Hart 0, **禁止运行时随机绑定**。

```c
// 12-scheduler.md § Work-Stealing (D145 升级, R46 勘误后)
typedef struct {
    int my_hart;
    task_table_t local_tasks[MAX_TASKS_PER_HART];  // D145: per-Hart 静态分配
} pin_binding_t;

// D145 R46: task_affinity 显式声明 (build_options 派生)
typedef struct {
    const char *task_name;
    int         hart_id;        // D145: 必须显式指定, 不允许 -1
} task_affinity_entry_t;

extern const task_affinity_entry_t task_affinity_table[TASK_AFFINITY_COUNT];
extern const int task_affinity_count;

// D145 编译期分支
comptime {
    if (build_options.num_harts > 1 and !build_options.has_global_coherence) {
        // D145: 多 Hart 无 coherence → 自动降级到 Pin-Binding, 不是编译期错误
        @compileLog("D145: multi-Hart no-coherence → Pin-Binding fallback");

        // D145 R46: task_affinity 校验 — 任何 task_affinity_table.hart_id 必须在 [0, num_harts) 范围
        for (task_affinity_table) |entry| {
            if (entry.hart_id < 0 or entry.hart_id >= build_options.num_harts) {
                @compileError("D145 R46 FAIL: task_affinity[" + entry.task_name +
                    "].hart_id=" + entry.hart_id + " 越出 num_harts=" + build_options.num_harts);
            }
        }
    }
}
```

```bash
# D145 R46 编译期闸门: task_affinity 表校验
make test-d145-task-affinity
# 期望: 任何任务必须有显式 affinity, 未声明任务默认 Hart 0 (D145 R46)
AFFINITY_COUNT=$(grep -c "^task_affinity_table\[\]" build/scheduler.conf || echo 0)
[ "$AFFINITY_COUNT" -gt 0 ] || { echo "D145 R46 FAIL: task_affinity 表为空"; exit 1; }
# 校验每条 affinity 的 hart_id 在 num_harts 范围内
for entry in $(cat build/scheduler.conf | grep "^task_affinity_table"); do
    HART=$(echo "$entry" | awk -F'hart_id=' '{print $2}' | awk -F',' '{print $1}')
    if [ "$HART" -ge "$NUM_HARTS" ]; then
        echo "D145 R46 FAIL: task_affinity hart_id=$HART 越出 num_harts=$NUM_HARTS"; exit 1
    fi
done
```

**场景矩阵 (4 格)**: 多 Hart 全局 coherence + Work-Stealing / 多 Hart 无 coherence + Work-Stealing (D111 拒绝, D145 降级) / 多 Hart 无 coherence + Pin-Binding (D145 实现 + task_affinity 显式) / 单 Hart + RR (Phase 0 默认)。

**传染面**: `08-risc-v-hal.md` Tier 2 联动 + `15-phase0-mvp.md` T1.20 (PMP) + `20-documentation-gate.md` 新增禁词 "Pin-Binding alternative 假定实现" / "运行时随机 Hart 绑定"。

---

## D150 增补 (R45 Q65, R46 勘误后): in_kernel_space 跨 Hart 可见性 — IPI+CMO 替代 SBI RFENCE

> **回链**: R45 审计新增 D150, D82 in_kernel_space 跨 Hart Tier 2 可见性, R37 D128 留下的 follow-up。
> **R46 勘误**: 场景被 D145 预闭; SBI RFENCE 无数据一致性语义, 改 IPI+CMO (Zicbom)。

### 问题与动机

D43 Work-Stealing 跨 Hart 偷任务前需检查 victim Hart 的 `in_kernel_space`, Tier 2 (无 cross-Hart coherence) 场景下 victim 写值 stale, 调度器可能在 victim kernel mode 时偷任务, 栈撕裂。

### R46 勘误 (双重)

1. **场景被 D145 预闭**: D145 立法 "多 Hart 无 coherence ⇒ Pin-Binding, 禁止跨 Hart 调度", Work-Stealing 只在有 coherence 的硬件上存在 (D111 编译期门禁). **"Tier 2 跨 Hart 偷任务前读 victim 的 in_kernel_space" 这条路径根本不会生成**
2. **机制勘误**: `sbi_remote_fence_vma` 是 TLB/地址翻译 fence, `remote_fence_i` 是 I-cache fence — **SBI RFENCE 家族没有任何数据 cache 维护语义**. 无 coherence 硬件上的数据可见性只能走 **Zicbom** (`cbo.clean` / `cbo.inval`) 或 **IPI 握手携带本地 CMO**

### D150 立法 (R46 修正版)

in_kernel_space 的跨 Hart 读仅限调试/审计路径, 且必须经 **IPI 握手 + 读侧本地 CMO**:

```c
// 12-scheduler.md § Work-Stealing (D150 R46 修正版)
// D150: 调试/审计路径专用, 不进 Work-Stealing 热路径
//      (D145 Pin-Binding 已禁多 Hart 无 coherence 调度, 这里仅是兜底可见性读)
static int debug_audit_read_in_kernel_space(int peer_hart) {
    // D150 R46: SBI RFENCE 无数据一致性, 改 IPI+CMO (Zicbom)
    if (!build_options.has_global_coherence) {
        // 路径 1: Zicbom 扩展可用 (RISC-V Profiles RVA22+)
        if (build_options.has_zicbom) {
            sbi_send_ipi(1 << peer_hart);     // IPI 通知 peer 准备
            while (!ipi_acked(1 << peer_hart)) { wfi(); }
            // D150 R46: 本地 CMO invalid (peer 不一定有 cache, 本地必须 invalid 读侧 stale)
            asm volatile("cbo.inval (%0)" :: "r"(HLCB + peer_hart) : "memory");
            return HLCB[peer_hart].in_kernel_space.load(SeqCst);
        }
        // 路径 2: 无 Zicbom, IPI 握手携带数据
        sbi_send_ipi(1 << peer_hart);
        while (!ipi_acked(1 << peer_hart)) { wfi(); }
        // peer 在 handler 内主动把 in_kernel_space 写到共享内存 (DBCN putchar 风格)
        // 读侧读共享内存, 不读 HLCB
        return ipi_data_slab[peer_hart].in_kernel_space;
    }
    // 全局 coherence: cache 自动 invalidate, 直读 HLCB
    return HLCB[peer_hart].in_kernel_space.load(SeqCst);
}
```

**新增禁词**: "SBI RFENCE 用作数据一致性原语" / "跨 Hart 偷任务前 SBI RFENCE" / "remote_fence_vma 用于数据 cache 同步"

**传染面**: `08-risc-v-hal.md` § D94 Tier 2 联动 + `20-documentation-gate.md` 新增禁词三条。

## D104: FS/VS Lazy Save

```c
typedef struct {
    uint64_t f[32];     // 256B
    uint32_t fcsr;
} fp_context_t;

typedef struct {
    uint8_t  v[32][VLEN_MAX];  // up to 32 × 4096B = 128KB
    uint64_t vl, vtype;
    uint64_t vcsr;
} vector_context_t;

static inline void save_context(int task_id, uint64_t prev_sstatus) {
    // D104: only save if dirty
    if (cosmo_hal_fs_is_dirty(prev_sstatus)) {
        fp_context_t *fp = &task_table[task_id].fp_ctx;
        asm volatile ("fsd f0,  0(%0); fsd f1,  8(%0); ..." ::
                         "r"(fp) : "memory");
        // 32 × 8B = 256B save
        // After save: set FS = Clean (0b10)
    }
    if (cosmo_hal_vs_is_dirty(prev_sstatus)) {
        vector_context_t *v = &task_table[task_id].vec_ctx;
        // 32 × vlenb save (1KB - 128KB depending on VLEN)
        // After save: set VS = Clean (0b10)
    }
}
```

**Performance**:
| Profile | FS state | VS state | Save cost |
|---------|----------|----------|-----------|
| Embedded RV64IMAC (no F/V) | Off | Off | 0 cycles |
| Embedded RV64GC (F, no V) | Initial | Off | 0 cycles per task |
| Server RVV (F + V) | Dirty? | Dirty? | 256B + 32×vlenb |
| Server RVV (idle FPU cycle) | Clean | Clean | 0 cycles |

## D107/Q23 落地约束: context_switch HLCB 刷新规则

context_switch **只允许刷新当前 Hart 的 HLCB 槽位**(`hlcb[current_hart_id]`),严禁跨 Hart 写入 HLCB 内存。理由:
- D107 range check 锚定 `hlcb[tp].kernel_stack_base/top` per-Hart 区间,跨 Hart 写入会破坏其他 Hart 的范围检查
- D82 `in_kernel_space` 同样按 Hart 粒度管理
- 跨 Hart HLCB 写入在多核环境下是 race condition 高发区,本约束彻底消除该向量

```c
// D107 binding constraint
static inline void context_switch(int next_task_id) {
    hart_id_t my_hart = current_hart_id();   // D99: 从 tp 读
    // ONLY touch hlcb[my_hart], never hlcb[peer_hart]
    hlcb_table[my_hart].current_task_id = next_task_id;
    hlcb_table[my_hart].context_switch_count += 1;
    // DO NOT touch hlcb[peer] — peer Hart manages its own slot
}
```

`make audit-context-switch` 在 CI 静态扫描 context_switch 函数体,grep 模式 `hlcb_table\[[^m]` (即非常量或非常量表达式 my_hart 索引) 必须返回 0 匹配,违反即熔断。

## Cross-references

- **Memory Subsystem** (09): task contexts stored in HLCB/task_table
- **HAL** (08): provides `cosmo_hal_fs_is_dirty` / `cosmo_hal_vs_is_dirty`
- **Build Pipeline** (13): `-Dsched=rr|worksteal` selection
- **Documentation Gate** §二十.7: see gate catalog for forbidden phrases (R30 D104)

## Verification

- `make test-rr-quantum` — Round-Robin quantum = 10ms, observed switch rate
- `make test-worksteal-load` — 8-Hart QEMU with work-stealing, no starvation
- `make test-fs-dirty` — task uses FPU, next context switch pays 256B save
- `make test-vs-dirty` — task uses RVV, next context switch pays 32×vlenb save
