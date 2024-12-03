#!/bin/bash
set -e

# Function to check internet connectivity
check_internet() {
    ONLINE_SERVICES=("1.1.1.1" "google.com" "8.8.8.8" "yandex.ru")
    for service in "${ONLINE_SERVICES[@]}"; do
        if ping -c 1 "$service" &> /dev/null; then
            echo "Service $service is reachable."
            return 0
        else
            echo "Service $service is unreachable."
        fi
    done
    return 1
}

# Function to check if we can resolve and connect to hot_standby
check_hot_standby() {
    if ping -c 1 "hot_standby" &> /dev/null; then
        echo "hot_standby is reachable."
        return 0
    else
        echo "Cannot reach hot_standby."
        return 1
    fi
}

# Initialize variables
PGPASSWORD="replicator_password"

# Check if PGDATA is empty (first-time setup)
if [ -z "$(ls -A "$PGDATA")" ]; then
    echo "Data directory is empty. Initializing database..."
    
    # Initialize the database using the original entrypoint script
    /usr/local/bin/docker-entrypoint.sh postgres &
    pid="$!"

    # Wait for PostgreSQL to start
    until pg_isready -h localhost -p 5432 -U postgres; do
        echo "Waiting for PostgreSQL to start..."
        sleep 1
    done

    # Run the init-master.sh script
    /home/init/init-master.sh

    # Stop PostgreSQL after initialization
    kill "$pid"
    wait "$pid" || true

    echo "Database initialized. Proceeding to start PostgreSQL normally."
fi

echo "Data directory exists. Checking if pg_rewind is needed..."

# Wait until we have internet connectivity
until check_internet; do
    echo "No internet connectivity. Waiting..."
    sleep 5
done

# Check if we can resolve and connect to hot_standby
if ! check_hot_standby; then
    echo "Cannot reach hot_standby. Assuming no pg_rewind is needed. Starting normally."
    exec /usr/local/bin/docker-entrypoint.sh postgres
fi

# Get the current timeline ID from pg_controldata
CURRENT_TLI=$(pg_controldata "$PGDATA" | grep '\sTimeLineID:' | sed 's/.*TimeLineID: *//')

# Try to get the new primary's timeline ID
NEW_PRIMARY_TLI=$(PGPASSWORD="replicator_password" psql -h hot_standby -U replicator -d postgres -Atc "SELECT timeline_id FROM pg_control_checkpoint();" || true)

if [ -z "$NEW_PRIMARY_TLI" ]; then
    echo "Cannot retrieve timeline ID from new primary. Starting as primary."
    exec /usr/local/bin/docker-entrypoint.sh postgres
fi

echo "Current timeline ID: $CURRENT_TLI"
echo "New primary timeline ID: $NEW_PRIMARY_TLI"

if [ "$NEW_PRIMARY_TLI" -gt "$CURRENT_TLI" ]; then
    echo "New primary has a higher timeline ID. Performing pg_rewind..."

    # Ensure the server is stopped
    if [ -f "$PGDATA/postmaster.pid" ]; then
        echo "Stopping PostgreSQL server..."
        kill $(head -1 "$PGDATA/postmaster.pid") || true
        sleep 5
    fi

    # Remove leftover PID file
    rm -f "$PGDATA/postmaster.pid"

    # Perform pg_rewind
    su postgres -c 'pg_rewind --target-pgdata="$PGDATA" --source-server="host=hot_standby port=5432 dbname=postgres user=replicator password=replicator_password"'

    # Update configuration files
    cp /etc/postgresql/postgresql.conf "$PGDATA/postgresql.conf"
    cp /etc/postgresql/pg_hba.conf "$PGDATA/pg_hba.conf"

    # Set primary_conninfo in postgresql.conf
    echo "primary_conninfo = 'host=hot_standby port=5432 user=replicator password=replicator_password'" >> "$PGDATA/postgresql.conf"

    # Create standby.signal file
    touch "$PGDATA/standby.signal"

    chown -R postgres:postgres "$PGDATA"

    echo "pg_rewind completed. Starting as standby."
fi

# Start PostgreSQL using the original entrypoint script
exec /usr/local/bin/docker-entrypoint.sh postgres
