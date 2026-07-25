#!/usr/bin/env python3
"""D176 §1.5 豁免展开: SELF/PREV/FILE 三态.

三态:
- SELF: marker 行即被豁免行
- PREV: marker 行到下一空行 (段落级), 单实例特例 01:20 → 01:21
- FILE: frontmatter 覆盖整个文件

Usage: python3 expand_gate_exempt.py [sidecar_file]
Output: 每行 "file:line" (相对路径, 1-based), 排序去重
"""
import sys
import os
import re


def main():
    sidecar_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.getcwd(), "tools/spec_lab/extracted/gate-exempt-markers.txt"
    )
    project_root = os.getcwd()

    if not os.path.isfile(sidecar_path):
        print(f"[FATAL] sidecar 不存在: {sidecar_path}", file=sys.stderr)
        sys.exit(2)

    # 1. 解析 sidecar (file:line:content)
    file_self_lines = {}
    file_using_file_mode = set()

    with open(sidecar_path, encoding="utf-8", errors="replace") as f:
        for raw in f:
            m = re.match(r"^([^:]+):(\d+):(.*)$", raw.rstrip("\n"))
            if not m:
                continue
            file = m.group(1)
            line = int(m.group(2))
            content = m.group(3)
            if "gate-exempt-file:" in content:
                file_using_file_mode.add(file)
            elif "<!-- gate-exempt:" in content:
                file_self_lines.setdefault(file, set()).add(line)

    exempt = set()

    # 2. FILE 模式展开: 整文件每行
    for file in file_using_file_mode:
        full_path = os.path.join(project_root, file)
        if not os.path.isfile(full_path):
            continue
        with open(full_path, encoding="utf-8", errors="replace") as fh:
            for n, _line in enumerate(fh, 1):
                exempt.add(f"{file}:{n}")

    # 3. SELF 模式展开: marker 行精确匹配
    for file, lines in file_self_lines.items():
        for n in lines:
            exempt.add(f"{file}:{n}")

    # 4. PREV 模式特判 (01:20 → 01:21)
    prev_extras = [("docs/01-system-overview.md", 21)]
    for file, n in prev_extras:
        if file in file_self_lines and any(
            marker_line == 20 for marker_line in file_self_lines[file]
        ):
            exempt.add(f"{file}:{n}")

    # 5. 排序输出
    for line in sorted(exempt):
        print(line)


if __name__ == "__main__":
    main()