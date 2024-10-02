Определим переменные окружения:
```bash
PGUSERNAME=postgres1
PGDATA=$HOME/khk43
PGENCODE=ISO_8859_5
PGLOCALE=ru_RU.ISO8859-5
export PGUSERNAME PGDATA PGENCODE PGLOCALE
```

# Этап 1. Инициализация кластера БД

Создаем директорию кластера и инициализируем базу данных:
```bash
mkdir -p $PGDATA
chown $PGUSERNAME $PGDATA
initdb -D $PGDATA --encoding=$PGENCODE --locale=$PGLOCALE --username=$PGUSERNAME
```

![Step 1 result](image.png)

# Этап 2. Конфигурация и запуск сервера БД

Скачиваем конфигурационные файлы:

```bash
scp postgres1@pg167:khk43/postgresql.conf ~
scp postgres1@pg167:khk43/pg_hba.conf ~
```

## Способы подключения:
Редактируем файл `postgresql.conf`:
 - сокет TCP/IP, принимать подключения к любому IP-адресу узла
 - Номер порта: 9555
```conf
# - Connection Settings -

listen_addresses = '*'		# what IP address(es) to listen on;
					# comma-separated list of addresses;
					# defaults to 'localhost'; use '*' for all
					# (change requires restart)
port = 9555				# (change requires restart)
```

Редактируем файл `pg_hba.conf`:
 - Unix-domain сокет в режиме peer
 - Способ аутентификации TCP/IP клиентов: по имени пользователя
 - Остальные способы подключений запретить.
Из-за проблем ident в Гелиос, меняем на md5.

```conf
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Разрешить локальные подключения через Unix-domain сокет с аутентификацией peer
local   all             all                                     peer
# Разрешить TCP/IP подключения со всех IP-адресов с аутентификацией по имени пользователя (ident)
host    all             all             0.0.0.0/0               md5
host    all             all             ::/0                    md5
# Запретить все остальные подключения
local   replication     all                                     reject
host    replication     all             127.0.0.1/32            reject
host    replication     all             ::1/128                 reject
```
`postgresql.conf`:
```conf
password_encryption = md5	# scram-sha-256 or md5
```

## Настроить следующие параметры сервера БД:
**max_connections**:
```conf
max_connections = 100
```

**shared_buffers**:
Ставим 1/4 от оперативной памяти согласно документации [postgresql](https://www.postgresql.org/docs/current/runtime-config-resource.html#GUC-SHARED-BUFFERS), т.е. 1ГБ.
```conf
shared_buffers = 1GB
```

**temp_buffers**:
Количество памяти, выделенной для временных таблиц на одну сессию. Учитывая максимальное количество соединений, temp_buffers займут 100 * 16MB = 1600MB.
```conf
temp_buffers = 16MB
```

**work_mem**:
Количество памяти, выделенной для операций сортировки и хеширования на одно соединение. Не зная какого вида операции будут производиться, (сложные соединения и сортировки или простые запросы) то оставляем значение по умолчанию 4MB. Work_mem максимально может занимать 100 * 4MB = 400MB.
```conf
work_mem = 4MB
```

**checkpoint_timeout**:
Интервал времени между контрольными точками (checkpoints). Контрольные точки обеспечивают согласованность данных на диске. Учитывая, что у нас HDD, более длинный интервал времени между контрольными точками уменьшит нагрузку на диск.
```conf
checkpoint_timeout = 15min
```
**effective_cache_size**:
Этот параметр представляет собой оценку для планировщика о количестве дискового кэша, доступного для PostgreSQL. Это значение должно быть больше shared_buffers. Учитывая, что у нас HDD, то операции ввода-вывода будут медленными, поэтому считывание из кэша будет предпочтительнее. Так, ставим 75% от оперативной памяти, т.е. 3ГБ.
```conf
effective_cache_size = 3GB
```
**fsync**:
Этот параметр должен быть включен для обеспечения безопасности данных в случае сбоя системы. Отключение этого параметра может улучшить производительность, но риск потери данных в случае сбоя неприемлем для большинства производственных систем.
```conf
fsync = on
```
**commit_delay**:
Этот параметр задает задержку в миллисекундах перед сохранением WAL. Без тестирования, сложно подобрать оптимальное значение. По умолчанию 0.
```conf
commit_delay = 0
```

## WAL файлы и логирование:

**Директория WAL файлов**:

Создадим директорию для WAL файлов:
```bash
mkdir -p $HOME/oka84
chown $PGUSERNAME $HOME/oka84
```

В `postgresql.conf`:
`archive_mode` - включает архивирование WAL файлов.
`archive_command` - команда, которая будет выполняться для архивирования WAL файлов. В данном случае, копируем файл в директорию $HOME/oka84.
```conf
archive_mode = on
archive_command = 'cp %p $HOME/oka84/%f'
```

**Формат лог-файлов**:
В `postgresql.conf`:
`log_destination` - куда писать логи. В данном случае, в файл csv.
`logging_collector` - включает сборщик логов и позволяет перенаправлять в файлы.
`log_directory` - директория для логов. Оставляем по умолчанию.
`log_filename` - формат имени файла лога. Ставим формат csv.

```conf
log_destination = 'csvlog'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.csv'
```

**Уровень сообщений лога**:
`log_min_messages` - минимальный уровень сообщений, которые будут записаны в лог. В данном случае, только ошибки и выше.
```conf
log_min_messages = error
```

**Дополнительно логировать**:
`log_connections` - логировать подключения.
`log_disconnections` - логировать отключения. Оба параметра используем для отслеживания завершения сессий.
`log_duration` - логировать продолжительность выполнения команд.
`log_min_duration_statement` - минимальная продолжительность выполнения команды, которая будет логироваться. В данном случае, 0 - логировать все команды.
```conf
log_connections = on
log_disconnections = on
log_duration = on
log_min_duration_statement = 0
```

## Запуск сервера БД

Загрузим обратно конфигурационные файлы:
```bash
scp ~/postgresql.conf postgres1@pg167:khk43
scp ~/pg_hba.conf postgres1@pg167:khk43
```

Запускаем сервер:
```bash
pg_ctl -D /var/db/postgres1/khk43 -l файл_журнала start
```

## Проверка всех параметров

**Статус сервера**:
```bash
pg_ctl -D ~/khk43 status
```
```output
[postgres1@pg167 ~]$ pg_ctl -D ~/khk43 status
pg_ctl: сервер работает (PID: 63080)
/usr/local/bin/postgres "-D" "/var/db/postgres1/khk43"
```


**Остановка сервера**:
```bash
pg_ctl -D ~/khk43 stop -m fast
```


**Подключение локально**:
```bash
psql -p 9555 -d postgres
```
```output
[postgres1@pg167 ~]$ psql -p 9555 -d postgres
psql (16.4)
Введите "help", чтобы получить справку.

postgres=#
```

**Подключение удаленно**:
Создадим нового пользователя PostgreSQL с паролем:
```sql
CREATE ROLE testuser WITH LOGIN PASSWORD 'testpassword';
```

Попробуем подключиться удаленно:
```bash
psql -h pg167 -p 9555 -U testuser -d postgres
```
```output
[s372819@helios ~]$ psql -h pg167 -p 9555 -U testuser -d postgres
Пароль пользователя testuser: 
psql (16.4)
Введите "help", чтобы получить справку.

postgres=> 
```

**Проверка параметров**:
```sql
SHOW max_connections;
SHOW shared_buffers;
SHOW temp_buffers;
SHOW work_mem;
SHOW checkpoint_timeout;
SHOW effective_cache_size;
SHOW fsync;
SHOW commit_delay;
```
```output
postgres=# SHOW max_connections;
SHOW shared_buffers;
SHOW temp_buffers;
SHOW work_mem;
SHOW checkpoint_timeout;
SHOW effective_cache_size;
SHOW fsync;
SHOW commit_delay;
 max_connections 
-----------------
 100
(1 строка)

 shared_buffers
----------------
 1GB
(1 строка)

 temp_buffers
--------------
 16MB
(1 строка)

 work_mem
----------
 4MB
(1 строка)

 checkpoint_timeout
--------------------
 15min
(1 строка)

 effective_cache_size
----------------------
 3GB
(1 строка)

 fsync
-------
 on
(1 строка)

 commit_delay
--------------
 0
(1 строка)

postgres=# 
```

# Этап 3. Дополнительные табличные пространства и наполнение базы

## Создание табличных пространств

```bash
mkdir -p /var/db/postgres1/mqb89
mkdir -p /var/db/postgres1/utr38
```

```sql
CREATE TABLESPACE mqb89 LOCATION '/var/db/postgres1/mqb89';
CREATE TABLESPACE utr38 LOCATION '/var/db/postgres1/utr38';
```

**Проверка**:
```sql
\db
```
```output
postgres=# \db
           Список табличных пространств
    Имя     | Владелец  |      Расположение
------------+-----------+-------------------------
 mqb89      | postgres1 | /var/db/postgres1/mqb89
 pg_default | postgres1 | 
 pg_global  | postgres1 |
 utr38      | postgres1 | /var/db/postgres1/utr38
(4 строки)
```

## Создание базы данных

```sql
CREATE DATABASE uglyredbird TEMPLATE template0;
```

**Проверка**:
```sql
\l
```
```output
postgres=# \l
                                                                Список баз данных
     Имя     | Владелец  | Кодировка  | Провайдер локали |   LC_COLLATE    |    LC_CTYPE     | локаль ICU | Правила ICU |      Права доступа      
-------------+-----------+------------+------------------+-----------------+-----------------+------------+-------------+-------------------------
 postgres    | postgres1 | ISO_8859_5 | libc             | ru_RU.ISO8859-5 | ru_RU.ISO8859-5 |            |             | 
 template0   | postgres1 | ISO_8859_5 | libc             | ru_RU.ISO8859-5 | ru_RU.ISO8859-5 |            |             | =c/postgres1           +
             |           |            |                  |                 |                 |            |             | postgres1=CTc/postgres1
 template1   | postgres1 | ISO_8859_5 | libc             | ru_RU.ISO8859-5 | ru_RU.ISO8859-5 |            |             | =c/postgres1           +
             |           |            |                  |                 |                 |            |             | postgres1=CTc/postgres1
 uglyredbird | postgres1 | ISO_8859_5 | libc             | ru_RU.ISO8859-5 | ru_RU.ISO8859-5 |            |             |
(4 строки)
```

## Создание роли

```sql
CREATE ROLE newuser WITH LOGIN;  --Пароль не нужен так как используем подключение peer
-- Предоставить необходимые права
GRANT CONNECT, CREATE ON DATABASE uglyredbird TO newuser;
GRANT CREATE ON TABLESPACE mqb89 TO newuser;
GRANT CREATE ON TABLESPACE utr38 TO newuser;
```

## От имени новой роли (не администратора) произвести наполнение ВСЕХ созданных баз тестовыми наборами данных. ВСЕ табличные пространства должны использоваться по назначению.
Запускаем скрипт наполнения базы от имени нового пользователя:
```bash
psql -p 9555 -d uglyredbird -U newuser -f $HOME/creating.sql
```

Запускаем скрипт наполнения таблиц от имени нового пользователя:
```bash
psql -p 9555 -d uglyredbird -U newuser -f $HOME/inserting.sql
```

**Проверка**:
```sql
SELECT * FROM pg_catalog.pg_tables WHERE tableowner = 'newuser';
```
```output
uglyredbird=> SELECT * FROM pg_catalog.pg_tables WHERE tableowner = 'newuser';
 schemaname |       tablename        | tableowner | tablespace | hasindexes | hasrules | hastriggers | rowsecurity 
------------+------------------------+------------+------------+------------+----------+-------------+-------------
 main       | students               | newuser    |            | t          | f        | f           | f
 main       | courses                | newuser    |            | t          | f        | f           | f
 pg_temp_3  | temp_enrollments       | newuser    | mqb89      | t          | f        | f           | f
 pg_temp_3  | temp_course_statistics | newuser    | utr38      | f          | f        | f           | f
(4 строки)
```

## Вывести список всех табличных пространств кластера и содержащиеся в них объекты
Выведем все табличные пространства
```sql
SELECT * FROM pg_tablespace;
```
```output
uglyredbird=> SELECT * FROM pg_tablespace;
  oid  |  spcname   | spcowner |                   spcacl                    | spcoptions 
-------+------------+----------+---------------------------------------------+------------
  1663 | pg_default |       10 |                                             |
  1664 | pg_global  |       10 |                                             |
 16389 | mqb89      |       10 | {postgres1=C/postgres1,newuser=C/postgres1} |
 16390 | utr38      |       10 | {postgres1=C/postgres1,newuser=C/postgres1} |
(4 строки)
```

Выведем все объекты в табличных пространствах
```sql
SELECT
    spcname AS tablespace,
    relname
FROM
    pg_class
    LEFT JOIN pg_tablespace ON pg_tablespace.oid = reltablespace;
```


Выведем все объекты созданные новым пользователем:
```sql
SELECT
    oid, relname, reltablespace
FROM
    pg_class
WHERE
    relowner = (SELECT oid FROM pg_roles WHERE rolname = 'newuser');
```
```output
  oid  |           relname            | reltablespace 
-------+------------------------------+---------------
 16395 | students_student_id_seq      |             0
 16396 | students                     |             0
 16400 | students_pkey                |             0
 16402 | courses_course_id_seq        |             0
 16403 | courses                      |             0
 16407 | courses_pkey                 |             0
 16433 | temp_enrollments_temp_id_seq |             0
 16434 | temp_enrollments             |         16389
 16438 | temp_enrollments_pkey        |             0
 16440 | temp_course_statistics       |         16390
(10 строк)
```