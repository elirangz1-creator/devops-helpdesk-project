# Prometheus and Grafana lab

## Required beginner outcome

Deploy monitoring in Kubernetes, explain the three supplied baseline panels (target availability, API request rate and error percentage), and verify the database-unavailable alert fires and resolves. The Kubernetes reference now has one application namespace, `helpdesk`, three panels and one rule. The additional local Compose panels and alerts below are optional examples.

## What is already supplied

The app exposes HTTP counters, latency histograms, database availability and Python process metrics. Prometheus scrapes every 15 seconds. Grafana reads the Prometheus datasource and provisions the RT Helpdesk dashboard from JSON.

| Panel | Meaning |
|---|---|
| Reachable targets | Number of app metrics targets that respond |
| Database reachable | 1 if the app can query the tickets table, 0 otherwise |
| Requests per second | API throughput, excluding probes and metrics |
| 5xx error percentage | Percentage of API responses with a server error |
| P95 latency | Approximate 95th percentile of API request duration |
| Response status rate | Traffic grouped by response status |
| Process memory | API process resident memory; not total EC2 memory |

Metrics use route templates such as `/api/tickets/<int:ticket_id>`, never ticket IDs, request bodies or requester names as labels. This keeps the number of time series bounded.

## Useful PromQL

```promql
sum(rate(helpdesk_http_requests_total{job="helpdesk",route=~"/api/.*"}[5m]))
```

```promql
100 * (
  sum(rate(helpdesk_http_requests_total{job="helpdesk",route=~"/api/.*",status=~"5.."}[5m])) or vector(0)
) / clamp_min(sum(rate(helpdesk_http_requests_total{job="helpdesk",route=~"/api/.*"}[5m])), 0.001)
```

```promql
histogram_quantile(0.95,
  sum by (le) (rate(helpdesk_http_request_duration_seconds_bucket{job="helpdesk",route=~"/api/.*"}[5m]))
)
```

## Failure exercise

1. Start the full stack with `docker compose --profile monitoring up --build -d`.
2. Start `python scripts/traffic.py --seconds 300` in another terminal.
3. Run `docker compose stop db`.
4. Verify `/healthz` stays 200, `/readyz` returns 503, and API requests return 503. `/metrics` still responds, so `up` can stay 1 while `helpdesk_database_up` becomes 0.
5. Wait for `HelpdeskDatabaseUnavailable` to become Firing in Prometheus. Its `for: 1m` is in addition to scrape/evaluation delay. The error-rate alert also requires at least 20 requests in a five-minute window.
6. Run `docker compose start db`. Verify readiness recovers and the database alert resolves. The error-rate alert can remain active until errors leave its five-minute window.
7. Confirm previously created tickets are still present. Record timestamps and screenshots.

As an optional extra exercise, stop only the API: `docker compose stop api`. Verify `HelpdeskTargetDown` fires, then recover with `docker compose start api`. No email/chat notification is sent; adding Alertmanager or a Grafana contact point is an optional extension.

## Kubernetes setup using the supplied templates

- Deploy Prometheus and Grafana in a `monitoring` namespace. Helm charts or plain manifests are acceptable; record exact versions and keep Values/configuration in Git.
- Discover and scrape **each API Pod**, rather than scraping a load-balanced Service that might return a different replica on each scrape.
- Preserve the label `job="helpdesk"` and an `environment` label, or update every supplied query/rule consistently.
- Reuse the supplied namespace/Pod labels. The baseline monitors only `helpdesk`; an environment filter is optional.
- Reuse the supplied namespace-scoped discovery permissions. For a Prometheus Operator chart, use a ServiceMonitor with matching labels. For plain Prometheus, use Kubernetes service discovery and relabeling.
- Store dashboard JSON, scrape configuration and alert rules in Git. Demonstrate that they survive a monitoring Pod restart.
- Keep Grafana behind a tunnel or restricted access and supply its password from a Secret.

The Compose dashboard is a local reference. In Kubernetes adapt labels, datasource address and provisioning paths; do not copy `api:8000` as the only target.

## Limitations students should explain

An app exporter is not an independent user-experience probe. Prometheus `up` measures scrape success, not successful ticket creation. If the single application host also runs monitoring, its failure can take down both. Add a blackbox probe or run monitoring on a separate host as an extension. Node Exporter adds host CPU, memory and disk metrics; the supplied process-memory metric does not replace it.

## Required outage exercise on Kubernetes

Use `kubectl -n helpdesk scale statefulset/db --replicas=0`, wait for the database alert, then restore with `kubectl -n helpdesk scale statefulset/db --replicas=1`. Keep the PVC. Use port-forward to an API Pod for health/readiness inspection during the outage. Save the alert firing and resolved evidence. For the assessed result, run this exercise on the AWS deployment; the Compose exercise is useful preparation.
