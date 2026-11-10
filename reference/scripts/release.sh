#!/usr/bin/env bash
# Executed over SSH as deploy, with a namespace-restricted kubeconfig.
set -euo pipefail
ns=${1:?namespace}; image=${2:?image digest}; expected=${3:?commit SHA}
[[ "$ns" == helpdesk ]]
[[ "$image" =~ ^[a-zA-Z0-9./:_-]+@sha256:[a-f0-9]{64}$ ]]
[[ "$expected" =~ ^[a-f0-9]{40}$ ]]
export KUBECONFIG="$HOME/.kube/$ns"
previous=$(kubectl -n "$ns" get deployment api -o jsonpath='{.spec.template.spec.containers[0].image}')
rollback() {
  code=$?; trap - ERR
  echo "Release failed; restoring previous image in $ns" >&2
  kubectl -n "$ns" set image deployment/api "api=$previous"
  kubectl -n "$ns" rollout status deployment/api --timeout=180s || true
  exit "$code"
}
trap rollback ERR
kubectl -n "$ns" set image deployment/api "api=$image"
kubectl -n "$ns" rollout status deployment/api --timeout=180s
# Check each replica directly, then exercise the Service and shared database.
for pod in $(kubectl -n "$ns" get pods -l app=api -o json | python3 -c 'import json,sys; print(" ".join(p["metadata"]["name"] for p in json.load(sys.stdin)["items"] if not p["metadata"].get("deletionTimestamp")))'); do
  kubectl -n "$ns" exec "$pod" -- python -c \
    'import json,sys,urllib.request as u; assert json.load(u.urlopen("http://127.0.0.1:8000/version",timeout=10))["version"]==sys.argv[1]; assert u.urlopen("http://127.0.0.1:8000/readyz",timeout=10).status==200' "$expected"
done
kubectl -n "$ns" exec deployment/api -- python -c '
import json,urllib.request as u
base="http://api:8000"
r=u.Request(base+"/api/tickets",data=json.dumps({"title":"Release smoke test","description":"Fictional deployment check","requester":"Jenkins"}).encode(),headers={"Content-Type":"application/json"},method="POST")
with u.urlopen(r,timeout=15) as response: created=json.load(response)
with u.urlopen(base+"/api/tickets/"+str(created["id"]),timeout=15) as response: assert json.load(response)["title"]=="Release smoke test"
'
echo "Verified $ns at $expected"
