#!/usr/bin/env bash
# Rebuilds the whole project from scratch and re-runs every query.
# Run from the project root. Needs PostgreSQL (psql, createdb, dropdb) and Python 3.
# Connection settings come from the usual PG* variables (PGHOST, PGPORT, PGUSER, PGPASSWORD).
#   ./run_all.sh            -> uses a database called "olist"
#   ./run_all.sh mydb       -> uses "mydb"
set -euo pipefail
DB="${1:-olist}"
dropdb --if-exists "$DB"
createdb "$DB"
psql -d "$DB" -v ON_ERROR_STOP=1 -q -f sql/01_schema.sql
psql -d "$DB" -v ON_ERROR_STOP=1 -f sql/02_load_data.sql
psql -d "$DB" -v ON_ERROR_STOP=1 -q -f sql/04_views.sql
python3 run_queries.py "$DB"
