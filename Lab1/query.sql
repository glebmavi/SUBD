SET my.schema_name TO :'schema_name';

DO $$
DECLARE
    schema_name TEXT := current_setting('my.schema_name');
    schema_exists BOOLEAN;
    r RECORD;
BEGIN

RAISE NOTICE 'Проверка существования схемы %', schema_name;
SELECT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname = schema_name) INTO schema_exists;

IF NOT schema_exists THEN
    RAISE NOTICE 'Схемы не существует';
    RETURN;
END IF;

-- Форматированный вывод ограничений
RAISE NOTICE 'Номер | Имя ограничения                | Тип        | Имя таблицы                    | Имя столбца                    | Текст ограничения              ';
RAISE NOTICE '------|--------------------------------|------------|--------------------------------|--------------------------------|--------------------------------';

-- Основной цикл для вывода ограничений
FOR r IN
    WITH constraints AS (
        -- Получаем CHECK ограничения
        SELECT
            conname AS имя_ограничения,
            'CHECK' AS тип,
            relname AS имя_таблицы,
            attname AS имя_столбца,
            pg_catalog.pg_get_expr(pg_constraint.conbin, conrelid) AS текст_ограничения
        FROM
            pg_constraint
            JOIN pg_class ON conrelid = pg_class.oid
            JOIN pg_namespace ON pg_class.relnamespace = pg_namespace.oid
            JOIN pg_attribute ON attnum = ANY(conkey) AND attrelid = conrelid
        WHERE
            nspname = schema_name AND contype = 'c'
        
        UNION ALL
        
        -- Получаем NOT NULL ограничения
        SELECT
            'attnotnull' AS имя_ограничения,
            'NOT NULL' AS тип,
            relname AS имя_таблицы,
            attname AS имя_столбца,
            'IS NOT NULL' AS текст_ограничения
        FROM
            pg_attribute
            JOIN pg_class ON attrelid = pg_class.oid
            JOIN pg_namespace ON pg_class.relnamespace = pg_namespace.oid
        WHERE
            nspname = schema_name AND attnotnull = TRUE
    )
    SELECT 
        ROW_NUMBER() OVER () AS номер,
        * 
    FROM 
        constraints
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
END $$ LANGUAGE plpgsql;