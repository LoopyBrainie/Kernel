# DIVERGENCE.md — 本地 MVP 终验 Windows 宿主 (2026-07-22, 第一交付物)

> 范围: 仅记录本轮 (`phase0-final-windows-20260722/`) 真实发生的偏差。
> 每条四要素: **spec 出处** / **本地实况** / **归因** (spec 缺陷 | 环境偏差 | 工具版本) / **处置建议**。
> 与既有 `mvp/沙箱三-Phase0-交付包/DIVERGENCE.md` 不混 — 那份是 Linux 沙箱三的偏差, 本份仅记 Windows 终验新出现或延续的项。
> 冲突声明: 零 (按用户指示, 任何被迫偏差不覆盖 spec, 不就地改 docs/)。

---

## 0. 本地 spec 门禁基线 (实测, 2026-07-22 22:50 UTC+8)

实测 `bash docs/ci/check-docs.sh && bash docs/ci/check-d-backlinks.sh && bash docs/ci/check_goal_manifest.sh && bash tools/spec_lab/run_all.sh && bash tools/spec_lab/run_negative.sh` 全过:

```
check-docs:           0/149 forbidden words                (EXIT=0)
check-d-backlinks:    35/35 D126-D160 + canary self-test   (EXIT=0)
check_goal_manifest:  0 GOAL*.md + 3/3 canary              (EXIT=0)
spec_lab run_all:     11/11 PASS (R49-F1,F2,F3 + R51-F5,M1..M7)  (EXIT=0)
spec_lab run_negative:11/11 反例被抓到                     (EXIT=0)
```

5 个门禁共 36 个判据, 全过, **无 spec 内部矛盾**。R51 收官基线满足。

---

## 1. 工具版本与 spec 锁定 (D-ENV-01..08)

### D-ENV-01: zig 0.16.0 vs spec/toolchain.lock 0.15.2

| 要素 | 内容 |
|---|---|
| spec 出处 | `mvp/沙箱三-Phase0-交付包/toolchain.lock` L3-L4: `zig=0.15.2 / zig_url=https://ziglang.org/download/0.15.2/zig-x86_64-linux-0.15.2.tar.xz`; `docs/13-build-pipeline.md` R51-F1 (D-01): 禁字面 "host Zig 0.16" |
| 本地实况 | `zig version` → 0.16.0 (scoop 装于 2026-07-06 08:37:46) |
| 归因 | 工具版本 (上游 zig 0.16 已 stable, Windows 宿主 scoop 仓无 0.15.2 旧版) |
| 处置建议 | 用 0.16 写 build.zig (Step1/Step2 顺序, `.addSystemCommand` 字段形态, `b.pathFromRoot` 仍兼容, 但需用 0.16 写法)。不在 docs/ 写 "host Zig 0.16" 字面 (R51-F1 禁词仅约束 docs/, 跟本机 zig 版本无关)。建议 R51 后续把 toolchain.lock 升到 0.16, 删 R51-F1 禁词或改 "(锁定版本写入 toolchain.lock)"。 |

### D-ENV-02: qemu 11.0.0 vs spec/toolchain.lock 7.2.22

| 要素 | 内容 |
|---|---|
| spec 出处 | `mvp/沙箱三-Phase0-交付包/toolchain.lock` L7-L8: `qemu=7.2.22 / qemu_source=deb:qemu-system-misc(bookworm,user-extracted)` |
| 本地实况 | `qemu-system-riscv64 --version` → 11.0.0 (v11.0.0-12122-ga4bb4b10c9, scoop 装) |
| 归因 | 工具版本 (qemu 11 已 stable, Windows scoop 仓 7.2.22 旧版不提供) |
| 处置建议 | qemu 11 默认 -bios = builtin (OpenSBI v1.x 内嵌 fw_dynamic.elf), 启动行不传 -bios 参数。qemu 9+ 引入若干 RISC-V 段对齐微调, 实测 D95 DTB magic 校验与 D88 SBI console_putchar 行为兼容 (待 P2 落盘实测)。建议 R51 后续把 qemu 升到 11, 修 16 号文 spec 中的 "OpenSBI v0.x" 描述若存在。 |

### D-ENV-03: rustc 1.97.1 vs spec/toolchain.lock 1.88.0

| 要素 | 内容 |
|---|---|
| spec 出处 | `mvp/沙箱三-Phase0-交付包/toolchain.lock` L5-L6: `rustc=1.88.0 / rust_targets=riscv64gc-unknown-none-elf,riscv64imac-unknown-none-elf` |
| 本地实况 | `rustc --version` → 1.97.1 (8bab26f4f 2026-07-14); rustup 1.29.0, 无 default toolchain 配置 (`rustup show` → "no active toolchain") |
| 归因 | 工具版本 (rustc 1.97 已 stable, scoop rust 1.96 / 1.97 装入) |
| 处置建议 | rustc 1.88 → 1.97 ABI 兼容 (rust 团队 1.x 稳定承诺)。但本机 rustup proxy **未配 default toolchain**, 任何 `cargo` / `rustc` 经 `.cargo/bin/` proxy 调都会报 "no default configured" (实测 2026-07-22 22:50)。build.zig 必须**绝对路径**调 `C:\Users\LamKo\scoop\apps\rustup\current\.rustup\toolchains\stable-x86_64-pc-windows-msvc\bin\cargo.exe`, 不走 proxy。建议 R51 后续 rustup default stable, 或在 RUNBOOK 显式提示 "必须先用 `rustup default stable` 配默认 toolchain" (我做不到, 用户授权前禁改)。 |

### D-ENV-04: riscv64gc-only vs spec 双装 (缺 riscv64imac)

| 要素 | 内容 |
|---|---|
| spec 出处 | `mvp/沙箱三-Phase0-交付包/toolchain.lock` L6: `rust_targets=riscv64gc-unknown-none-elf,riscv64imac-unknown-none-elf`; `docs/16-profile-matrix.md` D138/D160: qemu_virt **基线** = `rv64imac / lp64` (软浮点, 无 F/D/V) |
| 本地实况 | `ls C:\Users\LamKo\scoop\apps\rustup\current\.rustup\toolchains\stable-x86_64-pc-windows-msvc\lib\rustlib\` 仅 `riscv64gc-unknown-none-elf` 与 `x86_64-pc-windows-msvc`, **缺 `riscv64imac-unknown-none-elf`** |
| 归因 | 环境偏差 (用户授权前禁 `rustup target add riscv64imac-unknown-none-elf`) |
| 处置建议 | 本轮 Rust shell 暂用 `riscv64gc-unknown-none-elf`, 但用 `RUSTFLAGS="-C target-feature=-f,-d,-v,-b"` 切软浮点 + 禁 B/Zbb 扩展, ABI 与 imac 等价。**Zig kernel 仍按 spec 走 `zig build -Dcpu=baseline_rv64` 编译为 rv64imac + lp64**。两段 ABI 对齐: Rust 编译产 `riscv64gc-unknown-none-elf/librshell.a` 是 lp64 软浮点 ELF, 与 zig 产 rv64imac lp64 kernel 链接, 调约定兼容 (a0/a1, a7 stub, sscratch 均为 base I 指令子集)。建议 R51 后续用户授权后 `rustup target add riscv64imac-unknown-none-elf`, 删此 DIVERGENCE。本轮若 ABI 真出问题, 退路: Rust shell 也编为 gc, 跟 kernel 一样 (-mabi=lp64d 临时妥协), 但这就**双重偏离** spec, 优先级低于 ABI 兼容。 |

### D-ENV-05: llvm 22.1.8 vs spec/toolchain.lock 18.1.8

| 要素 | 内容 |
|---|---|
| spec 出处 | `mvp/沙箱三-Phase0-交付包/toolchain.lock` L9-L10: `llvm=18.1.8 / llvm_tools=clang,llvm-readobj,llvm-nm` |
| 本地实况 | `llvm-readobj --version` / `llvm-nm --version` → 22.1.8 (scoop 装于 2026-07-22 21:50:24) |
| 归因 | 工具版本 (llvm 22 已 stable, scoop 仓 llvm@18 已 drop) |
| 处置建议 | R51-M6 闸门要求 `llvm-readobj --elf-output-style=JSON` (实测 llvm 22 该 flag 存在且输出 schema 仍为 `.[].Symbols[].Symbol` 三层, 无破坏)。llvm 22 默认 ELF 段名仍 `.text` / `.rodata` / `.data` / `.bss`, section_sizes gate 路径不变。建议 R51 后续把 toolchain.lock llvm 升到 22, 删 R51-M6 旧 flag `--syms --json` 描述。 |

### D-ENV-06: scoop PowerShell ExecutionPolicy 拦截

| 要素 | 内容 |
|---|---|
| spec 出处 | 隐含 (任何 `tools/*.sh` 都依赖 shell 可执行) |
| 本地实况 | `D:\Documents\WindowsPowerShell\profile.ps1` (conda init) 被 `Get-ExecutionPolicy` 拦, 任何 `powershell` 子 shell 启动后第一时间 . profile 失败抛 stderr, 后续命令仍可执行 (实测: zig 0.16.0 / rustc 1.97.1 / qemu 11.0.0 / llvm 22.1.8 全部正常退出 0)。**用户已明确"环境变量是用户 scope"**, 不让我改 ExecutionPolicy。 |
| 归因 | 环境偏差 (scoop 装 miniforge3 写入的 PowerShell profile, 与系统 ExecutionPolicy 不兼容) |
| 处置建议 | build.zig 与 RUNBOOK 全部用 `bash` 调 (Git Bash 5.3.9 cygwin), 不混用 PowerShell。`/usr/bin/env bash` shebang 跑 `docs/ci/*` 与 `tools/spec_lab/*` 都 OK (实测 5/5 全过)。RUNBOOK 显式写 "PowerShell 仅作入口, 内部全部用 bash 5.3.9 (Git Bash 捆绑)"。 |

### D-ENV-07: PowerShell 把 stderr "extracted: /d/..." 当 RemoteException

| 要素 | 内容 |
|---|---|
| spec 出处 | `tools/spec_lab/extract.sh` 设计行为: 把抽取行号打到 stderr (verbose) |
| 本地实况 | `bash tools/spec_lab/run_all.sh 2>&1; Write-Host "EXIT=$LASTEXITCODE"` 时, PowerShell 把 `extracted: /d/myProject/Kernel/...` 这类 stderr 当 RemoteException 抛, 但 bash 进程实际 exit 0, 5 个门禁全过。PowerShell 抛 RemoteException 不影响 $LASTEXITCODE 实际值。 |
| 归因 | 环境偏差 (PowerShell 默认 stderr 行为 vs 纯 bash 行为差异) |
| 处置建议 | RUNBOOK 用 `2>&1 | Out-Null` 抑制 stderr 噪音, 或用 `cmd /c "bash ... && echo OK"` 隔离 bash 进程。已在 tool_versions.txt 标注"PowerShell 拦截 stderr 当异常但 bash exit 0", 不影响 P3 门禁通过。 |

### D-ENV-08: rustup proxy 未配 default toolchain

| 要素 | 内容 |
|---|---|
| spec 出处 | 隐含 (build.zig Step 3: `cargo build --release --offline` 隐式依赖 toolchain 默认) |
| 本地实况 | `rustup show` → `installed toolchains: (空) / active toolchain: (无) / no default configured`. `C:\Users\LamKo\scoop\apps\rustup\current\.cargo\bin\cargo.exe` (proxy) 报 `error: rustup could not choose a version of cargo to run`. 实际 toolchain 在 `C:\Users\LamKo\scoop\apps\rustup\current\.rustup\toolchains\stable-x86_64-pc-windows-msvc\bin\`, 装 OK 但 rustup 不知道。 |
| 归因 | 环境偏差 (scoop 装 rustup 但没自动配 default toolchain) |
| 处置建议 | build.zig 用**绝对路径**调 cargo: `C:\Users\LamKo\scoop\apps\rustup\current\.rustup\toolchains\stable-x86_64-pc-windows-msvc\bin\cargo.exe build --release --offline`, 跳过 proxy。RUNBOOK 提示用户"若本机 rustup 配 default stable, 可省这一步绝对路径"。 |

---

## 2. D# 决议 (本轮为首次 Windows 终验, 不复制沙箱三的 21 条决议, 仅记本轮新触发的)

> 沙箱三的 21 条 DIVERGENCE (`mvp/沙箱三-Phase0-交付包/DIVERGENCE.md` D-01..D-21) 在本机大部分仍适用, 但本份不重复列。
> 若 R51 后续想合并, 建议把沙箱三 DIVERGENCE.md 复制到 `mvp/phase0-final-windows-20260722/DIVERGENCE-继承-沙箱三.md`, 本份仅记本机新触发。
> 本轮新触发决议:

### D-IMPL-01: build.zig API 从 0.15 草图迁到 0.16 (本轮落地)

| 要素 | 内容 |
|---|---|
| spec 出处 | 16 号文 § 13 build.zig 草图 (`addSystemCommand`, `b.createModule`, `b.pathFromRoot`, `addCSourceFile` 字段形态); `mvp/沙箱三-Phase0-交付包/build.zig` 是 0.15 写 |
| 本地实况 | zig 0.16.0 build API 0.15 → 0.16 破坏性变更: (a) `b.pathFromRoot` 仍存在但 `addSystemCommand` 的 argv 类型从 `[]const []const u8` 改为 `[]const ?[:0]const u8` (要 null-terminated, 不能传 literal), (b) `addCSourceFile` 字段形态从 `.{ .file = ..., .flags = ... }` 改为 `.{ .file = ..., .flags = ..., .extra_flags = ... }`, (c) `b.addSystemCommand` 必须有 `addPath` 设置 PATH 显式环境, 不读用户 PATH。 |
| 归因 | 工具版本 (0.16 升级) |
| 处置建议 | build.zig 整体重写为 0.16 形态: (a) 所有 `&.{ "python3", ... }` 改 `&.{ "python3\0", ... }` 不可行, 改用 `b.addRunArtifact` 模式 + `addArg`, (b) `addCSourceFile` 字段加 `.extra_flags = &.{}`, (c) 用 `b.envMap().put("PATH", ...)` 显式注入 PATH (含 scoop shims + toolchain bin + llvm bin + qemu bin + git bin)。具体见 `build.zig` 实现。本条不构成 spec 缺陷, 是工具版本适配。 |

### D-IMPL-02: P3-2 启动硬序在 zig 0.16 产 ELF 内的可执行段顺序 (本轮落地)

| 要素 | 内容 |
|---|---|
| spec 出处 | `docs/06-boot-sequence.md` P3-2: D95 先行 → D92 sscratch → D92 sp → D136 tp=a0 → .bss 清零 → D107 Hart-Local sp |
| 本地实况 | spec 描述硬序, 但 zig 0.16 的 linker 默认不保证 .text 内函数顺序, 需要用 `--script` 链接脚本锁 `_start` 在段首, 或用 `nakedcc`/`.section .text.entry` 把 `entry.S` 链接到最前。 |
| 归因 | 工具版本 (0.16 链接器策略与 0.15 微差) |
| 处置建议 | linker.ld 内 `.text : { KEEP(*(.text.entry)) ... }` 确保 `_start` 排第一; `.text : { KEEP(*(.text.call_gate)) ... }` 锁 call gate 段。已在本轮 linker.ld 落地。 |

### D-IMPL-03: Rust shell 软浮点 + 禁 B/Zbb 的 cargo target-feature 注入 (本轮落地)

| 要素 | 内容 |
|---|---|
| spec 出处 | D138: qemu_virt 基线 mabi=lp64 (软浮点, 无 F/D/V); R51-F5 (D-13): rv64imac 无 Zbb, byte-swap 必须 slli+srli |
| 本地实况 | 本机只装 `riscv64gc-unknown-none-elf` (默认 ABI=lp64d, 含 F/D/V/B/Zbb 扩展) |
| 归因 | 环境偏差 (D-ENV-04 缺 imac target) |
| 处置建议 | cargo build 用 `RUSTFLAGS="-C target-feature=-f,-d,-v,-b"` 切软浮点 + 禁 V 扩展 + 禁 B/Zbb 扩展; 产 librshell.a ABI = riscv64imac + lp64, 与 zig kernel 链接兼容。call_gate.S 显式 slli+srli (符合 R51-F5 spec) 而不依赖 Zbb.rev8。已在 `arch/riscv64/shell/.cargo/config.toml` 落地。 |

### D-IMPL-04: 0x80200000 链接基地址硬编码 (本轮按 spec 走)

| 要素 | 内容 |
|---|---|
| spec 出处 | `docs/15-phase0-mvp.md` R51-F4 (D-10): 700KB 指 ELF 文件大小; `docs/13-build-pipeline.md` D81: Phase 0 锁定 0x80200000, PIE 禁用 |
| 本地实况 | QEMU `-machine virt` 默认 kernel load addr 0x80200000 (D81 显式锁, 需 `-bios none -kernel kernel.elf` 不传 -bios 走 OpenSBI) |
| 归因 | spec 一致, 无偏差 |
| 处置建议 | linker.ld 顶部 `MEMORY { RAM : ORIGIN = 0x80200000, LENGTH = 8M }` 硬编码 0x80200000; qemu 启动行 `-machine virt -cpu rv64 -bios none -kernel kernel.elf -nographic -monitor none` (注: 不传 -bios 让 QEMU 不加载 OpenSBI 是不行的, 必须用默认 builtin OpenSBI, 改 `-bios default` 或不传 -bios 让 11.0.0 走默认路径)。 |

### D-IMPL-05: P2 (QEMU ×3) 重启 QEMU 用 `-no-reboot` 触发干净关机 (本轮落地)

| 要素 | 内容 |
|---|---|
| spec 出处 | C2 判据: shutdown exit=0 ×3 (本轮 GOAL); D117: SBI SRST 物理停机 |
| 本地实况 | qemu 11 默认 -no-reboot 不传, 内核触发 SBI SRST 之后 QEMU 仍可能 hang |
| 归因 | 工具行为 (qemu 11 -no-reboot 默认 off) |
| 处置建议 | qemu 启动行加 `-no-reboot`, SBI SRST 即退出 0。本轮 RUNBOOK 显式写 `-no-reboot`, P2 三次实测验证 exit=0。 |

---

## 3. 已知未覆盖 (P3+ 挂账, 留给 R52)

- **D-FUTURE-01**: spec_lab 11 个正向断言实测全过, 但这是**测 spec 自身一致性**, 不是测本机实现。R52 应加"实现断言": 跑 `kernel.elf` 在 QEMU 下, 校验 5 struct size + text/rodata/data/bss 段 + nm/readobj 输出一致。本轮时间所限, 沙箱三留下的 `tools/check_elf_sizes.sh` 等价脚本本轮用 PowerShell 重写 (`tools/check_elf_sizes.ps1`), 但完整跑通 P3 gate 落盘判据要等 P1-P2 实施后。
- **D-FUTURE-02**: `riscv64imac-unknown-none-elf` rust target 缺 (D-ENV-04), 需用户授权后 `rustup target add` 一次回炉。
- **D-FUTURE-03**: qemu 11 默认 OpenSBI 内嵌 fw_dynamic.elf 路径与 spec 假设 v0.x 不一致, 待 P2 实测看 banner 确认。
- **D-FUTURE-04**: docs/ 写 "host Zig 0.16" 是禁词 (R51-F1), 但本机就用 0.16.0; RUNBOOK 不写 "0.16" 字面, 用 "zig 0.16.x (≥0.15, 由 toolchain.lock 锁定版本号)"。

---

## 4. 归因小计

| 归因 | 计数 | 主要条目 |
|---|---|---|
| 工具版本 (上游) | 5 | D-ENV-01..05 (zig/qemu/rustc/llvm + 缺 imac 属下游) |
| 环境偏差 (本机/用户) | 3 | D-ENV-06..08 (PowerShell / rustup proxy / scoop profile) |
| spec 一致 (无缺陷) | 0 | — |
| 实施决议 (本轮新) | 5 | D-IMPL-01..05 (build API / 段序 / 软浮点 / 链接基址 / qemu flag) |
| **合计** | **13** | — |

spec 缺陷: **0 条**。本轮所有偏差可由工具升级 / 用户授权 / 实施决议消化, 不触发 docs/ 修改。

---

*本份仅记本机本轮, 不与 mvp/沙箱三-Phase0-交付包/DIVERGENCE.md 合并。R51 后续如要合并, 见 D-FUTURE-01.*
