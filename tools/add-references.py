#!/usr/bin/env python3
"""Insert/refresh the "## References" section of every lab from tools/references.py."""
import glob, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from references import REFS

labs = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lab", "labs")
for d in sorted(glob.glob(os.path.join(labs, "[0-9][0-9]-*"))):
    n = os.path.basename(d)[:2]
    p = os.path.join(d, "task.md")
    s = open(p).read()
    if "\n## References\n" in s:                       # drop the old section
        a = s.index("\n## References\n")
        b = s.find("\n## ", a + 5)
        s = s[:a] + (s[b:] if b != -1 else "\n")
    sec = ["", "## References", "",
           "Official documentation. Practise finding answers on kubernetes.io: it is the main resource the exam lets you open (the Linux Foundation candidate handbook has the current list).", ""]
    for title, url in REFS[n]:
        sec.append(f"- [{title}]({url})")
    block = "\n".join(sec) + "\n"
    at = s.find("\n## Cleaning up")
    s = (s[:at].rstrip("\n") + "\n" + block + s[at:]) if at != -1 else s.rstrip("\n") + "\n" + block
    open(p, "w").write(s)
print(f"references added to {len(REFS)} labs")
