FROM postgres:latest
COPY conf/postgresql.conf /etc/postgresql/postgresql.conf
COPY conf/pg_hba.conf /etc/postgresql/pg_hba.conf
COPY init/init-standby.sh /docker-entrypoint-initdb.d/init-standby.sh
COPY scripts/read_client.sh /home/scripts/read_client.sh
RUN chmod +x /home/scripts/read_client.sh
RUN chmod +x /docker-entrypoint-initdb.d/init-standby.sh

RUN apt-get update && apt-get install -y iputils-ping
