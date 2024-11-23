#!/bin/bash
set -e

# Wait for master to be ready
until pg_isready -h master -p 5432 -U postgres; do
  echo "Waiting for master to be ready..."
  sleep 2
done

export PGPASSWORD='replicator_password'

# Clean up the data directory
rm -rf /var/lib/postgresql/data/*

# Perform base backup
pg_basebackup -h master -D /var/lib/postgresql/data -U replicator -v -P --wal-method=stream

# Create standby.signal file
touch /var/lib/postgresql/data/standby.signal

# Set permissions
chown -R postgres:postgres /var/lib/postgresql/data
