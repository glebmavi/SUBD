#!/bin/bash
set -e

# Wait for master to be ready
until pg_isready -h master -p 5432 -U postgres; do
  echo "Waiting for master to be ready..."
  sleep 2
done

# Stop the server
pg_ctl stop -D "$PGDATA"

# Clean up the data directory
rm -rf "$PGDATA"/*
echo "Data directory cleaned up"

# Perform base backup
PGPASSWORD='replicator_password' pg_basebackup -h master -D /var/lib/postgresql/data -U replicator -v -P --wal-method=stream
echo "Base backup completed"

# Create standby.signal file
touch "$PGDATA/standby.signal"

# Set permissions
chown -R postgres:postgres "$PGDATA"

# Copy conf files
cp /etc/postgresql/postgresql.conf "$PGDATA/postgresql.conf"
cp /etc/postgresql/pg_hba.conf "$PGDATA/pg_hba.conf"
echo "Conf files copied"

# Start the server
pg_ctl -D "$PGDATA" start

# Wait for master to be ready
until pg_isready -h master -p 5432 -U postgres; do
  echo "Waiting for master to be ready..."
  sleep 1
done

echo "Hot standby is now running"