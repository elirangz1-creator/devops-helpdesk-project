# RT Helpdesk DevOps final project

A supplied Flask + PostgreSQL application for Real Time College. Students operate and deploy this app. **No Python, frontend or business-logic coding is required.**

Read [the final project assignment](docs/FINAL_PROJECT.md) first. It covers AWS, Terraform, Kubernetes, Docker, Jenkins, Git, GitHub Actions, Linux, Prometheus and Grafana.

## What is included

| Included and ready to use | Built by students during the project |
|---|---|
| Flask API, browser UI and PostgreSQL schema | AWS infrastructure in Terraform |
| Five fictional tickets and automated tests | Linux server configuration and automation |
| Container packaging brief and local Compose environment | Dockerfile, .dockerignore and container verification |
| Kubernetes and database initialization examples | Kubernetes manifests and environment configuration |
| Example GitHub Actions checks | Jenkins release and deployment pipeline |
| App metrics, Prometheus rules and Grafana dashboard | Kubernetes monitoring deployment and failure evidence |
| Local and Kubernetes backup helpers | One S3 backup and a verified restore |

This is an individual project targeting 70-90 hours, with one application namespace (`helpdesk`) plus monitoring. Bash/cloud-init cover server setup; Ansible is not required. The [reference solution and setup guide](reference/README.md) supply templates for the supported beginner path. Students use their own AWS accounts and available AWS credits, configure their own budgets, Jenkins agents and deployment credentials, connect the pipeline and verify each required outcome. The instructor supplies tested templates and guidance. The schedule allocates 74 planned hours plus up to 16 troubleshooting hours. The package has not been deployed to an AWS account.

## Complete container packaging first

This is the student package. `Dockerfile` and `.dockerignore` are intentionally absent. Follow [CONTAINER_PACKAGING.md](docs/CONTAINER_PACKAGING.md) to create them. It supplies the exact Python commands, required files, stage names, runtime settings and verification steps. No Python changes are needed. Allow 3-4 hours within the existing first-week budget.

Compose startup and the CI image-build step will fail until the Dockerfile is complete. The finished Docker files are in a separate instructor package.

## Start locally

After completing the packaging assignment, use the following steps.

Requirements: Docker Engine or Docker Desktop with Compose v2, Git, and Python 3.10+ for the helper scripts. Docker Desktop on Windows should use Linux containers. Run all commands from this folder. On Windows, use `py` if `python` is not available.

```sh
python scripts/setup_env.py
docker compose up --build -d
docker compose exec api flask --app app seed-db
```

Open **http://localhost:8000**. Create a ticket and close or reopen it. No login is needed in this lab.

The setup script generates three random passwords in `.env`. It will not overwrite an existing file. Do not commit `.env`. PostgreSQL is reachable only inside the Compose network, and web ports bind to localhost. Use fictional data. Public access and user authentication are outside this lab's default setup.

Initial startup creates the non-superuser `helpdesk_app` role, its schema, and the tickets table. The `migrate` service is a one-shot initialization step. It must finish successfully before the API starts. API restarts do not clear tickets or recreate the schema.

Useful commands:

```sh
docker compose ps -a
docker compose logs --tail 100 api migrate db
docker compose restart api
docker compose down
```

`docker compose down` keeps the data volume. `docker compose down -v` deletes volumes and their contents; use it only when you intentionally want a fresh lab. Changing passwords in `.env` does not change passwords in an existing PostgreSQL volume. Keep the original passwords, rotate them in PostgreSQL, or reset an expendable lab volume.

## Add Prometheus and Grafana

```sh
docker compose --profile monitoring up --build -d
python scripts/traffic.py --seconds 180
```

| Service | Local address |
|---|---|
| Helpdesk UI | http://localhost:8000 |
| App metrics | http://localhost:8000/metrics |
| Prometheus targets | http://localhost:9090/targets |
| Prometheus alerts | http://localhost:9090/alerts |
| Grafana | http://localhost:3000 |

Log into Grafana as `admin`, using `GRAFANA_ADMIN_PASSWORD` from `.env`. Open **Dashboards → DevOps Lab → RT Helpdesk**. The Prometheus datasource and dashboard are provisioned from files. Allow at least two scrapes for rates to appear. An error-rate panel showing zero with healthy traffic is expected.

Read [the monitoring lab](docs/MONITORING.md) for queries, alert exercises and Kubernetes requirements. Prometheus displays firing/resolved alerts. Email or chat notifications are not configured in this package.

## Tests

The following command uses a separate, disposable PostgreSQL test database. It does not test against the application's persistent database.

```sh
docker compose --profile test run --build --rm tests
docker compose --profile test stop test-db
docker compose --profile test rm -f test-db
```

For local Python development, install Python 3.12 and run:

```sh
python -m venv .venv
# Linux/macOS: source .venv/bin/activate
# Windows PowerShell: .venv\Scripts\Activate.ps1
python -m pip install -r requirements-dev.txt
python -m pytest -q
```

Without `RUN_DB_TESTS=1`, database integration tests explicitly skip. To run them against your own disposable PostgreSQL, set `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_SSLMODE` and `RUN_DB_TESTS=1`. `DB_NAME` must end in `_test`; these tests clear its tickets table. The test user must be able to create the `helpdesk` schema. Do not use a shared or live database.

`.github/workflows/ci.yml` runs all tests with a PostgreSQL service on pull requests and `main`. It also builds the runtime image without pushing it. Enable the workflow after pushing the repository to GitHub, then require its check where your repository supports that feature. Otherwise record successful checks before merging. No independent PR approval is required for this individual project. Actions use version tags for readability; pin reviewed commit SHAs for a stronger supply-chain policy.

## Backup and restore locally

```sh
python scripts/db_backup.py --output backups/lab.dump
python scripts/db_restore.py backups/lab.dump --database helpdesk_restore_check1
```

The backup uses `pg_dump` custom format. Restore only accepts a **new** name beginning with `helpdesk_restore_`. It does not overwrite the live database and fails if the destination already exists. It prints a restored row count. Compare actual ticket values as well before declaring recovery successful.

Remove the temporary restore database after inspection:

```sh
docker compose exec db dropdb -U postgres helpdesk_restore_check1
```

If a restore fails, the newly created test database is left in place for diagnosis. Drop that disposable database explicitly before retrying. Backup archives contain ticket data; keep them private.

## API and deployment contract

See [API.md](docs/API.md) for requests and configuration. All web responses use port **8000**. Required paths are `/healthz`, `/readyz`, `/version` and `/metrics`.

Your runtime image must include Gunicorn, use UID/GID **10001**, write application logs to stdout and support a read-only root filesystem with writable `/tmp`. **Keep one Gunicorn worker per container** for correct metrics. Four threads serve requests; scale with Kubernetes replicas. Adding worker processes requires Prometheus multiprocess configuration that is not included here.

Build an image with an identifiable version:

```sh
docker build --target runtime --build-arg APP_VERSION=demo-v1 -t rt-helpdesk:demo-v1 .
```

In Jenkins, replace `demo-v1` with the exact checked-out Git commit SHA. Bake the version into the image and deploy the published image digest to the single `helpdesk` environment. `APP_ENV` is runtime configuration; normally do not override baked-in `APP_VERSION` in Kubernetes.

Before starting the app in a new Kubernetes environment, provision the database and `helpdesk` schema, then run the image once as a Job with:

```sh
flask --app app init-db
```

The initialization retries temporary connection failures up to ten times. `schema.sql` is the initial schema, not a general migration framework. App restarts do not execute DDL.

## Versions and verification

Python dependencies are pinned in `requirements.txt` and `requirements-dev.txt`. PostgreSQL uses the maintained `16-bookworm` tag; Python uses `3.12-slim-bookworm`. These tags can receive updates. Record resolved digests in your release evidence. Prometheus and Grafana use explicit versions in Compose. Review and scan versions before running a class.

See [VALIDATION.md](docs/VALIDATION.md) for what was actually executed while preparing this package and what still requires a Docker/AWS environment.
