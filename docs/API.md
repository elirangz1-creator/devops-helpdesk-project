# App contract

No application development is required. Students may change infrastructure and configuration without changing these routes.

| Method | Path | Result |
|---|---|---|
| GET | `/` | Browser UI |
| GET | `/api/tickets?limit=20&offset=0` | `items`, `limit`, `offset`, `has_more` |
| POST | `/api/tickets` | Create a ticket; HTTP 201 and Location header |
| GET | `/api/tickets/{id}` | One ticket or HTTP 404 |
| PATCH | `/api/tickets/{id}` | Set status to `open` or `closed` |
| GET | `/healthz` | HTTP 200 while the Flask process works; no DB check |
| GET | `/readyz` | HTTP 200 if database/table is reachable, otherwise 503 |
| GET | `/version` | Image version and environment |
| GET | `/metrics` | Prometheus text format; includes a database reachability check |

Create request:

```json
{"title":"Cannot reach training VM","description":"SSH times out.","requester":"Demo Student"}
```

Update request:

```json
{"status":"closed"}
```

Use `Content-Type: application/json` for POST/PATCH. Title is required, up to 120 characters. Requester is required, up to 80. Description is optional, up to 2,000. Unexpected fields, null bytes and wrong types are rejected. The maximum request body is 16 KiB. List limit is 1..100 and offset is 0..1,000,000. List order is newest first.

The database generates IDs and timestamps. Updates use parameterized SQL and commit before success is returned. A failed database operation returns a generic 503 without exposing connection details. No delete endpoint is provided.

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| DB_HOST | db | PostgreSQL host |
| DB_PORT | 5432 | PostgreSQL port |
| DB_NAME | helpdesk | Database name |
| DB_USER | helpdesk_app | Non-superuser application role |
| DB_PASSWORD | Required | Application database password |
| DB_SSLMODE | prefer | Set `disable` only for the local isolated lab; use appropriate TLS verification for remote databases |
| APP_VERSION | local, or image build argument | Identifies the release |
| APP_ENV | development | Environment label |

The app reads process environment variables, not a `.env` file directly. Compose reads `.env` and passes selected variables into services. Supply Secrets/ConfigMaps in Kubernetes. The application does not need AWS API credentials.

## Kubernetes runtime requirements

- Port 8000, UID/GID 10001, read-only root filesystem, writable `/tmp` using an `emptyDir` volume.
- Liveness: `/healthz`. Readiness: `/readyz`. Use a readiness timeout of at least 10 seconds; DB connection timeout is 3 seconds and query timeout is 5 seconds. Tune after measurement.
- No local application data volume. All tickets live in PostgreSQL. Two API replicas share one database per environment.
- PostgreSQL needs a persistent volume. A PVC is not a backup and local-node storage does not survive losing that node.
- Bootstrap the application database role/schema separately, run `init-db` once per environment, then start API replicas. Limit database admin credentials to bootstrap/recovery operations.
- The lab app role owns its schema to keep initialization simple. Separating migration ownership from runtime CRUD permissions is an optional hardening exercise.
- `/metrics` should be reachable by Prometheus inside the lab network, not publicly exposed.
- Test service routing and load distribution through the Service from a test Pod. `kubectl port-forward` is useful for demonstration but is not a load-balancing test.

## PostgreSQL without Docker Compose

Create a database named `helpdesk` and a login role `helpdesk_app` using your database administrator. Give that role ownership of a schema named `helpdesk` and permission to connect to the database. Use the supplied `postgres/init/01-app-role.sh` as the reference, passing a real password through a secret source. Never paste real passwords into Git.

Export the DB variables, then run:

```sh
flask --app app init-db
flask --app app seed-db
gunicorn --config gunicorn.conf.py 'app:create_app()'
```

Gunicorn is the Linux/container runtime. For local development on Windows only, `flask --app app run --port 8000` is sufficient after configuring a database. Do not use the Flask development server as your deployed service.
