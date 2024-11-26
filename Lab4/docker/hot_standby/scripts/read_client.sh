#!/bin/bash
while true; do
    psql -U postgres -d test -c "SELECT COUNT(*) FROM users;"
    psql -U postgres -d test -c "SELECT * FROM orders;"
    sleep 2
done
