#!/usr/bin/bash

# Запрашиваем у пользователя имя схемы
read -p "Введите имя схемы: " input

# Проверяем, является ли имя схемы валидным в соответствии с правилами PostgreSQL
if [[ ! "$input" =~ ^[a-zA-Z_][a-zA-Z0-9_$]*$ ]]; then
    echo "Название схемы '$input' не является валидным в PostgreSQL"
    exit 1
fi

psql -h pg -d studs -U s372819 -v schema_name=$input -f query.sql
