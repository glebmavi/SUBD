При повторном запуске стоит начинать с:

Очистка данных
(Запуск внутри папки docker)
```bash
Remove-Item -Path .\master\data\*, .\hot_standby\data\* -Recurse -Force
```

## Запуск

Запуск master
```bash
docker-compose up -d --build master
```

Ожидаем лога `database system is ready to accept connections`

Запуск init-master.sh
```bash
docker exec -it master bash -c "/home/init/init-master.sh"
docker restart master
```

Ожидаем

Запуск hot_standby
```bash
docker-compose up -d --build hot_standby
```
При работающем стендбае запустим скрипт автоматического promote:
```bash
docker exec -d hot_standby bash -c "/home/scripts/auto_promote.sh"
```

## Проверка

Проверим данные на мастере:
```bash
docker exec -it master psql -U postgres -d test -c "SELECT * FROM users;"
```

Проверим режим чтения на стендбае:
```bash
docker exec -it hot_standby psql -U postgres -d test -c "SELECT * FROM users;"
```

Попробуем записать данные на стендбае: (Должно быть ошибка)
```bash
docker exec -it hot_standby psql -U postgres -d test -c "INSERT INTO users (name) VALUES ('Charlie');"
```

## Симуляция работы

Запуск:
```bash
docker exec -it master bash /home/scripts/read_client.sh
docker exec -it master bash /home/scripts/write_client.sh
docker exec -it hot_standby bash /home/scripts/read_client.sh
```
Данные в обоих клиентах будут одинаковыми.

## Сбой мастера

Симулируем сбой мастера отключив сетевой интерфейс:
```bash
docker network disconnect docker_pg_net master
```

При этом чтение в стандбае продолжится:
```bash
docker exec -it hot_standby bash /home/scripts/read_client.sh
```

## Обработка

Проверим чтение и запись на стендбае после promote (автоматический):
```bash
docker exec -it hot_standby psql -U postgres -d test -c "INSERT INTO users (name) VALUES ('Charlie');"
docker exec -it hot_standby psql -U postgres -d test -c "SELECT * FROM users;"
```

## Восстановление
Включаем сеть мастера:
```bash
docker network connect docker_pg_net master
```

Восстанавливаем работу мастера:
```bash
docker exec -it master bash
```
В консоли мастера:
```bash
su postrges
```
```bash
pg_basebackup -P -X stream -c fast -h hot_standby -U replicator -D ~/backup
# password: replicator_password
rm -rf /var/lib/postgresql/data/*
mv ~/backup/* /var/lib/postgresql/data/
```
Выходим из контейнера мастера.


```bash
docker exec -it hot_standby bash
```
В консоли стендбая:
```bash
touch /var/lib/postgresql/data/standby.signal
```
Выходим из контейнера стендбая.

Останавливаем стендбай:
```bash
docker-compose stop hot_standby
Remove-Item -Path .\hot_standby\data\* -Recurse -Force
```

Заново запускаем мастера:
```bash
docker-compose up -d master
```

Пересоздаем стендбай чтобы заново стал hot_standby:
```bash
docker-compose up -d --build hot_standby
```


Проверяем:
```bash
docker exec -it master bash /home/scripts/read_client.sh
docker exec -it master bash /home/scripts/write_client.sh
docker exec -it hot_standby bash /home/scripts/read_client.sh
```
