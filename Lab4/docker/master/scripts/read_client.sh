#!/bin/bash
while true; do
    psql -U postgres -d test -c "SELECT COUNT(*) FROM users;"
    sleep 2
done
