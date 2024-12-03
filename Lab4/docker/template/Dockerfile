FROM postgres:latest

RUN apt-get update && apt-get install -y iputils-ping

COPY conf/postgresql.conf /etc/postgresql/postgresql.conf
COPY conf/pg_hba.conf /etc/postgresql/pg_hba.conf

COPY init/init-master.sh /home/init/init-master.sh
COPY init/init-standby.sh /home/init/init-standby.sh

COPY scripts/init-db.sql /home/scripts/init-db.sql
COPY scripts/read_client.sh /home/scripts/read_client.sh
COPY scripts/write_client.sh /home/scripts/write_client.sh
COPY scripts/auto_promote.sh /home/scripts/auto_promote.sh

COPY scripts/custom-entrypoint.sh /home/scripts/custom-entrypoint.sh
RUN chmod +x /home/scripts/custom-entrypoint.sh

RUN chmod +x /home/scripts/read_client.sh
RUN chmod +x /home/scripts/write_client.sh
RUN chmod +x /home/init/init-master.sh
RUN chmod +x /home/init/init-standby.sh
RUN chmod +x /home/scripts/auto_promote.sh