### Dedicate a node to one team

Reserve node **`{{NODE}}`** for team `{{TEAM}}`: taint it
`dedicated={{TEAM}}:NoSchedule` and label it `team={{TEAM}}`.

Then run Pod **`{{POD}}`** (`busybox:1.37`, `sleep 3600`) in `{{NS}}` so that it
can only ever be scheduled to `{{NODE}}`.

**Time budget:** 2:30
