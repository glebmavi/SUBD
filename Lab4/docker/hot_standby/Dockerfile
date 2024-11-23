FROM postgres:latest

COPY conf/replica.conf /etc/postgresql/conf.d/replica.conf
COPY init/init-standby.sh /docker-entrypoint-initdb.d/init-standby.sh
RUN chmod +x /docker-entrypoint-initdb.d/init-standby.sh
