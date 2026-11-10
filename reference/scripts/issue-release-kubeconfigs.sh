#!/usr/bin/env bash
# Administrator only, on app host. Refresh before each lab day.
set -euo pipefail
id deploy >/dev/null
sudo install -d -o deploy -g deploy -m 700 /home/deploy/.kube
work=$(mktemp -d); chmod 700 "$work"; trap 'rm -rf "$work"' EXIT
kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > "$work/ca.crt"
for ns in helpdesk; do
  token=$(kubectl -n "$ns" create token jenkins-release --duration=24h)
  # API servers may shorten this requested duration. Refresh when authentication expires.
  file="$work/$ns"; touch "$file"; chmod 600 "$file"
  kubectl --kubeconfig="$file" config set-cluster lab --server=https://127.0.0.1:6443 --certificate-authority="$work/ca.crt" --embed-certs=true >/dev/null
  kubectl --kubeconfig="$file" config set-credentials release --token="$token" >/dev/null
  kubectl --kubeconfig="$file" config set-context lab --cluster=lab --user=release --namespace="$ns" >/dev/null
  kubectl --kubeconfig="$file" config use-context lab >/dev/null
  unset token
  sudo install -o deploy -g deploy -m 600 "$file" "/home/deploy/.kube/$ns"
done
