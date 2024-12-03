#!/bin/bash

# Check if the hostname and role arguments are provided
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "custom-entrypoint.sh: Usage: $0 <hostname> <role>"
  echo "custom-entrypoint.sh: Role must be 'master' or 'hot_standby'"
  exit 1
fi
OTHERS_HOST_NAME=$1
ROLE=$2

# Validate role
if [[ "$ROLE" != "master" && "$ROLE" != "hot_standby" ]]; then
  echo "custom-entrypoint.sh: Invalid role: $ROLE. Must be 'master' or 'hot_standby'."
  exit 1
fi

# Function to check internet connectivity
check_internet() {
    ONLINE_SERVICES=("1.1.1.1" "google.com" "8.8.8.8" "yandex.ru")
    for service in "${ONLINE_SERVICES[@]}"; do
        if ping -c 1 "$service" &> /dev/null; then
            echo "custom-entrypoint.sh: Service $service is reachable."
            return 0
        else
            echo "custom-entrypoint.sh: Service $service is unreachable."
        fi
    done
    return 1
}

# Function to check if we can resolve and connect to hot_standby
check_hot_standby() {
    if PGPASSWORD="replicator_password" psql -h "$OTHERS_HOST_NAME" -U replicator -d postgres -c "SELECT 1;" &> /dev/null; then
        echo "custom-entrypoint.sh: PostgreSQL on $OTHERS_HOST_NAME is reachable."
        return 0
    else
        echo "custom-entrypoint.sh: Cannot connect to PostgreSQL on $OTHERS_HOST_NAME."
        return 1
    fi
}

# Initialize variables
PGPASSWORD="replicator_password"

# Check if PGDATA is empty (first-time setup)
if [ -z "$(ls -A "$PGDATA")" ]; then
    echo "custom-entrypoint.sh: Data directory is empty. Initializing database..."
    
    # Initialize the database using the original entrypoint script
    /usr/local/bin/docker-entrypoint.sh postgres &
    pid="$!"

    # Wait for PostgreSQL to start
    until pg_isready -h localhost -p 5432 -U postgres; do
        echo "custom-entrypoint.sh: Waiting for PostgreSQL to start..."
        sleep 1
    done

    # Run initialization based on role
    if [ "$ROLE" = "master" ]; then
        /home/init/init-master.sh
    elif [ "$ROLE" = "hot_standby" ]; then
        /home/init/init-standby.sh "$OTHERS_HOST_NAME"
    else
        echo "custom-entrypoint.sh: Unknown role: $ROLE"
        exit 1
    fi

    # Stop PostgreSQL after initialization
    kill "$pid"
    wait "$pid"

    echo "custom-entrypoint.sh: Database initialized. Proceeding to start PostgreSQL normally."
    exit 0
fi
if [ "$ROLE" = "hot_standby" ]; then
    echo "custom-entrypoint.sh: Data directory exists. Starting normally."
    exec /usr/local/bin/docker-entrypoint.sh postgres
fi
    
if [ "$ROLE" = "master" ]; then
    echo "custom-entrypoint.sh: Data directory exists. Checking if pg_rewind is needed..."

    # Wait until we have internet connectivity
    until check_internet; do
        echo "custom-entrypoint.sh: No internet connectivity. Waiting..."
        sleep 5
    done

    # Check if we can resolve and connect to hot_standby
    if ! check_hot_standby; then
        echo "custom-entrypoint.sh: Cannot reach $OTHERS_HOST_NAME. Assuming no pg_rewind is needed. Starting normally."
        exec /usr/local/bin/docker-entrypoint.sh postgres
    fi

    # Get the current timeline ID from pg_controldata
    CURRENT_TLI=$(pg_controldata "$PGDATA" | grep '\sTimeLineID:' | sed 's/.*TimeLineID: *//')

    # Try to get the new primary's timeline ID
    NEW_PRIMARY_TLI=$(PGPASSWORD="replicator_password" psql -h $OTHERS_HOST_NAME -U replicator -d postgres -Atc "SELECT timeline_id FROM pg_control_checkpoint();" || true)

    if [ -z "$NEW_PRIMARY_TLI" ]; then
        echo "custom-entrypoint.sh: Cannot retrieve timeline ID from new primary. Starting as primary."
        exec /usr/local/bin/docker-entrypoint.sh postgres
    fi

    echo "custom-entrypoint.sh: Current timeline ID: $CURRENT_TLI"
    echo "custom-entrypoint.sh: New primary timeline ID: $NEW_PRIMARY_TLI"

    if [ "$NEW_PRIMARY_TLI" -gt "$CURRENT_TLI" ]; then
        echo "custom-entrypoint.sh: New primary has a higher timeline ID. Performing pg_rewind..."

        # Ensure the server is stopped
        if [ -f "$PGDATA/postmaster.pid" ]; then
            echo "custom-entrypoint.sh: Stopping PostgreSQL server..."
            kill $(head -1 "$PGDATA/postmaster.pid") || true
            sleep 5
        fi

        # Remove leftover PID file
        rm -f "$PGDATA/postmaster.pid"

        # Perform pg_rewind
        su postgres -c "pg_rewind --target-pgdata=\"$PGDATA\" --source-server=\"host=$OTHERS_HOST_NAME port=5432 dbname=postgres user=replicator password=replicator_password\""

        # Update configuration files
        cp /etc/postgresql/postgresql.conf "$PGDATA/postgresql.conf"
        cp /etc/postgresql/pg_hba.conf "$PGDATA/pg_hba.conf"

        # Set primary_conninfo in postgresql.conf
        echo "primary_conninfo = 'host=$OTHERS_HOST_NAME port=5432 user=replicator password=replicator_password'" >> "$PGDATA/postgresql.conf"
        # Set hot_standby in postgresql.conf
        echo "hot_standby = on" >> "$PGDATA/postgresql.conf"

        # Create standby.signal file
        touch "$PGDATA/standby.signal"

        chown -R postgres:postgres "$PGDATA"

        echo "custom-entrypoint.sh: pg_rewind completed. Starting as standby."
        exec /usr/local/bin/docker-entrypoint.sh postgres
    fi
fi
