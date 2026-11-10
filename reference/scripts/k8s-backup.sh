#!/usr/bin/env bash
set -euo pipefail
ns=${1:?namespace}; bucket=${2:?S3 backup bucket}
[[ "$ns" == helpdesk ]]
[[ "$bucket" =~ ^[a-z0-9][a-z0-9.-]+[a-z0-9]$ ]]
umask 077
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
stamp=$(date -u +%Y%m%dT%H%M%SZ)
kubectl -n "$ns" exec db-0 -- pg_dump -U postgres -d helpdesk -Fc > "$work/backup.dump"
test -s "$work/backup.dump"
aws s3 cp "$work/backup.dump" "s3://$bucket/backups/$ns/$stamp.dump" --only-show-errors
echo "Backup uploaded: backups/$ns/$stamp.dump"
