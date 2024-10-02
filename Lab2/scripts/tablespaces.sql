CREATE TABLESPACE mqb89 LOCATION '/var/db/postgres1/mqb89';
CREATE TABLESPACE utr38 LOCATION '/var/db/postgres1/utr38';
CREATE DATABASE uglyredbird TEMPLATE template0;
CREATE ROLE newuser WITH LOGIN;  --Пароль не нужен так как используем подключение peer
-- Предоставить необходимые права
GRANT CONNECT, CREATE ON DATABASE uglyredbird TO newuser;
GRANT CREATE ON TABLESPACE mqb89 TO newuser;
GRANT CREATE ON TABLESPACE utr38 TO newuser;