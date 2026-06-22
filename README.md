# Чат-Бот ДПО Школа коммуникаций НИУ ВШЭ

Telegram-бот, который отвечает на вопросы о программах дополнительного профессионального
образования (ДПО) Школы коммуникаций НИУ ВШЭ. База знаний — `.docx`-файл с FAQ; ответы
генерирует **Qwen 3.6 35B через Yandex AI Studio** (OpenAI-совместимый API).

- **Бот в Telegram:** [@dposchoolcomm_bot](https://t.me/dposchoolcomm_bot) («Чат-Бот ДПО Школа коммуникаций»)
- **Репозиторий:** https://github.com/leonovvladimirhq-svg/botdpohse
- **Хостинг:** **Yandex Cloud** (каталог `project2-chatbotdpo`, зона `ru-central1`), запуск в Docker.

---

## Содержание
1. [Что делает бот](#что-делает-бот)
2. [Архитектура](#архитектура)
3. [Структура репозитория](#структура-репозитория)
4. [Конфигурация (.env)](#конфигурация-env)
5. [Локальный запуск](#локальный-запуск)
6. [Деплой на Yandex Cloud](#деплой-на-yandex-cloud)
7. [Типовые задачи поддержки](#типовые-задачи-поддержки)
8. [Логи и отладка](#логи-и-отладка)

---

## Что делает бот

1. Пользователь пишет `/start` — видит главное меню с 3 кнопками:
   - **❓ Задать вопрос виртуальному помощнику** — режим Q&A.
   - **📞 Связаться с менеджером** — контакты (Telegram, e-mail, телефон).
   - **📋 Часто задаваемые вопросы** — ссылка на полный FAQ на Яндекс.Диске.
2. В режиме Q&A текст пользователя уходит в модель с системным промптом, включающим весь
   FAQ-документ. Модель отвечает **только на основе FAQ**; если ответа нет — возвращает
   фразу-маркер «нет данных по этому вопросу».
3. После ответа — кнопки «👍 Полезно / 👎 Не помогло». Оценка пишется в CSV и пересылается админам.
4. Если бот не нашёл ответ, он подбирает **до 3 близких по смыслу вопросов** из FAQ
   (отдельный вызов модели в JSON-режиме) и предлагает их пользователю.
5. Все вопросы/ответы/оценки логируются в `questions_log.csv` и дублируются в Telegram админам.

---

## Архитектура

```
Пользователь Telegram
       │
       ▼
 python-telegram-bot v21 (long polling)
       │
       ├─► Qwen 3.6 35B  (Yandex AI Studio, OpenAI-совместимый эндпоинт)
       │       ├─ ask_question()           — основной ответ (system prompt = FAQ)
       │       └─ suggest_reformulations() — JSON-подсказки переформулировок
       │
       ├─► CSV-лог  questions_log.csv
       └─► Уведомления в Telegram админам
```

Ключевые компоненты в `bot.py`:

| Сущность | Назначение |
|---|---|
| `load_document()` | Парсит `.docx` (текст + таблицы + гиперссылки) в строку для system prompt. |
| `SYSTEM_PROMPT` | Инструкция модели + содержимое FAQ. Запрещает markdown и выход за рамки FAQ. |
| `ask_question()` | Основной вызов модели с историей последних 5 Q&A пользователя. |
| `suggest_reformulations()` | Подбор близких вопросов из FAQ (JSON-режим). |

Клиент модели — пакет `openai`, направленный на OpenAI-совместимый эндпоинт Yandex AI Studio
(`base_url` + URI модели задаются через окружение).

---

## Структура репозитория

```
├── bot.py                # Основной код бота
├── requirements.txt      # Python-зависимости
├── FAQ_DPO_HSE_v5.docx   # База знаний (актуальный FAQ)
├── Procfile              # worker: python bot.py
└── Чат бот/              # Историческая копия (на прод не используется)
```

> Все правки кода — в корневом `bot.py`. База знаний — `FAQ_DPO_HSE_v5.docx`.

---

## Конфигурация (.env)

Реальные значения **не хранятся в репозитории** — задаются при деплое:

| Переменная | Назначение |
|---|---|
| `TELEGRAM_TOKEN` | Токен Telegram-бота от @BotFather |
| `OPENAI_API_KEY` | API-ключ сервисного аккаунта Yandex Cloud (для Yandex AI Studio) |
| `OPENAI_BASE_URL` | OpenAI-совместимый эндпоинт: `https://llm.api.cloud.yandex.net/v1` |
| `OPENAI_MODEL` | URI модели: `gpt://<folder-id>/qwen3.6-35b-a3b/latest` |
| `DOCUMENT_PATH` | Имя файла FAQ (`FAQ_DPO_HSE_v5.docx`) |
| `ADMIN_CHAT_ID`, `ADMIN_CHAT_ID_2` | Telegram chat_id админов для уведомлений (задаются при деплое) |

> Qwen 3.6 35B — reasoning-модель: при вызове передаётся `reasoning_effort=none`, иначе модель
> расходует бюджет токенов на «размышления» и возвращает пустой ответ.

---

## Локальный запуск

```bash
git clone https://github.com/leonovvladimirhq-svg/botdpohse.git
cd botdpohse
python -m venv venv && . venv/bin/activate     # Windows: venv\Scripts\activate
pip install -r requirements.txt
# создать .env с переменными из таблицы выше, затем:
python bot.py
```

---

## Деплой на Yandex Cloud

- **Облако:** Yandex Cloud, каталог `project2-chatbotdpo`, зона `ru-central1-a`.
- **ВМ:** Ubuntu 22.04, запуск в **Docker** (`docker compose`), контейнер с `restart: unless-stopped`
  (автозапуск после ребута ВМ).
- **Режим:** long polling (исходящие подключения; входящий публичный доступ не требуется).

```bash
ssh yc-user@<vm-ip>
cd /opt/faqbot
git pull            # или scp обновлённых файлов
sudo docker compose up -d --build
```

> **Нюанс региона:** в `ru-central1` DNS отдаёт для `api.telegram.org` только IPv6 (которого на ВМ
> нет), поэтому в `docker-compose.yml` рабочий IPv4 Bot API закреплён через `extra_hosts`
> (`api.telegram.org:149.154.167.220`). Без этого бот не достучится до Telegram.

---

## Типовые задачи поддержки

**Обновить FAQ:** заменить `FAQ_DPO_HSE_v5.docx`, перенести на ВМ, пересобрать контейнер
(`docker compose up -d --build`).

**Сменить модель:** изменить `OPENAI_MODEL` в `.env` и пересоздать контейнер. Для reasoning-моделей
не забыть про `reasoning_effort=none`.

**Скачать лог вопросов:** `questions_log.csv` лежит в смонтированном томе данных на ВМ.

---

## Логи и отладка

```bash
cd /opt/faqbot
sudo docker compose logs -f          # живой лог бота
sudo docker compose logs --tail 200  # последние 200 строк
```

| Симптом | Где смотреть | Причина / решение |
|---|---|---|
| Бот стартует, но молчит | логи контейнера | Ошибка аутентификации к Yandex AI Studio → проверить `OPENAI_API_KEY`/`OPENAI_BASE_URL`/`OPENAI_MODEL`. |
| Ответ приходит пустой | логи | Не передан `reasoning_effort=none` для Qwen → модель «думает» весь бюджет токенов. |
| Конфликт `getUpdates` (409) | логи | Запущено два поллера с одним токеном — должен работать только один экземпляр. |
| Сменили `.env`, не применилось | — | Нужно пересоздать контейнер (`docker compose up -d`). |
