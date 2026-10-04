# Внешние сервисы, ключи и аккаунты

Единственное место, где перечислено, **от чего зависит бот** и **где лежат ключи**.
Самих значений ключей здесь нет и быть не должно: репозиторий **публичный**.

Сверено с фактическим состоянием 2026-10-04.

---

## Сводка

| Сервис | Зачем | Аккаунт / где управлять | Секрет → где лежит значение | Как перевыпустить | Стоимость |
|---|---|---|---|---|---|
| **Yandex Cloud — ВМ** | Сервер, на котором работают оба бота | Облако `b1gtf2pdbkfrkhbd3rt6`, каталог `project2-chatbotdpo` (`b1gvtru3guuc1oipcs4p`), ВМ `faqbot` | SSH-ключ `~/.ssh/yc_faqbot_key` — **только на компьютере владельца** | Новый ключ добавить в метаданные ВМ через консоль YC (см. [RESTORE.md](RESTORE.md)) | ВМ 2 vCPU 5% / 1 ГБ / 10 ГБ HDD — помесячно по тарифу YC |
| **Yandex Cloud — статический IP** | Постоянный адрес ВМ `93.77.187.243`; на него завязан релей Telegram | Адрес `faqbot-static-ip` (`e9bgc9a6nhebh8avds4h`) | — | — (**не снимать резервирование**: сменится IP — ляжет Telegram) | Небольшая доплата за статический адрес |
| **Yandex AI Studio** | Модель Qwen 3.6 35B, которая отвечает на вопросы | Тот же каталог; сервисный аккаунт `leonov-deployer` (`ajercun172vma0sg1eig`), API-ключ `ajemrsiu65kq1ge65nnv` | `YANDEX_API_KEY` → `/opt/maxbot/.env` и `/opt/faqbot/.env` | `yc iam api-key create --service-account-id ajercun172vma0sg1eig`, вписать в оба `.env`, пересоздать контейнеры | Оплата за токены |
| **yc CLI** (администрирование облака) | Управлять ВМ, IP, ключами с компьютера | Тот же сервисный аккаунт `leonov-deployer` | Файл `leonov-deployer-key.json` — **только на компьютере владельца**, в git не попадает | `yc iam key create --service-account-id ajercun172vma0sg1eig -o key.json` | — |
| **MAX** | Основной канал: бот «Чат-Бот ДПО Школа Коммуникаций» `@se14233220_bot` (id 412305012) | Создан через MasterBot в MAX | `MAX_TOKEN` → `/opt/maxbot/.env` | В MasterBot выпустить новый токен, вписать в `.env`, пересоздать контейнер | Бесплатно |
| **Telegram** | Дополнительный канал: бот `@hse_dpo_faq_bot` (id 8709764083) | Создан через @BotFather | `TELEGRAM_TOKEN` → `/opt/faqbot/.env` | @BotFather → `/revoke`, вписать новый в `.env`. Номер бота (`8709764083`, часть токена до двоеточия) при этом не меняется — `relay/wrangler.toml` трогать не нужно | Бесплатно |
| **Cloudflare Workers** | Посредник до Telegram: `https://tg-relay-dpo.leonov-vladimir-hq.workers.dev` | Аккаунт `leonov.vladimir.hq@gmail.com`, Worker `tg-relay-dpo`, поддомен `leonov-vladimir-hq` | Секретов нет: `ALLOWED_IPS` и `ALLOWED_BOT_IDS` — в `relay/wrangler.toml`. Вход wrangler (OAuth) — на компьютере владельца | `cd relay && npx wrangler login && npx wrangler deploy` | Бесплатный тариф (100 000 запросов/сутки, бот тратит < 9 000) |
| **Дашборд мониторинга** | Статистика вопросов, оценок и эскалаций MAX-бота | `http://89.169.146.175:8080`, ВМ `vkr-checker` (каталог project3). Код: `C:\VKR 2\projects-dashboard` | `DASHBOARD_TOKEN` → `/opt/maxbot/.env`; логин/пароль входа — в `.env` дашборда | Новый токен — скриптом `scripts/seed-project.mjs` в репозитории дашборда | Входит в стоимость ВМ `vkr-checker` |
| **Яндекс Диск** | Публичный FAQ для слушателей: `https://disk.yandex.ru/i/b0hBdX16YfwFBQ` (ссылка в приветствии и кнопке «Часто задаваемые вопросы») | Диск владельца | — | Загрузить новый файл → «Поделиться» → заменить ссылку в `bot.py` и `maxbot/maxbot.py` (по 2 места) | Бесплатно |
| **GitHub** | Код и документация | `github.com/leonovvladimirhq-svg/botdpohse`, **публичный** | — | — | Бесплатно |

---

## Где лежат секреты

Все секреты — только в двух файлах `.env` на сервере:

| Файл на сервере | Переменные-секреты | Локальная копия у владельца |
|---|---|---|
| `/opt/maxbot/.env` | `MAX_TOKEN`, `YANDEX_API_KEY`, `DASHBOARD_TOKEN` | `C:\Chatbot_DPO\maxbot\.env` |
| `/opt/faqbot/.env` | `TELEGRAM_TOKEN`, `YANDEX_API_KEY` | `C:\Chatbot_DPO\bot\.env` |

На 2026-10-04 локальные копии **совпадают с серверными**. Полный список переменных
с пояснениями — в [`.env.example`](../.env.example) (Telegram) и
[`maxbot/.env.example`](../maxbot/.env.example) (MAX).

Рекомендация: продублировать значения в менеджер паролей. Локальные копии лежат
на одном компьютере; если он сломается одновременно с ВМ, ключи придётся выпускать
заново (это возможно для всех — см. колонку «Как перевыпустить»).

Только на компьютере владельца, нигде больше:
- `~/.ssh/yc_faqbot_key` — SSH-ключ к ВМ;
- `leonov-deployer-key.json` — ключ сервисного аккаунта для `yc`;
- вход `wrangler` в Cloudflare (`%APPDATA%\xdg.config\.wrangler\config\default.toml`).

GitHub Actions и секретов хостинга нет — сборка и деплой выполняются вручную.

---

## Данные, которые пишет бот

| Файл на сервере | Что внутри | Персональные данные |
|---|---|---|
| `/opt/maxbot/data/questions_log.csv` | дата, user_id, username, имя, фамилия, вопрос, ответ, оценка | **да** |
| `/opt/maxbot/data/escalations_log.csv` | дата, user_id, username, имя, фамилия — нажатия «Связаться с менеджером» | **да** |
| `/opt/faqbot/data/questions_log.csv` | то же для Telegram | **да** |

Данные хранятся в РФ (Yandex Cloud, `ru-central1`) — требование 152-ФЗ. Копии
выгружать только на носители в РФ, **не** в облака иностранных компаний и не в git.

---

## Внешние ресурсы, на которые ссылается FAQ (не наши, но от них зависят ответы)

- Каталог программ Школы: `https://www.hse.ru/edu/dpo/?orgUnit=122999271` — **единственный
  каталог, который бот имеет право давать** (общий `hse.ru/edu/dpo/` — нельзя, см. DECISIONS).
- Личный кабинет `busedu.hse.ru`, оплата `pay.hse.ru/moscow/dou`, платформа `hse.ispringlearn.ru`.
- Инструкции на `file.communication.school` и шаблон заявления на налоговый вычет на Яндекс Диске.

Если какой-то из этих адресов поменяется, нужно обновить FAQ (`FAQ_DPO_HSE_v5.docx`).
