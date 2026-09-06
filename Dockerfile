FROM python:3.11-slim

WORKDIR /app

# Зависимости отдельным слоем для кеширования
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Код и база знаний (FAQ). Лог вопросов пишется в /data (volume), см. .env: LOG_FILE
COPY bot.py .
COPY FAQ_DPO_HSE_v5.docx FAQ_DPO_HSE_v3.docx ./

# Каталог для персистентных данных (лог вопросов)
RUN mkdir -p /data

CMD ["python", "-u", "bot.py"]
