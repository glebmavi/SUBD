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

Редактируем файл `postgresql.conf`:

Способы подключения:
```conf
# - Connection Settings -

listen_addresses = '*'		# what IP address(es) to listen on;
					# comma-separated list of addresses;
					# defaults to 'localhost'; use '*' for all
					# (change requires restart)
port = 9555				# (change requires restart)
max_connections = 100			# (change requires restart)
```