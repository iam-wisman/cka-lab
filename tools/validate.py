#!/usr/bin/env python3
"""Consistency checks that need no cluster: lab and exam metadata, prerequisites,
files every lab must have, and images the README points to. Exit 1 on any problem."""
import os, re, sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
problems = []


def meta(path):
    out = {}
    for line in open(path):
        m = re.match(r'^([A-Z_]+)=(.*)$', line.strip())
        if m:
            out[m.group(1)] = m.group(2).strip().strip('"\'')
    return out


labs_dir = os.path.join(root, "lab", "labs")
labs = sorted(d for d in os.listdir(labs_dir) if re.match(r"^\d\d-", d))
nums = {d[:2] for d in labs}
for d in labs:
    p = os.path.join(labs_dir, d)
    for f in ("meta", "task.md", "check.sh"):
        if not os.path.isfile(os.path.join(p, f)):
            problems.append(f"{d}: missing {f}")
    if not os.path.isfile(os.path.join(p, "meta")):
        continue
    m = meta(os.path.join(p, "meta"))
    for k in ("TITLE", "DOMAIN", "CURRICULUM", "TIME"):
        if not m.get(k):
            problems.append(f"{d}: meta has no {k}")
    for n in m.get("NEEDS", "").split():
        if n not in nums:
            problems.append(f"{d}: NEEDS unknown lab {n}")
        elif int(n) >= int(d[:2]):
            problems.append(f"{d}: NEEDS {n}, which isn't an earlier lab")
    setup = os.path.join(p, "setup.sh")
    if os.path.exists(setup) and not os.access(setup, os.X_OK):
        problems.append(f"{d}: setup.sh isn't executable (lab start only runs executable setups)")

exams_dir = os.path.join(root, "lab", "exams")
for e in sorted(os.listdir(exams_dir)):
    p = os.path.join(exams_dir, e)
    if not os.path.isdir(p):
        continue
    for n in meta(os.path.join(p, "meta")).get("NEEDS", "").split() if os.path.exists(os.path.join(p, "meta")) else []:
        if n not in nums:
            problems.append(f"exam {e}: NEEDS unknown lab {n}")
    for t in sorted(os.listdir(os.path.join(p, "tasks"))):
        tp = os.path.join(p, "tasks", t)
        for f in ("meta", "task.md", "check.sh"):
            if not os.path.isfile(os.path.join(tp, f)):
                problems.append(f"exam {e}/{t}: missing {f}")
        if os.path.isfile(os.path.join(tp, "meta")) and not meta(os.path.join(tp, "meta")).get("WEIGHT", "").isdigit():
            problems.append(f"exam {e}/{t}: meta has no numeric WEIGHT")

drills_dir = os.path.join(root, "lab", "drills")
for d in sorted(os.listdir(drills_dir)) if os.path.isdir(drills_dir) else []:
    p = os.path.join(drills_dir, d)
    for f in ("meta", "params", "task.md", "setup.sh", "check.sh", "cleanup.sh"):
        if not os.path.isfile(os.path.join(p, f)):
            problems.append(f"drill {d}: missing {f}")
    m = meta(os.path.join(p, "meta")) if os.path.isfile(os.path.join(p, "meta")) else {}
    if not m.get("SECONDS", "").isdigit():
        problems.append(f"drill {d}: meta has no numeric SECONDS")
    for n in m.get("NEEDS", "").split():
        if n not in nums:
            problems.append(f"drill {d}: NEEDS unknown lab {n}")
    keys = {l.split()[0] for l in open(os.path.join(p, "params")) if l.strip() and not l.startswith("#")} if os.path.isfile(os.path.join(p, "params")) else set()
    for used in set(re.findall(r"\{\{([A-Z_][A-Z0-9_]*)\}\}", open(os.path.join(p, "task.md")).read())) - keys:
        problems.append(f"drill {d}: task.md uses {{{{{used}}}}}, which params doesn't define")

for d in labs:   # placeholders in labs must be declared too
    p = os.path.join(labs_dir, d)
    used = set(re.findall(r"\{\{([A-Z_][A-Z0-9_]*)\}\}", open(os.path.join(p, "task.md")).read()))
    keys = {l.split()[0] for l in open(os.path.join(p, "params")) if l.strip() and not l.startswith("#")} if os.path.isfile(os.path.join(p, "params")) else set()
    for k in used - keys:
        problems.append(f"{d}: task.md uses {{{{{k}}}}}, which params doesn't define")

readme = open(os.path.join(root, "README.md")).read()
for ref in sorted(set(re.findall(r'(?:src|href)="((?:docs|lab)/[^"#]+)"|\]\(((?:docs|lab)/[^)#]+)\)', readme))):
    path = ref[0] or ref[1]
    if not os.path.exists(os.path.join(root, path)):
        problems.append(f"README: {path} doesn't exist")

for p in problems:
    print("FAIL", p)
print(f"{len(labs)} labs and {len(os.listdir(drills_dir)) if os.path.isdir(drills_dir) else 0} drills checked, {len(problems)} problem(s)")
sys.exit(1 if problems else 0)
