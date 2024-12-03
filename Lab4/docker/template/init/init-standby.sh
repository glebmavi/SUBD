#!/bin/bash
set -e
echo "init-standby.sh: Initializing hot standby..."
# Check if the hostname argument is provided
if [ -z "$1" ]; then
  echo "init-standby.sh: Usage: $0 <hostname>"
  exit 1
fi
OTHERS_HOST_NAME=$1

# Function to wait for master to be ready
wait_for_master() {
  until pg_isready -h "$OTHERS_HOST_NAME" -p 5432 -U postgres; do
    echo "init-standby.sh: Waiting for $OTHERS_HOST_NAME to be ready..."
    sleep 2
  done
}

wait_for_master

echo -e "\n" >> /etc/postgresql/postgresql.conf
echo -e "hot_standby = on \n" >> /etc/postgresql/postgresql.conf
echo -e "primary_conninfo = 'host=$OTHERS_HOST_NAME port=5432 user=replicator password=replicator_password' \n" >> /etc/postgresql/postgresql.conf

# Stop the server
su postgres -c "pg_ctl stop -D \"$PGDATA\""

# Clean up the data directory
rm -rf "$PGDATA"/*
echo "init-standby.sh: Data directory cleaned up"

# Perform base backup
PGPASSWORD='replicator_password' pg_basebackup -h $OTHERS_HOST_NAME -D /var/lib/postgresql/data -U replicator -v -P --wal-method=stream
echo "init-standby.sh: Base backup completed"

# Create standby.signal file
touch "$PGDATA/standby.signal"

# Set permissions
chown -R postgres:postgres "$PGDATA"

# Copy conf files
cp /etc/postgresql/postgresql.conf "$PGDATA/postgresql.conf"
cp /etc/postgresql/pg_hba.conf "$PGDATA/pg_hba.conf"
echo "init-standby.sh: Conf files copied"

# Restart the server
su postgres -c "pg_ctl start -D \"$PGDATA\""
