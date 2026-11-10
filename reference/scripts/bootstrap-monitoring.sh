#!/usr/bin/env bash
set -euo pipefail
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl -n monitoring create configmap prometheus-config \
  --from-file=prometheus.yml=reference/k8s/prometheus.yml \
  --from-file=alerts.yml=reference/k8s/alerts.yml \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n monitoring create configmap grafana-datasources \
  --from-file=monitoring/grafana/provisioning/datasources/prometheus.yml \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n monitoring create configmap grafana-dashboards \
  --from-file=monitoring/grafana/provisioning/dashboards/helpdesk.yml \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n monitoring create configmap grafana-dashboard-json \
  --from-file=helpdesk.json=reference/k8s/helpdesk-dashboard.json \
  --dry-run=client -o yaml | kubectl apply -f -
if ! kubectl -n monitoring get secret grafana-secret >/dev/null 2>&1; then
  read -r -s -p 'New Grafana admin password (at least 16 characters): ' pass; echo
  [[ ${#pass} -ge 16 ]]
  secret_file=$(mktemp); chmod 600 "$secret_file"
  trap 'rm -f "$secret_file"' EXIT
  printf '%s' "$pass" > "$secret_file"; unset pass
  kubectl -n monitoring create secret generic grafana-secret --from-file=admin-password="$secret_file"
fi
kubectl apply -f reference/k8s/monitoring.yaml
kubectl -n monitoring rollout restart deployment/prometheus deployment/grafana
kubectl -n monitoring rollout status deployment/prometheus --timeout=180s
kubectl -n monitoring rollout status deployment/grafana --timeout=180s
