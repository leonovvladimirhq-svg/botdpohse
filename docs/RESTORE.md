# Восстановление проекта с нуля

Три сценария — от простого к тяжёлому. Перед стартом откройте
[SERVICES.md](SERVICES.md): там все аккаунты и где брать ключи.

---

## Сценарий А. Новый компьютер, сервер жив

Бот продолжает работать — нужно лишь вернуть себе возможность его обслуживать.

1. **Код:**
   ```bash
   git clone https://github.com/leonovvladimirhq-svg/botdpohse.git
   ```
2. **Доступ к серверу по SSH.** Если ключ `~/.ssh/yc_faqbot_key` не сохранился —
   сделать новый и добавить его на ВМ:
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/yc_faqbot_key
   ```
   Консоль Yandex Cloud → каталог `project2-chatbotdpo` → ВМ `faqbot` → «Изменить» →
   «Метаданные» → ключ `ssh-keys`, значение `yc-user:<содержимое yc_faqbot_key.pub>`.
   Проверка: `ssh -i ~/.ssh/yc_faqbot_key yc-user@93.77.187.243`.
3. **yc CLI** (по желанию, для управления облаком): установить, `yc init` под своей
   учётной записью Yandex Cloud либо с ключом сервисного аккаунта `leonov-deployer`.
4. **Cloudflare** (нужно только чтобы менять релей): `cd relay && npx wrangler login`.
5. **`.env`** — локальные копии не обязательны: оригиналы лежат на сервере
   (`/opt/maxbot/.env`, `/opt/faqbot/.env`).

---

## Сценарий Б. Сервер потерян (ВМ удалили или она не поднимается)

### 1. Создать ВМ
Консоль Yandex Cloud → каталог `project2-chatbotdpo` → Compute Cloud → «Создать ВМ»:
- Ubuntu 22.04, зона `ru-central1-a`, 2 vCPU (гарантированная доля 5%), 1 ГБ RAM, 10 ГБ HDD;
- **публичный адрес — выбрать из списка статический `faqbot-static-ip` (93.77.187.243)**,
  если он ещё существует. Тогда релей Telegram трогать не придётся;
- пользователь `yc-user`, SSH-ключ — публичная часть `yc_faqbot_key`.

Если статического адреса больше нет: получите новый, **зарезервируйте его**
(сделать статическим) и впишите в `ALLOWED_IPS` в `relay/wrangler.toml`, затем
`cd relay && npx wrangler deploy`.

### 2. Подготовить сервер
```bash
ssh -i ~/.ssh/yc_faqbot_key yc-user@<IP>
sudo apt update && sudo apt install -y docker.io docker-compose-v2
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab      # 1 ГБ RAM мало для сборки без swap
sudo mkdir -p /opt/maxbot /opt/faqbot && sudo chown yc-user: /opt/maxbot /opt/faqbot
```

### 3. Залить код (с компьютера, из корня репозитория)
```bash
scp -i ~/.ssh/yc_faqbot_key maxbot/{maxbot.py,FAQ_DPO_HSE_v5.docx,Dockerfile,docker-compose.yml,requirements.txt,.dockerignore} yc-user@<IP>:/opt/maxbot/
scp -i ~/.ssh/yc_faqbot_key {bot.py,FAQ_DPO_HSE_v5.docx,Dockerfile,docker-compose.yml,requirements.txt,.dockerignore} yc-user@<IP>:/opt/faqbot/
```

### 4. Вернуть `.env`
Скопировать локальные копии (`C:\Chatbot_DPO\maxbot\.env` → `/opt/maxbot/.env`,
`C:\Chatbot_DPO\bot\.env` → `/opt/faqbot/.env`) или собрать заново по
`.env.example`, перевыпустив ключи по [SERVICES.md](SERVICES.md).

### 5. Вернуть данные (если есть бэкап)
Логи вопросов и эскалаций — в папке бэкапа `server-data/` (см. «Где бэкапы» ниже):
```bash
mkdir -p /opt/maxbot/data /opt/faqbot/data
# с компьютера:
scp -i ~/.ssh/yc_faqbot_key server-data/maxbot/*.csv yc-user@<IP>:/opt/maxbot/data/
scp -i ~/.ssh/yc_faqbot_key server-data/faqbot/questions_log.csv yc-user@<IP>:/opt/faqbot/data/
```
Без бэкапа бот создаст пустые логи сам — работать это не мешает.

### 6. Запустить
```bash
cd /opt/maxbot && sudo docker compose up -d --build
cd /opt/faqbot && sudo docker compose up -d --build
```

### 7. Проверить (чек-лист)
- [ ] `sudo docker ps` — `maxbot` и `faqbot` в статусе `Up`, а не `Restarting`.
- [ ] `sudo docker logs maxbot` — «Документ загружен: FAQ_DPO_HSE_v5.docx», «Бот запущен: …@se14233220_bot».
- [ ] `sudo docker logs faqbot` — «Telegram Bot API через релей», `getUpdates … 200 OK`.
- [ ] С ВМ: `curl https://tg-relay-dpo.leonov-vladimir-hq.workers.dev/check` → 404 «Ожидается путь…»
      (если 403 — IP ВМ не совпадает с `ALLOWED_IPS`).
- [ ] Написать боту в MAX и в Telegram `/start`, задать вопрос, получить ответ.
- [ ] Через минуту вопрос виден на дашборде `http://89.169.146.175:8080`.

---

## Сценарий В. Откатить неудачное изменение

- **Код:** у каждого бэкапа есть тег `backup/<дата>`:
  ```bash
  git checkout backup/2026-10-04 -- maxbot/maxbot.py    # вернуть один файл
  ```
  затем залить файл на сервер и пересобрать контейнер.
- **На сервере** перед каждым изменением остаются копии `*.bak-<метка>` рядом с файлом
  (`/opt/maxbot/maxbot.py.bak-catalog` и т. п.): `cp maxbot.py.bak-catalog maxbot.py`
  и `sudo docker compose up -d --build`.

---

## Где бэкапы

| Что | Где | Как сделать заново |
|---|---|---|
| Весь git-репозиторий с историей | `C:\Chatbot_DPO\_backups\<дата>\botdpohse-<дата>.bundle` | `git bundle create <файл> --all` |
| Логи вопросов/эскалаций с сервера | `C:\Chatbot_DPO\_backups\<дата>\server-data\` | `scp` из `/opt/*/data/` |
| Код и документация | GitHub, тег `backup/<дата>` | `git tag backup/<дата> && git push origin --tags` |

Восстановить репозиторий из bundle, если GitHub недоступен:
```bash
git clone botdpohse-2026-10-04.bundle botdpohse
```

⚠️ `server-data/` содержит персональные данные слушателей. Хранить только на
носителях в РФ, в git и в иностранные облака не класть. История бэкапов —
[BACKUP_LOG.md](BACKUP_LOG.md).
