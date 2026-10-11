# Lab 13: ConfigMaps and Secrets

**Domain:** Workloads & Scheduling (15%)
**Curriculum:** Use ConfigMaps and Secrets to configure applications
**Suggested time:** 50 minutes · **Start with:** `lab start 13` · **Namespace:** `config`

`lab start 13` put input files in `~/config/`.

## Tasks

### Objects

| Name | Kind | From |
|---|---|---|
| `app-props` | ConfigMap | `~/config/app.properties` as **one key** named `app.properties` |
| `app-env` | ConfigMap | `~/config/app.env`, **one key per line**; **immutable** |
| `nginx-conf` | ConfigMap | `~/config/nginx.conf`, key `nginx.conf` |
| `db` | Secret (Opaque) | `username=app` and key `password` from `~/config/db-password.txt` |
| `web-tls` | Secret, TLS type | `~/config/tls.crt` and `~/config/tls.key` |

### Pod `app` (namespace `config`)

Two containers sharing the pod:

**Container `main`**, image `busybox:1.37`, command `sleep 86400`, memory
limit `96Mi` (request `32Mi`), CPU request `50m`:

1. every key of `app-env` as an environment variable prefixed **`CFG_`**
   (`CFG_LOG_LEVEL`, ...)
2. `DB_USER` from Secret `db`, key `username`
3. `app.properties` from `app-props` at **`/etc/app/application.properties`**,
   and no other files in `/etc/app`
4. Secret `db` mounted **read-only** at `/run/secrets/db`, files with mode **0400**
5. One **projected** volume at `/etc/meta` containing:
   - `props`: the `app.properties` key of `app-props`
   - `tls.crt`: the certificate from `web-tls` (not the key!)
   - `labels`: the pod's labels
   - `mem_limit`: this container's memory limit **in MiB** (the file must contain `96`)

**Container `nginx`**, image `nginx:1.27-alpine`: `nginx-conf` mounted so it
replaces **only** `/etc/nginx/nginx.conf`. Every other file nginx ships in
`/etc/nginx` (e.g. `mime.types`) must still be there.

The pod must have the label `app: config-demo` and be `Running` with both containers ready.

## Grading

```
lab check 13
```

## Notes

- `kubectl create configmap --from-file`, `--from-env-file` and `--from-literal`
  produce different key layouts. Look at what each one gives you.
- An immutable ConfigMap can't be edited, only deleted and recreated.
- `subPath` mounts don't receive updates when the ConfigMap changes. Know why.
