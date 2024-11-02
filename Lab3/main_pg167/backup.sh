#!/bin/sh

CURRENT_DATE=$(date "+%Y-%m-%d_%H:%M:%S")
BACKUP_DIR="$HOME/backups/$CURRENT_DATE"
mkdir -p "$BACKUP_DIR"

# Создаем полную резервную копию
pg_basebackup -D "$BACKUP_DIR" -F tar -z -P -p 9555 # 9555 - порт указанный в основном узле postgresql.conf

# Копируем резервную копию на резервный узел
scp "$BACKUP_DIR"/*.tar.gz postgres0@pg175:~/backups/$CURRENT_DATE/

# Удаляем резервные копии старше 7 дней на основном узле
find $HOME/backups/ -type d -mtime +7 -exec rm -rf {} \;

# Удаляем WAL-файлы старше 7 дней на основном узле
find $HOME/oka84/ -type f -mtime +7 -exec rm -f {} \; # по предыдущему заданию WAL-файлы хранятся в '~/oka84/'

# Удаляем резервные копии старше 28 дней на резервном узле
ssh postgres0@pg175 'find ~/backups/ -type d -mtime +28 -exec rm -rf {} \;'

# Удаляем WAL-файлы старше 28 дней на резервном узле
ssh postgres0@pg175 'find ~/wal_archive/ -type f -mtime +28 -exec rm -f {} \;'