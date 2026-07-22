# 13 · Build Pipeline (SSOT + Profile Switch + 3 Hard Gates)

**Plan section**: §十三
**Key decisions**: D48, D74, D81, D93, D100, D101, D105
**Status**: Frozen; 3 hard gates + SSOT auto-generation

---

## Overview

The build pipeline is a 3-stage `build.zig` chain that (1) compiles each language with profile-specific flags, (2) auto-generates cross-language FFI bindings from a Zig SSOT, and (3) runs 3 hard gates: SSOT alignment (L1-L4 of D74/D85/D86/D90), post-build ELF size gate (D101), and initrd file count gate (D105). All three gates fail closed and abort the build.

**R51-F1 (D-01)**: Host Zig version is `Zig ≥0.15`, locked by `toolchain.lock` (not by `host Zig 0.16` — that version does not exist). The forbidden-word list enforces this: literal `Zig 0.16` / `host Zig 0.16` are banned. Back-link: `05-call-gate.md:193`.

**R51-F2 (D-02)**: Toolchain audit vs build profile — **two distinct profiles must not be conflated**:
- `rustup target add riscv64gc-unknown-linux-gnu` (lp64d, hard-float) is the **toolchain audit** profile used by Rust cargo for crate-resolution audits. It is **not** a build output.
- Build target is D138 embedded profile: `riscv64imac-unknown-none-elf` (lp64, soft-float, no-f/d/v). This is what `zig build` produces and what `qemu_virt` boots.
- Lesson: mismatch between audit profile (lp64d) and build profile (lp64 imac) caused sandbox-two O2 silent override of D138. Frozen in R51 via the `audit profile is build profile` distinction. Back-link: R49-GOV.2 (O2 first-case archived as `R49-EMBEDDED-LP64`).

## 3-stage build chain

```
build.zig
  │
  ├── Stage 1: Compile
  │   ├── Zig kernel (comptime type checks D86/D90)
  │   ├── C HAL (C99 + _Static_assert D86)
  │   ├── Rust Shell (cargo-geiger D97)
  │   └── RISC-V assembly (entry.S D92/D95/D99/D106)
  │
  ├── Stage 2: SSOT translate-abi (D74)
  │   ├── Parse Zig extern struct from kernel/include/sys/abi.zig
  │   ├── Generate Rust (arch/riscv64/abi.rs)
  │   ├── Generate C (kernel/include/sys/abi.h)
  │   └── Verify three-end offsetof (D85)
  │
  └── Stage 3: 3 Hard Gates (fail-closed)
      ├── Gate 1: D86 + D90 + D74 SSOT (compile-time)
      ├── Gate 2: D101 check_elf_sizes.sh (post-link)
      └── Gate 3: D105 initrd_file_count ≤ 50 (asset validation)
```

## D74: SSOT auto-generation

```zig
// build.zig (sketch)
const abi = @import("kernel/include/sys/abi.zig");
const std = @import("std");

pub fn build(b: *std.Build) void {
    const translate_abi = b.addSystemCommand(&.{
        "python3", "tools/translate_abi.py",
        "--input", "kernel/include/sys/abi.zig",
        "--rust-out", "arch/riscv64/abi.rs",
        "--c-out", "kernel/include/sys/abi.h",
    });
    b.getInstallStep().dependOn(&translate_abi.step);
}
```

The translator walks the Zig SSOT, generates matching `#[repr(C, align(N))]` Rust structs, and matching `_Static_assert`-guarded C structs. Manual edits to the generated files are detected by `git diff` pre-commit hook and rejected (R21 D74 forbids hand-written abi.rs).

## D93 + D111: Profile switch + Work-Stealing compile-time guard

```bash
# Default: Embedded (RV64IMAC, RR scheduler, 16KB stack)
zig build -Dtarget=embedded -Dsched=rr -Denable_rvv=false

# Server (RV64GC + RVV, Work-Stealing, 8KB+ stack)
zig build -Dtarget=server -Dsched=worksteal -Denable_rvv=true

# Server with Page-Aggregation (Phase 1+)
zig build -Dtarget=server -Denable_page_aggregation=true

# Pin-Binding static (D111, multi-Hart + no coherence)
zig build -Dtarget=server -Dsched=pin_binding
```

```zig
// R51-M4 (D-11 / D157): Phase 0 ledger 上限固化 (编译期熔断, 越界 build ABORT)
// 单一真相: 02 § D49 ceiling 644 KB; 各 section 严格 ≤ 限额
pub const ledger_caps = struct {
    pub const text_max: u32    = 81920;   // .text  ≤ 80 KB
    pub const rodata_max: u32  = 10240;   // .rodata ≤ 10 KB
    pub const data_max: u32    = 4096;    // .data   ≤ 4 KB
    pub const bss_max: u32     = 8192;    // .bss    ≤ 8 KB
};
comptime {
    if (kernel.text_size    > ledger_caps.text_max)   @compileError("R51-M4: text 越界");
    if (kernel.rodata_size  > ledger_caps.rodata_max) @compileError("R51-M4: rodata 越界");
    if (kernel.data_size    > ledger_caps.data_max)   @compileError("R51-M4: data 越界");
    if (kernel.bss_size     > ledger_caps.bss_max)    @compileError("R51-M4: bss 越界");
}
```

```zig
// R51-M7 (D-21 / D159): ReleaseSmall 默认 `-Dstrip` 让 nm/readobj 输空表, 门禁空真通过.
// 必须显式 `-Dstrip=false -Doptimize=ReleaseSafe`, 否则 D129 T-属性门禁 + D113 size-csv
// 闸门都返回空表, 误判 ELF 合规. 沙箱三实测: ReleaseSmall 默认 + nm 输出空 → elf size gate PASS
// 但实际 symbol 全 strip → 真实不通过. 修正: build.zig 强制 `-Dstrip=false`.
pub const kernel_optimize: std.builtin.OptimizeMode = .ReleaseSafe;
pub const kernel_strip: bool = false;  // R51-M7 强制 false; D-21 收口
```

```zig
// R51-M6 (D-20): size-csv 工具链锁定 LLVM 18 兼容命令 (沙箱三实测撞过)
// **正确命令**: llvm-readobj --syms --elf-output-style=JSON | jq '.[].Symbols[].Symbol'
// **错误命令 (R47 草图)**: llvm-readobj --syms --json | jq '.[]' — LLVM 18 不存在 --json
//   标志, 返回空 symbol, 误判 D113 size-csv 闸门通过 (空真). 必须 --elf-output-style=JSON.
// jq 三层路径: .[] (program headers) → .Symbols[] (符号表) → .Symbol (Symbol struct)
// spec_lab 双向断言 R51-M6-size-csv.{sh,_negative.sh}.
pub fn size_csv_extract(kernel_elf: []const u8) ![]const u8 {
    var stdout: [4096]u8 = undefined;
    const argv = &[_][]const u8{
        "llvm-readobj", "--syms", "--elf-output-style=JSON",
    };
    // 3 层 jq: .[].Symbols[].Symbol (note: NOT --json flag)
    // ...
}
```

```zig
// D111 R31: build.zig 编译期门禁
pub fn select_sched(num_harts: u16, has_global_coherence: bool) SchedBackend {
    const requested = build_options.sched;
    if (requested == .worksteal) {
        if (num_harts > 1 and !has_global_coherence) {
            @compileError(
                "Work-Stealing requires hardware cache coherence on multi-Hart. " ++
                "Use -Dsched=rr or -Dsched=pin_binding. D111 compile-time guard.");
        }
    }
    return requested;
}
```

Profile switch re-runs all 3 hard gates (D109) because ELF size can drift between profiles even when the source is identical.

## D108/Q24 落地约束: -Dip_family 非法值编译期熔断

```zig
// D108 binding constraint: 非法值编译期熔断,禁止静默 fallback
pub const IpFamily = enum { v4, v6 };

pub fn parse_ip_family(s: []const u8) IpFamily {
    if (std.mem.eql(u8, s, "v4")) return .v4;
    if (std.mem.eql(u8, s, "v6")) return .v6;
    // D108: 明确熔断,严禁静默 fallback 到 v4
    @compileError("Invalid -Dip_family value: '" ++ s ++ "'. " ++
        "Allowed: v4, v6. Silent fallback to v4 is FORBIDDEN (D108 binding constraint).");
}

pub const build_options = struct {
    ip_family: IpFamily = parse_ip_family(b.option([]const u8, "ip_family", "v4") orelse "v4"),
    // ...
};
```

**Why this matters**: 默认值 `"v4"` 由 `orelse "v4"` 提供给 `parse_ip_family`,传 `"v6"` 也走 `parse_ip_family` 合法路径。传 `"v5"` 或 `"ipv4"` 等任何非 `v4`/`v6` 字符串 → 编译期熔断。这避免了"Rust 生态常见的 `Result::unwrap_or(default)` 静默 fallback"反模式 — 用户输错 L3 协议族是一个 hard error,不是 warning。

## D101: post-build ELF physical-size gate

```bash
#!/usr/bin/env bash
# docs/ci/check-docs.sh sibling: check_elf_sizes.sh
set -e

EXPECTED=(
  "sys_result_t:16"
  "sys_result_payload_t:8"
  "rpc_unit_t:1536"
  "network_frame_t:1536"
  "block_t:1536"
)

for elf in zig-out/bin/*; do
  for entry in "${EXPECTED[@]}"; do
    sym="${entry%%:*}"; expected="${entry##*:}"
    actual=$(llvm-readobj --symbols "$elf" 2>/dev/null | \
             awk -v s="$sym" '$0 ~ s {print $5; exit}')
    if [ "$actual" != "$expected" ]; then
      echo "FATAL: $sym size drift in $elf: expected=$expected actual=$actual"
      exit 1
    fi
  done
done
echo "✓ Post-build ELF size gate passed (5 struct sizes verified)"
```

## D113: check_elf_sizes.sh 用 jq + --json 强类型解析 (Q28 R32 fix)

**Status**: **RATIFIED** (Q28 → D113, R32).

D101 R30/R31 脚本用 `awk '$5'` 提取大小存在三处脆弱点:
1. `$5` 字段假设错误——`llvm-readobj --symbols` 输出列定义不固定
2. `$0 ~ s` 子串误匹配——`sys_result_t` 是 `sys_result_payload_t` 子串
3. `set -e` 不保护空匹配——符号未导出时错误信息丢失

D113 改用 `--json` 强类型输出 + `jq` 路径选择 + `set -euo pipefail`:

```bash
#!/usr/bin/env bash
# docs/ci/check_elf_sizes.sh (D113 R32 fix)
set -euo pipefail  # D113: -u 防止未定义变量, -o pipefail 防止 jq 失败被吞

EXPECTED=(
  "sys_result_t:16"
  "sys_result_payload_t:8"
  "rpc_unit_t:1536"
  "network_frame_t:1536"
  "block_t:1536"
)

for elf in zig-out/bin/*; do
    [[ -f "$elf" ]] || continue
    # R51-FIX (F-1 传染失败修补): 旧脚本用 `llvm-readobj --syms --json`, LLVM 18 不存在 --json 旗标,
    # 沙箱三实测空表空真过. 新 size-csv 段 (13:107-115) 用 --elf-output-style=JSON + jq 三层.
    # 本块 [OBSOLETED-by-R51-M6]: 旧命令在本仓库不再适用, 严禁复活.
    sym_json=$(llvm-readobj --elf-output-style=JSON --syms "$elf" 2>/dev/null) || {
        echo "FATAL: cannot read $elf"; exit 1;
    }
    for entry in "${EXPECTED[@]}"; do
        sym="${entry%%:*}"; expected="${entry##*:}"
        # P3-7 (R47 勘误): llvm-readobj --syms --json 的 schema 是 [{Symbols:[{Symbol:{Name,Size,...}}]}],
        # 即 3 层嵌套 (顶层数组 → Symbols → Symbol 对象), 原 .[]?.[]? 只下 2 层永远匹配不到。
        # 改 .[].Symbols[].Symbol; 注记: 强烈建议将已知-good JSON 快照入库, 锚定 schema 防 llvm 版本漂移。
        actual=$(echo "$sym_json" | jq -r --arg n "$sym" \
            '.[].Symbols[].Symbol | select(.Name? == $n) | .Size? // empty' | head -1)
        if [[ -z "$actual" ]]; then
            echo "FATAL: $sym not found in $elf"
            exit 1
        fi
        if [[ "$actual" != "$expected" ]]; then
            echo "FATAL: $sym size drift in $elf: expected=$expected actual=$actual"
            exit 1
        fi
    done
done
echo "✓ Post-build ELF size gate passed (5 struct sizes verified, D113)"
```

## D124: BlockPool stride gate 派生常量 (R36 fix)

D101 size 闸门 + D113 jq 升级补 2D 防御:**stride gate**。期望值由 build option 编译期派生,禁硬编码字面量。

```bash
#!/usr/bin/env bash
# docs/ci/check_blockpool_stride.sh (D124 R36 fix)
set -euo pipefail

# D124 binding: 期望值由 build option 派生, 不是字面量
EXPECTED_BLOCK_COUNT=$(nm zig-out/bin/kernel.elf | grep -c '__block_[0-9]')
BLOCKS_PER_PAGE=$(grep -E 'blocks_per_page.*=' kernel/src/mem.zig | head -1 | awk -F'= ' '{print $2}' | tr -d ';')
PAGE_SIZE=4096

EXPECTED_PAGES=$((EXPECTED_BLOCK_COUNT / BLOCKS_PER_PAGE))
EXPECTED_STRIDE=$((EXPECTED_PAGES * PAGE_SIZE))

# D124 落地约束 ①: 同时校验基址 4KB 对齐
ACTUAL_START=$(nm zig-out/bin/kernel.elf | grep '__blockpool_start ' | awk '{print "0x" $1}')
ACTUAL_END=$(nm zig-out/bin/kernel.elf | grep '__blockpool_end ' | awk '{print "0x" $1}')
ACTUAL_STRIDE=$((ACTUAL_END - ACTUAL_START))

# D124 落地约束 ②: Phase 0 范围限 BlockPool (NodePool/MacDmaPool 留 Phase 1)
if [ "$ACTUAL_STRIDE" -ne "$EXPECTED_STRIDE" ]; then
    echo "FATAL: D124 BlockPool stride drift"
    echo "  expected = $EXPECTED_STRIDE bytes ($EXPECTED_PAGES pages × $PAGE_SIZE)"
    echo "  actual   = $ACTUAL_STRIDE bytes"
    exit 1
fi
if [ $((ACTUAL_START & 0xFFF)) -ne 0 ]; then
    echo "FATAL: D124 __blockpool_start not 4KB aligned: 0x$ACTUAL_START"
    exit 1
fi
echo "✓ D124 stride gate passed (BlockPool $EXPECTED_BLOCK_COUNT blocks, $EXPECTED_PAGES pages, $ACTUAL_STRIDE bytes)"
```

**D124 边界说明**: 类型身份问题(block_t 与 rpc_unit_t 同 size 偏移对调)stride gate 同样抓不到——D124 补的是布局维度,类型身份由 D121 已立法的「要么 SSOT 生成、要么手写内嵌三端 offset 断言」兜底。

## D126: stride 期望值按 build profile × layout 派生 (Q41 R37)

D124 单公式 `EXPECTED_PAGES × PAGE_SIZE` 不感知 build profile,会把 server_compact (256×1536B 物理 = 384KB) 误判为 512KB sparse → 体积回归熔断。D126 升级: 闸门先读 profile,再选期望值表。

| profile | layout | blocks | 物理期望 | blocks/page | source |
|---------|--------|--------|----------|-------------|--------|
| qemu_virt | sparse | 256 | 512 KB (128 页) | 2 | D45/D102 |
| qemu_virt | compact | 256 | 384 KB (256 块/物理连续) | n/a (D102) | D102 |
| server | sparse | 256 | 512 KB | 2 | D45/D102 |
| server | compact | 256 | 384 KB | n/a (D102) | D102 |

```bash
#!/usr/bin/env bash
# docs/ci/check_blockpool_stride.sh (D126 R37 refinement)
set -euo pipefail

# D126: 读 profile build option (D102), 不假设默认 sparse
PROFILE="${PROFILE:-qemu_virt}"
LAYOUT="${LAYOUT:-sparse}"

# D126: 期望值由 profile × layout 双层派生, 严禁 (估) 字面量
case "${PROFILE}/${LAYOUT}" in
    qemu_virt/sparse)   EXPECTED_PHYSICAL_KB=512; EXPECTED_BLOCKS=256; EXPECTED_PAGES=128 ;;
    qemu_virt/compact)  EXPECTED_PHYSICAL_KB=384; EXPECTED_BLOCKS=256; EXPECTED_PAGES=96  ;;  # D102 重排
    server/sparse)      EXPECTED_PHYSICAL_KB=512; EXPECTED_BLOCKS=256; EXPECTED_PAGES=128 ;;
    server/compact)     EXPECTED_PHYSICAL_KB=384; EXPECTED_BLOCKS=256; EXPECTED_PAGES=96  ;;  # D102 重排
    *) echo "FATAL: D126 unknown profile/layout: $PROFILE/$LAYOUT"; exit 1 ;;
esac

# D126 落地约束 ①: 实测 row count 不接受过松或过严
ACTUAL_PHYSICAL_BYTES=$(( $(nm zig-out/bin/kernel.elf | grep '__blockpool_end ' | awk '{print "0x" $1}') \
                        - $(nm zig-out/bin/kernel.elf | grep '__blockpool_start ' | awk '{print "0x" $1}') ))
ACTUAL_PHYSICAL_KB=$((ACTUAL_PHYSICAL_BYTES / 1024))

if [ "$ACTUAL_PHYSICAL_KB" -gt "$EXPECTED_PHYSICAL_KB" ]; then
    echo "FATAL: D126 stride exceeds profile×layout ceiling"
    echo "  $PROFILE/$LAYOUT ceiling = ${EXPECTED_PHYSICAL_KB} KB"
    echo "  measured               = $ACTUAL_PHYSICAL_KB KB"
    exit 1
fi

# D126 落地约束 ②: 与 D123 ceiling ledger 逐数一致 (R36 元规则四)
if [ "$EXPECTED_PHYSICAL_KB" -gt 644 ]; then
    echo "FATAL: D126 $PROFILE/$LAYOUT profile = ${EXPECTED_PHYSICAL_KB} KB > D49 ceiling (644 KB)"
    exit 1
fi

# D126 落地约束 ③: 4 种组合单测纳入 T1.11 DoD
case "${PROFILE}/${LAYOUT}" in
    qemu_virt/sparse|qemu_virt/compact|server/sparse|server/compact) ;;
    *) echo "FATAL: D126 缺 T1.11 单测组合: $PROFILE/$LAYOUT"; exit 1 ;;
esac

echo "✓ D126 stride gate passed ($PROFILE/$LAYOUT, measured $ACTUAL_PHYSICAL_KB KB ≤ $EXPECTED_PHYSICAL_KB KB ceiling)"
```

**传染面清单** (R37 元规则四):
- `02-memory-topology.md` § D45/D102 双 Profile 表同步
- `check_elf_sizes.sh` 升级点 (D113 → D126)
- `15-phase0-mvp.md` T1.11 (D113 → D126)
- `20-documentation-gate.md` 新增禁词: `stride 期望值未感知 profile` (已入册, R37)

**Cost / Benefit**:

| 维度 | D101/D113 (1D) | + D124 (2D) |
|------|----------------|-------------|
| 同 size 不同 layout 漂移 | ❌ 漏检 | ✓ stride gate 捕获 |
| 期望值漂移 | (适用) | 编译期派生,不会与实际漂移 |
| 闸门实现成本 | 5 个 size 字段 | + 1 个 stride 字段 |

**Cost / Benefit**:

| Dimension | D101 (R30/R31, awk 脆弱) | D113 (R32, jq + JSON) |
|-----------|---------------------------|------------------------|
| LLVM 版本漂移 | ❌ $5 含义在 14→17 之间漂移 | ✓ JSON schema 在 15+ 稳定 |
| 子串误匹配 | ❌ sys_result_t 匹配 sys_result_payload_t | ✓ `select(.Name? == $n)` 精确匹配 |
| 符号未导出 | ❌ awk 静默空输出 | ✓ `[[ -z "$actual" ]]` 显式 FATAL |
| 工具链依赖 | awk (POSIX 必有) | awk + jq (Linux/macOS 必有) |
| 错误信息 | "expected=X actual=" | 完整 ELF 路径 + 符号名 + 实际值 |

**Verification**:

```bash
# R31 测试 (在 D113 修复前应当 FAIL 或误报)
make test-llvm-17-upgrade  # 升级到 LLVM 17, 验证 gate 仍正确
make test-substring-clash  # 添加 sys_result_aux_t, 验证不被误匹配

# R32 新增
make test-symbol-missing   # 删除 sys_result_t 符号, 验证 FATAL 信息完整
make test-empty-elf        # 空 ELF 文件, 验证 graceful failure
```

**Why Option A (Q28) was chosen over B/C**:

- **Option B** (`llvm-readelf -s`) 输出格式仍依赖 LLVM 版本,awk 复杂度未降 → **拒绝**
- **Option C** (Rust `object` crate) 是 Phase 1+ 选项,但增加编译依赖,R32 不引入

D113 是 Q28 推荐选项 A 的实现,接受 `jq` 工具链依赖换取解析稳健性。

## D105: initrd file count gate

```zig
// build.zig comptime asset validation
const initrd_path = b.option([]const u8, "initrd", "initrd CPIO path") orelse "initrd.cpio";
const initrd_files = parse_cpio(initrd_path);

if (initrd_files.len > MAX_FILES) {  // D46: MAX_FILES = 50
    @compileError("initrd file count " ++ @as(u32, @intCast(initrd_files.len))
        ++ " exceeds MAX_FILES=50. Remove " ++
        @as(u32, @intCast(initrd_files.len - MAX_FILES)) ++ " files.");
}
```

## D100: UKI Loader ELF Program Header scan

The UKI Loader is a ~2KB hand-written ELF parser that runs **before** the kernel. It locates `__boot_meta_start` symbol's PT_LOAD segment and writes the Active Slot state to the corresponding file offset. Cures D63 DTB decoupling for layouts with elastic `.text` size.

## D81: PIE dynamic base

```bash
# Phase 0: fixed link base 0x80200000
zig build -Dkernel_phys_start=0x80200000

# Phase 1+: PIE dynamic (build.zig emits relocatable image)
zig build -Dpie=true
```

D93 forbids full PIE in Phase 0 (embedded tax), but the option exists for Phase 1+.

## Cross-references

- **ABI Contract** (04): SSOT feeds L1 of 5-layer defense
- **Boot Sequence** (06): UKI Loader (D100) runs as pre-kernel step
- **Documentation Gate** §二十.7: see gate catalog for forbidden phrases (R27 D93, R29 D100/D101, R30 D105)

## Verification

- `zig build` (default) — Embedded Profile, 3 hard gates pass
- `zig build -Dtarget=server` — Server Profile, all 3 gates re-run
- `make test-initrd-overflow` — inject 51 files, expect D105 compile error
- `make test-elf-drift` — manually corrupt one struct size, expect D101 abort
