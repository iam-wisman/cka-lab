## Task 10 (7 %) · Services & Networking

### Route a path through the Gateway

Gateway `infra/cka-gw` (lab 23) serves `store.cka.lab` over HTTPS.
In namespace `e1-t10`, Service `promo` answers `promo`. Make
`https://store.cka.lab/promo` (and paths below it) reach it through that
Gateway's **https** listener, using an HTTPRoute named **`promo`** in
`e1-t10`. Don't modify the Gateway.
