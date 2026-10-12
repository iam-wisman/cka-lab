## Task 14 (5 %) · Workloads & Scheduling

### A scheduled report

In namespace `e2-t14` create CronJob **`report`** (`busybox:1.37`, command
`date`) running **every 15 minutes**, keeping **3** successful Jobs. Then trigger
one run immediately from it as Job **`report-now`**, which must complete.
