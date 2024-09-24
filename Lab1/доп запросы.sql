SELECT relname
    FROM pg_catalog.pg_class JOIN pg_catalog.pg_namespace ON pg_class.relnamespace = pg_namespace.oid
    WHERE nspname = 's372819' AND reltype != 0;