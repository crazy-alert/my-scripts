<div align="center">
  
# mtprotoRelay2hiddify — Telegram MTProto Proxy через Hiddify
![Bash](https://img.shields.io/badge/language-bash-blue.svg)
![Docker](https://img.shields.io/badge/docker-required-blue)
![License](https://img.shields.io/badge/license-MIT-green)

**Одна команда — полноценный Telegram MTProto Proxy, который ходит в интернет через ваш Hiddify-сервер**
```bash
curl -sSL https://raw.githubusercontent.com/crazy-alert/my-scripts/refs/heads/main/mtrptoRelay2hiddify.sh | bash
```

**Relay для Hiddify сервера**
```bash
bash -c "$(curl -L https://raw.githubusercontent.com/hiddify/hiddify-relay/main/install.sh)"
```
**Ubuntu: настроить SSH только по ключам, установить и настроить fail2ban, а также межсетевой экран ufw**
https://