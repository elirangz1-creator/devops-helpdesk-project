"""Restore a dump into a NEW disposable database, never over the live database."""
import argparse
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument("backup", type=Path)
p.add_argument("--database", required=True, help="New name, starting with helpdesk_restore_")
a = p.parse_args()
if not re.fullmatch(r"helpdesk_restore_[a-z0-9_]{1,40}", a.database):
    p.error("Database name must begin helpdesk_restore_ followed by 1..40 lowercase letters, digits or underscores")
if not a.backup.is_file():
    p.error("Backup file does not exist")
base = ["docker", "compose", "exec", "-T", "db"]
# createdb fails if the destination already exists. Do not catch/ignore this.
subprocess.run(base + ["createdb", "-U", "postgres", a.database], cwd=ROOT, check=True)
with a.backup.open("rb") as stream:
    subprocess.run(base + ["pg_restore", "-U", "postgres", "-d", a.database, "--no-owner", "--no-privileges", "--exit-on-error"], cwd=ROOT, stdin=stream, check=True)
subprocess.run(base + ["psql", "-U", "postgres", "-d", a.database, "-v", "ON_ERROR_STOP=1", "-c", "SELECT count(*) AS restored_tickets FROM helpdesk.tickets"], cwd=ROOT, check=True)
print("Restored into", a.database, "; the live helpdesk database was not changed.")
