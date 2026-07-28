#!/usr/bin/env bash
# =============================================================================
# Wriggly-Octopus D# Back-link Gate (P0-5)
# =============================================================================
# Purpose: every D# in 03-design-decisions.md status table from D126+ must be
#          greppable in at least one subsystem docs/ file (excluding catalog
#          and audit-history files). Empty back-link = propagation未闭环 = FAIL.
# R51-FIX (终态核验): 原版本 `hits=$(grep ... | wc -l)` 在 set -euo pipefail 下
#   当 grep 零命中时 pipefail 触发 set -e 静默退出 — 一个 [ERROR] 都不打.
#   新版本: if/then/else 包裹, pipefail 不影响分支走向; 并加金丝雀自检.
# Source: D# ledger in docs/03-design-decisions.md
# Exit codes: 0 = all back-links present, 1 = dangling D# found
# =============================================================================
set -euo pipefail

LEDGER=docs/03-design-decisions.md
QA=docs/30-open-questions.md
GATE_NAME=check-d-backlinks

# Files where the D# appears as data, not as content (must be excluded)
EXCLUDE_FILES=(
  "03-design-decisions.md"
  "20-documentation-gate.md"
  "30-open-questions.md"
  "check-docs.sh"
  "check-d-backlinks.sh"
  "check_goal_manifest.sh"
)

EXIT=0

# 1. Collect D126-D175 from the status table rows in 03.
# R50: extended to D160 (profile matrix legislation).
# R62: D164-D174 (命名迁移立法 R53-R62).
# R63: regex 扩 1[3-9][0-9] 覆盖 D130-D199 (前瞻 D175+ 至 D199), floor 同步 35→50 (D126-D175 实际计数).
mapfile -t D_TAGS < <(grep -oE '\| D(12[6-9]|1[3-9][0-9]) \|' "$LEDGER" | sed -E 's/\| D([0-9]+) \|/\1/' | sort -u)

# R63 floor: D126-D175 = 51 (R66-3 enacted R66-3 rows 同步, 与实测 03 中 D126-D175 unique 计数对齐)
# D126-D175 计数公式: R37-R50 [35] + R52-R62 命名迁移 [14] + R63 扫描面 [1] + R66-3 enacted [1] = 51
if [[ ${#D_TAGS[@]} -lt 51 ]]; then
  echo "[FATAL] $GATE_NAME expected >=51 D126-D175 tags in $LEDGER, got ${#D_TAGS[@]}"
  exit 2
fi

# 2. For each D# tag, grep across subsystem docs (excluding audit/catalog files).
EXCLUDE_GREP=$(printf -- '--exclude=%s ' "${EXCLUDE_FILES[@]}")

MISSING=()
for d in "${D_TAGS[@]}"; do
  # R51-FIX: if/then/else 替代 `hits=$(grep ... | wc -l)`, 消除 pipefail 静默死亡.
  #   当 grep 零命中 (exit=1) 时, if 条件为 false → hits=0 明确赋值.
  if result=$(grep -rnE "(^|[^0-9])D$d([^0-9]|$)" $EXCLUDE_GREP docs/ 2>/dev/null); then
    hits=$(echo "$result" | wc -l)
  else
    hits=0
  fi
  if [[ "$hits" -eq 0 ]]; then
    MISSING+=("$d")
    echo "[ERROR] D#$d not found in any subsystem docs (excluding catalog/history)"
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo ""
  echo "[FAIL] $GATE_NAME: ${#MISSING[@]} dangling D# back-links: ${MISSING[*]}"
  echo "       Fix by promoting the D-tag into its contagion target doc."
  exit 1
fi

# =============================================================================
# Section 2b: gate-exempt D-ref 校验 (D176 §1.4, R64 即生效)
# =============================================================================
# 校验 docs/**/*.md 中所有 <!-- gate-exempt[: -file]: 标记的 D### ref
# 必须**在 03-design-decisions.md D-table 中存在** (不限状态, ACTIVE / DEPRECATED / SUPERSEDED 均合法).
# 三种 marker 形态都校验, 但只取 D### 部分做 ledger 查表:
#   - <!-- gate-exempt: D175 -->                       (单 D)
#   - <!-- gate-exempt: R63-D175 -->                   (R##-D### 形态; R## 前缀不校验, commit 可回溯性靠人审)
#   - <!-- gate-exempt: D172,D175 -->                  (多 D 逗号分隔)
#   - <!-- gate-exempt-file: desc (D121,D153) -->      (文件级 frontmatter 可附 D 列表)
#
# 反伪充要条件是存在性不是活性 (D176 §1.4):
#   - 存在性: D999 没立过法 → 必假 → fail (反伪目标)
#   - 活性会误伤合法 DEPRECATED 历史叙述豁免
#     (R47 撤销行 / R48 旧 sys_result_t 形态叙述 / R51-F5 asm rv64imac 注释 等都需要 DEPRECATED 仍可豁免)
# R64 时无 marker (空集通过 fail-closed); R65+ 起防伪洞实时生效, R51-D1722 类手写拼写错误不过夜.
# =============================================================================

GATE_EXEMPT_REFS=()
# R64-HOTFIX F1: §2b 必须独立排除集 (不复用 §1 EXCLUDE_GREP).
#   §1 排除 03/20/30 因其是 ledger 数据载体 (D-table / census / 审计档案).
#   §2b 管辖 marker 落盘文件 (R65 起 49 行 marker 落 03 + 1 文件级 frontmatter 落 30),
#       这些必须纳入校验 — 否则 "R65 起任何不存在的 D### 立即 fail" 立法承诺
#       对 98% 的 marker 不成立 (实证: docs/99-tmp.md 伪造 D999 → fail; 同一伪造落 03 → exit 0).
# 仅排除 ci/ 脚本 (其中 marker 形式是叙述性提及, 非真实落盘).
# F2: 同步 SPEC.md (与抽取器扫描面一致, 防止"抽出但永不校验" 脱钩).
# R65-α F4: regex 扩为 `-->[[:space:]]*\|?[[:space:]]*$` (与抽取器同款),
#   允许 markdown 表格行末单元格 marker (`-->` 后仅余 ` |`), 同时 narrative 提及
#   (反引号 / 括号 / 斜杠 等非空白非 `|` 字符) 仍被 $ 锚点排除.
# R65-α F3: D-ref 提取收窄到 `<!-- ... -->` 跨度内 (用 `<!-- gate-exempt(-file)?:.*?-->`
#   非贪婪先抽出 marker 体, 再 `\bD[0-9]+\b` 取 D 号) — 防 narrative 行同句出现
#   未立法 D 号 (如 "D97 草案撤回") 误报. 规约见 D176 §1.1 放置规则.
MARKERS=$(grep -rnE \
  --exclude=check-docs.sh --exclude=check-d-backlinks.sh \
  --exclude=check_goal_manifest.sh --exclude=check-toolchain.sh \
  '<!-- gate-exempt(-file)?:.*-->[[:space:]]*\|?[[:space:]]*$' \
  docs/ SPEC.md 2>/dev/null || true)
if [[ -n "$MARKERS" ]]; then
  while IFS= read -r marker_line; do
    [[ -z "$marker_line" ]] && continue
    # F3: 先抽 marker 体 (`<!-- gate-exempt(-file)?:.*?-->` 非贪婪), 再从体中提 D 号
    #   例 `text <!-- gate-exempt: D175 --> |` → marker 体 `<!-- gate-exempt: D175 -->` → D175
    #   例 `describes <!-- gate-exempt: D175 --> D97 reference` → marker 体 → 仅 D175 (D97 不在体中)
    D_REFS=$(echo "$marker_line" | grep -oE '<!-- gate-exempt(-file)?:.*?-->' | grep -oE '\bD[0-9]+\b' || true)
    for d in $D_REFS; do
      GATE_EXEMPT_REFS+=("$d")
    done
  done <<< "$MARKERS"
fi

# 去重 (sort -u)
if [[ ${#GATE_EXEMPT_REFS[@]} -gt 0 ]]; then
  GATE_EXEMPT_REFS=($(printf '%s\n' "${GATE_EXEMPT_REFS[@]}" | sort -u))
fi

# 校验每个 D-ref 在 $LEDGER 中存在 (状态不限)
BAD_REFS=()
if [[ ${#GATE_EXEMPT_REFS[@]} -gt 0 ]]; then
  for ref in "${GATE_EXEMPT_REFS[@]}"; do
    if ! grep -qE "\| $ref \|" "$LEDGER"; then
      BAD_REFS+=("$ref")
      echo "[ERROR] gate-exempt D-ref 不存在: $ref (must exist in $LEDGER regardless of status)"
    fi
  done
fi

if [[ ${#BAD_REFS[@]} -gt 0 ]]; then
  echo ""
  echo "[FAIL] $GATE_NAME: ${#BAD_REFS[@]} 个伪造/手写错 D-ref: ${BAD_REFS[*]}"
  echo "       D176 §1.4 反伪规则: 存在性不限状态 (标 DEPRECATED 也合法, 历史叙述豁免常引)"
  echo "       Fix: 1) 修 marker 引用的 D### 笔误; 2) 若真需新 D#, 在 03-design-decisions.md D-table 添加"
  exit 1
fi

# 3. Canary self-test (R49-GOV.6: 副本上做, 真 docs/ 恒不可变):
#    在 mktemp docs/ 副本里抹 D156 回链 → 必须触发 0 命中 → 否则门禁机制失效.
#    旧版原地 sed -i 改真 10 号文再恢复 (P5 疣子 #1: 中断留污 + mktemp 建了没用);
#    现改副本, 真 spec 零触碰 (捕兽夹自指判据: 本门跑完 git status 必 clean).
CANARY_DOC_REL="docs/10-error-handling.md"
if ! grep -qE "(^|[^0-9])D156([^0-9]|$)" "$CANARY_DOC_REL"; then
  echo "[FATAL] Canary pre-check failed: D156 not found in $CANARY_DOC_REL (gate mechanism broken)"
  exit 2
fi

CANARY_TMP=$(mktemp -d)
trap 'rm -rf "$CANARY_TMP"' EXIT
cp -r docs "$CANARY_TMP/docs"
# 在副本里抹掉 D156 令牌 (真 docs/ 不动)
sed -i "s/D156/CANARY_DELETED/g" "$CANARY_TMP/$CANARY_DOC_REL"

# 用主循环同逻辑, 但扫副本 docs/
if canary_result=$(grep -rnE "(^|[^0-9])D156([^0-9]|$)" $EXCLUDE_GREP "$CANARY_TMP/docs/" 2>/dev/null); then
  canary_hits=$(echo "$canary_result" | wc -l)
else
  canary_hits=0
fi

if [[ "$canary_hits" -ne 0 ]]; then
  echo "[FATAL] Canary FAILED: D156 still found after deletion — gate mechanism broken"
  echo "        (grep matched $canary_hits lines after canary removal in copy)"
  exit 2
fi

echo "✓ $GATE_NAME passed (${#D_TAGS[@]} D126-D175 tags, all back-linked, canary self-test OK)"
