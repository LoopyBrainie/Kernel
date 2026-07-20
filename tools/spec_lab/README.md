# spec_lab: 把 "frozen = 编译过的" 落到机器

> **R49 立骨**: 任何写进 `docs/*.md` 的指令级 / ABI 级代码片段, 必须能在编译期被验证, 否则不享受 "frozen" 身份.
> 验证手段: 脚本从 markdown 的代码围栏 (`` ```asm `` / `` ```c `` / `` ```zig ``) 按 anchor 抽取, 喂给对应编译器, 通过则 frozen.

---

## 设计硬性要求 (R49 立法, 不可破坏)

1. **抽取式断言, 禁止副本**: 任何 assertion 脚本 **不得** 把代码片段复制到本目录下. 必须用 `extract.sh` 按 anchor 从 `docs/*.md` 现抓现编译. 这是 R49 的核心反漂移机制 — 副本三个月后必然与 spec 漂移, "frozen" 就成了制度性造假.

2. **anchor → fence 一一对应**: 每个 assertion 注册一个 anchor (在 doc 里有显式标记, 如 `R49-F1 jr t0 勘误`), `extract.sh` 找到 anchor 后的第一个代码围栏, 抽到 `extracted/<assertion_id>.ext.<lang>`.

3. **runner 编译验证**: `run_all.sh` 顺序执行所有 `assertions/*.sh`, 每个脚本对自己抽出的文件做 `clang -c` / `zig build-obj` / `riscv64-linux-gnu-gcc -c`, 期望通过 (exit 0). 失败 → gate 熔断, R49 收官失败.

4. **反例负测**: 每条 assertion 必须附带一个 `assertions/<id>_negative.sh`, 故意把 anchor 指向"草图烂掉"的内容 (e.g. `lw` 而非 `lwu`), 验证 runner 能抓到. 这是 "frozen = 编译过的" 的反向防御.

---

## 首批三条断言 (R49-LAB 与 F1/F2/F3 同源)

| ID | Anchor | 抽取位置 | 验证内容 | 期望结果 |
|----|--------|---------|---------|---------|
| `R49-F1-jr` | `R49-F1 勘误: 改回 jr t0 尾调用` | `docs/05-call-gate.md` § entry_call_gate.S | 草图第一行应为 `jr t0`, 不应为 `jalr ra, t0` | `grep -q 'jr[[:space:]]*t0'` 通过; 反例 grep `jalr.*t0` 失败 |
| `R49-F2-lwu` | `R49-F2 勘误: lw → lwu` | `docs/06-boot-sequence.md` § Step 0 | DTB magic 加载应为 `lwu t0, 0(a1)`, 不应为 `lw` | `grep -q 'lwu[[:space:]]*t0.*0(a1)'` 通过 |
| `R49-F3-hlcb1` | `R49-F3 勘误: HLCB_SIZE=1 单 Hart 边界条款` | `docs/06-boot-sequence.md` § .comptime_assert_power_of_2 下方 | 必须出现 "HLCB_SIZE=1" 与 "@compileError" 字面量 | `grep -q 'HLCB_SIZE == 1'` 与 `grep -q '@compileError'` 双过 |

---

## 目录结构

```
tools/spec_lab/
├── README.md                   # 本文件 (R49 立骨)
├── extract.sh                  # anchor → fence 抽取器
├── run_all.sh                  # 顺跑所有 assertions/*.sh
├── run_negative.sh             # 顺跑所有 _negative.sh, 期望全部 FAIL
├── extracted/                  # 抽取落盘的临时文件 (gitignored)
└── assertions/
    ├── R49-F1-jr.sh            # 正向: 抽 jr t0 → grep 验证
    ├── R49-F1-jr_negative.sh   # 反向: 故意抽 jalr → grep 应抓到
    ├── R49-F2-lwu.sh
    ├── R49-F2-lwu_negative.sh
    ├── R49-F3-hlcb1.sh
    ├── R49-F3-hlcb1_negative.sh
    └── audit-rust-unsafe.sh    # 沙箱执行的 Rust unsafe 计数门禁 (GOAL ≤ 3)
```

---

## 运行

```bash
# 顺跑所有正向断言 (R49 收官判据)
bash tools/spec_lab/run_all.sh
# 期望: 3/3 PASS

# 顺跑所有反向断言 (验证 runner 真能抓到烂草图)
bash tools/spec_lab/run_negative.sh
# 期望: 3/3 FAIL (因为草图故意坏掉)

# 沙箱内执行 Rust unsafe 计数 (需要在 sandbox 跑)
bash tools/spec_lab/assertions/audit-rust-unsafe.sh path/to/shell/src
# 期望: unsafe count ≤ 3 (R49 目标, 沙箱二 O5 实测 5)
```

---

## 禁止漂移词 (R49 立法)

- "spec_lab 副本" (指断言目录下出现代码副本, 不是抽取得到的)
- "frozen 等同于已写" (任何 frozen 内容必须经此 runner)
- "R49 草图烂掉靠 reviewer 眼" (必须是机器 enforced)

详细禁词入 `docs/ci/check-docs.sh` 由 R50 处理.