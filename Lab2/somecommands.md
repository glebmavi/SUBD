Передача файлов на сервер:
```bash
cd ./Lab2
scp -P 2222 -r ./scripts s372819@se.ifmo.ru:~
scp -P 2222 -r ./configs s372819@se.ifmo.ru:~
ssh s372819@se.ifmo.ru -p 2222

scp -r ~/scripts postgres1@pg167:~
scp -r ~/configs postgres1@pg167:~
```

```
scp -r ./scripts postgres1@pg167.cs.ifmo.ru:~
```

Запуск скриптов на сервере:
```bash
./scripts/restart.sh
./scripts/SUBD_LAB2.sh
```

Подключение к postgres (type local, peer):
```bash
psql -p 9555 -d postgres
```

Подключение к postgres (type host, md5):
```bash
psql -p 9555 -h localhost -d postgres
```

Подключение к postgres (type host, md5) из Гелиоса:
```bash
psql -p 9555 -h pg167 -d postgres -U testuser # password: testpassword
```


