# RT-Helpdesk — End-to-End Cloud-Native DevOps Project

A production-grade deployment and automation pipeline for the **RT-Helpdesk** ticketing application. This project demonstrates Infrastructure as Code (IaC), container hardening, Kubernetes orchestration, automated CI/CD with Jenkins, real-time observability with Prometheus & Grafana, automated email alerting via Alertmanager, and verified disaster recovery on AWS.

---

## 1. System Architecture & Tech Stack

| Layer | Technology | Implementation Details |
| :--- | :--- | :--- |
| **Cloud Infrastructure** | **AWS** (VPC, EC2, S3, IAM, Budgets) | Isolated VPC, hardened Security Groups (SSH port 22 restricted to Admin IP `/32`), cost-optimized EC2 instances (`t3.micro` CI, `t3.small` App), encrypted S3 buckets, and automated 80% budget alerts. |
| **Infrastructure as Code** | **Terraform >= 1.10** | Two-stage architecture: `bootstrap` (versioned, encrypted S3 state bucket with native S3 locking & `prevent_destroy`) and `lab` (compute, networking, IAM least-privilege roles). |
| **Containerization** | **Docker** | Multi-stage production build running as a non-root user with pinned base images and minimal attack surface. |
| **Orchestration** | **Kubernetes (Kind)** | Namespace isolation (`helpdesk` for application/DB, `monitoring` for observability), persistent volumes (`StatefulSet` for PostgreSQL), Liveness/Readiness probes, and strict RBAC. |
| **CI/CD Automation** | **Jenkins & GHCR** | Dedicated build agent (`helpdesk-build`), automated testing, container image signing/pushing to GitHub Container Registry using immutable digests, and zero-downtime Kubernetes rollouts. |
| **Observability & Alerting** | **Prometheus, Grafana, Alertmanager** | Live metrics scraping, custom Grafana dashboards, and real-time HTML email notifications via Gmail SMTP (`FIRING` & `RESOLVED` states) backed by Kubernetes Secrets. |
| **Backup & Recovery** | **AWS S3 & PostgreSQL** | Automated `pg_dump` backups uploaded to private S3 storage (`helpdesk-backups-egetz-2026`) and verified isolated database restores. |

---

## 2. Repository Structure

```text
helpdesk-project/
├── app/                          # Python FastAPI application & unit/integration tests
├── docs/
│   └── images/                   # Verification screenshots & evidence
└── reference/
    ├── k8s/                      # Kubernetes manifests (App, DB, RBAC, Prometheus, Grafana, Alertmanager)
    ├── scripts/                  # Backup, restore, and synthetic traffic generation scripts
    └── terraform/
        ├── bootstrap/            # S3 remote state bucket & locking setup
        └── lab/                  # VPC, EC2, Security Groups, IAM, and AWS Budgets
```

---

## 3. Security & Cost Optimization Highlights

* **Zero Public App Ports:** No HTTP/HTTPS, database, Jenkins, Prometheus, or Grafana ports are exposed to the public internet. All administrative access uses encrypted **SSH Local Port Forwarding**.
* **Secrets Management:** Sensitive credentials (such as Gmail SMTP App Passwords and GHCR tokens) are never committed to Git; they are injected at runtime using **Kubernetes Secrets** (`readOnly: true` volume mounts) and Jenkins Credentials.
* **Least-Privilege IAM:** The application EC2 instance uses an IAM role restricted strictly to S3 backup object operations, with zero infrastructure-admin permissions.
* **Cost-Optimized Compute:** Instance types in `variables.tf` and `terraform.tfvars` are tuned to `t3.micro` (Jenkins) and `t3.small` (Kubernetes App) alongside AWS Budgets alerts to prevent unexpected cloud spend.

---

## 4. Alertmanager & Gmail SMTP Configuration

To enable real-time email notifications without incurring extra third-party email service costs, **Prometheus Alertmanager** is configured to relay alerts through Google's free SMTP server (`://gmail.com`) using TLS encryption and a dedicated **Google App Password**.

### 1. Security & Secrets Management
* **Google App Password:** Generated a dedicated 16-character App Password under Google Account Security (with 2-Step Verification enabled), avoiding the use of primary account credentials.
* **Kubernetes Secret (`alertmanager-smtp`):** Stored the App Password securely inside the `monitoring` namespace rather than hardcoding it in Git:
  ```bash
  kubectl -n monitoring create secret generic alertmanager-smtp \
    --from-literal=smtp_password='<GOOGLE_APP_PASSWORD>'
  ```
* **Read-Only Volume Mount:** Mounted the secret into the Alertmanager pod at `/etc/alertmanager/secrets/smtp_password` (`readOnly: true`) and referenced it via `smtp_auth_password_file`.

### 2. Alert Routing & Custom HTML Template (`reference/k8s/alertmanager.yaml`)
* **SMTP Relay:** Configured `smtp_smarthost: '://gmail.com'` with `smtp_require_tls: true`.
* **Grouping & Deduplication:** Alerts are grouped by `alertname` (`group_wait: 10s`, `repeat_interval: 1h`) to prevent inbox flooding during outages.
* **Dynamic HTML Notifications:** Configured `send_resolved: true` with a custom HTML template that renders a **Red (`[FIRING]`)** banner when an incident starts and a **Green (`[RESOLVED]`)** banner upon automatic recovery.

### 3. Prometheus Integration (`reference/k8s/prometheus.yml`)
Connected Prometheus to the internal Alertmanager Kubernetes `Service` endpoint:
```yaml
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - alertmanager.monitoring.svc.cluster.local:9093
```

---

## 5. Operational Exercises & Verification Evidence

### Exercise 1: End-to-End Application & Observability Health
Verified that the **RT-Helpdesk** web application is live with the latest Git commit SHA badge, Prometheus actively scrapes the `/metrics` endpoint (`UP`), and Grafana visualizes real-time request rates and target health.

* **RT-Helpdesk Web UI (`http://localhost:8000`):**
  ![RT-Helpdesk UI](docs/images/01-helpdesk-ui.png)
* **Prometheus Scrape Targets (`http://localhost:9090/targets`):**
  ![Prometheus Targets](docs/images/02-prometheus-targets.png)
* **Grafana Live Dashboard (`http://localhost:3000`):**
  ![Grafana Dashboard](docs/images/03-grafana-dashboard.png)

---

### Exercise 2: Jenkins Dedicated Build Agent Verification
Configured a dedicated `helpdesk-build` agent node and executed a verification pipeline (`agent-verify-dedicated-script`) confirming non-root execution (`buildagent`) and Docker Engine availability.

* **Jenkins Console Output (`id -un` & `docker version`):**
  ![Jenkins Agent Verification](docs/images/04-jenkins-agent-verify.png)

---

### Exercise 3: Database Outage & Graceful Degradation (Chaos Exercise)
Simulated a database outage by scaling the PostgreSQL `StatefulSet` to `0` (`kubectl -n helpdesk scale statefulset db --replicas=0`):
1. The API container remained alive (Liveness probe passed) while failing its Readiness probe to stop receiving normal service traffic.
2. Direct requests to the API pod cleanly returned **`503 Service Unavailable`** (`database_unavailable`) instead of crashing.
3. Prometheus detected the failure and transitioned `HelpdeskDatabaseUnavailable` to **`FIRING`**.

* **API Graceful Degradation (`503 Service Unavailable`):**
  ![API 503 Response](docs/images/05-outage-503-response.png)
* **Prometheus Firing Alert (`http://localhost:9090/alerts`):**
  ![Prometheus Firing Alert](docs/images/06-prometheus-firing-alert.png)

---

### Exercise 4: Real-Time Email Alerting & Auto-Recovery (Alertmanager)
Integrated **Prometheus Alertmanager** with Gmail SMTP (`://gmail.com`) using a custom HTML template and a Kubernetes Secret (`alertmanager-smtp`):
1. Upon database failure, Alertmanager immediately dispatched a red **`[FIRING]`** HTML alert email.
2. After scaling the database back to `1` (`kubectl -n helpdesk scale statefulset db --replicas=1`), the cluster self-healed and Alertmanager dispatched a green **`[RESOLVED]`** recovery email.

* **Firing Alert Email Notification:**
  ![Alertmanager Firing Email](docs/images/07-email-alert-firing.png)
* **Resolved Recovery Email Notification:**
  ![Alertmanager Resolved Email](docs/images/08-email-alert-resolved.png)

---

## 6. Quick Operations & Cost-Control Commands

```bash
# Start EC2 instances and retrieve current public IPs
aws ec2 start-instances --region us-east-1 --instance-ids <CI_INSTANCE_ID> <APP_INSTANCE_ID>

# Open SSH tunnels to Application (8000), Grafana (3000), and Prometheus (9090)
ssh -L 8000:127.0.0.1:8000 -L 3000:127.0.0.1:3000 -L 9090:127.0.0.1:9090 ubuntu@<APP_IP>

# Open SSH tunnel to Jenkins (8080)
ssh -L 8080:127.0.0.1:8080 ubuntu@<CI_IP> -N

# Stop EC2 instances when idle to eliminate hourly compute charges
aws ec2 stop-instances --region us-east-1 --instance-ids <CI_INSTANCE_ID> <APP_INSTANCE_ID>
```



