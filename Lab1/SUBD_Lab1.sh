#!/usr/bin/bash

# Запрашиваем у пользователя имя схемы
read -p "Введите имя схемы: " SCHEMA_NAME

# Проверяем, является ли имя схемы валидным в соответствии с правилами PostgreSQL
if [[ ! "$SCHEMA_NAME" =~ ^[a-zA-Z_][a-zA-Z0-9_$]*$ ]]; then
    echo "Название схемы '$SCHEMA_NAME' не является валидным в postgresql"
    exit 1
fi

# Выполняем анонимный блок PL/pgSQL через psql
psql -h pg -d studs -U s372819 -c "
DO \$\$
DECLARE
    schema_name text := '$SCHEMA_NAME';
    schema_exists BOOLEAN;
    r RECORD;
BEGIN

-- Проверяем существование схемы
SELECT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname = schema_name) INTO schema_exists;

IF NOT schema_exists THEN
    RAISE NOTICE 'Схемы не существует';
    RETURN;
END IF;

-- Форматированный вывод ограничений
RAISE NOTICE 'Номер | Имя ограничения                | Тип        | Имя таблицы                    | Имя столбца                    | Текст ограничения              ';
RAISE NOTICE '------|--------------------------------|------------|--------------------------------|--------------------------------|--------------------------------';

FOR r IN
    SELECT
        ROW_NUMBER() OVER () AS номер,
        conname AS имя_ограничения,
        CASE WHEN contype = 'c' THEN 'CHECK'
            END AS тип,
        relname AS имя_таблицы,
        attname AS имя_столбца,
        pg_get_constraintdef(pg_catalog.pg_constraint.oid) AS текст_ограничения
    FROM
        pg_catalog.pg_constraint
        JOIN
        pg_catalog.pg_class ON conrelid = pg_catalog.pg_class.oid
        JOIN
        pg_catalog.pg_namespace ON pg_catalog.pg_class.relnamespace = pg_catalog.pg_namespace.oid
        JOIN
        pg_catalog.pg_attribute ON attnum = ANY(conkey) AND attrelid = conrelid
    WHERE
        nspname = schema_name AND contype = 'c' -- NOT NULL находится в pg_attribute

    UNION ALL

    SELECT
        ROW_NUMBER() OVER () AS номер,
        'attnotnull' AS имя_ограничения, -- attnotnull - булевый атрибут в pg_attribute
        'NOT NULL' AS тип,
        relname AS имя_таблицы,
        attname AS имя_столбца,
        'IS NOT NULL' AS текст_ограничения
    FROM
        pg_catalog.pg_attribute
        JOIN
        pg_catalog.pg_class ON attrelid = pg_catalog.pg_class.oid
        JOIN
        pg_catalog.pg_namespace ON pg_catalog.pg_class.relnamespace = pg_catalog.pg_namespace.oid
    WHERE
        nspname = schema_name AND attnotnull = TRUE

    ORDER BY номер

    LOOP
    -- Форматирование вывода строк
        RAISE NOTICE '% | % | % | % | % | %',
            RPAD(r.номер::text, 5),
            RPAD(r.имя_ограничения, 30),
            RPAD(r.тип, 10),
            RPAD(r.имя_таблицы, 30),
            RPAD(r.имя_столбца, 30),
            RPAD(r.текст_ограничения, 30);
    END LOOP;
END \$\$;
" --tuples-only
