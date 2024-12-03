#!/bin/bash

MASTER_HOST="master"
CHECK_INTERVAL=5
ONLINE_SERVICES=("1.1.1.1" "google.com" "8.8.8.8" "yandex.ru")

while true; do
  if ! ping -c 1 "$MASTER_HOST" &> /dev/null; then
    echo "Master isn't available. Checking online services..."
    for service in "${ONLINE_SERVICES[@]}"; do
      if ping -c 1 "$service" &> /dev/null; then
        echo "Service $service is reachable. Promoting standby."
        psql -U postgres -c "SELECT pg_promote();"
        exit 0
      else
        echo "Service $service is unreachable."
      fi
    done
    echo "No online services reachable. Retrying in $CHECK_INTERVAL seconds."
  else
    echo "Master is connected."
  fi
  sleep "$CHECK_INTERVAL"
done