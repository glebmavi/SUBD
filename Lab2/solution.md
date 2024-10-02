PGUSERNAME=postgres1
PGDATA=$HOME/khk43
PGENCODE=ISO_8859_5
PGLOCALE=ru_RU.ISO8859-5
export PGUSERNAME PGDATA PGENCODE PGLOCALE

# Этап 1. Инициализация кластера БД

mkdir -p $PGDATA
chown $PGUSERNAME $PGDATA
initdb -D $PGDATA --encoding=$PGENCODE --locale=$PGLOCALE --username=$PGUSERNAME

![Step 1 result](image.png)

# Этап 2. Конфигурация и запуск сервера БД

Скачиваем конфигурационные файлы:

scp postgres1@pg167:khk43/postgresql.conf ~
scp postgres1@pg167:khk43/pg_hba.conf ~

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
chown $PGUSERNAME:$PGUSERNAME $HOME/oka84
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