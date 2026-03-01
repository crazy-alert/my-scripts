SECRET_KEY=$(openssl rand -hex 16 | tr -d '\n' | tr -d ' ')
PROXY_PORT=1443
HIDDIFY_URL=https://sub.kleomars.top/4upKJvqjmyZ5RJK0hgWb/2e34fb55-eec9-46d2-8528-c65cd87754da/#MTProto

docker-compose down
docker rm -f hiddify-client 2>/dev/null
rm -f docker-compose.yml .env hiddify-config.json mtproto-config.toml

cat > .env <<EOF
SECRET=${SECRET_KEY}
HIDDIFY_URL=${HIDDIFY_URL}
PROXY_PORT=${PROXY_PORT}
EOF

cat > mtproto.conf <<EOF
proxy hiddify:1080;
port ${PROXY_PORT};
secret ${SECRET_KEY};
workers 2
EOF

cat > docker-compose.yml <<'EOF'
services:
  hiddify:
    image: alpine:latest
    container_name: hiddify
    restart: unless-stopped
    command: >
      sh -c "
      apk add --no-cache curl wget &&
      wget -O /tmp/sing-box.tar.gz https://github.com/SagerNet/sing-box/releases/download/v1.8.0/sing-box-1.8.0-linux-amd64.tar.gz &&
      tar -xzf /tmp/sing-box.tar.gz -C /tmp/ &&
      mv /tmp/sing-box-1.8.0-linux-amd64/sing-box /usr/local/bin/ &&
      rm -rf /tmp/sing-box* &&
      curl -sL $${HIDDIFY_URL} -o /etc/sing-box/config.json &&
      /usr/local/bin/sing-box run -c /etc/sing-box/config.json
      "
    environment:
      - HIDDIFY_URL=${HIDDIFY_URL}
    networks:
      - proxy-net

  mtproto:
    image: telegrammessenger/proxy:latest
    container_name: mtproto
    restart: unless-stopped
    ports:
      - "${PROXY_PORT}:${PROXY_PORT}"
    volumes:
      - ./mtproto.conf:/mtproto.conf
    command: mtproto-proxy /mtproto.conf
    networks:
      - proxy-net
    depends_on:
      - hiddify

networks:
  proxy-net:
    driver: bridge
EOF


echo "🔗 Ссылка для Telegram:"
echo "tg://proxy?server=$(curl -s ifconfig.me)&port=${PROXY_PORT}&secret=${SECRET_KEY}"
echo ""

docker-compose up -d && docker-compose logs -f