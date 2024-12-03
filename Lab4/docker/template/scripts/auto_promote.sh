#!/bin/bash
set -e

# Check if the hostname argument is provided
if [ -z "$1" ]; then
  echo "auto_promote.sh: Usage: $0 <hostname>"
  exit 1
fi
MASTER_HOST=$1
CHECK_INTERVAL=5
ONLINE_SERVICES=("1.1.1.1" "google.com" "8.8.8.8" "yandex.ru")

while true; do
  if ! PGPASSWORD="replicator_password" psql -h "$MASTER_HOST" -U replicator -d postgres -c "SELECT 1;" &> /dev/null; then
    echo "auto_promote.sh: $MASTER_HOST isn't available. Checking online services..."
    for service in "${ONLINE_SERVICES[@]}"; do
      if ping -c 1 "$service" &> /dev/null; then
        echo "auto_promote.sh: Service $service is reachable. Promoting standby."
        psql -U postgres -c "SELECT pg_promote();"
        exit 0
      else
        echo "auto_promote.sh: Service $service is unreachable."
      fi
    done
    echo "auto_promote.sh: No online services reachable. Retrying in $CHECK_INTERVAL seconds."
  else
    echo "auto_promote.sh: Master is connected."
  fi
  sleep "$CHECK_INTERVAL"
done