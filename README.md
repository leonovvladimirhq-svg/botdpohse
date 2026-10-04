# Чат-Бот ДПО Школа коммуникаций НИУ ВШЭ

Бот отвечает слушателям на вопросы о программах дополнительного профессионального
образования (ДПО) Школы коммуникаций НИУ ВШЭ: поступление, договор, оплата, скидки,
удостоверения, платформа обучения. Ответы — **строго по FAQ-документу**; формулирует
их модель **Qwen 3.6 35B в Yandex AI Studio**.

| Канал | Код | Статус |
|---|---|---|
| 🟢 **MAX** — основной | [`maxbot/`](./maxbot/) | Работает. Бот «Чат-Бот ДПО Школа Коммуникаций» `@se14233220_bot` |
| 🟢 **Telegram** — дополнительный | корень репозитория + [`relay/`](./relay/) | Работает через посредника на Cloudflare. Бот `@hse_dpo_faq_bot` |

Оба бота — на одной ВМ в Yandex Cloud (`93.77.187.243`), независимыми Docker-контейнерами:
любой можно выключить, не трогая второй.

## Документация

| Документ | Что там |
|---|---|
| [docs/SERVICES.md](docs/SERVICES.md) | Внешние сервисы, аккаунты, где лежат ключи и как их перевыпустить |
| [docs/RESTORE.md](docs/RESTORE.md) | Как восстановить всё с нуля: новый компьютер, потеря сервера, откат |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Важные решения и почему они такие; открытые юридические вопросы |
| [docs/CHANGELOG.md](docs/CHANGELOG.md) | Что менялось по датам |
| [docs/BACKUP_LOG.md](docs/BACKUP_LOG.md) | Журнал бэкапов |
| [maxbot/README.md](maxbot/README.md) | Особенности MAX и его Bot API |
| [relay/README.md](relay/README.md) | Посредник Telegram: развёртывание и эксплуатация |
| [CLAUDE.md](CLAUDE.md) | Правила для ИИ-ассистента, который правит проект |

---

## Что делает бот

1. Пользователь открывает бота или пишет `/start` — приветствие и меню из трёх кнопок:
   - **❓ Задать вопрос помощнику** — режим вопросов и ответов;
   - **📞 Связаться с менеджером** — контакты ДПО (MAX, почта, телефон); нажатие считается
     **эскалацией** и видно на дашборде отдельной метрикой;
   - **📋 Часто задаваемые вопросы** — ссылка на полный FAQ на Яндекс Диске.
2. Вопрос уходит в модель вместе со всем FAQ. Модель отвечает только по FAQ; если ответа
   нет — так и говорит и предлагает до трёх похожих вопросов из FAQ (в MAX — кнопками).
3. После ответа — «👍 Полезно / 👎 Не помогло». Вопросы, ответы и оценки пишутся в CSV и
   пересылаются администраторам в мессенджер.

```
Пользователь MAX ──► MAX Bot API ◄──── maxbot (контейнер)  ──┐
Пользователь TG ──► Telegram ◄─ Cloudflare Worker ◄─ faqbot ─┤
                                                             ├─► Qwen 3.6 35B (Yandex AI Studio)
                         ВМ faqbot, Yandex Cloud, РФ ────────┤   CSV-логи в /opt/*/data
                                                             └─► дашборд (только MAX)
```

## Структура репозитория

```
├── maxbot/                 # MAX-бот (основной)
│   ├── maxbot.py           #   весь код: клиент MAX API, меню, вопросы, логи
│   ├── FAQ_DPO_HSE_v5.docx #   база знаний (копия)
│   └── Dockerfile, docker-compose.yml, requirements.txt, .env.example, README.md
├── bot.py                  # Telegram-бот (дополнительный)
├── FAQ_DPO_HSE_v5.docx     # база знаний (копия)
├── Dockerfile, docker-compose.yml, requirements.txt, .env.example
├── relay/                  # посредник Telegram на Cloudflare Workers
└── docs/                   # сервисы, восстановление, решения, история, бэкапы
```

> ⚠️ **FAQ лежит в двух местах** — в корне и в `maxbot/`: каждая папка собирается в
> Docker отдельно. Обновляете FAQ — меняйте **оба** файла **и** файл на Яндекс Диске.

---

## Запуск на своём компьютере

Нужен Python 3.11 и заполненный `.env` (список переменных с пояснениями — в
[`maxbot/.env.example`](maxbot/.env.example) и [`.env.example`](.env.example); где брать
значения — [docs/SERVICES.md](docs/SERVICES.md)).

```bash
git clone https://github.com/leonovvladimirhq-svg/botdpohse.git
cd botdpohse/maxbot                            # Telegram-версия: cd botdpohse
python -m venv venv && . venv/bin/activate     # Windows: venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env                           # заполнить значения
python maxbot.py                               # Telegram-версия: python bot.py
```

⚠️ Пока работает бот на сервере, локально запускайте **другого** тестового бота
(другой токен). Два экземпляра на одном токене мешают друг другу.

## Сервер и обновление

ВМ `faqbot`, Yandex Cloud, каталог `project2-chatbotdpo`. Каталоги `/opt/maxbot` (MAX)
и `/opt/faqbot` (Telegram). Бот сам опрашивает мессенджеры (long polling) — входящие
порты не нужны.

```bash
# обновить код MAX-бота (для Telegram — bot.py в /opt/faqbot)
scp -i ~/.ssh/yc_faqbot_key maxbot/maxbot.py yc-user@93.77.187.243:/opt/maxbot/
ssh -i ~/.ssh/yc_faqbot_key yc-user@93.77.187.243
cd /opt/maxbot && sudo docker compose up -d --build
```

Перед заменой файла на сервере делайте копию рядом: `cp maxbot.py maxbot.py.bak-<метка>`.

## Типовые задачи

| Задача | Как |
|---|---|
| **Обновить FAQ** | Заменить `FAQ_DPO_HSE_v5.docx` в корне и в `maxbot/` → залить в `/opt/faqbot/` и `/opt/maxbot/` → пересобрать оба контейнера → перезалить файл на Яндекс Диске |
| **Добавить администратора** | MAX: админ пишет боту `/whoami`, ID вписать в `ADMIN_CHAT_ID_2` в `/opt/maxbot/.env` → `sudo docker compose up -d`. ID в MAX и Telegram разные |
| **Выключить / включить Telegram** | `cd /opt/faqbot && sudo docker compose stop` / `start`. MAX не затрагивается |
| **Сменить модель** | `MODEL_URI` в `.env` → `sudo docker compose up -d` |
| **Скачать логи** | `/opt/maxbot/data/questions_log.csv`, `escalations_log.csv`, `/opt/faqbot/data/questions_log.csv`. Там персональные данные — хранить только в РФ |
| **Посмотреть статистику** | Дашборд `http://89.169.146.175:8080` (вход — см. SERVICES.md) |

## Если что-то сломалось

```bash
sudo docker ps                       # оба контейнера должны быть Up
sudo docker logs --tail 100 maxbot   # или faqbot
```

| Симптом | Причина и решение |
|---|---|
| `faqbot` в статусе `Restarting`, в логе `TelegramError: Invalid server response` | Релей не пускает ВМ: её IP не совпадает с `ALLOWED_IPS` в `relay/wrangler.toml`. Проверка с ВМ: `curl https://tg-relay-dpo.leonov-vladimir-hq.workers.dev/check` — 403 = не пускает, 404 = всё в порядке. Решение — [relay/README.md](relay/README.md) |
| Бот отвечает пусто | Для Qwen не передан `reasoning_effort="none"` |
| Бот стартует, но не отвечает на вопросы | Ошибка доступа к Yandex AI Studio — проверить `YANDEX_API_KEY`, `MODEL_URI` |
| Telegram: `409 Conflict` | Где-то запущен второй экземпляр бота с тем же токеном |
| Ошибки MAX API (`dialog.not.found`, `verify.token`, TLS `unknown CA` …) | Таблица кодов и причины — [maxbot/README.md](maxbot/README.md) |
| Изменил `.env`, ничего не поменялось | Пересоздать контейнер: `sudo docker compose up -d` |
