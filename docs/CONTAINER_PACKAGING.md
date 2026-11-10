# Container packaging assignment

You receive a complete Flask/PostgreSQL application. Your job is to package it using Docker. You do not need to understand, edit or write Python.

Create `Dockerfile` and `.dockerignore` in the repository root, beside `compose.yaml`. Neither file is supplied in the student package. The Compose stack and CI image build will not work until you complete them. Keep the supplied application, dependency versions, tests and Compose configuration unchanged for this exercise.

Allow 3-4 hours within Milestone 1's existing 10-hour budget. Start with the runtime image, then add the test target. Ask the instructor for a checkpoint after 60-90 minutes on the same blocker.

## Application facts supplied by the development team

| Item | Exact requirement |
|---|---|
| Runtime | Python 3.12 on Linux; use `python:3.12-slim-bookworm` for this cohort |
| Working directory | `/app` |
| Runtime dependencies | `requirements.txt`; keep the supplied pins |
| Install command | `python -m pip install --no-cache-dir -r requirements.txt` |
| Application files | Entire `app/` directory, including templates, static assets and `schema.sql` |
| Server configuration | `gunicorn.conf.py`, placed in `/app` |
| Start command | `gunicorn --config gunicorn.conf.py 'app:create_app()'` |
| Listening address | `0.0.0.0:8000`, already configured in `gunicorn.conf.py` |
| Runtime identity | UID 10001 and GID 10001 |
| Writable location | `/tmp`; the rest of the container filesystem must support read-only operation |
| Python environment | `PYTHONDONTWRITEBYTECODE=1` and `PYTHONUNBUFFERED=1` |
| Version | Build argument `APP_VERSION`, default `local`, retained as an environment variable in the image |
| Logs | Standard output/error; no application log directory needed |

`pip` installs the listed packages. `gunicorn` is the supplied web server. `app:create_app()` tells it how to load this application. Treat that last string as one command argument. When using Docker's JSON command form, include no literal single quotes around it.

The supplied dependencies include the PostgreSQL client library. You do not need to install a PostgreSQL server, a compiler, Node.js or a virtual environment in the application image. PostgreSQL runs in its own container. Keep the supplied Gunicorn setting of one worker and four threads for correct metrics.

## Files needed by each target

| Path | Runtime image | Test image |
|---|---|---|
| `requirements.txt` | Yes | Yes |
| `app/` | Yes, including all subdirectories | Yes |
| `gunicorn.conf.py` | Yes | Yes |
| `requirements-dev.txt` | No | Yes |
| `tests/` and `pytest.ini` | No | Yes |
| `postgres/`, `monitoring/`, `scripts/`, `reference/`, `docs/` | No | No |
| Local credentials, state, backups and Git history | Never | Never |

The directories marked No still belong in the repository. Compose mounts PostgreSQL and monitoring configuration directly from the host. Backup scripts run from the host. They do not belong inside the application image.

## What your Dockerfile must achieve

1. Provide a named `runtime` build target. Compose, GitHub Actions and Jenkins already use that name.
2. Install runtime dependencies before copying application source, so a source-only change can reuse the dependency layer.
3. Include only the runtime files above. Create the required Linux user/group and run the web server as UID/GID 10001. Use a command form that lets Gunicorn receive container stop signals.
4. Document port 8000 and preserve the supplied start command. Compose supplies the host port mapping.
5. Support a build argument for the release version, with no credentials in build arguments or image layers.
6. Provide a named `test` target that contains the runtime, test dependencies and supplied tests. It can extend `runtime`. Installing extra packages may need a temporary build-time user change; its final runtime user must still be 10001:10001.
7. Make a build without `--target` produce the web application image, without test dependencies. Docker uses the last stage by default. Decide how to arrange your stages to meet this requirement.

Use these exact commands for the test target:

```sh
# Dependency installation during image construction
python -m pip install --no-cache-dir -r requirements-dev.txt

# Default command when the test container starts
python -m pytest -q -p no:cacheprovider
```

`requirements-dev.txt` also references `requirements.txt`, so both must be available during installation. The test command disables pytest's cache writes. Don't run tests while building the image: the integration tests need the disposable PostgreSQL service that Compose starts later.

Use an overridable default command. Compose replaces it with `flask --app app init-db` for the one-time schema step. Do not initialize or seed a database during an image build or every API startup.

## What your .dockerignore must achieve

Write the exclusion patterns yourself. Inspect the repository and cover these categories:

- Git history and local editor files.
- Local environment files, credentials, private keys and kubeconfigs.
- Virtual environments, Python bytecode and test caches/results.
- Database backups/dumps and local logs.
- Terraform working directories, state, saved plans and local variable files.
- Documentation, infrastructure examples and other folders unnecessary for either image.

The ignore file filters the build context for **both targets**. Do not exclude `tests/`, `pytest.ini` or `requirements-dev.txt`: the test target needs them. Keep them out of the runtime image by choosing what that target copies. Ignoring a file for Docker does not stop Git from committing it; review `.gitignore` separately.

Consider files inside subdirectories as well as at the repository root. Do not solve this exercise by copying the entire repository into the runtime image and deleting unwanted files in a later layer.

## Check your result

Run from the repository root. These are verification commands, not Dockerfile content. Docker must be running in Linux-container mode. Windows users can use Git Bash or WSL for the shell commands, and `py` instead of `python` for the host helper.

### 1. Build both targets and the default image

```sh
docker build --target runtime --build-arg APP_VERSION=packaging-check -t rt-helpdesk:packaging-check .
docker build --target test -t rt-helpdesk:test-check .
docker build -t rt-helpdesk:default-check .
docker image inspect rt-helpdesk:default-check --format '{{json .Config.Cmd}}'
```

All three builds must succeed. The default command must start Gunicorn, not pytest. A later build with unchanged inputs should reuse cached layers. For a source-change check, add a harmless CSS comment to `app/static/style.css`, rebuild the runtime target, and confirm the dependency-install layer is cached. Remove only your temporary comment afterward.

### 2. Inspect runtime behavior and contents

```sh
docker image inspect rt-helpdesk:packaging-check --format '{{.Config.User}}'
docker run --rm --read-only --tmpfs /tmp --entrypoint sh rt-helpdesk:packaging-check -c 'id; ls /app; touch /tmp/packaging-check'
docker run --rm --entrypoint python rt-helpdesk:packaging-check -m pip show pytest
```

The configured user must be `10001:10001`. The second command must succeed. `/app` must contain the application and server configuration, without tests, infrastructure, backups or credentials. The final command must report that pytest is not installed and return a nonzero exit status; that outcome is expected for the runtime image. Also inspect `default-check` to confirm it contains no pytest or test files.

Review `.dockerignore` with the instructor to confirm excluded categories cannot be sent in the build context. A clean final image alone does not prove that secrets were excluded from the context or earlier layers.

### 3. Start the application and test persistence

```sh
python scripts/setup_env.py
docker compose up --build -d
docker compose ps -a
docker compose exec api flask --app app seed-db
curl --fail http://localhost:8000/healthz
curl --fail http://localhost:8000/readyz
```

Wait for the database and API to become healthy before seeding or checking readiness. The `migrate` service should exit with code 0. If startup fails, inspect `docker compose logs --tail 100 api migrate db`.

Open http://localhost:8000, create a ticket and change its status. Then restart both services:

```sh
docker compose restart api db
```

Wait for readiness and verify the ticket remains. Check `/metrics` and `/version` too. Compose defaults the version to `local`; it can override the image's value. To verify the baked version independently, run:

```sh
docker run --rm --entrypoint printenv rt-helpdesk:packaging-check APP_VERSION
```

Expected output: `packaging-check`. Database values are supplied by Compose at runtime from the generated `.env`; never copy that file into the image. See [API.md](API.md) for the full environment-variable contract.

### 4. Run the supplied tests

```sh
docker compose --profile test run --build --rm tests
docker compose --profile test stop test-db
docker compose --profile test rm -f test-db
```

The test run must exit with code 0 and report 36 passed, with no integration tests skipped. This uses an independent disposable database. Leave the application database intact. Submit the command output with your first successful CI run.

## Submit and explain

Commit your Dockerfile and `.dockerignore`. In your README, briefly explain the stage names, dependency caching, non-root user, runtime secrets, writable `/tmp`, and why tests stay in the context but out of the runtime image. Include the build/test results and persistence check. You do not need a separate report or Python changes.

The existing Docker/local-operation allocation remains 10 points: image behavior and targets (4), context exclusions (2), caching/non-root/runtime configuration explanation (2), and tests plus persistence evidence (2).

If stuck, use these references and ask for a targeted hint:

- [Dockerfile reference](https://docs.docker.com/reference/dockerfile/)
- [Named build stages and targets](https://docs.docker.com/build/building/multi-stage/)
- [Build context and .dockerignore](https://docs.docker.com/build/concepts/context/)

The instructor has a separate solution package for checking and troubleshooting. It is not part of the student handout.
