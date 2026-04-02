#!/bin/bash
# Fix RST indentation errors + warnings in CVA6 documentation
# Usage: bash fix_rst_indentation.sh [DOCS_DIR]
# Default DOCS_DIR is the directory where this script resides.

set -e

DOCS_DIR="${1:-$(dirname "$0")}"

python3 - "$DOCS_DIR" << 'PYEOF'
import re, os, sys

docs_dir = sys.argv[1]

# =========================================================================
# Helper: wrap pseudocode blocks in ".. code-block:: text"
# =========================================================================
def fix_pseudocode(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    result = []
    i = 0
    changed = 0
    while i < len(lines):
        line = lines[i]
        if re.match(r' {4}\*\*Pseudocode\*\*:', line):
            match = re.match(r' {4}\*\*Pseudocode\*\*: (.*)', line)
            if match and match.group(1).strip():
                first_code = match.group(1)
                result.append('    **Pseudocode**:\n\n')
                result.append('    .. code-block:: text\n\n')
                result.append('        ' + first_code + '\n')
                i += 1
                while i < len(lines):
                    cline = lines[i]
                    if cline.strip() == '':
                        if i + 1 < len(lines):
                            next_l = lines[i + 1]
                            if re.match(r' {4}\*\*', next_l) or \
                               (re.match(r'- ', next_l) and not re.match(r' {20,}', next_l)):
                                result.append('\n')
                                break
                        result.append(cline)
                        i += 1
                    elif re.match(r' {20,}', cline):
                        result.append('    ' + cline)
                        i += 1
                    else:
                        break
                changed += 1
            else:
                result.append(line)
                i += 1
        else:
            result.append(line)
            i += 1
    if changed:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.writelines(result)
        print(f"  Fixed {changed} pseudocode blocks in {filepath}")

# =========================================================================
# Helper: fix title underline/overline too short
# =========================================================================
def fix_title_underlines(filepath):
    with open(filepath, 'r') as f:
        lines = f.readlines()
    fixed = 0
    for i in range(len(lines)):
        curr = lines[i].rstrip('\n')
        if curr and all(c == curr[0] for c in curr) and curr[0] in '=-~^':
            if i > 0:
                prev = lines[i-1].rstrip('\n')
                if prev.strip() and not all(c == prev[0] for c in prev) and len(curr) < len(prev):
                    lines[i] = curr[0] * len(prev) + '\n'
                    fixed += 1
            if i < len(lines)-1:
                nxt = lines[i+1].rstrip('\n')
                if nxt.strip() and not all(c == nxt[0] for c in nxt) and len(curr) < len(nxt):
                    lines[i] = curr[0] * len(nxt) + '\n'
                    fixed += 1
    if fixed:
        with open(filepath, 'w') as f:
            f.writelines(lines)
        print(f"  Fixed {fixed} title underlines in {filepath}")

# =========================================================================
# Helper: add :orphan: at top of file
# =========================================================================
def add_orphan(filepath):
    with open(filepath, 'r', encoding='utf-8-sig') as f:
        content = f.read()
    if content.startswith(':orphan:'):
        return
    content = ':orphan:\n\n' + content
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"  Added :orphan: to {filepath}")

# =========================================================================
# 1. Fix RISCV_Instructions_RVZcmp.rst pseudocode blocks
# =========================================================================
print("Fixing RVZcmp pseudocode blocks...")
fix_pseudocode(os.path.join(docs_dir, '01_cva6_user/RISCV_Instructions_RVZcmp.rst'))

# =========================================================================
# 2. Fix other RV* instruction files pseudocode blocks + title underlines
# =========================================================================
rv_files = [
    '01_cva6_user/RISCV_Instructions_RVZbkb.rst',
    '01_cva6_user/RISCV_Instructions_RVZbkx.rst',
    '01_cva6_user/RISCV_Instructions_RVZknd.rst',
    '01_cva6_user/RISCV_Instructions_RVZkne.rst',
    '01_cva6_user/RISCV_Instructions_RVZknh.rst',
]
print("Fixing RV* instruction files...")
for rel in rv_files:
    fpath = os.path.join(docs_dir, rel)
    if os.path.exists(fpath):
        fix_pseudocode(fpath)
        fix_title_underlines(fpath)

# =========================================================================
# 3. Fix Trigger_Module.rst (trailing whitespace + nested lists)
# =========================================================================
print("Fixing Trigger_Module.rst...")
trigger_path = os.path.join(docs_dir, '01_cva6_user/Trigger_Module.rst')
with open(trigger_path, 'r', encoding='utf-8') as f:
    content = f.read()

ARROW = '\u2192'

# Remove trailing whitespace
lines = content.split('\n')
lines = [line.rstrip() for line in lines]
content = '\n'.join(lines)

# Convert 4-space arrow items to 2-space colon items
content = re.sub(
    r'\n( {4})- (``\d+``) ' + re.escape(ARROW) + r' ([^\n]+)',
    r'\n  - \2: \3', content)

# Convert "Bit N → X" items
content = re.sub(
    r'\n( +)- (Bit \d+) ' + re.escape(ARROW) + r' ([^\n]+)',
    r'\n  - \2: \3', content)

# Flatten Key Fields action definitions
content = content.replace(
    '- ``action``: Determines what to do on match:\n\n    - ``0``: Raise a breakpoint exception\n    - ``1``: Enter debug mode',
    '- ``action``: Determines what to do on match: ``0`` = Raise a breakpoint exception, ``1`` = Enter debug mode')
content = content.replace(
    '- ``action``: Determines the response:\n    - ``0``: Raise a breakpoint exception\n    - ``1``: Enter debug mode',
    '- ``action``: Determines the response: ``0`` = Raise a breakpoint exception, ``1`` = Enter debug mode')
content = content.replace(
    '- ``action``: Determines what to do when the interrupt matches:\n    - ``0``: Breakpoint\n    - ``1``: Debug mode',
    '- ``action``: Determines what to do when the interrupt matches: ``0`` = Breakpoint, ``1`` = Debug mode')

# Flatten Action Taken sub-items
content = content.replace(
    '- Breakpoint (``action == 0``):\n  - Sets ``break_from_trigger_d = 1``, which results in:\n    - Trap entry\n    - Updates to ``mstatus``, ``mepc``, ``mcause``',
    '- Breakpoint (``action == 0``):\n  - Sets ``break_from_trigger_d = 1``, resulting in trap entry and updates to ``mstatus``, ``mepc``, ``mcause``')
content = content.replace(
    '- Debug Entry (``action == 1``):\n  - Sets ``debug_from_trigger_d = 1``, resulting in:\n    - Trap into debug mode\n    - Updates ``dpc``, ``dcsr``',
    '- Debug Entry (``action == 1``):\n  - Sets ``debug_from_trigger_d = 1``, resulting in trap into debug mode and updates to ``dpc``, ``dcsr``')

# Fix mcontrol6 Condition Match → table
content = content.replace(
    '2. Condition Match:\n'
    '   - Based on operation type and mode:\n'
    '     - Instruction Execute:\n'
    '       - Match against PC (`commit_instr_i.pc`) or instruction (`orig_instr_i`).\n'
    '     - Store Operation:\n'
    '       - Match against store data (`store_result_i`) or address (`vaddr_from_lsu_i`).\n'
    '     - Load Operation:\n'
    '       - Match against load result (`commit_instr_i.result`) or load address (`vaddr_from_lsu_i`).',
    '2. Condition Match:\n'
    '   - Based on operation type and mode:\n\n'
    '     .. list-table::\n'
    '        :widths: 30 70\n'
    '        :header-rows: 0\n\n'
    '        * - Instruction Execute\n'
    '          - Match against PC (`commit_instr_i.pc`) or instruction (`orig_instr_i`).\n'
    '        * - Store Operation\n'
    '          - Match against store data (`store_result_i`) or address (`vaddr_from_lsu_i`).\n'
    '        * - Load Operation\n'
    '          - Match against load result (`commit_instr_i.result`) or load address (`vaddr_from_lsu_i`).')

# Fix mcontrol6 On match sub-items
content = content.replace(
    'On match:\n- The configured ``action`` is executed.\n- In debug mode, internal state is reset:\n  - ``hit0`` is cleared\n  - ``hit1`` is latched',
    'On match:\n- The configured ``action`` is executed.\n- In debug mode, internal state is reset: ``hit0`` is cleared, ``hit1`` is latched.')

with open(trigger_path, 'w', encoding='utf-8') as f:
    f.write(content)
print(f"  Fixed: {trigger_path}")

# =========================================================================
# 4. Add :orphan: to documents not in any toctree
# =========================================================================
print("Adding :orphan: to orphan documents...")
orphan_files = [
    '01_cva6_user/CV32A6_Control_Status_Registers.rst',
    '01_cva6_user/Trigger_Module.rst',
    '07_cv32a60x/riscv/priv.rst',
    '07_cv32a60x/riscv/unpriv.rst',
    'csr-from-ip-xact/cv32a60ax/cva6_csr.rst',
]
for rel in orphan_files:
    fpath = os.path.join(docs_dir, rel)
    if os.path.exists(fpath):
        add_orphan(fpath)

# =========================================================================
# 5. Fix title underlines across remaining files
# =========================================================================
print("Fixing title underlines...")
title_fix_files = [
    '01_cva6_user/CSR_CV64A6_MMU.rst',
    '01_cva6_user/CSR_CV64A6_MMU_list.rst',
    '01_cva6_user/Programmer_View.rst',
    '06_cv64a6_mmu/index.rst',
]
for rel in title_fix_files:
    fpath = os.path.join(docs_dir, rel)
    if os.path.exists(fpath):
        fix_title_underlines(fpath)

# =========================================================================
# 6. Fix spec_builder.py: remove duplicate label + add :orphan: to header
# =========================================================================
print("Fixing spec_builder.py...")
spec_path = os.path.join(docs_dir, 'scripts/spec_builder.py')
with open(spec_path, 'r') as f:
    src = f.read()

# Add :orphan: to HEADER_RST
src = src.replace(
    'HEADER_RST = """\\\n..\n   Copyright 2024 Thales DIS France SAS',
    'HEADER_RST = """\\\n:orphan:\n\n..\n   Copyright 2024 Thales DIS France SAS')

# Remove the duplicate label from generated user_cfg_doc
src = src.replace('.. _cva6_user_cfg_doc:\n\n.. list-table', '.. list-table')

with open(spec_path, 'w') as f:
    f.write(src)
print(f"  Fixed: {spec_path}")

print("\nAll RST fixes applied successfully.")
PYEOF
