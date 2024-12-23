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
chmod -R 750 ~/khk43 ~/mqb89 ~/utr38 # Маска прав должна быть u=rwx (0700) или u=rwx,g=rx (0750).
chown -R postgres0 ~/mqb89
chown -R postgres0 ~/utr38
echo "Установлены права доступа"

touch ~/khk43/recovery.signal
chown postgres0 ~/khk43/recovery.signal
chmod -R 700 ~/khk43/recovery.signal
echo "Создан файл recovery.signal"

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