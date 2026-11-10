# DevOps final project

## Deploy and operate RT Helpdesk on AWS

**Level:** practical integration project for a student who has completed the beginner DevOps courses.  
**Format:** individual project, 6 weeks, approximately 70-90 hours total.  
**Application coding:** none required. The complete working Flask/PostgreSQL application is supplied.  
**Configuration management:** Bash and cloud-init are sufficient. Ansible is not required.

Build and operate a working support-ticket service on AWS. Your repository must contain the infrastructure configuration, deployment process and operating instructions. Verify that releases work, data persists, an alert detects a database outage, and a backup can be restored.

The 70-90 hour target assumes you have completed the courses and use the supplied templates plus one short instructor checkpoint each week. The plan allocates 74 hours to required work and up to 16 hours to troubleshooting and revision. Use your own AWS account and the AWS credits provided to you. Confirm account activation and credit availability before starting; check permitted services, credit coverage and expiry before deployment. You configure your own account access, budget alerts and Jenkins agent. Fixing defects in the supplied application remains instructor preparation.

Use the provided application without adding Python or frontend features. A new release can use the unchanged application from a new Git commit, with the commit SHA baked into its image version.

## What is supplied and what you build

| Supplied starting material | Your responsibility |
|---|---|
| Working application, schema, fictional data, API tests, Compose stack and container packaging brief | Write Dockerfile and .dockerignore, run the app and verify persistence |
| Example GitHub Actions workflow | Configure it for your repository and add Terraform validation |
| Terraform state-bucket bootstrap and backup IAM example | Write or adapt the main VPC, EC2, security-group and S3 configuration |
| Linux installation scripts, Jenkins agent setup instructions and deployment permission templates | Configure your own Jenkins agent and credentials, inspect services and explain access permissions |
| PostgreSQL initialization Job, app manifest examples and namespace RBAC | Configure one application environment, storage, probes and resources |
| Monitoring manifests, scrape configuration, dashboard and alert examples | Deploy monitoring, explain three panels and test one alert |
| Release/smoke-test helper and backup instructions | Connect the steps in Jenkins, verify rollback, upload a backup and verify a restore |

The instructor validates the setup scripts and provides guidance. You configure your own Jenkins controller and agent connection, credentials, release job and application settings. Use the supplied namespace permission templates to create deployment credentials and explain their purpose. Keep passwords, private keys and account access under your control.

The `reference/` directory contains infrastructure examples and setup guidance. The student package intentionally omits `Dockerfile` and `.dockerignore`; write both using `docs/CONTAINER_PACKAGING.md`. Completed Docker files are kept in a separate instructor package. Reusing supplied setup components is allowed. You must identify what you reused, keep your own configuration changes in Git and explain the result. Copying the solution and submitting screenshots without understanding or operating it does not satisfy the project.

## Required architecture

Use two EC2 hosts in one VPC and one public subnet:

- **CI host:** Jenkins controller and a separate agent process under different Linux users. You configure and connect your own agent using the supplied instructions. Builds run on the agent, not on the controller.
- **Application host:** one single-node kind Kubernetes cluster, with `helpdesk` and `monitoring` namespaces.
- **Application:** one Flask Deployment, initially one replica, an internal Service, one PostgreSQL instance and one persistent volume claim.
- **Monitoring:** Prometheus and Grafana, using the supplied provisioning files.
- **Storage:** a private Terraform state bucket and a private backup bucket.
- **Registry:** one registry agreed with the instructor. A public image containing no secrets is sufficient for the baseline.

This is a working cloud training system. A single application host and database do not provide high availability. Local Kubernetes volumes do not survive deletion of the kind cluster. Explain these limitations and use S3 backups for the recovery exercise.

Limit SSH to your approved IP and CI-to-app administration to the required private connection. Use SSH tunnels and `kubectl port-forward` for browser access. A public domain, HTTPS ingress, EKS, RDS, a load balancer and a NAT Gateway are outside the required scope.

## Milestone 1 Package the app and establish Git and CI

**Planned effort: 10 hours, including 3-4 hours for container packaging.**

1. Follow [the container packaging assignment](CONTAINER_PACKAGING.md). Write `Dockerfile` and `.dockerignore`, build the required `runtime` and `test` targets, then start the supplied Compose stack and create a ticket. Exact Python install/start commands are provided; no Python coding is needed.
2. Restart the app and database without deleting volumes. Confirm the ticket remains.
3. Run the supplied tests against the disposable PostgreSQL test database. Verify non-root operation, build caching and exclusion of sensitive files. Explain your Dockerfile, environment variables, ports and data volume.
4. Create your own GitHub repository. Exclude passwords, `.env`, private keys, state files, plans, kubeconfigs and backups.
5. Use short branches and at least three meaningful pull requests over the whole project. Review your own diff, write a short checklist and merge only after checks pass. Independent peer approval is not required.
6. Configure the supplied GitHub Actions workflow to run tests on pull requests and pushes to `main`. Keep the supplied image-build check. Preserve test results.
7. Once Terraform files exist, add `terraform fmt -check` and `terraform validate`, initializing with backend access disabled for validation.

Use the supplied workflow permissions and keep AWS/deployment secrets out of PR jobs. Configure required checks if your repository supports them. Otherwise record successful checks before merging. Do not configure a required approving review that you cannot provide as a solo author.

**Acceptance:** your Docker files meet the packaging checklist; a clean local startup works; CI passes; an instructor-provided failing test fixture makes CI fail and removing it restores success. No application feature change is needed. A forced merge conflict, custom security scanners and a separate task-board submission are optional.

## Milestone 2 Provision AWS with Terraform

**Planned effort: 16 hours, including AWS account access and budget setup.**

Use your own AWS account and available credits. Set up your AWS CLI authentication, confirm the required services are available in your account, and configure a budget notification to your own email. Record a cost estimate and credit balance before provisioning. Then create or adapt Terraform for the VPC, subnet, routing, Internet Gateway, two EC2 instances, encrypted root disks, security groups and private backup bucket. Use inputs for region, names, instance sizes and administrator IP. Output the host addresses and backup bucket name.

Use the supplied state-bucket bootstrap to configure encrypted, versioned remote state with locking. Reuse the supplied instance-role policy for S3 backup access and explain what it permits. You do not need to design the IAM policy or write a custom Terraform module from scratch. The reference's host module may be reused.

Run format, validate, Plan and Apply. Review the Plan with the instructor before the first deployment. Commit provider lock files. Record the selected instance sizes, a cost estimate and the agreed spending budget. You configure the account budget notification and monitor spending and remaining credits. Confirm credit coverage and expiry rather than assuming every resource is covered. Include your teardown procedure and verify that resources are removed after assessment.

**Acceptance:** the expected resources exist, a second Plan has no unexplained changes, administrative ports are restricted, and your README includes a teardown procedure. Do not delete the state backend while resources still depend on it. Stopping an EC2 instance alone is not full cleanup.

## Milestone 3 Configure Linux and deploy to Kubernetes

**Planned effort: 16 hours.**

Apply the supplied installation scripts on the two hosts, using instructor-tested tool versions. Inspect Docker and Jenkins with `systemctl` and `journalctl`. Use SSH keys and explain the purpose of the `ubuntu`, `buildagent` and `deploy` users. Keep `deploy` out of sudo and the Docker group.

Create the kind cluster with the supplied configuration. Configure the application in the single `helpdesk` namespace:

- App Deployment and Service, initially one API replica.
- ConfigMap for ordinary settings and Secrets created outside Git.
- PostgreSQL with a PVC. Use the supplied database role initialization and one-time schema Job.
- Readiness and liveness probes, CPU/memory requests and limits, and the supplied non-root API security context with writable `/tmp`.
- The supplied namespace-limited release identity. You issue and refresh its credentials using the supplied helper; the instructor can help diagnose problems. Do not use cluster-admin credentials in Jenkins.

You may adapt the example manifests rather than write them from an empty file. Explain each resource and record your changes. No second application environment, custom CNI, Helm packaging or NetworkPolicy is required.

**Acceptance:** access the app through the tunnel, create a ticket, delete an API Pod and verify it is replaced. Restart the database Pod with the same PVC and verify the ticket remains. Diagnose one incorrect configuration using logs and `kubectl describe`. A brief scaling exercise is optional.

## Milestone 4 Build and deploy with Jenkins

**Planned effort: 14 hours, including Jenkins agent setup and verification.**

GitHub Actions checks repository changes. Jenkins builds and deploys releases to the one application environment. Configure your own Jenkins controller, agent and credential bindings using the reference setup guide, then adapt the Jenkinsfile and release helper. Create the dedicated buildagent Linux user, configure SSH authentication and host-key verification, register the helpdesk-build agent and confirm it is online. Set controller executors to zero. Run a small job on that agent that prints the Linux user and runs docker version, and confirm it runs as buildagent with Docker access. Then configure registry and deployment credentials. One agent process on your CI host is sufficient; no third EC2 instance is required.

The required pipeline must:

1. Check out trusted `main` and record the exact commit SHA.
2. Run the supplied tests for that checkout. This simple repeat avoids writing a GitHub API integration to verify check status.
3. Build an image with the SHA as its version, publish it and record its digest.
4. Update the `helpdesk` Deployment to that digest and wait for the rollout with a timeout.
5. Verify readiness and `/version`, then create and retrieve a fictional ticket using the supplied smoke-test helper.
6. Fail clearly if verification fails. Restore the previous image using the supplied helper or a documented manual rollback.

Run the release job only for trusted `main`. Keep credentials in Jenkins Credentials, preserve the existing SSH host-key verification, prevent overlapping releases and do not print secrets. A manual job trigger is sufficient. Automatic webhooks, image scans, a separate approval gate and promotion between environments are optional.

**Acceptance:** complete a successful release and one controlled bad-image or readiness-configuration exercise. Recover the previous working image and verify the app. There is no fixed recovery stopwatch and no requirement to write custom automatic rollback logic.

## Milestone 5 Monitor and verify data recovery

**Planned effort: 10 hours.**

Deploy Prometheus and Grafana in `monitoring` using the supplied manifests and configuration. Keep dashboard JSON, scrape configuration and alert rules in Git. Reuse the supplied per-Pod discovery permissions rather than design them from scratch.

The required dashboard has three panels: target availability, API request rate and API error percentage. Explain what each measures and generate traffic with the supplied script. Extra panels in the local Compose dashboard are available for exploration but are not graded requirements.

Use one required alert: **database unavailable**. Stop the Kubernetes database temporarily, verify the alert becomes Firing, then restart it and verify recovery. Explain why liveness can remain healthy while readiness fails. No email/chat notifications, environment selector, latency analysis or custom PromQL beyond adapting a supplied query is required.

Create one `pg_dump` backup, upload it to the private S3 bucket using the supplied helper and instance role, then download and restore it into a new disposable database. Compare actual ticket records with those captured before backup. Do not overwrite the application's database. Scheduling backups is optional.

**Acceptance:** the three panels receive data, the database alert fires and resolves, and records are verified after restoring an S3 backup. Record the commands, expected outcome and actual outcome in your README. A separate incident report is not required.

## Milestone 6 Document and complete the practical assessment

**Planned effort: 8 hours, including a 2-3 hour self-study task.**

Produce one concise README with setup/deployment commands, an architecture diagram, a small port/access table, rollback steps, backup/restore steps and cleanup instructions. Include links to successful and failed pipeline runs, alert evidence and restored records. Short notes in the README are sufficient; separate design reports, runbooks and a presentation are not required.

Choose one small self-study task: add a Grafana panel using an existing metric, adjust an alert's duration and explain its behavior, or use Linux tools to diagnose a resource problem and describe the fix. Spend 2-3 hours and record what you learned. HPA, additional AWS services and application coding are not required.

The final assessment is a 25-30 minute practical review of your working AWS deployment and repository. Explain the main components, perform a release or rollback, and discuss the recorded alert and restore results. The earlier completed exercises count as evidence; you do not have to repeat every slow operation during the assessment. Screenshots alone are insufficient. Complete the agreed resource cleanup after assessment.

## Workload and checkpoints

| Week | Planned work | Hours |
|---|---|---:|
| 1 | Docker packaging, local app, Git and GitHub Actions | 10 |
| 2 | Own AWS account, budget setup and Terraform | 16 |
| 3 | Linux and one Kubernetes application environment | 16 |
| 4 | Own Jenkins agent, release and rollback | 14 |
| 5 | Three monitoring panels, one alert and S3 restore | 10 |
| 6 | README, small self-study task and assessment | 8 |
| Total planned work | Includes weekly instructor checkpoints | 74 |
| Troubleshooting allowance | Spread across the six weeks | 0-16 |
| Overall target | Individual project | 70-90 |

Aim for approximately 12-15 hours per week. Seek instructor help after about 60-90 minutes on the same blocker with no progress. Bring the error message, commands tried and relevant logs. If the budget is slipping, complete the core acceptance checks before adding optional work. The estimate is a planning target, not a completion guarantee.

## Grading

| Area | Points |
|---|---:|
| Git and GitHub Actions | 15 |
| Docker and local operation | 10 |
| AWS and Terraform | 20 |
| Linux administration | 10 |
| Kubernetes and persistent data | 15 |
| Jenkins deployment and rollback | 15 |
| Prometheus and Grafana | 10 |
| README, verified S3 recovery and self-study | 5 |
| Total | 100 |

Suggested pass mark: 70. Passing also requires a working deployment, a passing and failing CI check, a verified rollback, a firing/resolved database alert and a verified restore. You must explain your configuration and carry out basic diagnosis independently. Instructor help with setup and blockers does not invalidate individual work.

## Optional extensions after the core passes

Choose extensions only if time remains. None is required to pass or fit within the 70-90 hour target:

- Separate staging and production environments with manual promotion of the same image digest.
- Scheduled backups, extra alert rules, P95 latency or host monitoring.
- Container, secret and IaC scanning with a defined blocking rule.
- Custom Terraform modules, more advanced Git conflict exercises or fully automated recovery.
- HPA, NetworkPolicy, Helm, EKS, RDS or HTTPS ingress with instructor-approved scope and costs.

Optional extensions can earn up to 5 additional points, capped at a total of 100. They cannot replace failed core requirements.

## Instructor preparation

Before assigning the project, copy the separate instructor Docker solution into a private copy of the student repository, then run the supplied stack and the single-environment reference on the teaching machines. Distribute only the student ZIP to students. Do not place the Docker solution in their repository or its Git history. Validate the application, image builds, provisioning, Jenkins agent connection, deployment permissions, monitoring and restore flow. The package's `docs/VALIDATION.md` distinguishes checks already performed from cloud/container checks still required.

Provide the tested student package, installation versions, remote-state bootstrap and configuration examples. Students supply their own AWS accounts with their available AWS credits, set their own budgets and registry credentials, and configure their own Jenkins agents and deployment credentials. Review the first Terraform plan and agent verification evidence. Allow the supplied monitoring, database and permission templates, and explain which settings each student must change. Provide a failing CI test fixture, weekly guidance and the final practical assessment.

If the supplied app or setup scripts have a defect, distribute a corrected baseline. Do not turn it into an unplanned programming assignment. Preserve one weekly checkpoint and help resolve environment problems before they consume the troubleshooting allowance.
