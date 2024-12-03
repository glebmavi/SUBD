Только последовательности действий, необходимых для выполнения, см. [run_sequence.md](./run_sequence.md)

## Структура:
```
│   docker-compose.yml
│
└───template
    │   Dockerfile
    │
    ├───conf
    │       pg_hba.conf
    │       postgresql.conf
    │
    ├───init
    │       init-master.sh
    │       init-standby.sh
    │
    └───scripts
            auto_promote.sh
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
      context: ./template
    restart: unless-stopped
    ports:
      - "9001:5432"
    environment:
      - PGDATA=/var/lib/postgresql/data
      - PGENCODING=UTF8
      - PGLOCALE=en_US.UTF8
      - PGUSERNAME=postgres
      - POSTGRES_PASSWORD=postgres
    entrypoint: ["/home/scripts/custom-entrypoint.sh"]
    command: ["hot_standby", "master"]
    volumes:
      - ./master/data:/var/lib/postgresql/data
    networks:
      - pg_net

  hot_standby:
    container_name: hot_standby
    build:
      context: ./template
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
    entrypoint: ["/home/scripts/custom-entrypoint.sh"]
    command: ["master", "hot_standby"]
    volumes:
      - ./hot_standby/data:/var/lib/postgresql/data
    networks:
      - pg_net

networks:
  pg_net:
    driver: bridge
```

## Этап 1. Конфигурация

[Dockefile](./docker/template/Dockerfile)
```Dockerfile
FROM postgres:latest

RUN apt-get update && apt-get install -y iputils-ping

COPY conf/postgresql.conf /etc/postgresql/postgresql.conf
COPY conf/pg_hba.conf /etc/postgresql/pg_hba.conf

COPY init/init-master.sh /home/init/init-master.sh
COPY init/init-standby.sh /home/init/init-standby.sh

COPY scripts/init-db.sql /home/scripts/init-db.sql
COPY scripts/read_client.sh /home/scripts/read_client.sh
COPY scripts/write_client.sh /home/scripts/write_client.sh
COPY scripts/auto_promote.sh /home/scripts/auto_promote.sh

COPY scripts/custom-entrypoint.sh /home/scripts/custom-entrypoint.sh
RUN chmod +x /home/scripts/custom-entrypoint.sh

RUN chmod +x /home/scripts/read_client.sh
RUN chmod +x /home/scripts/write_client.sh
RUN chmod +x /home/init/init-master.sh
RUN chmod +x /home/init/init-standby.sh
RUN chmod +x /home/scripts/auto_promote.sh
```

[custom-entrypoint.sh](./docker/template/scripts/custom-entrypoint.sh)
```bash
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
```

[init-master.sh](./docker/template/init/init-master.sh)
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
echo "init-master.sh: Conf files copied"
```

[postgresql.conf](./docker/template/conf/postgresql.conf)
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

[pg_hba.conf](./docker/template/conf/pg_hba.conf)
```conf
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             all                                     trust
host    all             postgres        0.0.0.0/0               md5
host    replication     replicator      0.0.0.0/0               md5
host    all             all             0.0.0.0/0               md5
```


[init-standby.sh](./docker/template/init/init-standby.sh)
```bash
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
docker exec -d hot_standby bash -c "/home/scripts/auto_promote.sh master"
```

[auto_promote.sh](./docker/template/scripts/auto_promote.sh)
```bash
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
```


### Наполнение базы
На примере не менее, чем двух таблиц, столбцов, строк, транзакций и клиентских сессий:
[init-db.sql](./docker/template/scripts/init-db.sql)
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

[read_client.sh](./docker/template/scripts/read_client.sh)
```bash
#!/bin/bash
while true; do
    psql -U postgres -d test -c "SELECT * FROM users;"
    psql -U postgres -d test -c "SELECT * FROM orders;"
    sleep 2
done
```

[write_client.sh](./docker/template/scripts/write_client.sh)
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
