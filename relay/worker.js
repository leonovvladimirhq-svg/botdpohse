/**
 * Посредник Telegram Bot API на Cloudflare Workers.
 *
 * Зачем: с сентября 2026 api.telegram.org недоступен с российских серверов
 * (фильтрация по назначению, не по нашему IP — замер на четырёх ВМ дал
 * идентичный результат). Бот обращается сюда, Worker передаёт запрос в Telegram
 * и возвращает ответ. Виртуальную машину арендовать не нужно.
 *
 * Бот ходит по адресу https://<worker>/bot<TOKEN>/<метод>, потому что
 * python-telegram-bot сам дописывает `bot<токен>` к base_url. Файлы —
 * https://<worker>/file/bot<TOKEN>/<путь>.
 *
 * Данные здесь не хранятся и не логируются: Worker без состояния, тела запросов
 * и токен никуда не пишутся. База, лог и обращения к Yandex AI Studio остаются в РФ.
 *
 * Настройки (переменные окружения Worker, задаются при деплое):
 *   ALLOWED_IPS      — кто может пользоваться релеем, через запятую (IP ВМ бота).
 *   ALLOWED_BOT_IDS  — какие боты пропускать: числа до двоеточия в токене.
 * Хотя бы одна из них обязана быть задана — иначе Worker откажется работать.
 * Без этого получится открытый прокси к Telegram для кого угодно с любым токеном.
 */

const TELEGRAM_API = "https://api.telegram.org";

// /bot<id>:<секрет>/<метод>  или  /file/bot<id>:<секрет>/<путь>
const BOT_PATH = /^\/(file\/)?bot(\d{5,}):[A-Za-z0-9_-]{20,}(\/|$)/;

// Заголовки, которые не имеет смысла или нельзя передавать дальше.
const DROP_HEADERS = new Set([
  "host", "connection", "content-length", "cf-connecting-ip", "cf-ipcountry",
  "cf-ray", "cf-visitor", "cf-worker", "cf-ew-via", "cdn-loop",
  "x-forwarded-for", "x-forwarded-proto", "x-forwarded-host", "x-real-ip",
]);

function textResponse(status, message) {
  return new Response(message + "\n", {
    status,
    headers: { "content-type": "text/plain; charset=utf-8" },
  });
}

function parseList(value) {
  return (value || "").split(",").map((s) => s.trim()).filter(Boolean);
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // Проверка живости — можно дёрнуть с ВМ бота, токен не нужен.
    if (url.pathname === "/relay-health") {
      return textResponse(200, "ok");
    }

    const allowedIps = parseList(env.ALLOWED_IPS);
    const allowedBotIds = parseList(env.ALLOWED_BOT_IDS);

    // Fail closed: пока не заданы ограничения, релей не работает. Иначе любой,
    // кто узнает адрес, получит бесплатный прокси к Telegram.
    if (allowedIps.length === 0 && allowedBotIds.length === 0) {
      return textResponse(
        503,
        "Релей не настроен. Задайте переменные ALLOWED_IPS и/или ALLOWED_BOT_IDS " +
          "в настройках Worker (Settings → Variables) и повторите деплой."
      );
    }

    // Кто пришёл. CF-Connecting-IP проставляет сам Cloudflare, подделать нельзя.
    if (allowedIps.length > 0) {
      const clientIp = request.headers.get("CF-Connecting-IP") || "";
      if (!allowedIps.includes(clientIp)) {
        return textResponse(403, "Доступ запрещён: этот IP не в списке разрешённых.");
      }
    }

    // Путь должен быть похож на обращение к Bot API.
    const match = url.pathname.match(BOT_PATH);
    if (!match) {
      return textResponse(
        404,
        "Ожидается путь вида /bot<TOKEN>/<метод> или /file/bot<TOKEN>/<путь>."
      );
    }

    // Какой бот. Ограничиваем релей своими ботами, даже если IP совпал.
    if (allowedBotIds.length > 0 && !allowedBotIds.includes(match[2])) {
      return textResponse(403, "Доступ запрещён: этот бот не в списке разрешённых.");
    }

    // Пересборка запроса в Telegram: путь и query сохраняются как есть.
    const headers = new Headers();
    for (const [name, value] of request.headers) {
      if (!DROP_HEADERS.has(name.toLowerCase())) headers.set(name, value);
    }

    const hasBody = request.method !== "GET" && request.method !== "HEAD";
    const init = {
      method: request.method,
      headers,
      body: hasBody ? request.body : undefined,
      redirect: "follow",
    };
    // Тело передаётся потоком (важно для sendDocument и других больших запросов).
    // В Workers это работает само, а undici в Node требует явного duplex —
    // без него оффлайн-тест worker.js падает. Лишним здесь параметр не бывает.
    if (hasBody) init.duplex = "half";
    const upstream = new Request(TELEGRAM_API + url.pathname + url.search, init);

    try {
      const response = await fetch(upstream);
      // Тело отдаём потоком — это важно для getFile и длинных ответов.
      const outHeaders = new Headers(response.headers);
      outHeaders.delete("transfer-encoding");
      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers: outHeaders,
      });
    } catch (err) {
      // Сообщение об ошибке — без пути и токена.
      return textResponse(502, "Не удалось связаться с Telegram: " + (err && err.name));
    }
  },
};
