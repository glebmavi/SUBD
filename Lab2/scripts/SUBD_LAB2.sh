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

initdb -D $PGDATA --encoding=$PGENCODE --locale=$PGLOCALE --username=$PGUSERNAME

cp ~/configs/* $PGDATA # Предполагается, что в директории configs лежат файлы postgresql.conf, pg_hba.conf и pg_ident.conf.

pg_ctl -D /var/db/postgres1/khk43 -l файл_журнала start

pg_ctl -D ~/khk43 status

# Создание табличных пространств.
mkdir -p /var/db/postgres1/mqb89
mkdir -p /var/db/postgres1/utr38

psql -p 9555 -d postgres -f $HOME/scripts/tablespaces.sql

# Создание таблиц, заполнение их данными и вывод результатов.
psql -p 9555 -d uglyredbird -U newuser -f $HOME/scripts/newuser.sql

# Остановка сервера.
pg_ctl -D ~/khk43 stop -m fast