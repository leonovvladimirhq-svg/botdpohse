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
- **С сентября 2026 `api.telegram.org` с российских серверов недоступен вообще** — ТСПУ
  режет все подсети Telegram на исходящем (проверено 21.09.2026 с ВМ `faqbot`: 149.154.167.220,
  149.154.166.110, 149.154.167.99, 91.108.56.100 — таймаут). Летний пин IPv4 в `extra_hosts`
  мёртв и из `docker-compose.yml` убран. Webhook не поможет (блок двусторонний), смена облака
  не поможет (то же у Selectel/Reg.ru).
- **Решение — релей за пределами РФ** (`relay/`): reverse-proxy nginx в Yandex Cloud kz1
  (Казахстан) + long polling. Бот читает `TELEGRAM_RELAY_URL` и подставляет его в
  `Application.builder().base_url()/base_file_url()` (PTB 21.6 сам дописывает токен).
  База, лог и обращения к AI Studio остаются в РФ; релей ничего не хранит, тела не логирует,
  принимает только с IP бэкенда. Подробности, юридический контекст и порядок покупки ВМ —
  `relay/README.md`; сама установка — `relay/install-relay.sh` (одна команда).
- **Yandex Cloud Казахстан — отдельная инсталляция** (`kz.console.yandex.cloud`,
  `api.yandexcloud.kz`, свой биллинг и IAM). Наш СА `leonov-deployer` там не существует —
  ВМ релея создаёт владелец облака вручную, затем передаёт IP.
- Только один экземпляр поллера на токен (иначе Telegram отдаёт 409 Conflict).

## Мониторинг: дашборд запросов (только MAX-версия)
- Дашборд — отдельный сервис на ВМ `vkr-checker`: **http://89.169.146.175:8080**,
  исходники в `C:\VKR 2\projects-dashboard` (свой репозиторий и свой CLAUDE.md).
  Логин/пароль — в `.env` дашборда.
- Бот шлёт события в `POST {DASHBOARD_URL}/api/ingest` с `Authorization: Bearer {DASHBOARD_TOKEN}`
  через `_dashboard_post()` — **fire-and-forget в фоновом потоке, таймаут 5 с**. Если дашборд
  лежит или переменные пустые, бот работает как раньше; мониторинг не имеет права его замедлить.
- Что уходит: каждый вопрос/ответ из `log_question()` (с `latency_ms`, `model`, `dedup_key =
  user_id:дата_время`), оценка 👍/👎 из `update_last_rating()` (`{"op":"rate"}`), и
  **эскалация** из `log_escalation()`.
- **Эскалация к менеджеру** = нажатие кнопки «📞 Связаться с менеджером» (`CB_MANAGER`, в том
  числе если пользователь набрал подпись кнопки текстом). Событие `event_type: "escalation"`,
  без текста и оценки. Локально дублируется в **отдельный** `data/escalations_log.csv` —
  в `questions_log.csv` нельзя: `update_last_rating()` прицепил бы к такой строке оценку
  следующего ответа. Введено 15.09.2026 по требованию заказчика как отдельная метрика.
- Не считается эскалацией: автоматический показ контактов менеджера в `MANAGER_PHONES_TEXT`,
  когда бот сам не нашёл ответ, — это решение бота, а не пользователя.

## Переменные окружения
Реальные значения — вне репозитория (задаются при деплое в `.env` на сервере).

- **MAX:** `MAX_TOKEN`, `MAX_API_BASE`, `YANDEX_API_KEY`, `YANDEX_BASE_URL`, `MODEL_URI`,
  `DOCUMENT_PATH`, `LOG_FILE`, `ADMIN_CHAT_ID`, `ADMIN_CHAT_ID_2`,
  `DASHBOARD_URL`, `DASHBOARD_TOKEN` (опционально `ESCALATION_LOG_FILE`).
- **Telegram:** то же, но вместо `MAX_TOKEN`/`MAX_API_BASE` — `TELEGRAM_TOKEN` и
  `TELEGRAM_RELAY_URL` (`https://<хост релея>`, пусто = напрямую); в дашборд не шлёт.

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

**Просто `docker compose start` больше не поможет** — без релея бот не достучится до
Telegram (см. «Специфика Telegram Bot API»). Порядок восстановления теперь такой:
1. Релей в Yandex Cloud kz1 поднят по `relay/README.md` (ВМ покупает владелец облака,
   установка — `relay/install-relay.sh <IP бэкенда>`).
2. На ВМ `faqbot` в `/opt/faqbot/.env` добавить `TELEGRAM_RELAY_URL=https://<хост релея>`,
   залить обновлённые `bot.py` и `docker-compose.yml` из этого репозитория.
3. `cd /opt/faqbot && sudo docker compose up -d --build`, затем
   `sudo docker logs -f faqbot` — ждём «Telegram Bot API через релей: …» и getUpdates 200.

Контейнер, образ `faqbot:latest`, `/opt/faqbot/.env` с токеном и CSV-лог на ВМ сохранены
(остановка 06.09.2026 через `docker compose stop`).

**Что может помешать восстановлению:**
- Токен бота BotFather не протухает от простоя — сам по себе он останется валидным.
- Релей недоступен/лёг — `faqbot` уйдёт в перезапуск по `restart: unless-stopped`; MAX-бот
  (`maxbot`) это не затрагивает, контейнеры независимы.
- Одновременно с восстановлением нельзя держать второй поллер на том же токене — 409 Conflict.
- Юридически: заключение по ч. 8 ст. 10 149-ФЗ и уведомление РКН о трансграничной передаче
  (см. записку и `relay/README.md`) — до запуска в эксплуатацию.

## Безопасность
- Секреты (токены ботов, API-ключ, chat_id админов) — только в `.env` на сервере,
  никогда в репозитории. `.env` закрыт `.gitignore`.
- Ключ сервисного аккаунта Yandex Cloud (`leonov-deployer-key.json`) хранится локально
  и в репозиторий не попадает.
