Структура:
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
COPY scripts/init-db.sql /docker-entrypoint-initdb.d/init-db.sql
RUN chmod +x /docker-entrypoint-initdb.d/init-master.sh
```

[init-master.sh](./docker/master/init/init-master.sh)
```bash
#!/bin/bash
#!/bin/bash
set -e

# Replicator role
psql -v ON_ERROR_STOP=1 --username "postgres" -c "CREATE ROLE replicator WITH REPLICATION PASSWORD 'replicator_password' LOGIN;"

# DB init and populate
psql -v ON_ERROR_STOP=1 --username "postgres" -f "/docker-entrypoint-initdb.d/init-db.sql"

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

Очистка данных
(Может понадобится при повторном запуске)
```bash
Remove-Item -Path .\master\data\*, .\hot_standby\data\* -Recurse -Force
```

Запуск master
```bash
docker-compose up -d --build master
```

Запуск init-master.sh
```bash
docker exec -it master bash -c "/home/init/init-master.sh"
docker restart master
```

Запуск hot_standby
```bash
docker-compose up -d --build hot_standby
```
Remove-Item -Path .\hot_standby\data\* -Recurse -Force

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
    psql -U postgres -d test -c "INSERT INTO orders (user_id, item) VALUES ($last_user_id, '$random_item');"
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

В стандбае видим логи:
```
2024-11-26 12:28:45 2024-11-26 09:28:45.898 GMT [190] FATAL:  could not connect to the primary server: could not translate host name "master" to address: Temporary failure in name resolution
2024-11-26 12:28:53 2024-11-26 09:28:53.908 GMT [191] FATAL:  could not connect to the primary server: could not translate host name "master" to address: Temporary failure in name resolution
```

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

Переводим стендбай в режим мастера:
```bash
docker exec -it hot_standby psql -U postgres -c "select pg_promote();"
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
```

Восстанавливаем работу мастера:
```bash
docker exec -it master bash
```

```bash
su postrges
```
```bash
pg_basebackup -P -X stream -c fast -h hot_standby -U replicator -D ~/backup
rm -rf /var/lib/postgresql/data/*
mv ~/backup/* /var/lib/postgresql/data/
```

```bash
docker exec -it hot_standby bash
```
```bash
touch /var/lib/postgresql/data/standby.signal
```
  
```bash
docker-compose up master
```

Проверяем:
```bash
docker exec -it master bash /home/scripts/read_client.sh
docker exec -it master bash /home/scripts/write_client.sh
docker exec -it hot_standby bash /home/scripts/read_client.sh
```
