#!/usr/bin/env sh
# Ensure the dedicated MAS role + database exist on the shared Postgres.
set -eu

: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"
: "${MAS_POSTGRES_PASSWORD:?MAS_POSTGRES_PASSWORD is required}"

export PGPASSWORD="$POSTGRES_PASSWORD"
# Escape single quotes for safe inclusion in SQL string literals.
mas_password_sql=$(printf '%s' "$MAS_POSTGRES_PASSWORD" | sed "s/'/''/g")

echo "Ensuring MAS PostgreSQL role and database exist"
psql -v ON_ERROR_STOP=1 -h postgres -U synapse -d postgres <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'mas') THEN
    CREATE ROLE mas LOGIN PASSWORD '${mas_password_sql}';
  ELSE
    ALTER ROLE mas WITH LOGIN PASSWORD '${mas_password_sql}';
  END IF;
END
\$\$;

SELECT 'CREATE DATABASE mas OWNER mas'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'mas')\gexec

GRANT ALL PRIVILEGES ON DATABASE mas TO mas;
SQL

echo "MAS database ready"
