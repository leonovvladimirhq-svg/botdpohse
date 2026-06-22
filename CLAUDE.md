# CLAUDE.md — Чат-Бот ДПО Школа коммуникаций НИУ ВШЭ

Техническая справка для разработки и сопровождения. Пользовательская документация — в [README.md](./README.md).

## Описание
Telegram-бот (FAQ-помощник) для программ ДПО Школы коммуникаций НИУ ВШЭ. Отвечает на вопросы
строго по базе знаний (`.docx`-FAQ), используя **Qwen 3.6 35B через Yandex AI Studio**.

## Технологический стек
- **Язык/фреймворк:** Python, `python-telegram-bot` v21 (long polling).
- **Модель:** Qwen 3.6 35B через **Yandex AI Studio** (OpenAI-совместимый эндпоинт; клиент — пакет `openai`).
- **База знаний:** `.docx` (парсинг через `python-docx`), целиком кладётся в system prompt.
- **Лог:** `questions_log.csv` (вопрос, ответ, оценка) + дублирование в Telegram админам.
- **Деплой:** Docker (`docker compose`) на **Yandex Cloud**.

## Структура
- `bot.py` — весь код: меню, режим Q&A, вызовы модели, логирование, уведомления админам.
- `FAQ_DPO_HSE_v5.docx` — актуальная база знаний (`DOCUMENT_PATH`).
- `requirements.txt`, `Procfile`.

## Ключевые функции (`bot.py`)
- `load_document()` — `.docx` → текст (с таблицами и гиперссылками) для system prompt.
- `ask_question(question, history)` — основной вызов модели (system prompt = FAQ, история ≤5 Q&A).
- `suggest_reformulations(question)` — подбор близких вопросов из FAQ (JSON-режим, `response_format`).
- `strip_markdown()` — чистит markdown из ответа (бот шлёт plain text).

## Интеграция с моделью (Yandex AI Studio)
- OpenAI-совместимый эндпоинт: `OPENAI_BASE_URL=https://llm.api.cloud.yandex.net/v1`.
- Модель: `OPENAI_MODEL=gpt://<folder-id>/qwen3.6-35b-a3b/latest`.
- Аутентификация: API-ключ сервисного аккаунта Yandex Cloud (`OPENAI_API_KEY`).
- **Важно:** Qwen 3.6 35B — reasoning-модель. В запросы передаётся `reasoning_effort=none`,
  иначе модель тратит весь бюджет токенов на «размышления» и возвращает пустой `content`.

## Переменные окружения (.env)
Реальные значения — вне репозитория (задаются при деплое):
`TELEGRAM_TOKEN`, `OPENAI_API_KEY`, `OPENAI_BASE_URL`, `OPENAI_MODEL`, `DOCUMENT_PATH`,
`LOG_FILE`, `ADMIN_CHAT_ID`, `ADMIN_CHAT_ID_2`.

## Деплой (Yandex Cloud)
- Каталог `project2-chatbotdpo` (зона `ru-central1-a`), ВМ Ubuntu 22.04, Docker.
- Контейнер с `restart: unless-stopped`; данные (лог) — в смонтированном томе.
- Режим **long polling** — нужен только исходящий доступ.
- **Нюанс региона:** `api.telegram.org` в `ru-central1` резолвится только в IPv6 (которого на ВМ
  нет). Рабочий IPv4 Bot API закреплён в `docker-compose.yml` через
  `extra_hosts: api.telegram.org:149.154.167.220`.
- Только один экземпляр поллера на токен (иначе Telegram отдаёт 409 Conflict).

## Безопасность
- Секреты (токен бота, API-ключ, chat_id админов) — только в `.env` на сервере, не в репозитории.
