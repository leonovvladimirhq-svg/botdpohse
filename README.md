# Чат-Бот ДПО Школа коммуникаций НИУ ВШЭ

Бот, который отвечает на вопросы о программах дополнительного профессионального
образования (ДПО) Школы коммуникаций НИУ ВШЭ. База знаний — `.docx`-файл с FAQ; ответы
генерирует **Qwen 3.6 35B через Yandex AI Studio** (OpenAI-совместимый API).

| Версия | Где живёт | Статус |
|---|---|---|
| 🟢 **MAX** — основная | [`maxbot/`](./maxbot/) | Работает. Бот «Чат-Бот ДПО Школа Коммуникаций» (`@se14233220_bot`) |
| ⏸️ **Telegram** — резерв | корень репозитория | Остановлена 2026-09-06, можно вернуть одной командой |

**Почему переехали:** Telegram блокируется в РФ, и до бота перестали дотягиваться
*пользователи*. На стороне сервера Telegram работал до последнего дня — дело было
не в хостинге, а в аудитории.

- **Хостинг:** Yandex Cloud (каталог `project2-chatbotdpo`, зона `ru-central1-a`), Docker.
- **Техническая справка:** [CLAUDE.md](./CLAUDE.md) · **Детали MAX-версии:** [maxbot/README.md](./maxbot/README.md)

---

## Содержание
1. [Что делает бот](#что-делает-бот)
2. [Архитектура](#архитектура)
3. [Структура репозитория](#структура-репозитория)
4. [Конфигурация (.env)](#конфигурация-env)
5. [Локальный запуск](#локальный-запуск)
6. [Деплой на Yandex Cloud](#деплой-на-yandex-cloud)
7. [Восстановление Telegram-версии](#восстановление-telegram-версии)
8. [Типовые задачи поддержки](#типовые-задачи-поддержки)
9. [Логи и отладка](#логи-и-отладка)

---

## Что делает бот

1. Пользователь открывает диалог или пишет `/start` — видит главное меню с 3 кнопками:
   - **❓ Задать вопрос виртуальному помощнику** — режим Q&A.
   - **📞 Связаться с менеджером** — контакты (Telegram, e-mail, телефон).
   - **📋 Часто задаваемые вопросы** — ссылка на полный FAQ на Яндекс.Диске.
2. В режиме Q&A текст пользователя уходит в модель с системным промптом, включающим весь
   FAQ-документ. Модель отвечает **только на основе FAQ**; если ответа нет — возвращает
   фразу-маркер «нет данных по этому вопросу».
3. После ответа — кнопки «👍 Полезно / 👎 Не помогло». Оценка пишется в CSV и пересылается админам.
4. Если бот не нашёл ответ, он подбирает **до 3 близких по смыслу вопросов** из FAQ
   (отдельный вызов модели в JSON-режиме) и предлагает их пользователю.
5. Все вопросы/ответы/оценки логируются в `questions_log.csv` и дублируются админам.

Поведение обеих версий идентично. Единственное видимое отличие: в MAX нет
reply-клавиатуры, поэтому меню — это inline-кнопки, прикреплённые к сообщению,
а не панель под полем ввода.

---

## Архитектура

```
Пользователь (MAX / Telegram)
       │
       ▼
 MAX Bot API (requests, long polling)   ◄── maxbot/maxbot.py
 python-telegram-bot v21 (long polling) ◄── bot.py
       │
       ├─► Qwen 3.6 35B  (Yandex AI Studio, OpenAI-совместимый эндпоинт)
       │       ├─ ask_question()           — основной ответ (system prompt = FAQ)
       │       └─ suggest_reformulations() — JSON-подсказки переформулировок
       │
       ├─► CSV-лог  questions_log.csv
       └─► Уведомления админам в мессенджер
```

| Сущность | Назначение |
|---|---|
| `load_document()` | Парсит `.docx` (текст + таблицы + гиперссылки) в строку для system prompt. |
| `SYSTEM_PROMPT` | Инструкция модели + содержимое FAQ. Запрещает markdown и выход за рамки FAQ. |
| `ask_question()` | Основной вызов модели с историей последних 5 Q&A пользователя. |
| `suggest_reformulations()` | Подбор близких вопросов из FAQ (JSON-режим). |
| `MaxBot` (только MAX) | Тонкий клиент Bot API MAX на `requests`, без внешних SDK. |

Клиент модели — пакет `openai`, направленный на OpenAI-совместимый эндпоинт Yandex AI Studio.

---

## Структура репозитория

```
├── maxbot/                # ОСНОВНАЯ версия (мессенджер MAX)
│   ├── maxbot.py          # Клиент MAX API + логика бота
│   ├── FAQ_DPO_HSE_v5.docx
│   ├── Dockerfile, docker-compose.yml, requirements.txt, .env.example
│   └── README.md
├── bot.py                 # РЕЗЕРВНАЯ версия (Telegram)
├── requirements.txt       # Зависимости Telegram-версии
├── Dockerfile             # Сборка Telegram-версии
├── docker-compose.yml     # Telegram-версия (с пином IPv4 Telegram API)
├── .env.example
├── FAQ_DPO_HSE_v5.docx    # База знаний (актуальный FAQ)
├── Procfile
└── Чат бот/               # Историческая копия (на прод не используется)
```

> ⚠️ **База знаний лежит в двух местах** — в корне и в `maxbot/` — чтобы каждый каталог был
> самодостаточным контекстом Docker-сборки. **При обновлении FAQ меняйте оба файла.**

---

## Конфигурация (.env)

Реальные значения **не хранятся в репозитории** — задаются при деплое.

| Переменная | Назначение |
|---|---|
| `MAX_TOKEN` | Токен бота в MAX (только MAX-версия) |
| `MAX_API_BASE` | `https://botapi.max.ru` — см. предупреждение ниже |
| `TELEGRAM_TOKEN` | Токен Telegram-бота от @BotFather (только Telegram-версия) |
| `YANDEX_API_KEY` | API-ключ сервисного аккаунта Yandex Cloud (для Yandex AI Studio) |
| `YANDEX_BASE_URL` | OpenAI-совместимый эндпоинт: `https://llm.api.cloud.yandex.net/v1` |
| `MODEL_URI` | URI модели: `gpt://<folder-id>/qwen3.6-35b-a3b/latest` |
| `DOCUMENT_PATH` | Имя файла FAQ (`FAQ_DPO_HSE_v5.docx`) |
| `LOG_FILE` | Путь к CSV-логу внутри контейнера (`/data/questions_log.csv`) |
| `ADMIN_CHAT_ID`, `ADMIN_CHAT_ID_2` | ID админов для уведомлений |

> ⚠️ **ID администраторов в MAX и Telegram разные.** Telegram-идентификаторы в MAX
> не работают. Чтобы узнать свой MAX ID, админ открывает бота и отправляет `/whoami`.
> Пока поля пустые, бот работает штатно, но уведомления не шлёт — всё пишется в CSV.

> ⚠️ **Домен MAX API — только `botapi.max.ru`.** Документация называет актуальным
> `platform-api2.max.ru`, но из Yandex Cloud он недоступен: TLS-хендшейк падает с
> `unknown CA` (сертификат российского УЦ отсутствует в стандартном `ca-certificates`).

> Qwen 3.6 35B — reasoning-модель: при вызове передаётся `reasoning_effort=none`, иначе модель
> расходует бюджет токенов на «размышления» и возвращает пустой ответ.

---

## Локальный запуск

```bash
git clone https://github.com/leonovvladimirhq-svg/botdpohse.git
cd botdpohse/maxbot                            # для Telegram-версии: cd botdpohse
python -m venv venv && . venv/bin/activate     # Windows: venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env                           # заполнить значения
python maxbot.py                               # для Telegram-версии: python bot.py
```

---

## Деплой на Yandex Cloud

- **Облако:** Yandex Cloud, каталог `project2-chatbotdpo`, зона `ru-central1-a`.
- **ВМ:** `faqbot`, Ubuntu 22.04, внешний IP `89.169.142.74` (менялся — сверяйтесь
  с `yc compute instance list`). SSH-ключ `~/.ssh/yc_faqbot_key`.
- **Каталоги:** `/opt/maxbot` (MAX) и `/opt/faqbot` (Telegram) — независимые compose-проекты.
- **Режим:** long polling (только исходящие подключения, входящих портов не нужно).

```bash
scp -i ~/.ssh/yc_faqbot_key maxbot/maxbot.py yc-user@89.169.142.74:/opt/maxbot/
ssh -i ~/.ssh/yc_faqbot_key yc-user@89.169.142.74
cd /opt/maxbot && sudo docker compose up -d --build
```

---

## Восстановление Telegram-версии

Telegram-бот остановлен через `docker compose stop`. Сохранены **и** контейнер,
**и** образ `faqbot:latest`, **и** `/opt/faqbot/.env` с токеном, **и** накопленный CSV-лог.
Ничего не удалено.

```bash
ssh -i ~/.ssh/yc_faqbot_key yc-user@89.169.142.74
cd /opt/faqbot && sudo docker compose start
sudo docker logs -f faqbot        # ждём "Бот запущен!" и getUpdates 200 OK
```

Если контейнера или образа уже нет (ВМ пересоздали, выполняли `docker system prune`) —
пересобрать из этого репозитория: скопировать корневые файлы в `/opt/faqbot`,
создать `.env` по `.env.example`, затем `sudo docker compose up -d --build`.

Что учесть:
- Токен BotFather не протухает от простоя — он останется валидным.
- Реальный риск — сетевой: пин `149.154.167.220` в `docker-compose.yml` может перестать
  работать, если блокировки ужесточат. Тогда понадобится прокси вне РФ.
- Нельзя держать два поллера на одном токене одновременно — Telegram отдаст 409 Conflict.

---

## Типовые задачи поддержки

**Обновить FAQ:** заменить `FAQ_DPO_HSE_v5.docx` **в обоих местах** (корень и `maxbot/`),
перенести на ВМ, пересобрать контейнер (`docker compose up -d --build`).

**Добавить админа для уведомлений:** админ пишет боту `/whoami` → полученный ID вписать
в `ADMIN_CHAT_ID` / `ADMIN_CHAT_ID_2` в `/opt/maxbot/.env` → `docker compose up -d`.

**Сменить модель:** изменить `MODEL_URI` в `.env` и пересоздать контейнер. Для reasoning-моделей
не забыть про `reasoning_effort=none`.

**Скачать лог вопросов:** `questions_log.csv` лежит в томе `./data` рядом с compose-файлом
(`/opt/maxbot/data/` или `/opt/faqbot/data/`).

---

## Логи и отладка

```bash
sudo docker ps                       # какие контейнеры подняты
sudo docker logs -f maxbot           # живой лог MAX-версии
sudo docker logs --tail 200 maxbot   # последние 200 строк
```

Проверить токен и доступность MAX API с сервера:

```bash
curl -s -H "Authorization: $MAX_TOKEN" https://botapi.max.ru/me
```

| Симптом | Причина / решение |
|---|---|
| Бот стартует, но молчит | Ошибка аутентификации к Yandex AI Studio → проверить `YANDEX_API_KEY` / `YANDEX_BASE_URL` / `MODEL_URI`. |
| Ответ приходит пустой | Не передан `reasoning_effort=none` для Qwen → модель «думает» весь бюджет токенов. |
| `dialog.not.found` (404) | Адресат не открывал диалог с ботом. Бот не может написать первым. |
| `proto.payload` (400) | Некорректное тело запроса к MAX API. |
| `verify.token` (401) | Токен передан query-параметром вместо заголовка `Authorization`. |
| TLS `unknown CA` | Используется `platform-api2.max.ru` → вернуть `MAX_API_BASE=https://botapi.max.ru`. |
| Конфликт `getUpdates` (409) | Запущено два поллера с одним токеном — должен работать один. |
| Сменили `.env`, не применилось | Нужно пересоздать контейнер (`docker compose up -d`). |
