## Task 9 (7 %) · Services & Networking

### Lock down the database

Namespace `e1-t9` runs pods `frontend` (`app=frontend`), `backend`
(`app=backend`) and `db` (`app=db`, TCP **5432**). Create NetworkPolicy
**`db-access`** so that `db` accepts connections **only** from `backend`, on
TCP 5432. Nothing else about the namespace's traffic should change.
