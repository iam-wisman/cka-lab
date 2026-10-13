### A static pod on a worker

Run Pod **`{{POD}}`** (`{{IMG}}`) in namespace `{{NS}}` as a **static pod**
on `{{NODE}}`: its kubelet runs it, not the API server, and it comes back by
itself if the API server's copy is deleted.

**Time budget:** 2:30
