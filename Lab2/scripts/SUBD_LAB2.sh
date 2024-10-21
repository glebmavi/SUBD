#!/bin/sh

# Создание базы данных.
# Скрипт требует готовых .conf файлов.
PGUSERNAME=postgres1
PGDATA=$HOME/khk43
PGENCODE=ISO_8859_5
PGLOCALE=ru_RU.ISO8859-5
export PGUSERNAME PGDATA PGENCODE PGLOCALE

mkdir -p $PGDATA
chown $PGUSERNAME $PGDATA

mkdir -p $HOME/oka84
chown $PGUSERNAME $HOME/oka84

initdb -D $PGDATA --encoding=$PGENCODE --locale=$PGLOCALE --username=$PGUSERNAME --waldir=$HOME/oka84

cp ~/configs/* $PGDATA # Предполагается, что в директории configs лежат файлы postgresql.conf, pg_hba.conf и pg_ident.conf.
echo "copied configs"

# Тоже вариант, но в данном случае ставится через initdp параметр --waldir.
#mv khk43/pg_wal oka84/pg_wal
#ln -s ~/oka84/pg_wal/ khk43/pg_wal
#echo "moved pg_wal and created symlink"

pg_ctl -D /var/db/postgres1/khk43 -l файл_журнала start

pg_ctl -D ~/khk43 status

# Создание директорий для табличных пространств.
mkdir -p /var/db/postgres1/mqb89
mkdir -p /var/db/postgres1/utr38

psql -p 9555 -d postgres -f $HOME/scripts/tablespaces.sql
# Добавление пользователя с паролем для проверки удалённого подключения.
psql -p 9555 -d postgres -f $HOME/scripts/testuser.sql

# подключение через tcp/ip локально
psql -p 9555 -U testuser -d postgres -h localhost # the password is "testpassword"

# Создание таблиц, заполнение их данными и вывод результатов.
psql -p 9555 -d uglyredbird -U newuser -f $HOME/scripts/newuser.sql
