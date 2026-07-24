# 00 · Naming Taxonomy (R53 RATIFIED — 系统级命名 SSOT)

**Status**: Frozen (R53 收口); 命名法 SSOT,非实现细节。
**Authority**: 唯一权威命名条款源;子系统文档中复述命名规则必须回链本文件锚点,无回链视为私自立法(熔断)。
**Supersedes**: R51 D153 (Dispatcher 命名锚,本文件 § 5 收口)、R47 散落命名约定。
**Rounds**: R53-R62 命名迁移立法总账 (R53-R60 命名迁移 + R61 syscall 11-15 增补 + R62 收官 D174 mmap 后缀漏网 + GOV.5 三件套纪律)。R63 同步 SPEC.md 扫描面 + boot banner SSOT (D175 立法)。

---

## 1. 系统层命名 (System-level Naming)

| 项 | 值 |
|---|---|
| 系统全称 | **Neur-Aegis** |
| CLI / Namespace | `neura` |
| 旧全称 (R52 前) | Wriggly-Octopus |
| 旧缩写 (R53 退役) | `cosmo_` |
| Tagline | "A triple-language-verifiable RISC-V S-Mode microkernel." |

> **R53 顶层改名**: SPEC.md 标题 `Wriggly-Octopus` → `Neur-Aegis`。CLI 入口命名空间 `neura`(绑 R59 D171 syscall API 前缀)。

---

## 2. 三大组件代号 (Component Codenames)

| 代号 (codename) | 语言 | 角色 | 路径 (Phase 0) | 实现前缀 (R##) |
|---|---|---|---|---|
| **Basal** | C | Hardware Abstraction Layer + ABI SSOT | `basal/` (R54) | `basal_` (R54-R57) |
| **Synapse** | Zig | Microkernel Dispatcher + Call Gate + Build | `synapse/` (R55) | (snake_case 类型/函数) |
| **Cortix** | Rust | S-Mode Userspace / Co-resident Shell | `cortix/` (R58, 绑 Q69) | `cortix_kernel` crate |

> **代号 ≡ 实现前缀**:
> - Basal → C 源码 `basal_panic_abort.c`、`basal_call_gate.S`、`basal_hal_*.h`(R54-R57 分批迁移)
> - Synapse → Zig 源码 `synapse/syscall_dispatch.zig`、`synapse/synapse.zig`(R55 收)
> - Cortix → Rust crate 名 `cortix_kernel`,目录 `cortix/src/`(R58 收,绑 Q69)
>
> **D166 范式**: 任何代号 / 目录 / 前缀变更须经 D## 立法 + 1X 子系统文档回链 + 禁词 census 同步;不允许"R## 收口中段跨多 D# 撤销"。

---

## 3. 跨语言公共符号 (D121 SSOT)

D121 5 struct 白名单 — **不加任何组件前缀**:

| 名称 | 含义 | D# |
|---|---|---|
| `sys_result_t` / `sys_result_payload_t` | 16B 系统调用结果 | D121 |
| `RpcUnit` / `rpc_unit_t` | 1536B 协议单元 (8B header + 1528B payload) | D121 |
| `NetworkFrame` / `network_frame_t` | 1536B 网络帧 (external 1536B + internal 14B MAC) | D121 |
| `block_t` | 1536B 物理块 | D121 |

> **D165 反向锚定**: 禁止 `neura_sys_result_t` / `basal_sys_result_t` / `cortix_sys_result_t` / `synapse_sys_result_t` 任意一种字面串出现于 `docs/`。Linux 内核惯例(无组件前缀跨语言公共类型),与 `syscall_*` / `task_*` / `file_*` 同款命名哲学。

---

## 4. C 内部前缀策略 (basal_ 分批范式, D166)

| 批次 | 符号族 | 撤销立法 |
|---|---|---|
| **R54** | `basal_panic_abort*` / `basal_oops_panic` / `basal_do_user_fault_fixup` / `__basal_panic_in_progress` | D76 → D168 |
| **R55** | `basal_call_gate` / `__basal_dispatcher_ptr` | D129 → D169 |
| **R56** | `basal_hal_*` + 其他 C HAL 函数(13 符号) | — |
| **R57** | `__basal_abi_` ABI 过滤前缀 | — |
| **R59** | `basal_node_id` | — |

> **D166 范式**: 分批迁移,每批独立 R## 收口全量门禁。单批变更不得跨多个 D# 撤销。

---

## 5. Zig 内部命名 (D153 锁定)

- Dispatcher 唯一合法文件名: **`syscall_dispatch.zig`** (D153,改名视为熔断)
- 父目录迁移: `kernel/dispatcher/` → `synapse/` (R55 收)
- 类型 PascalCase (`RpcUnit` / `NetworkFrame` / `HartLocalControl`),函数 camelCase (`syscallDispatch` / `initHartLocal`)

---

## 6. Rust 内部命名 (R58 收,绑 Q69)

- Shell crate 名: **`cortix_kernel`** (R58 ✅ 补执行, 撤销 `cosmo_kernel`, D173 豁免 Q69 阻塞)
- Phase 0 目录: `cortix/src/` (绑 Q69 Rust crate 拓扑)
- 模块 snake_case (`syscall_stubs` / `early_console`),类型 PascalCase

---

## 7. Syscall API 前缀 (D171 RATIFIED, R59 收口)

跨语言 syscall 入口统一使用 **`neura_`** 前缀 (R59 迁移自旧前缀 `cosmo_*`):

| Syscall | Phase |
|---|---|
| `neura_open` | Phase 0 |
| `neura_read` | Phase 0 |
| `neura_write` | Phase 0 |
| `neura_close` | Phase 0 |
| `neura_seek` | Phase 0 |
| `neura_stat` | Phase 0 |
| `neura_yield` | Phase 0 |
| `neura_ping` | Phase 0 |
| `neura_pte_map_6arg` | Phase 1 typed |
| `neura_ipc_send_6arg` | Phase 1 typed |

> **D171 立法** (R59 收口): syscall API 入口 (用户态 shell 可调用的 FFI 符号) 统一 `neura_` 前缀, 与项目品牌 Neur-Aegis 一致; 内部 C HAL 函数 (`basal_*`) 与 Shell crate (`cortix_*`) 分立。R59 前旧名 `cosmo_*` 已废止 (D172 围栏外历史审计豁免)。

---

## 8. 目录结构映射 (R54-R58)

| 旧路径 | 新路径 | 收口轮次 |
|---|---|---|
| `kernel/include/sys/abi.zig` (D74 SSOT) | `basal/include/sys/abi.zig` | R54 |
| `kernel/include/sys/abi.h` (D74 C 生成) | `basal/include/sys/abi.h` | R54 |
| `kernel/hal/c/` | `basal/c/` | R54 |
| `kernel/dispatcher/` (Zig) | `synapse/` | R55 |
| `synapse/syscall_dispatch.zig` | (路径已迁,文件名不动 D153) | R55 |
| `cortix_kernel` crate 根 | `cortix/` | R58 (绑 Q69) |

---

## 9. SSOT 路径迁移 (D74 → D170)

- **D74 路径条款撤销** (R54): `kernel/include/sys/abi.zig` 不再是 SSOT 入口
- **D170 替代** (R54 收口): `basal/include/sys/abi.zig` 为新 SSOT 输入
- `arch/riscv64/abi.rs` 不变(Rust 端)
- `build.zig` 改 `--input basal/include/sys/abi.zig` + `--c-out basal/include/sys/abi.h`

> **传染面**: R54 必须同步更新 `13-build-pipeline.md` § SSOT 生成器段、`04-abi-contract.md` § D121 白名单路径、`SPEC.md` § Headline D-tag 索引。

---

## 10. 历史引用豁免 (D172)

- `docs/30-open-questions.md` 中**历史审计段落**(围栏外叙述)保留原样, 不强制替换 `cosmo_*` 为新前缀
- **当前有效代码示例**(围栏内可编译可执行代码)必须按 R54-R59 同步更新
- 判定标准: 用 grep 找三连反引号围栏内 vs 围栏外 — 围栏内同步、围栏外保留

> **D172 回链**: 见 `01-system-overview.md` § 命名法 R## 总账 + `15-phase0-mvp.md` § MVP 文档命名引用。R60 收口。

---

## 11. 命名变更纪律 (D167)

任何代号 / 目录 / 前缀变更须:

1. **D## 立法**: 在 `03-design-decisions.md` 立法条追加新 D# 或撤销旧 D#,并标注 SUPERSEDED 链
2. **1X 子系统文档回链**: 至少 1 个 `docs/1X-*.md` 子系统文档回链新 D#(back-link gate `check-d-backlinks.sh` 强制)
3. **禁词 census 同步**: 新禁词加 `check-docs.sh` FORBIDDEN 数组 + `20-documentation-gate.md` census 表(EXPECTED_TOTAL 一致)
4. **分批迁移**: D153 范式 — 每批 R## 收口独立全量门禁;单批变更不得跨多个 D# 撤销
5. **spec_lab 断言脚本同步**: 每批 R## 收口前必查 `tools/spec_lab/assertions/*.sh` + `extracted/*.ext` 是否有硬编码旧符号名

---

## 12. 回链

| D# | 主题 | 权威源 |
|---|---|---|
| D125 (FFI Pillars) | 跨切面前置阅读 | `docs/00-ffi-pillars.md` |
| D153 (Dispatcher 锚) | `syscall_dispatch.zig` 文件名锁定 | `docs/03-design-decisions.md:296` |
| D121 (ABI 白名单) | 跨语言无前缀规则 | `docs/04-abi-contract.md` |
| D74 (SSOT 路径) | `basal/include/sys/abi.zig` (R54 撤销 + D170 替代) | `docs/13-build-pipeline.md` |
| D76 (C HAL panic) | `basal_panic_abort` (R54 撤销 + D168 替代) | `docs/08-risc-v-hal.md` |
| D129 (call gate a7 锚定) | `basal_call_gate` (R55 撤销 + D169 替代) | `docs/05-call-gate.md` |
| D171 (syscall 前缀) | `neura_*` syscall API | `docs/14-syscall-api.md` (R59 收口) |
| Q69 (Cortix crate 拓扑) | `cortix_kernel` crate 名 | `docs/30-open-questions.md` (R58 关闭前) |

> **回链原则**: 本文件是 naming SSOT,被 1X 子系统文档引用;0X 跨切面文档(`00-ffi-pillars.md` 同级)不算 D# 回链源 — back-link gate 强制 1X 子系统文档至少 1 处。