Структура:
```
│   docker-compose.yml
│
├───hot_standby
│   │   Dockerfile
│   │
│   ├───conf
|   │       pg_hba.conf
│   │       replica.conf
│   │
│   ├───data
│   └───init
│           init-standby.sh
│
└───master
    │   Dockerfile
    │
    ├───conf
    │       pg_hba.conf
    │       postgresql.conf
    │
    ├───data
    └───init
            init-master.sh
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

COPY conf/postgresql.conf /etc/postgresql/postgresql.conf
COPY conf/pg_hba.conf /etc/postgresql/pg_hba.conf
COPY init/init-master.sh /docker-entrypoint-initdb.d/init-master.sh
RUN chmod +x /docker-entrypoint-initdb.d/init-master.sh
```

[init-master.sh](./docker/master/init/init-master.sh)
```bash
#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "postgres" -c "CREATE ROLE replicator WITH REPLICATION PASSWORD 'replicator_password' LOGIN;"

# Copy conf files
cp /etc/postgresql/postgresql.conf "$PGDATA/postgresql.conf"
cp /etc/postgresql/pg_hba.conf "$PGDATA/pg_hba.conf"

# Restart
pg_ctl -D "$PGDATA" -m fast -w restart
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
log_destination = 'jsonlog'
logging_collector = on
log_connections = on
log_disconnections = on
log_duration = on
log_directory = 'pg_log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
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

COPY conf/postgresql.conf /etc/postgresql/postgresql.conf
COPY conf/pg_hba.conf /etc/postgresql/pg_hba.conf
COPY init/init-standby.sh /docker-entrypoint-initdb.d/init-standby.sh
RUN chmod +x /docker-entrypoint-initdb.d/init-standby.sh
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
```

[postgresql.conf](./docker/hot_standby/conf/postgresql.conf)
```conf
hot_standby = on
primary_conninfo = 'host=master port=5432 user=replicator password=replicator_password'
```

[pg_hba.conf](./docker/hot_standby/conf/pg_hba.conf)
```conf
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             all                                     trust
host    replication     replicator      0.0.0.0/0               md5
host    all             all             0.0.0.0/0               md5
```

### Запуск

```bash
docker-compose up -d --build
```

(Может понадобится при повторном запуске)
```bash
Remove-Item -Path .\master\data\*, .\hot_standby\data\* -Recurse -Force
```

### Наполнение базы
На примере не менее, чем двух таблиц, столбцов, строк, транзакций и клиентских сессий:
```bash
docker exec -it master psql -U postgres -c "CREATE DATABASE test;"
docker exec -it master psql -U postgres -d test -c "CREATE TABLE users (id SERIAL PRIMARY KEY, name VARCHAR(255));"
docker exec -it master psql -U postgres -d test -c "INSERT INTO users (name) VALUES ('Alice');"
docker exec -it master psql -U postgres -d test -c "INSERT INTO users (name) VALUES ('Bob');"
```

Проверим данные на мастере:
```bash
docker exec -it master psql -U postgres -d test -c "SELECT * FROM users;"
```

```
PS C:\IMPRIMIR\3kurs\5Sem\SUBD\Lab4\docker> docker exec -it master psql -U postgres -c "CREATE DATABASE test;"
CREATE DATABASE
PS C:\IMPRIMIR\3kurs\5Sem\SUBD\Lab4\docker> docker exec -it master psql -U postgres -d test -c "CREATE TABLE users (id SERIAL PRIMARY KEY, name VARCHAR(255));"
CREATE TABLE
PS C:\IMPRIMIR\3kurs\5Sem\SUBD\Lab4\docker> docker exec -it master psql -U postgres -d test -c "INSERT INTO users (name) VALUES ('Alice');"
INSERT 0 1
PS C:\IMPRIMIR\3kurs\5Sem\SUBD\Lab4\docker> docker exec -it master psql -U postgres -d test -c "INSERT INTO users (name) VALUES ('Bob');"
INSERT 0 1
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