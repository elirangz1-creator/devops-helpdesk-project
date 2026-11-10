#!/bin/sh
set -eu
# Runs only when PostgreSQL initializes an EMPTY data volume.
# psql quotes the password as a SQL literal, not as executable SQL.
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  --set=ON_ERROR_STOP=1 --set=app_password="$APP_DB_PASSWORD" <<'SQL'
CREATE ROLE helpdesk_app LOGIN PASSWORD :'app_password';
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
CREATE SCHEMA helpdesk AUTHORIZATION helpdesk_app;
GRANT CONNECT ON DATABASE helpdesk TO helpdesk_app;
SQL
