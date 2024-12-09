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

Запуск hot_standby
```bash
docker-compose up -d --build hot_standby
```
Ожидаем появления что-то подобного:
```
2024-12-09 18:19:54.000 GMT [102] LOG:  completed backup recovery with redo LSN 0/2000028 and end LSN 0/2000158
2024-12-09 18:19:54.002 GMT [102] LOG:  consistent recovery state reached at 0/2000158
2024-12-09 18:19:54.002 GMT [99] LOG:  database system is ready to accept read-only connections
2024-12-09 18:19:54.026 GMT [103] LOG:  started streaming WAL from primary at 0/3000000 on timeline 1
 done
server started
custom-entrypoint.sh: Database initialized. Proceeding to start PostgreSQL normally.
custom-entrypoint.sh: Data directory exists. Starting normally.

PostgreSQL Database directory appears to contain a database; Skipping initialization
```

При работающем стендбае запустим скрипт автоматического promote:
```bash
docker exec -d hot_standby bash -c "/home/scripts/auto_promote.sh master"
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

Ожидаем автоматического promote на стендбае

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
docker restart master
```

Проверяем:
```bash
docker exec -it master bash /home/scripts/read_client.sh
docker exec -it master bash /home/scripts/write_client.sh # Не должно работать
docker exec -it hot_standby bash /home/scripts/read_client.sh
docker exec -it hot_standby psql -U postgres -d test -c "INSERT INTO users (name) VALUES ('Charlie2');" # Должно работать
```
