# Чат-Бот ДПО Школа коммуникаций НИУ ВШЭ

Бот, который отвечает на вопросы о программах дополнительного профессионального
образования (ДПО) Школы коммуникаций НИУ ВШЭ. База знаний — `.docx`-файл с FAQ; ответы
генерирует **Qwen 3.6 35B через Yandex AI Studio** (OpenAI-совместимый API).

| Версия | Где живёт | Статус |
|---|---|---|
| 🟢 **MAX** — основная | [`maxbot/`](./maxbot/) | Работает. Бот «Чат-Бот ДПО Школа Коммуникаций» (`@se14233220_bot`) |
| 🟢 **Telegram** — дополнительный | корень репозитория | Работает с 2026-09-23 через посредник [`relay/`](./relay/). Бот `@hse_dpo_faq_bot` |

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
7. [Telegram-канал и релей](#telegram-канал-и-релей)
8. [Типовые задачи поддержки](#типовые-задачи-поддержки)
9. [Логи и отладка](#логи-и-отладка)

---

## Что делает бот

1. Пользователь открывает диалог или пишет `/start` — видит главное меню с 3 кнопками:
   - **❓ Задать вопрос помощнику** — режим Q&A (в Telegram-версии подпись длиннее:
     «Задать вопрос Виртуальному помощнику (24/7)» — в MAX на телефоне она не помещалась).
   - **📞 Связаться с менеджером** — контакты (MAX, e-mail, телефон). Нажатие считается
     **эскалацией** и попадает в дашборд отдельной метрикой.
   - **📋 Часто задаваемые вопросы** — ссылка на полный FAQ на Яндекс.Диске.
2. В режиме Q&A текст пользователя уходит в модель с системным промптом, включающим весь
   FAQ-документ. Модель отвечает **только на основе FAQ**; если ответа нет — возвращает
   фразу-маркер «нет данных по этому вопросу».
3. После ответа — кнопки «👍 Полезно / 👎 Не помогло». Оценка пишется в CSV и пересылается админам.
4. Если бот не нашёл ответ, он подбирает **до 3 близких по смыслу вопросов** из FAQ
   (отдельный вызов модели в JSON-режиме) и предлагает их пользователю. В MAX-версии каждая
   подсказка — **кнопка**: нажал — бот ответил на этот вопрос, перепечатывать не нужно.
5. Все вопросы/ответы/оценки логируются в `questions_log.csv` и дублируются админам.

В MAX нет reply-клавиатуры, поэтому меню — это inline-кнопки, прикреплённые к сообщению,
а не панель под полем ввода. Из-за этого кнопка **«◀️ Назад в меню» есть на каждом
последнем сообщении бота** (после ответа, на вопросе об оценке, после оценки, на подсказках):
кнопки в MAX живут только на своём сообщении, и без этого пользователь оставался бы без
кнопок вообще.

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
├── docker-compose.yml     # Telegram-версия
├── relay/                 # Посредник Bot API на Cloudflare Workers (без ВМ)
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

## Telegram-канал и релей

**Работает с 23.09.2026** через посредник на Cloudflare Workers:
`https://tg-relay-dpo.leonov-vladimir-hq.workers.dev` — код и инструкция в
[`relay/`](./relay/). Виртуальная машина для этого не арендуется.

> **Почему понадобился релей.** С сентября 2026 `api.telegram.org` недоступен с любых
> серверов в РФ. Замер 22.09.2026 на четырёх наших ВМ в разных каталогах и подсетях дал
> идентичный результат: `github.com` → 200, `api.telegram.org` → HTTP 000.
> **Фильтрация идёт по назначению, а не по нашему IP**, поэтому перебор адресов и аренда
> новых ВМ ради «рабочего IP» результата не дадут — это проверено, повторять не нужно.
>
> База, лог и обращения к Yandex AI Studio остаются в РФ; релей ничего не хранит.

Как это развёрнуто — и как повторить, если придётся делать заново:

```bash
# 1. Развернуть Worker: cd relay && npx wrangler login && npx wrangler deploy
#    (см. relay/README.md — там же грабли первого деплоя)
# 2. На ВМ бота: обновить bot.py и docker-compose.yml из репозитория,
#    в /opt/faqbot/.env добавить TELEGRAM_RELAY_URL=https://<адрес>.workers.dev
ssh -i ~/.ssh/yc_faqbot_key yc-user@89.169.142.74
cd /opt/faqbot && sudo docker compose up -d --build
sudo docker logs -f faqbot        # ждём "Telegram Bot API через релей: …" и getUpdates 200 OK
```

Выключить или включить Telegram-канал (MAX при этом не затрагивается):

```bash
cd /opt/faqbot && sudo docker compose stop     # выключить
cd /opt/faqbot && sudo docker compose start    # включить
```

Что учесть:
- **403 на каждый запрос в логе** — сменился IP ВМ: поправить `ALLOWED_IPS` в
  `relay/wrangler.toml` и передеплоить Worker.
- Релей лёг — перезапускается только `faqbot`; MAX-бот работает независимо.
- Нельзя держать два поллера на одном токене одновременно — Telegram отдаст 409 Conflict.
- Токен BotFather не протухает от простоя.
- **Юридически не закрыто:** заключение по ч. 8 ст. 10 149-ФЗ и уведомление РКН о
  трансграничной передаче — ОАЭ (Telegram) и США (Cloudflare). Канал запущен по решению
  заказчика; при отрицательном заключении выключается командой выше.

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
