#!/bin/sh

cp khk43/pg_ident.conf pg_ident.conf
cp khk43/pg_hba.conf pg_hba.conf
cp khk43/postgresql.conf postgresql.conf
rm -rf ~/khk43/*
cd ~/backups/
BACKUP_DIR=$(ls -td */ | head -n 1) # выбираем последнюю резервную копию
cd $BACKUP_DIR
tar -xzf base.tar.gz -C ~/khk43
tar -xzf pg_wal.tar.gz -C ~/khk43/pg_wal

cp ~/pg_ident.conf ~/khk43/pg_ident.conf
cp ~/pg_hba.conf ~/khk43/pg_hba.conf
cp ~/postgresql.conf ~/khk43/postgresql.conf

touch ~/khk43/recovery.signal

pg_ctl -D ~/khk43 -l файл_журнала start