#!/usr/bin/env bash
# =============================================================================
# expand_gate_exempt.sh — D176 §1.5 豁免展开函数 (R66 切换基础设施, 调用 Python 实现)
# =============================================================================
# 用法:
#   bash tools/spec_lab/expand_gate_exempt.sh [sidecar_file]
#   bash tools/spec_lab/expand_gate_exempt.sh   # 默认 $PWD/tools/spec_lab/extracted/gate-exempt-markers.txt
#
# 输出: 每行 "file:line" (相对路径, 1-based), 排序去重
# =============================================================================
set -euo pipefail
exec python3 "$(dirname "$0")/expand_gate_exempt.py" "$@"