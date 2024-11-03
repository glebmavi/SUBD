pg_ctl -D ~/khk43 stop

mkdir -p ~/new_mqb89
echo "Создана директория ~/new_mqb89"

cd ~/backups
BACKUP_DIR=$(ls -td */ | head -n 1) # выбираем последнюю резервную копию
cd $BACKUP_DIR
echo "Выбрана резервная копия $BACKUP_DIR"

tar -xzf 16384.tar.gz -C ~/new_mqb89
echo "Распаковано табличное пространство"

chown -R postgres1 ~/new_mqb89
chmod 750 ~/new_mqb89
echo "Установлены права доступа"

cd ~/khk43/pg_tblspc
rm 16384
ln -s ~/new_mqb89 16384
echo "Изменены символические ссылки"

cd ~
pg_ctl -D ~/khk43 -l файл_журнала start