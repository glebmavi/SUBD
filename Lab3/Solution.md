# Выполнение

## Этап 1. Резервное копирование

### Включение режима архивирования WAL на основном узле

Изменяем конфигурационный файл [`postgresql.conf`](./main_pg167/postgresql.conf) на основном узле, отправляя WAL-логи на резервный узел:
```conf
wal_level = replica
archive_mode = on
archive_command = 'scp %p postgres0@pg175:~/wal_archive/%f'
```

В резервном узле создаем директорию для хранения WAL:
```bash
mkdir -p wal_archive # учитываем, что директория будет создана в домашнем каталоге пользователя
```

На основном узле сгенерируем SSH-ключ для автоматической авторизации scp:
```bash
ssh-keygen -t rsa -b 4096 -C "postgres1@pg167" # на все вопросы отвечаем Enter
ssh-copy-id -i ~/.ssh/id_rsa.pub postgres0@pg175
```

Проверка: (доступ к резервному узлу без пароля)
```
[postgres1@pg167 ~]$ ssh postgres0@pg175
Last login: Sat Nov  2 12:50:24 2024 from 192.168.11.167
[postgres0@pg175 ~]$ 
```

Загружаем изменения в конфигурацию:
```bash
scp -o "ProxyJump s372819@se.ifmo.ru:2222" main_pg167/postgresql.conf postgres1@pg167:~/khk43
```

### Настройка полного резервного копирования (pg_basebackup) по расписанию

Создаем директорию для хранения резервных копий на основном узле:
```bash
mkdir -p ~/backups
```
Также в резервном узле:
```bash
mkdir -p ~/backups
```

Для разрешения подключения для репликации на основном узле добавим строку в [`pg_hba.conf`](./main_pg167/pg_hba.conf):
```conf
local   replication     all                                     peer map=my_map
```
Загрузим изменения:
```bash
scp -o "ProxyJump s372819@se.ifmo.ru:2222" main_pg167/pg_hba.conf postgres1@pg167:~/khk43
```
Перезапустим сервер:
```bash
pg_ctl -D ~/khk43 restart
```

Создаем [скрипт](./main_pg167/backup.sh) для резервного копирования `backup.sh` на основном узле:
```bash
#!/bin/sh

CURRENT_DATE=$(date "+%Y-%m-%d_%H:%M:%S")
BACKUP_DIR="~/backups/$CURRENT_DATE"
mkdir -p "$BACKUP_DIR"

# Создаем полную резервную копию
pg_basebackup -D "$BACKUP_DIR" -F tar -z -P -p 9555 # 9555 - порт указанный в основном узле postgresql.conf

# Копируем резервную копию на резервный узел
scp "$BACKUP_DIR"/*.tar.gz postgres0@pg175:~/backups/

# Удаляем резервные копии старше 7 дней на основном узле
find ~/backups/ -type d -mtime +7 -exec rm -rf {} \;

# Удаляем WAL-файлы старше 7 дней на основном узле
find ~/oka84/ -type f -mtime +7 -exec rm -f {} \; # по предыдущему заданию WAL-файлы хранятся в '~/oka84/'

# Удаляем резервные копии старше 28 дней на резервном узле
ssh postgres0@pg175 'find ~/backups/ -type d -mtime +28 -exec rm -rf {} \;'

# Удаляем WAL-файлы старше 28 дней на резервном узле
ssh postgres0@pg175 'find ~/wal_archive/ -type f -mtime +28 -exec rm -f {} \;'
```
Загружаем скрипт на основной узел:
```bash
scp -o "ProxyJump s372819@se.ifmo.ru:2222" main_pg167/backup.sh postgres1@pg167:~
```
Сделаем скрипт исполняемым:
```bash
chmod +x backup.sh
```

Добавляем задачу в cron на основном узле:
```bash
crontab -e
```
Добавляем строку (каждое воскресенье в 2 часа ночи):
```
0 2 * * 0 ~/backup.sh >> ~/backup.log 2>&1
```

Проверим работоспособность скрипта:
```bash
bash ~/backup.sh >> ~/backup.log 2>&1
```
Результаты выполнения скрипта:
```
[postgres1@pg167 ~]$ cat backup.log
ожидание контрольной точки
    2/31300 КБ (0%), табличное пространство 0/3
    2/31300 КБ (0%), табличное пространство 1/3
    4/31300 КБ (0%), табличное пространство 1/3
    4/31300 КБ (0%), табличное пространство 2/3
31314/31314 КБ (100%), табличное пространство 2/3
31314/31314 КБ (100%), табличное пространство 3/3
```

### Подсчет объема резервных копий

**Исходные данные:**

- Средний объем новых данных в БД за сутки: 800 МБ
- Средний объем измененных данных за сутки: 1000 МБ
- Частота полного резервного копирования: раз в неделю (посредством pg_basebackup).
- Архивирование WAL: непрерывное, ежедневно.
- Срок хранения копий:
    - На основном узле: 1 неделя.
    - На резервном узле: 4 недели.

**Подсчет:**

Объем данных за неделю:
- Новые данные за неделю: 800 МБ/сутки * 7 дней = 5.6 ГБ.
- Измененные данные за неделю (WAL): 1000 МБ/сутки * 7 дней = 7 ГБ.

Объем резервных копий на основном узле:

- Полные резервные копии:
    - Количество хранимых копий: 1 (поскольку срок хранения — 1 неделя).
    - Объем последней полной копии: 5.6 ГБ * 4 недели = 22.4 ГБ. (Предполагается, что каждая последующая полная копия включает накопленные данные за предыдущие недели).

- Архивы WAL:
    - Количество хранимых архивов: 1 неделя.
    - Общий объем WAL за неделю: 7 ГБ.

- Итого объем на основном узле = 22.4 ГБ (полные копии) + 7 ГБ (WAL) = 29.4 ГБ.

Объем резервных копий на резервном узле:

- Полные резервные копии:
    - Количество хранимых копий: 4 (поскольку срок хранения — 4 недели).
    - Общий объем полных копий за месяц: $S_n = \frac{n \cdot (2a_1 + (n-1)d)}{2} = \frac{4 \cdot (2 \cdot 5.6 + 3 \cdot 5.6)}{2} = 10 \cdot 5.6 = 56$ ГБ.

- Архивы WAL:
    - Количество хранимых архивов: 4 недели.
    - Общий объем WAL за месяц: 4 * 7 = 28 ГБ.

- Итого объем на резервном узле = 56 ГБ (полные копии) + 28 ГБ (WAL) = 84 ГБ.

Тем не менее из-за сжатия данных, объем резервных копий будет меньше.


## Этап 2. Потеря основного узла

Для будущей проверки добавим таблицу в базу данных на основном узле:
```sql
CREATE TABLE test_table (id SERIAL PRIMARY KEY, data TEXT);
INSERT INTO test_table (data) VALUES ('Hello, World!');
```
```
postgres=# CREATE TABLE test_table (id SERIAL PRIMARY KEY, data TEXT);
INSERT INTO test_table (data) VALUES ('Hello, World!');
CREATE TABLE
INSERT 0 1
postgres=# SELECT * FROM test_table;
 id |     data      
----+---------------
  1 | Hello, World!
(1 строка)
```

Выполним резервное копирование на основном узле:
```bash
bash ~/backup.sh >> ~/backup.log 2>&1
```

В резервном узле создадим скрипт для восстановления базы данных [`restore.sh`](./reserve_pg175/restore.sh):
```bash
#!/bin/sh

mkdir -p ~/khk43 #  новый каталог для PostgreSQL, как в предыдущей лабораторной работе
echo "Создан каталог ~/khk43"

cd ~/backups
BACKUP_DIR=$(ls -td */ | head -n 1) # выбираем последнюю резервную копию
cd $BACKUP_DIR
echo "Выбрана резервная копия $BACKUP_DIR"

tar -xzf base.tar.gz -C ~/khk43
tar -xzf pg_wal.tar.gz -C ~/khk43/pg_wal
echo "Распакована резервная копия"

# создание директорий для tablespaces по аналогии с предыдущей лабораторной работой
mkdir -p ~/mqb89
mkdir -p ~/utr38
echo "Созданы каталоги для tablespaces"

tar -xzf 16384.tar.gz -C ~/mqb89 # OID табличного пространства mqb89
tar -xzf 16385.tar.gz -C ~/utr38 # OID табличного пространства utr38
echo "Распакованы табличные пространства"

chown -R postgres0 ~/khk43
chmod 750 ~/khk43 # Маска прав должна быть u=rwx (0700) или u=rwx,g=rx (0750).
chown -R postgres0 ~/mqb89
chown -R postgres0 ~/utr38

cd ~
cp ~/pg_hba.conf ~/khk43
cp ~/postgresql.conf ~/khk43
cp ~/pg_ident.conf ~/khk43
echo "Скопированы .conf файлы"

# запуск PostgreSQL
pg_ctl -D ~/khk43 -l файл_журнала start

# Остановка PostgreSQL
pg_ctl -D ~/khk43 stop

# Изменяем символические ссылки на табличные пространства
cd ~/khk43/pg_tblspc
rm 16384
rm 16385
ln -s ~/mqb89 16384
ln -s ~/utr38 16385

cd ~
# Запуск PostgreSQL
pg_ctl -D ~/khk43 -l файл_журнала start
```

Загружаем скрипт на резервный узел:
```bash
scp -o "ProxyJump s372819@se.ifmo.ru:2222" reserve_pg175/restore.sh postgres0@pg175:~
```

Для возможности повторения сценария [`cleanup.sh`](./reserve_pg175/cleanup.sh) на резервном узле:
```bash
#!/bin/sh

pg_ctl -D ~/khk43 stop

# Копирование .conf файлов
cp ~/khk43/postgresql.conf ~/khk43/pg_hba.conf ~/khk43/pg_ident.conf ~

rm -rf ~/khk43
rm -rf ~/mqb89
rm -rf ~/utr38
```

Загружаем скрипт на резервный узел:
```bash
scp -o "ProxyJump s372819@se.ifmo.ru:2222" reserve_pg175/cleanup.sh postgres0@pg175:~
```
```bash
chmod +x cleanup.sh
```


Добавим в [pg_ident.conf](./reserve_pg175/pg_ident.conf) на резервном узле:
```conf
my_map          postgres0               postgres1
```

Загрузим изменения:
```bash
scp -o "ProxyJump s372819@se.ifmo.ru:2222" reserve_pg175/pg_ident.conf postgres0@pg175:~/khk43
```

Применим изменения:
```bash
pg_ctl -D ~/khk43 restart
```

Для проверки целостности данных на резервном узле выполним:
```bash
psql -p 9555 -d postgres -U postgres1
```
```sql
SELECT * FROM test_table;
```

Результат:
```
postgres=# SELECT * FROM test_table;
 id |     data      
----+---------------
  1 | Hello, World!
(1 строка)
```

## Этап 3. Повреждение файлов БД
### Симулирование сбоя

Для будущей проверки добавим таблицу в табличное пространство на основном узле:
```sql
CREATE TABLE test_table_mqb89 (id SERIAL PRIMARY KEY, data TEXT) TABLESPACE mqb89;
INSERT INTO test_table_mqb89 (data) VALUES ('Data in tablespace mqb89');
```
```sql
SELECT * FROM test_table_mqb89;
```
```
postgres=# SELECT * FROM test_table_mqb89;
 id |           data
----+--------------------------
  1 | Data in tablespace mqb89
(1 строка)
```

Пусть у нас выполнилось сохранение данных на основном узле:
```bash
bash ~/backup.sh >> ~/backup.log 2>&1
```

Симулируем сбой на основном узле, удалив директорию с табличным пространством:
```bash
rm -rf ~/mqb89
```

### Проверка работоспособности
Проверяем работу СУБД, пытаясь получить данные из таблицы ts_table:
```sql
psql -p 9555 -d postgres -U postgres1
SELECT * FROM test_table_mqb89;
```
Результат:
```
postgres=# SELECT * FROM test_table_mqb89;
ОШИБКА:  не удалось открыть файл "pg_tblspc/16384/PG_16_202307071/5/16430": No such file or directory
postgres=# 
```

Попробуем перезапустить СУБД:
```bash
pg_ctl -D ~/khk43 stop
pg_ctl -D ~/khk43 -l файл_журнала start
```
Результат:
```
[postgres1@pg167 ~]$ psql -p 9555 -d postgres -U postgres1
psql (16.4)
Введите "help", чтобы получить справку.

postgres=# SELECT * FROM test_table_mqb89;
ОШИБКА:  не удалось открыть файл "pg_tblspc/16384/PG_16_202307071/5/16430": No such file or directory
postgres=#
```

Как видим, СУБД смогла перезапуститься, так как PostgreSQL не требует наличия всех табличных пространств для запуска. Главное, чтобы не было ошибок в системных таблицах.
Тем не менее не смогла получить данные из таблицы, так как файлы табличного пространства были утеряны.

### Восстановление данных

Учитывая что исходное расположение табличного пространства недоступно, разместим его в другой директории и скорректируем конфигурацию.

[`recover_mqb89.sh`](./main_pg167/recover_mqb89.sh):
```bash
pg_ctl -D ~/khk43 stop

mkdir -p ~/new_mqb89
echo "Создана директория ~/new_mqb89"

cd ~/backups
BACKUP_DIR=$(ls -td */ | head -n 1) # выбираем последнюю резервную копию
cd $BACKUP_DIR
echo "Выбрана резервная копия $BACKUP_DIR"

tar -xzf 16384.tar.gz -C ~/new_mqb89
echo "Распаковано табличное пространство"

chown -R postgres1 ~/new_mqb89
chmod 750 ~/new_mqb89
echo "Установлены права доступа"

cd ~/khk43/pg_tblspc
rm 16384
ln -s ~/new_mqb89 16384
echo "Изменены символические ссылки"

cd ~
pg_ctl -D ~/khk43 -l файл_журнала start
```

Загружаем скрипт на основной узел:
```bash
scp -o "ProxyJump s372819@se.ifmo.ru:2222" main_pg167/recover_mqb89.sh postgres1@pg167:~
```

Сделаем скрипт исполняемым:
```bash
chmod +x recover_mqb89.sh
```

Выполним скрипт на основном узле:
```bash
bash ~/recover_mqb89.sh
```

Проверим работоспособность СУБД:
```bash
psql -p 9555 -d postgres -U postgres1
```
```sql
SELECT * FROM test_table_mqb89;
```
Результат:
```
[postgres1@pg167 ~]$ psql -p 9555 -d postgres -U postgres1
psql (16.4)
Введите "help", чтобы получить справку.

postgres=# SELECT * FROM test_table_mqb89;
 id |           data
----+--------------------------
  1 | Data in tablespace mqb89
(1 строка)

postgres=#
```

Как видим, данные восстановлены успешно.