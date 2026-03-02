#!/bin/bash
set -e

# Цвета (можно убрать, но для читаемости оставим)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}🚀 Установка MTProto Proxy для Telegram${NC}"
echo ""

# --- Ввод основных параметров ---
DEFAULT_PORT=443
read -p "🔌 Введите внешний порт (по умолчанию ${DEFAULT_PORT}): " PORT
PORT=${PORT:-$DEFAULT_PORT}

echo -e "${YELLOW}🔑 Секретный ключ (16 байт в hex, 32 символа)${NC}"
echo "Если оставить пустым, будет сгенерирован автоматически."
read -p "👉 SECRET: " SECRET
if [ -z "$SECRET" ]; then
    SECRET=$(openssl rand -hex 16)
    echo -e "${BLUE}Сгенерирован секрет: ${SECRET}${NC}"
fi

read -p "🔢 Количество секретов (если нужно несколько, оставьте 1): " SECRET_COUNT
SECRET_COUNT=${SECRET_COUNT:-1}

read -p "⚙️ Количество воркеров (по умолчанию 2): " WORKERS
WORKERS=${WORKERS:-2}

# --- Ввод тега (опционально) ---
echo -e "${YELLOW}🏷 Регистрация у @MTProxybot (для статистики и тега)${NC}"
echo "Вы можете зарегистрировать прокси позже вручную."
read -p "👉 Введите тег, если уже получили (иначе оставьте пустым): " TAG

# --- Ввод вышестоящего прокси (опционально) ---
echo -e "${YELLOW}🌐 Вышестоящий прокси для подключения к Telegram${NC}"
echo "Если вы хотите, чтобы этот MTProxy выходил в интернет через другой прокси (например, Hiddify), укажите его."
echo "Поддерживаются форматы: http://proxy-ip:port, https://proxy-ip:port, socks5://proxy-ip:port"
echo "Также можно указать с аутентификацией: http://user:pass@proxy-ip:port"
UPSTREAM_PROXY=""
while true; do
    read -p "👉 Введите URL вышестоящего прокси (или оставьте пустым для прямого выхода): " PROXY_URL
    if [ -z "$PROXY_URL" ]; then
        echo -e "${BLUE}Прокси не используется, трафик пойдёт напрямую.${NC}"
        break
    fi
    # Проверка работоспособности прокси
    echo -e "${YELLOW}Проверяем прокси...${NC}"
    if curl -x "$PROXY_URL" -s -o /dev/null -I --max-time 10 https://core.telegram.org; then
        echo -e "${GREEN}✅ Прокси работает.${NC}"
        UPSTREAM_PROXY="$PROXY_URL"
        break
    else
        echo -e "${RED}❌ Не удалось подключиться через этот прокси. Попробуйте снова или оставьте пустым.${NC}"
    fi
done

# --- Сборка параметров docker run ---
ENV_VARS="-e SECRET=\"${SECRET}\" -e WORKERS=\"${WORKERS}\""

if [ "$SECRET_COUNT" -gt 1 ]; then
    ENV_VARS="$ENV_VARS -e SECRET_COUNT=\"${SECRET_COUNT}\""
fi

if [ -n "$TAG" ]; then
    ENV_VARS="$ENV_VARS -e TAG=\"${TAG}\""
fi

if [ -n "$UPSTREAM_PROXY" ]; then
    # Устанавливаем переменные HTTP_PROXY и HTTPS_PROXY (для совместимости)
    ENV_VARS="$ENV_VARS -e HTTP_PROXY=\"${UPSTREAM_PROXY}\" -e HTTPS_PROXY=\"${UPSTREAM_PROXY}\""
    # Можно также установить NO_PROXY для локальных адресов, если нужно
    ENV_VARS="$ENV_VARS -e NO_PROXY=\"localhost,127.0.0.1\""
fi

# --- Запуск контейнера ---
echo -e "${GREEN}🚀 Запускаем контейнер...${NC}"

# Формируем команду
CMD="docker run -d \\
    --name=mtproto-proxy \\
    --restart=always \\
    -p ${PORT}:443 \\
    ${ENV_VARS} \\
    -v proxy-config:/data \\
    telegrammessenger/proxy:latest"

# Выполняем
eval $CMD

# Небольшая задержка для инициализации
sleep 3

# --- Вывод результатов ---
echo -e "${YELLOW}📋 Логи контейнера:${NC}"
docker logs mtproto-proxy --tail 20

IP=$(curl -s ifconfig.me)
echo ""
echo -e "${GREEN}✅ Прокси запущен!${NC}"
echo -e "${BLUE}🔗 Ссылка для подключения:${NC}"
echo "tg://proxy?server=${IP}&port=${PORT}&secret=${SECRET}"
echo ""
echo -e "${GREEN}🎉 Готово! Контейнер будет автоматически запускаться при перезагрузке.${NC}"
echo "Для просмотра логов: docker logs -f mtproto-proxy"
echo "Для остановки: docker stop mtproto-proxy"
if [ -n "$UPSTREAM_PROXY" ]; then
    echo -e "${BLUE}🌐 Трафик к Telegram идёт через вышестоящий прокси: ${UPSTREAM_PROXY}${NC}"
fi