### Pod with exact requests and limits

In namespace `{{NS}}`, run Pod **`{{POD}}`**:

- image `nginx:{{TAG}}`, label `tier={{TIER}}`
- requests **{{CPU}}m** CPU and **{{MEM}}Mi** memory
- a memory limit of **{{MEMLIM}}Mi** and **no** CPU limit

It must be Running.

**Time budget:** 1:30
