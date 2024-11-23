#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "postgres" -c "CREATE ROLE replicator WITH REPLICATION PASSWORD 'replicator_password' LOGIN;"
