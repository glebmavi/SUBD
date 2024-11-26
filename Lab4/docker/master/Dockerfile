FROM postgres:latest

COPY conf/postgresql.conf /etc/postgresql/postgresql.conf
COPY conf/pg_hba.conf /etc/postgresql/pg_hba.conf
COPY init/init-master.sh /docker-entrypoint-initdb.d/init-master.sh
COPY scripts/init-db.sql /home/scripts/init-db.sql
COPY scripts/read_client.sh /home/scripts/read_client.sh
COPY scripts/write_client.sh /home/scripts/write_client.sh
RUN chmod +x /home/scripts/read_client.sh
RUN chmod +x /home/scripts/write_client.sh
RUN chmod +x /docker-entrypoint-initdb.d/init-master.sh
