Только последовательности действий, необходимых для выполнения, см. [run_sequence.md](./run_sequence.md)

## Структура:
```
│   docker-compose.yml
│
├───hot_standby
│   │   Dockerfile
│   │
│   ├───conf
│   │       pg_hba.conf
│   │       postgresql.conf
│   │
│   ├───data
│   ├───init
│   │       init-standby.sh
│   │
│   └───scripts
│           auto_promote.sh
│           read_client.sh
│
└───master
    │   Dockerfile
    │
    ├───conf
    │       pg_hba.conf
    │       postgresql.conf
    │
    ├───data
    ├───init
    │       init-master.sh
    │
    └───scripts
            custom-entrypoint.sh
            init-db.sql
            read_client.sh
            write_client.sh
```

Хосты настроены через [docker-compose.yml](./docker/docker-compose.yml)
```yaml
services:
  master:
    container_name: master
    build:
      context: ./master
    restart: unless-stopped
    ports:
      - "9001:5432"
    environment:
      - PGDATA=/var/lib/postgresql/data
      - PGENCODING=UTF8
      - PGLOCALE=en_US.UTF8
      - PGUSERNAME=postgres
      - POSTGRES_PASSWORD=postgres
    volumes:
      - ./master/data:/var/lib/postgresql/data
    networks:
      - pg_net

  hot_standby:
    container_name: hot_standby
    build:
      context: ./hot_standby
    restart: unless-stopped
    ports:
      - "9002:5432"
    depends_on:
      - master
    environment:
      - PGDATA=/var/lib/postgresql/data
      - PGENCODING=UTF8
      - PGLOCALE=en_US.UTF8
      - PGUSERNAME=postgres
      - POSTGRES_PASSWORD=postgres
    volumes:
      - ./hot_standby/data:/var/lib/postgresql/data
    networks:
      - pg_net

networks:
  pg_net:
    driver: bridge
```
Соединение между хостами настроено через сеть `pg_net` и порты `9001` и `9002` соответственно.

## Этап 1. Конфигурация

### Master
[Dockefile](./docker/master/Dockerfile)
```Dockerfile
FROM postgres:latest

RUN apt-get update && apt-get install -y iputils-ping

COPY conf/postgresql.conf /etc/postgresql/postgresql.conf
COPY conf/pg_hba.conf /etc/postgresql/pg_hba.conf
COPY init/init-master.sh /home/init/init-master.sh
COPY scripts/init-db.sql /home/scripts/init-db.sql
COPY scripts/read_client.sh /home/scripts/read_client.sh
COPY scripts/write_client.sh /home/scripts/write_client.sh

COPY scripts/custom-entrypoint.sh /home/scripts/custom-entrypoint.sh
RUN chmod +x /home/scripts/custom-entrypoint.sh

RUN chmod +x /home/scripts/read_client.sh
RUN chmod +x /home/scripts/write_client.sh
RUN chmod +x /home/init/init-master.sh

ENTRYPOINT ["/home/scripts/custom-entrypoint.sh"]
CMD ["postgres"]
```

[custom-entrypoint.sh](./docker/master/scripts/custom-entrypoint.sh)
```bash
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
```

[init-master.sh](./docker/master/init/init-master.sh)
```bash
#!/bin/bash
set -e

# Replicator role
psql -v ON_ERROR_STOP=1 --username "postgres" -c "CREATE ROLE replicator WITH SUPERUSER REPLICATION PASSWORD 'replicator_password' LOGIN;"

# DB init and populate
psql -v ON_ERROR_STOP=1 --username "postgres" -f "/home/scripts/init-db.sql"

# Copy conf files
cp /etc/postgresql/postgresql.conf "$PGDATA/postgresql.conf"
cp /etc/postgresql/pg_hba.conf "$PGDATA/pg_hba.conf"
echo "Conf files copied"
```

[postgresql.conf](./docker/master/conf/postgresql.conf)
```conf
listen_addresses = '*'
wal_level = replica
wal_keep_size = 64MB
max_wal_senders = 10
max_replication_slots = 10
archive_mode = on
archive_command = 'echo "dummy command, archive_command called"'
log_connections = on
log_disconnections = on
log_duration = on
wal_log_hints = on

```

[pg_hba.conf](./docker/master/conf/pg_hba.conf)
```conf
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             all                                     trust
host    replication     replicator      0.0.0.0/0               md5
host    all             all             0.0.0.0/0               md5
```

### Hot Standby
[Dockefile](./docker/hot_standby/Dockerfile)
```Dockerfile
FROM postgres:latest

RUN apt-get update && apt-get install -y iputils-ping

COPY conf/postgresql.conf /etc/postgresql/postgresql.conf
COPY conf/pg_hba.conf /etc/postgresql/pg_hba.conf
COPY init/init-standby.sh /docker-entrypoint-initdb.d/init-standby.sh
COPY scripts/read_client.sh /home/scripts/read_client.sh
COPY scripts/auto_promote.sh /home/scripts/auto_promote.sh
RUN chmod +x /home/scripts/read_client.sh
RUN chmod +x /docker-entrypoint-initdb.d/init-standby.sh
RUN chmod +x /home/scripts/auto_promote.sh
```

[init-standby.sh](./docker/hot_standby/init/init-standby.sh)
```bash
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
```

[postgresql.conf](./docker/hot_standby/conf/postgresql.conf)
```conf
listen_addresses = '*'
hot_standby = on
primary_conninfo = 'host=master port=5432 user=replicator password=replicator_password'
wal_log_hints = on
log_connections = on
log_disconnections = on
log_duration = on
wal_log_hints = on
```

[pg_hba.conf](./docker/hot_standby/conf/pg_hba.conf)
```conf
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             all                                     trust
host    all             postgres        0.0.0.0/0               md5
host    replication     replicator      0.0.0.0/0               md5
host    all             all             0.0.0.0/0               md5
```

### Запуск

Очистка данных
(Может понадобится при повторном запуске) (Запуск внутри папки docker)
```bash
Remove-Item -Path .\master\data\*, .\hot_standby\data\* -Recurse -Force
```

Запуск master
```bash
docker-compose up -d --build master
```

Ожидаем лога `database system is ready to accept connections`

Запуск hot_standby
```bash
docker-compose up -d --build hot_standby
```
Ожидаем
При работающем стендбае запустим скрипт автоматического promote:
```bash
docker exec -d hot_standby bash -c "/home/scripts/auto_promote.sh"
```

[auto_promote.sh](./docker/hot_standby/scripts/auto_promote.sh)
```bash
#!/bin/bash
set -e

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
```


### Наполнение базы
На примере не менее, чем двух таблиц, столбцов, строк, транзакций и клиентских сессий:
[init-db.sql](./docker/master/scripts/init-db.sql)
```sql
CREATE DATABASE test;

\c test;

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255)
);

CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(id),
    product VARCHAR(255)
);

INSERT INTO users (name) VALUES ('Alice'), ('Bob');
INSERT INTO orders (user_id, product) VALUES (1, 'Laptop'), (2, 'Smartphone');
```

Проверим данные на мастере:
```bash
docker exec -it master psql -U postgres -d test -c "SELECT * FROM users;"
```

```
PS C:\IMPRIMIR\3kurs\5Sem\SUBD\Lab4\docker> docker exec -it master psql -U postgres -d test -c "SELECT * FROM users;"
 id | name  
----+-------
  1 | Alice
  2 | Bob
(2 rows)
```

Проверим режим чтения на стендбае:
```bash
docker exec -it hot_standby psql -U postgres -d test -c "SELECT * FROM users;"
```

```
PS C:\IMPRIMIR\3kurs\5Sem\SUBD\Lab4\docker> docker exec -it hot_standby psql -U postgres -d test -c "SELECT * FROM users;"
 id | name  
----+-------
  1 | Alice
  2 | Bob
(2 rows)
```

Попробуем записать данные на стендбае:
```bash
docker exec -it hot_standby psql -U postgres -d test -c "INSERT INTO users (name) VALUES ('Charlie');"
```

```
PS C:\IMPRIMIR\3kurs\5Sem\SUBD\Lab4\docker> docker exec -it hot_standby psql -U postgres -d test -c "INSERT INTO users (name) VALUES ('Charlie');"
ERROR:  cannot execute INSERT in a read-only transaction
```

## Этап 2. Симуляция и обработка сбоя

### 2.1 Подготовка
Написаны скрипты для симуляции чтения и записи из мастера и чтение из стендбая:

[read_client.sh](./docker/master/scripts/read_client.sh)
```bash
#!/bin/bash
while true; do
    psql -U postgres -d test -c "SELECT COUNT(*) FROM users;"
    sleep 2
done
```

[write_client.sh](./docker/master/scripts/write_client.sh)
```bash
#!/bin/bash
while true; do
    psql -U postgres -d test -c "INSERT INTO users (name) VALUES ('User_$(date +%s)');"
    
    items=("TV" "Mouse" "Keyboard" "HDMI cable")
    random_item=${items[$RANDOM % ${#items[@]}]}
    last_user_id=$(psql -U postgres -d test -t -c "SELECT id FROM users ORDER BY id DESC LIMIT 1;")
    psql -U postgres -d test -c "INSERT INTO orders (user_id, product) VALUES ($last_user_id, '$random_item');"
    sleep 2
done
```

В стандбае [read_client.sh](./docker/hot_standby/scripts/read_client.sh)
```bash
#!/bin/bash
while true; do
    psql -U postgres -d test -c "SELECT * FROM users;"
    psql -U postgres -d test -c "SELECT * FROM orders;"
    sleep 2
done
```

Запуск:
```bash
docker exec -it master bash /home/scripts/read_client.sh
docker exec -it master bash /home/scripts/write_client.sh
docker exec -it hot_standby bash /home/scripts/read_client.sh
```

Ожидаем что в стандбае чтение будет автоматически показывать новые данные из мастера.

### 2.2 Сбой
Симулируем сбой мастера отключив сетевой интерфейс:
```bash
docker network disconnect docker_pg_net master
```

### 2.3 Обработка

При этом чтение работает:
```bash
docker exec -it hot_standby bash /home/scripts/read_client.sh
```
```
PS C:\IMPRIMIR\3kurs\5Sem\SUBD\Lab4\docker> docker exec -it hot_standby bash /home/scripts/read_client.sh
 count 
-------
     7
(1 row)

 id | user_id |  product   
----+---------+------------
  1 |       1 | Laptop
  2 |       2 | Smartphone
  3 |       3 | HDMI cable
  4 |       4 | HDMI cable
  5 |       5 | TV
  6 |       6 | TV
  7 |       7 | TV
(7 rows)
```


Проверим чтение и запись на стендбае после promote:
```bash
docker exec -it hot_standby psql -U postgres -d test -c "INSERT INTO users (name) VALUES ('Charlie');"
docker exec -it hot_standby psql -U postgres -d test -c "SELECT * FROM users;"
```

```
PS C:\IMPRIMIR\3kurs\5Sem\SUBD\Lab4\docker> docker exec -it hot_standby psql -U postgres -d test -c "INSERT INTO users (name) VALUES ('Charlie');"
INSERT 0 1
PS C:\IMPRIMIR\3kurs\5Sem\SUBD\Lab4\docker> docker exec -it hot_standby psql -U postgres -d test -c "SELECT * FROM users;"
 id |      name       
----+-----------------
  1 | Alice
  2 | Bob
  3 | User_1732610768
  4 | User_1732610770
  5 | User_1732610772
  6 | User_1732610775
  7 | User_1732610777
 36 | Charlie
(8 rows)
```

### 3. Восстановление

Включаем сеть мастера:
```bash
docker network connect docker_pg_net master
docker restart master
```

Ожидаем лога `database system is ready to accept read-only connections`

Проверяем:
```bash
docker exec -it master bash /home/scripts/read_client.sh
docker exec -it master bash /home/scripts/write_client.sh # Не должно работать
docker exec -it hot_standby bash /home/scripts/read_client.sh
docker exec -it hot_standby psql -U postgres -d test -c "INSERT INTO users (name) VALUES ('Charlie2');" # Должно работать
```
