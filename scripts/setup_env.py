"""Generate local-only lab passwords without printing them or replacing an existing file."""
import os
import secrets
from pathlib import Path

path = Path(__file__).resolve().parents[1] / ".env"
content = "\n".join([
    f"POSTGRES_PASSWORD={secrets.token_hex(24)}",
    f"DB_PASSWORD={secrets.token_hex(24)}",
    f"GRAFANA_ADMIN_PASSWORD={secrets.token_hex(24)}",
    "APP_VERSION=local", "APP_ENV=development", "",
])
try:
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
except FileExistsError:
    raise SystemExit(".env already exists; left unchanged")
with os.fdopen(fd, "w") as stream:
    stream.write(content)
print("Created .env. Keep it out of Git. Grafana admin password is in this file.")
