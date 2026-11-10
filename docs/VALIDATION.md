# Verification record

Prepared 8 November 2026. Revised to the individual 70-90 hour beginner baseline on the same date. Checks below describe what was actually executed, not what the supplied deployment files are intended to do.

| Check | Result |
|---|---|
| Application unit/API tests | 28 passed |
| PostgreSQL integration tests | 8 passed using an embedded PGlite PostgreSQL engine exposed through its PostgreSQL wire-protocol adapter and the real psycopg client |
| Combined application suite | 36 passed |
| Live Gunicorn HTTP checks | HTML response, readiness, baked version and metrics passed |
| Schema initialization and seed commands | Executed successfully against the embedded database |
| Python dependency consistency | pip check passed |
| Prometheus alert rules | promtool check rules passed for all 3 rules |
| Alert behavior tests | promtool test rules passed, including firing and recovery cases; the revised single-rule Kubernetes test also passed |
| Prometheus configuration syntax | Compose and Kubernetes scrape configurations passed promtool with local rule paths; Kubernetes discovery used an external API placeholder for this syntax-only check |
| Compose configuration | Docker Compose v2.40.3 config --quiet passed with test and monitoring profiles |
| Kubernetes API schema checks | Revised baseline: kubeconform strict validation passed for 19 resources across app, Job, release RBAC and monitoring manifests |
| Terraform formatting/HCL parsing | terraform fmt -check -recursive passed with Terraform 1.13.4 |
| Terraform provider schema validation | Not completed. Provider initialization succeeded, but provider process startup/handshake failed in this runtime. Run terraform validate in the teaching environment before planning resources. |
| Shell, JavaScript, YAML and JSON | Shell/JavaScript syntax and YAML/JSON parsing passed |
| Student Word brief | Rendered and all 6 pages visually reviewed |

## What these checks do not establish

PGlite runs PostgreSQL in an embedded environment. It is useful for SQL and application behavior checks, but it is not the supplied native PostgreSQL16 Docker image. Container initialization, volume ownership, pg_dump/pg_restore, and actual container networking must still be exercised with Docker.

No Docker daemon or AWS account was used. Docker image builds, the complete Compose stack, Kubernetes rollout/RBAC behavior, live Grafana provisioning, Jenkins execution, GitHub-hosted workflow execution, cloud IAM/networking, backups and disaster recovery were not tested end to end here. Browser automation could not launch because the browser binary was unavailable. The server-rendered HTML and JavaScript syntax were checked, but browser interactions need a lab check.

Terraform provider lock files came from provider initialization. No AWS Plan or Apply was executed. Version/API schema checks are not a substitute for an actual lab deployment.

## Instructor smoke checklist before distribution

1. Follow the root README on a clean Docker machine. Create, close and reopen a ticket in the browser.
2. Restart the app and database without deleting volumes, then verify the same ticket remains.
3. Run `docker compose --profile test run --build --rm tests` against native PostgreSQL16.
4. Start the monitoring profile. Confirm the target is up and the supplied Grafana dashboard displays traffic.
5. Stop and restart the demo database. Confirm readiness fails while liveness remains up, and the database alert fires then resolves.
6. Back up and restore into a fresh disposable database. Compare actual ticket values.
7. If using the instructor reference, run Terraform init/validate/plan in the lab account and review costs before Apply. Complete the reference setup guide, then verify the single helpdesk environment, Jenkins deployment/rollback, three dashboard panels, the database alert and S3 recovery.
8. Record the tested image digests and tool versions, then freeze the cohort baseline.

## Scope revision

The revised reference uses one application namespace (`helpdesk`), one initial API replica, a Jenkins deployment without promotion or mandatory Trivy scanning, three Kubernetes dashboard panels and one database alert. Namespace references, shell syntax, Kubernetes schemas and Prometheus configurations were checked after the change. Application code and the local Compose examples were not changed. Live cloud, Jenkins and Grafana checks remain outstanding as described above.

## Docker packaging exercise revision: 9 November 2026

The student ZIP now intentionally omits Dockerfile and .dockerignore. It includes docs/CONTAINER_PACKAGING.md with application facts, required runtime/test targets, hints and acceptance commands. Completed answers are in RT_DevOps_Docker_Instructor_Solution.zip. Instructors must install those files in a private copy before following the smoke checklist above.

The original application, dependency pins, Compose configuration, CI workflow and deployment code are unchanged. The instructor Dockerfile retains the original implementation; its ignore file adds exclusions for local tooling and sensitive/generated files in subdirectories. Documentation and archive separation were checked, and the updated Word brief was rendered and visually reviewed. No Docker executable/daemon is available in this editing environment, so the new exercise's image builds and acceptance commands have not been executed here. Earlier application test results above are historical, not new test runs.

Milestone 1 allocates 3-4 of its existing 10 hours to packaging. The six-week 70-90 hour total and all required technologies remain unchanged.

## AWS account and Jenkins ownership revision: 9 November 2026

The current brief and setup guide assign AWS account access, credits/budget checks, Jenkins agent setup and deployment credentials to each student. Instructor responsibilities are package validation, review, guidance and assessment. Planned work is now 74 hours with up to 16 troubleshooting hours. This supersedes earlier workload figures in this record. Only documentation changed in this revision; no application or infrastructure execution was performed.
