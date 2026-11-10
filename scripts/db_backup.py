"""Back up the local Compose database with PostgreSQL pg_dump (custom format)."""
import argparse
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument("--output", type=Path, default=ROOT / "backups" / (datetime.now(timezone.utc).strftime("helpdesk-%Y%m%dT%H%M%S%fZ.dump")))
a = p.parse_args()
a.output.parent.mkdir(parents=True, exist_ok=True)
fd = os.open(a.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
try:
    with os.fdopen(fd, "wb") as out:
        subprocess.run(["docker", "compose", "exec", "-T", "db", "pg_dump", "-U", "postgres", "-d", "helpdesk", "--schema=helpdesk", "--format=custom", "--no-owner", "--no-privileges"], cwd=ROOT, stdout=out, check=True)
    if a.output.stat().st_size == 0:
        raise RuntimeError("Empty backup")
except BaseException:
    a.output.unlink(missing_ok=True)
    raise
print(a.output.resolve())
