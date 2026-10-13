### CronJob with history, deadline and a manual run

In namespace `{{NS}}`, CronJob **`{{CJ}}`** runs `busybox:1.37` and prints
`{{WORD}}`, every **{{EVERY}} minutes**:

- a run never overlaps the previous one
- keep **{{KEEP}}** successful Jobs and **1** failed Job
- a run is killed after **{{DEADLINE}} seconds**
- a failed container is never restarted in place

Then run it once **now**, as Job **`{{CJ}}-now`** created from the CronJob. It
must complete.

**Time budget:** 3:00
