#!/bin/sh

pg_ctl -D ~/khk43 stop

# Копирование .conf файлов
cp ~/khk43/postgresql.conf ~/khk43/pg_hba.conf ~/khk43/pg_ident.conf ~
echo "Скопированы .conf файлы"

rm -rf ~/khk43
rm -rf ~/mqb89
rm -rf ~/utr38
echo "Удалены каталоги"