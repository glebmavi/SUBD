\pset pager off

CREATE TABLESPACE mqb89 LOCATION '/var/db/postgres1/mqb89';
CREATE TABLESPACE utr38 LOCATION '/var/db/postgres1/utr38';
-- Проверка на существование табличных пространств:
SELECT spcname AS "Имя",
       pg_roles.rolname AS "Владелец",
       COALESCE(pg_tablespace_location(pg_tablespace.oid), '') AS "Расположение"
FROM pg_tablespace
JOIN pg_roles ON pg_tablespace.spcowner = pg_roles.oid
ORDER BY spcname;


CREATE DATABASE uglyredbird TEMPLATE template0;
-- Проверка на существование базы данных:
SELECT datname AS "Имя",
       pg_roles.rolname AS "Владелец",
       pg_encoding_to_char(encoding) AS "Кодировка",
       datcollate AS "LC_COLLATE",
       datctype AS "LC_CTYPE"
FROM pg_database
JOIN pg_roles ON pg_database.datdba = pg_roles.oid
ORDER BY datname;


CREATE ROLE newuser WITH LOGIN;  --Пароль не нужен так как используем подключение peer
-- Предоставить необходимые права
GRANT CONNECT, CREATE ON DATABASE uglyredbird TO newuser;
GRANT CREATE ON TABLESPACE mqb89 TO newuser;
GRANT CREATE ON TABLESPACE utr38 TO newuser;

-- Устанавливаем табличные пространства для временных объектов
ALTER SYSTEM SET temp_tablespaces = 'mqb89', 'utr38';

-- Перезагружаем конфигурацию
SELECT pg_reload_conf();