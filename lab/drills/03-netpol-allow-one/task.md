### NetworkPolicy: one role, one port

In namespace `{{NS}}`, pods labelled `app=api` must accept ingress **only**
from pods labelled `role={{ROLE}}` in the same namespace, and only on TCP
**{{APORT}}**. Their egress stays unrestricted. Name the policy **`{{NP}}`**.

Pods `{{GOOD}}` and `intruder` are there to test with.

**Time budget:** 3:00
