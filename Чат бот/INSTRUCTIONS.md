# Telegram-бот для ответов по документу FAQ ДПО ВШЭ

Бот читает ваш документ FAQ_DPO_HSE_v3.docx и отвечает на вопросы пользователей, используя OpenAI API.

## Что нужно

- Python 3.10+
- Telegram-токен от @BotFather
- API-ключ OpenAI

## Пошаговая инструкция

### 1. Создайте бота в Telegram

1. Откройте Telegram и найдите бота **@BotFather**
2. Напишите ему `/newbot`
3. Введите имя бота (например: «FAQ ДПО ВШЭ»)
4. Введите username бота (например: `faq_dpo_hse_bot`) — должен заканчиваться на `bot`
5. BotFather пришлёт вам **токен** — скопируйте его

### 2. Получите ключ OpenAI API

1. Зайдите на https://platform.openai.com/api-keys
2. Создайте новый ключ (Create new secret key)
3. Скопируйте ключ (он начинается с `sk-`)

### 3. Настройте проект

```bash
# Скопируйте шаблон настроек
cp .env.example .env
```

Откройте файл `.env` в текстовом редакторе и заполните:

```
TELEGRAM_TOKEN=вставьте_токен_от_BotFather
OPENAI_API_KEY=sk-вставьте_ваш_ключ
DOCUMENT_PATH=FAQ_DPO_HSE_v3.docx
```

### 4. Установите зависимости

```bash
pip install -r requirements.txt
```

### 5. Запустите бота

```bash
python bot.py
```

Вы увидите сообщение «Бот запущен!» — теперь откройте Telegram, найдите вашего бота и напишите `/start`.

## Остановка бота

Нажмите `Ctrl+C` в терминале.

## Структура файлов

```
Чат бот/
├── bot.py                  # Код бота
├── requirements.txt        # Зависимости Python
├── .env.example            # Шаблон настроек
├── .env                    # Ваши настройки (создаёте сами)
└── FAQ_DPO_HSE_v3.docx     # Документ с FAQ (уже в папке)
```
