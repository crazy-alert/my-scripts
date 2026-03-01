#!/bin/bash
set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Папка установки по умолчанию
DEFAULT_INSTALL_DIR="/opt/telegram-via-hiddify"

echo -e "${GREEN}🚀 Начинаем интерактивную установку Telegram Proxy через Hiddify${NC}"
echo ""

# Запрос папки установки
echo -e "${YELLOW}📂 Введите путь для установки (по умолчанию: ${DEFAULT_INSTALL_DIR}):${NC}"
read -p "👉 " INSTALL_DIR
if [ -z "$INSTALL_DIR" ]; then
    INSTALL_DIR="${DEFAULT_INSTALL_DIR}"
    echo -e "${BLUE}Используется папка по умолчанию: ${INSTALL_DIR}${NC}"
else
    echo -e "${GREEN}Выбрана папка: ${INSTALL_DIR}${NC}"
fi

# Создание папки установки
mkdir -p "${INSTALL_DIR}"

# Запрос ссылки на подписку
echo -e "${YELLOW}📋 Введите вашу ссылку на подписку Hiddify (remote_url):${NC}"
echo -e "${BLUE}Пример: https://your-hiddify-server.com/subscription/path/your-uuid${NC}"
read -p "👉 " HIDDIFY_URL

if [ -z "$HIDDIFY_URL" ]; then
    echo -e "${RED}❌ Ошибка: ссылка не может быть пустой. Скрипт прерван.${NC}"
    exit 1
fi

# Запрос порта
echo -e "${YELLOW}🔌 Введите порт для Telegram Proxy (по умолчанию 443):${NC}"
read -p "👉 " PROXY_PORT
if [ -z "$PROXY_PORT" ]; then
    PROXY_PORT=443
    echo -e "${BLUE}Используется порт по умолчанию: ${PROXY_PORT}${NC}"
else
    echo -e "${GREEN}Выбран порт: ${PROXY_PORT}${NC}"
fi

echo -e "${GREEN}✅ Ссылка принята: ${HIDDIFY_URL}${NC}"
echo ""

# Обновление системы
echo -e "${YELLOW}📦 Обновление системы...${NC}"
sudo apt update && sudo apt upgrade -y

# Установка зависимостей
echo -e "${YELLOW}📦 Установка зависимостей...${NC}"
sudo apt install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common \
    git \
    wget \
    htop \
    net-tools \
    telnet \
    ufw \
    openssl \
    jq \
    vim \
    nano

# Установка Docker
echo -e "${YELLOW}🐳 Установка Docker...${NC}"
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Установка Docker Compose
echo -e "${YELLOW}📦 Установка Docker Compose...${NC}"
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Добавление пользователя в группу docker
sudo usermod -aG docker $USER

# Настройка файрвола
echo -e "${YELLOW}🔥 Настройка файрвола...${NC}"
sudo ufw --force enable
sudo ufw allow 22/tcp
sudo ufw allow ${PROXY_PORT}/tcp
sudo ufw allow 80/tcp

# Переход в папку установки
cd "${INSTALL_DIR}"

# Генерация секретного ключа
SECRET_KEY=$(openssl rand -hex 16)
echo -e "${GREEN}🔑 Сгенерирован секретный ключ: ${SECRET_KEY}${NC}"

# Создание конфига Hiddify
echo -e "${YELLOW}⚙️ Создание конфигурации Hiddify...${NC}"
cat > hiddify-config.json <<EOF
{
  "service-mode": "client",
  "log-level": "info",
  "allow-connection-from-lan": true,
  "inbounds": [
    {
      "type": "socks",
      "tag": "socks-in",
      "listen": "0.0.0.0",
      "listen_port": 1080
    }
  ],
  "outbounds": [
    {
      "type": "remote",
      "tag": "remote",
      "remote_url": "${HIDDIFY_URL}"
    }
  ],
  "route": {
    "rules": [
      {
        "inbound": ["socks-in"],
        "outbound": "remote"
      }
    ]
  }
}
EOF

# Создание конфига MTProto
cat > mtproto-config.toml <<EOF
listen = "0.0.0.0:${PROXY_PORT}"
proxy = "socks5://hiddify-client:1080"
workers = 2
EOF

# Создание docker-compose.yml
cat > docker-compose.yml <<EOF
version: '3.8'

services:
  hiddify-client:
    image: ghcr.io/hiddify/hiddify-core:latest
    container_name: hiddify-client
    restart: unless-stopped
    volumes:
      - ./hiddify-config.json:/app/config/config.json
    environment:
      - CONFIG=file:///app/config/config.json
    networks:
      - proxy-net

  mtproto-proxy:
    image: telegrammessenger/proxy:latest
    container_name: mtproto-proxy
    restart: unless-stopped
    ports:
      - "${PROXY_PORT}:${PROXY_PORT}"
    environment:
      - SECRET=\${SECRET}
    volumes:
      - ./mtproto-config.toml:/config.toml
    command: --config=/config.toml
    networks:
      - proxy-net
    depends_on:
      - hiddify-client

networks:
  proxy-net:
    driver: bridge
EOF

# Создание .env файла
echo "SECRET=${SECRET_KEY}" > .env

# Получение внешнего IP
SERVER_IP=$(curl -s ifconfig.me)

echo ""
echo -e "${GREEN}✅ ========== УСТАНОВКА ЗАВЕРШЕНА ==========${NC}"
echo -e "${GREEN}📋 Ваши данные для подключения:${NC}"
echo -e "${YELLOW}📂 Папка установки:${NC} ${INSTALL_DIR}"
echo -e "${YELLOW}🌐 IP сервера:${NC} ${SERVER_IP}"
echo -e "${YELLOW}🔌 Порт:${NC} ${PROXY_PORT}"
echo -e "${YELLOW}🔑 Секретный ключ:${NC} ${SECRET_KEY}"
echo -e "${YELLOW}📡 Ссылка подписки Hiddify:${NC} ${HIDDIFY_URL}"
echo ""
echo -e "${BLUE}🔗 Ссылка для Telegram:${NC}"
echo "tg://proxy?server=${SERVER_IP}&port=${PROXY_PORT}&secret=${SECRET_KEY}"
echo ""
echo -e "${YELLOW}👉 Дальнейшие действия:${NC}"
echo "1. Выполните команду: newgrp docker (или перелогиньтесь)"
echo "2. Перейдите в папку установки: cd ${INSTALL_DIR}"
echo "3. Запустите контейнеры: docker-compose up -d"
echo "4. Проверьте логи: docker-compose logs -f"
echo ""
echo -e "${GREEN}🎉 Готово! Скопируйте ссылку выше и отправьте себе в Telegram${NC}"