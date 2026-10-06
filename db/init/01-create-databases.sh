#!/bin/bash
# Runs once, on the first start of the postgres container (empty data volume).
# Creates two databases with dedicated roles:
#   - n8n       : owned by $N8N_DB_USER, used by n8n for its internal tables
#   - voltaluce : owned by $APP_DB_USER, used by the workflows for application data
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-SQL
    -- Roles are cluster-wide; LOGIN lets them open connections.
    CREATE ROLE "$N8N_DB_USER" WITH LOGIN PASSWORD '$N8N_DB_PASSWORD';
    CREATE ROLE "$APP_DB_USER" WITH LOGIN PASSWORD '$APP_DB_PASSWORD';

    -- Each database is owned by its role: the owner can create tables in it.
    CREATE DATABASE n8n OWNER "$N8N_DB_USER";
    CREATE DATABASE voltaluce OWNER "$APP_DB_USER";

    -- Least privilege: no cross access between the two databases.
    REVOKE CONNECT ON DATABASE n8n FROM PUBLIC;
    REVOKE CONNECT ON DATABASE voltaluce FROM PUBLIC;
    GRANT CONNECT ON DATABASE n8n TO "$N8N_DB_USER";
    GRANT CONNECT ON DATABASE voltaluce TO "$APP_DB_USER";
SQL
