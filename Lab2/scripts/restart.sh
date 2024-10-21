#!/bin/sh

# Остановка сервера.
pg_ctl -D ~/khk43 stop -m fast

# Удаление директорий.
rm -rf $HOME/khk43
rm -rf $HOME/oka84
rm -rf $HOME/utr38
rm -rf $HOME/mqb89
rm -rf $HOME/файл_журнала