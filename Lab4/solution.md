Структура:
```
│   docker-compose.yml
│
├───hot_standby
│   │   Dockerfile
│   │
│   ├───conf
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
```

[postgresql.conf](./docker/master/conf/postgresql.conf)
```conf
listen_addresses = '*'
wal_level = replica
archive_mode = on
archive_command = 'cp %p /var/lib/postgresql/data/archive/%f'
max_wal_senders = 10
wal_keep_size = 64MB
include_dir = '/etc/postgresql/conf.d'
```

[pg_hba.conf](./docker/master/conf/pg_hba.conf)
```conf
# TYPE  DATABASE        USER            ADDRESS                 METHOD

host    replication     replicator      0.0.0.0/0               md5
host    all             all             0.0.0.0/0               md5
```

### Hot Standby
[Dockefile](./docker/hot_standby/Dockerfile)
```Dockerfile
FROM postgres:latest

COPY conf/replica.conf /etc/postgresql/conf.d/replica.conf
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

export PGPASSWORD='replicator_password'

# Clean up the data directory
rm -rf /var/lib/postgresql/data/*

# Perform base backup
pg_basebackup -h master -D /var/lib/postgresql/data -U replicator -v -P --wal-method=stream

# Create standby.signal file
touch /var/lib/postgresql/data/standby.signal

# Set permissions
chown -R postgres:postgres /var/lib/postgresql/data
```

[replica.conf](./docker/hot_standby/conf/replica.conf)
```conf
hot_standby = on
primary_conninfo = 'host=master port=5432 user=replicator password=replicator_password'
```

### Запуск
```bash
docker-compose up -d --build
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

Проверим режим чтения на стендбае:
```bash
docker exec -it hot_standby psql -U postgres -d test -c "SELECT * FROM users;"
```

