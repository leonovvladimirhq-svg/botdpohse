# CLAUDE.md — Чат-Бот ДПО Школа коммуникаций НИУ ВШЭ

Техническая справка для разработки и сопровождения. Пользовательская документация — в [README.md](./README.md).

## Описание
FAQ-помощник по программам ДПО Школы коммуникаций НИУ ВШЭ. Отвечает на вопросы строго
по базе знаний (`.docx`-FAQ), используя **Qwen 3.6 35B через Yandex AI Studio**.

Существует в двух версиях с одинаковой продуктовой логикой:

| Версия | Каталог | Статус (2026-09-06) | Контейнер |
|---|---|---|---|
| **MAX** (основная) | [`maxbot/`](./maxbot/) | 🟢 работает | `maxbot` |
| **Telegram** (резерв) | корень репозитория | ⏸️ остановлена | `faqbot` |

Telegram-версия остановлена, но **не удалена** — её можно поднять одной командой,
см. [«Восстановление Telegram-версии»](#восстановление-telegram-версии).

## Технологический стек
- **Язык:** Python 3.11.
- **Транспорт MAX:** прямые HTTP-вызовы Bot API через `requests` (класс `MaxBot` в `maxbot.py`), long polling.
- **Транспорт Telegram:** `python-telegram-bot` v21, long polling.
- **Модель:** Qwen 3.6 35B через **Yandex AI Studio** (OpenAI-совместимый эндпоинт; клиент — пакет `openai`).
- **База знаний:** `.docx` (парсинг через `python-docx`), целиком кладётся в system prompt.
- **Лог:** `questions_log.csv` (вопрос, ответ, оценка) + дублирование админам в мессенджер.
- **Деплой:** Docker (`docker compose`) на **Yandex Cloud**.

## Структура
```
├── maxbot/                # ОСНОВНАЯ версия (мессенджер MAX)
│   ├── maxbot.py          # Клиент MAX API + вся логика бота
│   ├── FAQ_DPO_HSE_v5.docx
│   ├── Dockerfile, docker-compose.yml, requirements.txt, .env.example
│   └── README.md          # Подробности по MAX-версии
├── bot.py                 # РЕЗЕРВНАЯ версия (Telegram)
├── FAQ_DPO_HSE_v5.docx    # Актуальная база знаний
├── Dockerfile, docker-compose.yml, requirements.txt, .env.example
└── Чат бот/               # Историческая копия, на прод не используется
```

> ⚠️ **База знаний лежит в двух местах**: `FAQ_DPO_HSE_v5.docx` в корне (для Telegram-версии)
> и `maxbot/FAQ_DPO_HSE_v5.docx` (для MAX-версии). Так сделано, чтобы каждый каталог был
> самодостаточным контекстом сборки Docker. **При обновлении FAQ меняйте оба файла.**

## Ключевые функции (одинаковы в обеих версиях)
- `load_document()` — `.docx` → текст (с таблицами и гиперссылками) для system prompt.
- `ask_question(question, history)` — основной вызов модели (system prompt = FAQ, история ≤5 Q&A).
- `suggest_reformulations(question)` — подбор близких вопросов из FAQ (JSON-режим, `response_format`).
- `strip_markdown()` — чистит markdown из ответа (бот шлёт plain text).
- `split_message()` — режет длинные ответы по границам абзацев.

## Интеграция с моделью (Yandex AI Studio)
- OpenAI-совместимый эндпоинт: `YANDEX_BASE_URL=https://llm.api.cloud.yandex.net/v1`.
- Модель: `MODEL_URI=gpt://<folder-id>/qwen3.6-35b-a3b/latest`.
- Аутентификация: API-ключ сервисного аккаунта Yandex Cloud (`YANDEX_API_KEY`).
- **Важно:** Qwen 3.6 35B — reasoning-модель. В запросы передаётся
  `extra_body={"reasoning_effort": "none"}`, иначе модель тратит весь бюджет токенов
  на «размышления» и возвращает пустой `content` (`finish_reason=length`).
- Модель Gallery (Qwen) активируется **пер-каталог**, иначе 403 даже при роли editor.

## Специфика MAX Bot API
- **Домен — только `https://botapi.max.ru`.** Документация называет актуальным
  `platform-api2.max.ru`, но из Yandex Cloud он недоступен: TLS падает с
  `unknown CA` / `unable to get local issuer certificate` — сертификат российского УЦ,
  которого нет в стандартном `ca-certificates` образа `python:3.11-slim`.
- Авторизация — **только заголовок** `Authorization: <token>`; query-параметр
  `?access_token=` отдаёт 401 `verify.token`.
- **Нет reply-клавиатур** — только inline. Меню собрано на кнопках типа `callback`.
- Лимит текста 4000 символов (в коде `MAX_MSG_LIMIT = 3900`), rate limit 2 msg/sec на диалог.
- `POST /answers?callback_id=` одновременно подтверждает нажатие и редактирует сообщение.
- Событие `bot_started` играет роль первого `/start`; повторное приветствие гасится
  дедупликацией (окно 5 с).
- Бот может писать пользователю только после того, как тот открыл диалог (иначе
  `dialog.not.found` 404).
- **user_id в MAX другие, чем в Telegram.** Админские ID собираются заново:
  админ пишет боту `/whoami`, бот возвращает его MAX ID.
- Диагностика формы запроса: корректный payload на несуществующего адресата даёт
  404 `dialog.not.found`, а сломанный — 400 `proto.payload` («Can't deserialize body»).

## Специфика Telegram Bot API (для резервной версии)
- В `ru-central1` `api.telegram.org` резолвится только в IPv6, которого на ВМ нет.
  Рабочий IPv4 Bot API закреплён в `docker-compose.yml`:
  `extra_hosts: - "api.telegram.org:149.154.167.220"`.
- Только один экземпляр поллера на токен (иначе Telegram отдаёт 409 Conflict).

## Переменные окружения
Реальные значения — вне репозитория (задаются при деплое в `.env` на сервере).

- **MAX:** `MAX_TOKEN`, `MAX_API_BASE`, `YANDEX_API_KEY`, `YANDEX_BASE_URL`, `MODEL_URI`,
  `DOCUMENT_PATH`, `LOG_FILE`, `ADMIN_CHAT_ID`, `ADMIN_CHAT_ID_2`.
- **Telegram:** то же, но вместо `MAX_TOKEN`/`MAX_API_BASE` — `TELEGRAM_TOKEN`.

## Инфраструктура (Yandex Cloud)
- Каталог `project2-chatbotdpo` (`b1gvtru3guuc1oipcs4p`), зона `ru-central1-a`.
- ВМ `faqbot`, Ubuntu 22.04, 2 vCPU (core-fraction 5) / 1 ГБ RAM / 10 ГБ HDD, swap 2 ГБ.
  Не preemptible. Внешний IP **89.169.142.74** (менялся: ранее был 158.160.50.225 —
  проверяйте `yc compute instance list` перед подключением).
- SSH: `yc-user@89.169.142.74`, ключ `~/.ssh/yc_faqbot_key`.
- Каталоги на сервере: `/opt/maxbot` (MAX) и `/opt/faqbot` (Telegram).
- Оба compose-проекта независимы, у каждого свой том `./data` с `questions_log.csv`.
- Режим long polling — нужен только исходящий доступ, входящих портов не требуется.

## Восстановление Telegram-версии

Telegram-бот остановлен командой `docker compose stop` — это сохраняет и контейнер,
и образ `faqbot:latest`, и `/opt/faqbot/.env` с токеном, и накопленный CSV-лог.
Политика `restart: unless-stopped` означает, что вручную остановленный контейнер
**не поднимется сам** после перезагрузки ВМ.

Поднять обратно:
```bash
ssh -i ~/.ssh/yc_faqbot_key yc-user@89.169.142.74
cd /opt/faqbot && sudo docker compose start
sudo docker logs -f faqbot        # ждём "Бот запущен!" и getUpdates 200
```

Если контейнера или образа уже нет (ВМ пересоздали, `docker system prune`) — пересобрать
из этого репозитория: скопировать корневые файлы в `/opt/faqbot`, создать `.env`
по `.env.example` и выполнить `sudo docker compose up -d --build`.

**Что может помешать восстановлению:**
- Токен бота BotFather не протухает от простоя — сам по себе он останется валидным.
- Реальный риск — сетевой: пин `149.154.167.220` может перестать работать, если блокировки
  ужесточат. Тогда понадобится прокси вне РФ (PTB 21.x поддерживает `proxy`).
- Одновременно с восстановлением нельзя держать второй поллер на том же токене — 409 Conflict.

## Безопасность
- Секреты (токены ботов, API-ключ, chat_id админов) — только в `.env` на сервере,
  никогда в репозитории. `.env` закрыт `.gitignore`.
- Ключ сервисного аккаунта Yandex Cloud (`leonov-deployer-key.json`) хранится локально
  и в репозиторий не попадает.
