#!/usr/bin/env bash
# ============================================================
# Релей Telegram Bot API — reverse-proxy за пределами РФ.
#
# Ставится на свежую Ubuntu 22.04 в Yandex Cloud kz1 (Казахстан). Бот в РФ
# обращается к https://<хост релея>/bot<token>/..., релей передаёт запрос в
# https://api.telegram.org и возвращает ответ. Ничего не хранит, тела запросов
# не логирует, принимает соединения только с IP бэкенда.
#
# Использование (от root на ВМ релея):
#   sudo bash install-relay.sh <IP_бэкенда_в_РФ> [<хост релея>]
#
#   <IP_бэкенда_в_РФ> — публичный IP ВМ с ботом (сейчас 89.169.142.74).
#   <хост релея>      — DNS-имя для сертификата. Если не задано, берётся
#                       <публичный IP>.sslip.io — это публичный сервис, который
#                       резолвит имя вида 1-2-3-4.sslip.io в 1.2.3.4, и Let's
#                       Encrypt выдаёт на такое имя обычный доверенный сертификат.
#                       Своего домена для релея не нужно.
#
# Повторный запуск безопасен: конфиг перезаписывается, сертификат переиспользуется.
# ============================================================
set -euo pipefail

BACKEND_IP="${1:?Укажите IP бэкенда: sudo bash install-relay.sh <IP_бэкенда> [<хост>]}"
PUBLIC_IP="$(curl -s -4 --max-time 10 https://ifconfig.me || curl -s -4 --max-time 10 https://api.ipify.org)"
[ -n "$PUBLIC_IP" ] || { echo "Не удалось определить публичный IP ВМ"; exit 1; }
RELAY_HOST="${2:-${PUBLIC_IP//./-}.sslip.io}"

echo "==> Бэкенд (кому разрешён доступ): $BACKEND_IP"
echo "==> Публичный IP релея:            $PUBLIC_IP"
echo "==> Хост релея (сертификат):       $RELAY_HOST"

# --- 0. Проверка: отсюда Telegram вообще доступен? Иначе релей бессмыслен. ---
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 https://api.telegram.org/bot0:x/getMe || true)"
if [ "$code" != "404" ] && [ "$code" != "401" ]; then
  echo "!! api.telegram.org с этой ВМ недоступен (HTTP '$code'). Релей здесь работать не будет."
  exit 1
fi
echo "==> api.telegram.org доступен (HTTP $code) — продолжаем"

# --- 1. Пакеты ---
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq nginx certbot ufw >/dev/null

# --- 2. Файрвол: SSH всем, 80 всем (только для Let's Encrypt), 443 — только бэкенду ---
ufw --force reset >/dev/null
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow OpenSSH >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow from "$BACKEND_IP" to any port 443 proto tcp >/dev/null
ufw --force enable >/dev/null
echo "==> ufw: 22 всем, 80 всем (ACME), 443 только $BACKEND_IP"

# --- 3. Временный HTTP-конфиг для проверки владения именем (ACME http-01) ---
mkdir -p /var/www/html
rm -f /etc/nginx/sites-enabled/default
cat > /etc/nginx/sites-available/telegram-relay <<EOF
server {
    listen 80;
    server_name ${RELAY_HOST};
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 444; }
}
EOF
ln -sf /etc/nginx/sites-available/telegram-relay /etc/nginx/sites-enabled/telegram-relay
nginx -t
systemctl enable --now nginx >/dev/null
systemctl reload nginx

# --- 4. Сертификат Let's Encrypt (переиспользуется, если уже есть) ---
if [ ! -f "/etc/letsencrypt/live/${RELAY_HOST}/fullchain.pem" ]; then
  certbot certonly --webroot -w /var/www/html -d "$RELAY_HOST" \
    --non-interactive --agree-tos --register-unsafely-without-email \
    --deploy-hook "systemctl reload nginx"
fi
echo "==> сертификат: /etc/letsencrypt/live/${RELAY_HOST}/"

# --- 5. Боевой конфиг: TLS + allowlist + проксирование в Telegram ---
cat > /etc/nginx/sites-available/telegram-relay <<EOF
# Релей Telegram Bot API. Сгенерирован install-relay.sh $(date -u +%Y-%m-%dT%H:%MZ).
# Апстрим задан переменной + resolver, чтобы nginx перерезолвил api.telegram.org
# каждые 5 минут, а не один раз при старте.
resolver 1.1.1.1 8.8.8.8 valid=300s ipv6=off;
server_tokens off;

server {
    listen 80;
    server_name ${RELAY_HOST};
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 444; }
}

server {
    listen 443 ssl http2;
    server_name ${RELAY_HOST};

    ssl_certificate     /etc/letsencrypt/live/${RELAY_HOST}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${RELAY_HOST}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    # Только бэкенд. Открытый релей — это бесплатный прокси к Telegram для кого угодно.
    allow ${BACKEND_IP};
    deny all;

    # Тела запросов и токен бота в логах жить не должны.
    access_log off;
    error_log /var/log/nginx/telegram-relay.error.log warn;

    client_max_body_size 50m;

    location = /relay-health { default_type text/plain; return 200 "ok"; }

    location / {
        set \$upstream https://api.telegram.org;
        proxy_pass \$upstream;
        proxy_ssl_server_name on;
        proxy_ssl_name api.telegram.org;
        proxy_set_header Host api.telegram.org;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_buffering off;
        proxy_connect_timeout 15s;
        proxy_read_timeout 120s;   # long polling: бот держит getUpdates до 10–30 с
        proxy_send_timeout 60s;
    }
}
EOF
nginx -t
systemctl reload nginx

# --- 6. Самопроверка ---
echo "==> проверка через сам релей (ожидаем 404 — Telegram ответил на пустой токен):"
curl -s -o /dev/null -w "   https://${RELAY_HOST}/bot0:x/getMe -> HTTP %{http_code}\n" \
  --max-time 20 "https://${RELAY_HOST}/bot0:x/getMe" || true

cat <<EOF

============================================================
Релей готов.

В .env бота (на ВМ в РФ, /opt/faqbot/.env) добавьте:
    TELEGRAM_RELAY_URL=https://${RELAY_HOST}
и перезапустите: cd /opt/faqbot && sudo docker compose up -d

Проверка с ВМ бота:
    curl -s https://${RELAY_HOST}/bot<TOKEN>/getMe

Сертификат продлевается сам (systemd-таймер certbot, порт 80 для этого открыт).
Доступ к 443 разрешён только с ${BACKEND_IP} (ufw + nginx allow/deny).
Логи тел запросов отключены. Изменить бэкенд: перезапустить скрипт с новым IP.
============================================================
EOF
