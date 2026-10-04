# CLAUDE.md — Чат-Бот ДПО Школа коммуникаций НИУ ВШЭ

Правила для ИИ-ассистента. Что это за проект и как его обслуживать человеку — [README.md](README.md).
FAQ-бот: отвечает **строго по** `FAQ_DPO_HSE_v5.docx` через Qwen 3.6 35B (Yandex AI Studio).
Два канала, одна продуктовая логика: **MAX** (`maxbot/maxbot.py`, основной) и **Telegram**
(`bot.py`, дополнительный, через посредника `relay/`).

## Карта документации (один факт — одно место)

| Тема | Где |
|---|---|
| Сервисы, аккаунты, ключи, перевыпуск | [docs/SERVICES.md](docs/SERVICES.md) |
| Восстановление, откат, где бэкапы | [docs/RESTORE.md](docs/RESTORE.md) |
| Почему так сделано, юридические вопросы | [docs/DECISIONS.md](docs/DECISIONS.md) |
| История по датам | [docs/CHANGELOG.md](docs/CHANGELOG.md) |
| Bot API MAX: отличия, коды ошибок | [maxbot/README.md](maxbot/README.md) |
| Релей Telegram: деплой, диагностика | [relay/README.md](relay/README.md) |
| Переменные окружения | `.env.example`, `maxbot/.env.example` |
| Неполадки и типовые задачи | [README.md](README.md) |

Меняешь поведение или инфраструктуру — допиши `docs/CHANGELOG.md`; принял решение с
«почему» — `docs/DECISIONS.md`. Не дублируй факт в нескольких документах — ставь ссылку.

## Стек
- Python 3.11, Docker Compose, long polling (входящих портов нет).
- MAX: свой клиент `MaxBot` на `requests` (без SDK). Telegram: `python-telegram-bot` 21.6.
- Модель: пакет `openai` → `https://llm.api.cloud.yandex.net/v1`, `MODEL_URI=gpt://<folder>/qwen3.6-35b-a3b/latest`.
- FAQ парсится `python-docx` (текст + таблицы + URL гиперссылок) и целиком кладётся в system prompt.
- Релей: Cloudflare Worker (`relay/worker.js`), деплой `wrangler`.

## Где что работает
- ВМ `faqbot`, Yandex Cloud, каталог `project2-chatbotdpo` (`b1gvtru3guuc1oipcs4p`), `ru-central1-a`.
- IP **93.77.187.243, статический** (`faqbot-static-ip`). Не снимать резервирование — ляжет Telegram.
- SSH: `ssh -i ~/.ssh/yc_faqbot_key yc-user@93.77.187.243`.
- `/opt/maxbot` → контейнер `maxbot`; `/opt/faqbot` → контейнер `faqbot`. У каждого свой `.env` и `./data`.
- Если SSH не отвечает — сначала `yc compute instance list --folder-id b1gvtru3guuc1oipcs4p`.

## Команды

```bash
# деплой файла (пример для MAX; для Telegram — /opt/faqbot)
scp -i ~/.ssh/yc_faqbot_key maxbot/maxbot.py yc-user@93.77.187.243:/tmp/max_maxbot.py
ssh ... 'cd /opt/maxbot && cp maxbot.py maxbot.py.bak-<метка> && cp /tmp/max_maxbot.py maxbot.py \
         && md5sum maxbot.py && sudo docker compose up -d --build'
sudo docker ps; sudo docker logs --since 1m maxbot          # проверка после деплоя
cd relay && npx wrangler deploy                              # релей (из папки relay/)
python -m py_compile bot.py maxbot/maxbot.py                 # минимальная проверка перед деплоем
```

После деплоя бота проверить в логе: «Документ загружен: FAQ_DPO_HSE_v5.docx», «Бот запущен»,
для Telegram — `getUpdates … 200 OK`. Если меняли промпт/FAQ — прогнать вопросы через
`sudo docker exec maxbot python -c 'import maxbot; print(maxbot.ask_question("…", []))'`
(импорт не запускает поллинг — `main` под `if __name__ == "__main__"`).

## Обязательные правила
1. **Сервер может отличаться от репозитория** — его меняли и другие сессии. Перед правкой
   сверить md5 серверного файла с локальным; если расходятся — сначала разобраться.
2. **Заливка на сервер:** уникальные имена во `/tmp` (`tg_bot.py`, `max_maxbot.py` — один раз
   перепутали одноимённые файлы), бэкап `*.bak-<метка>` рядом, сверка md5 после копирования.
3. **FAQ — в трёх местах:** `FAQ_DPO_HSE_v5.docx` в корне и в `maxbot/` (каждая папка —
   отдельный Docker-контекст) + публичная копия на Яндекс Диске (ссылка в приветствии и
   кнопке FAQ, по 2 места в `bot.py` и `maxbot.py`). Меняешь базу — меняй все три.
   ⚠️ **Файл, пересохранённый в Яндекс Документах, боту не подкладывать:** там гиперссылки
   превращаются в поля `HYPERLINK` (`w:instrText`), а `extract_paragraph_with_links()` читает
   только `w:hyperlink` — бот молча потеряет все URL из FAQ. Правки из публичной копии
   переносить в базу вручную. Публичная копия на 2026-10-04 отличается от базы редакторскими
   правками владельца (убрано введение, частоты, примечание) — это допустимо.
4. **Репозиторий публичный.** Секреты — только в `.env` на сервере. Не коммитить `.env`,
   ключи, ID администраторов, логи. `.wrangler/` в `.gitignore`.
5. **152-ФЗ:** логи (`/opt/*/data/*.csv`) содержат ФИО и user_id — хранить в РФ, не в git
   и не в иностранных облаках. Релей ничего не хранит и не логирует.
6. **Старый VPS 206.251.48.91** — не трогать (там чужие контейнеры). Снос — только по явному «ок».
7. Платные действия в облаке (новые ВМ, адреса, ресурсы) — только с согласия владельца.
8. Коммиты — маленькие, на русском, в конце `Co-Authored-By: Claude …`.

## Модель (Qwen 3.6 35B)
- Модель «с размышлениями»: **всегда** `extra_body={"reasoning_effort": "none"}`, иначе пустой
  `content` (`finish_reason=length`).
- Qwen в AI Studio включается **для каждого каталога отдельно**, иначе 403 даже с ролью editor.
- `SYSTEM_PROMPT` одинаковый в обоих ботах — правишь один, правь и второй.
- `suggest_reformulations()` — JSON-режим (`response_format`), подбирает до 3 вопросов из FAQ.

## Продуктовые правила (согласованы с заказчиком)
- **Каталог программ — только Школы:** `https://www.hse.ru/edu/dpo/?orgUnit=122999271`.
  Общий `hse.ru/edu/dpo/` запрещён и в FAQ, и в промпте.
- **Эскалация** = нажатие «📞 Связаться с менеджером» (`CB_MANAGER`, в т.ч. подпись, набранная
  текстом). Пишется в отдельный `escalations_log.csv` — **не** в `questions_log.csv`
  (`update_last_rating()` прицепит к ней оценку). Автопоказ контактов при «нет ответа» — не эскалация.
- **«◀️ Назад в меню»** — на каждом последнем сообщении бота в MAX (кнопки живут только на своём
  сообщении; `attachments: []` стирает все кнопки).
- Подписи кнопок MAX: лимит API 64 символа, на телефоне видно ~26–28. Старые длинные подписи,
  набранные текстом, бот по-прежнему понимает (`BTN_ASK_LEGACY`).
- Подсказки «возможно, вы хотели спросить» — callback-кнопки `sug:<idx>:<sha1[:6]>`; после
  списка подсказок оценку не спрашивать.
- Контакт менеджера в MAX — по номеру +7 916 211 19 67 (у личных аккаунтов MAX нет ссылок).
  Не отправлять пользователей в Telegram из MAX-бота.

## MAX — коротко (подробно в maxbot/README.md)
- Домен **только `https://botapi.max.ru`**; `platform-api2.max.ru` — TLS `unknown CA`.
- Токен — только заголовком `Authorization: <token>` (query → 401 `verify.token`).
- Только inline-кнопки; лимит текста 4000 (`MAX_MSG_LIMIT = 3900`); 2 сообщения/с на диалог.
- `bot_started` = первый `/start`; повтор гасится дедупликацией 5 с.
- Бот пишет только тем, кто открыл диалог (иначе 404 `dialog.not.found`) — так же и админам.
- `PATCH /me` (установка команд) с 2026-09-29 отвечает 404 `method.not.found` — бот логирует
  предупреждение и работает дальше; чинить не обязательно.

## Telegram и релей — коротко (подробно в relay/README.md)
- `api.telegram.org` из РФ недоступен; перебор IP/ВМ **бесполезен** (проверено, см. DECISIONS).
- `TELEGRAM_RELAY_URL` → `Application.builder().base_url()/base_file_url()`; PTB сам
  дописывает `bot<token>`.
- Worker пускает только `ALLOWED_IPS` (= IP ВМ) и `ALLOWED_BOT_IDS` (8709764083); без них 503.
- Симптом «IP не пускают»: `faqbot` Restarting + `TelegramError: Invalid server response`
  (релей отвечает 403 текстом, PTB ждёт JSON).
- Один поллер на токен, иначе 409. Telegram-версия в дашборд не шлёт.

## Дашборд
- `http://89.169.146.175:8080`, отдельный проект `C:\VKR 2\projects-dashboard` (свой CLAUDE.md).
- MAX-бот шлёт `POST {DASHBOARD_URL}/api/ingest` (`Bearer DASHBOARD_TOKEN`) через
  `_dashboard_post()` — фоновый поток, таймаут 5 с. Мониторинг не имеет права тормозить бота.
- События: вопрос/ответ (`dedup_key = user_id:дата_время`), оценка (`{"op":"rate"}`), `event_type: "escalation"`.

## Среда (Windows, Claude Code)
- Bash — Git Bash: кириллица в путях ломает Python (`C:\Users\Владимир\...`) — работать с копиями
  в ASCII-путях или через PowerShell. В Bash `~/.ssh/known_hosts` недоступен — добавлять
  `-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null`.
- Авто-режим иногда блокирует Bash-команды про релей («Traffic Redirection»); PowerShell проходит.
- `wrangler`: «non-interactive… CLOUDFLARE_API_TOKEN» = истёк OAuth → `npx wrangler whoami` обновляет.
