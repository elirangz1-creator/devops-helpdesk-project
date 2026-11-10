#!/usr/bin/env bash
# Run from repository root on the application host as the cluster administrator.
set -euo pipefail
ns=${1:?Usage: bootstrap-app.sh helpdesk IMAGE_DIGEST}
image=${2:?Supply a public registry image by digest}
[[ "$ns" == helpdesk ]]
[[ "$image" =~ ^[a-zA-Z0-9./:_-]+@sha256:[a-f0-9]{64}$ ]]
kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
# Never rotate passwords on an existing database volume by replacing the Secret.
if ! kubectl -n "$ns" get secret app-secret >/dev/null 2>&1; then
  secret_dir=$(mktemp -d); chmod 700 "$secret_dir"
  trap 'rm -rf "$secret_dir"' EXIT
  python3 - "$secret_dir" <<'PY'
import secrets,sys,pathlib,os
for name,key in [('app','DB_PASSWORD'),('db','POSTGRES_PASSWORD')]:
 p=pathlib.Path(sys.argv[1])/name;p.write_text(key+'='+secrets.token_hex(24)+'\n');p.chmod(0o600)
PY
  kubectl -n "$ns" create secret generic app-secret --from-env-file="$secret_dir/app"
  kubectl -n "$ns" create secret generic db-secret --from-env-file="$secret_dir/db"
fi
sed "s|REPLACE_IMAGE|$image|g" reference/k8s/app.yaml | kubectl -n "$ns" apply -f -
kubectl -n "$ns" patch configmap app-config --type merge -p "{\"data\":{\"APP_ENV\":\"$ns\"}}"
kubectl -n "$ns" rollout status statefulset/db --timeout=300s
kubectl -n "$ns" delete job init-db --ignore-not-found --wait=true
sed "s|REPLACE_IMAGE|$image|g" reference/k8s/init-db.yaml | kubectl -n "$ns" apply -f -
kubectl -n "$ns" wait --for=condition=complete job/init-db --timeout=200s
kubectl -n "$ns" rollout restart deployment/api
kubectl -n "$ns" rollout status deployment/api --timeout=180s
kubectl -n "$ns" apply -f reference/k8s/release-rbac.yaml
kubectl -n "$ns" exec deployment/api -- flask --app app seed-db
