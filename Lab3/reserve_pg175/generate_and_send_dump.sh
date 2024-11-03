#!/bin/sh

# Ожидаем что существует актуальная резервная копия в '~/backups'
cd ~
./cleanup.sh
./restore.sh

# Генерация дампа
pg_dump -p 9555 -U postgres1 -d postgres > ~/pg_dump.sql
echo "Сгенерирован дамп"

# Отправка дампа на основной узел
scp ~/pg_dump.sql postgres1@pg167:~
echo "Дамп отправлен"