FROM postgres:latest

COPY conf/postgresql.conf /etc/postgresql/postgresql.conf
COPY conf/pg_hba.conf /etc/postgresql/pg_hba.conf
COPY init/init-master.sh /docker-entrypoint-initdb.d/init-master.sh
COPY scripts/init-db.sql /docker-entrypoint-initdb.d/init-db.sql
RUN chmod +x /docker-entrypoint-initdb.d/init-master.sh
