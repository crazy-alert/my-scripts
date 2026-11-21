#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Отключение входа по паролю SSH (socket-activation edition)
# ============================================================

CONF_DIR="/etc/ssh/sshd_config.d"
TARGET_CONF="${CONF_DIR}/01-hardening.conf"
BACKUP_SUFFIX=".bak.$(date +%Y%m%d%H%M%S)"
SSH_UNIT="ssh.socket"

log()  { echo -e "\033[1;32m[+]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
die()  { echo -e "\033[1;31m[✗]\033[0m $*" >&2; exit 1; }

# 1. Root
[[ "${EUID}" -eq 0 ]] || die "Запускать от root."

# 2. sshd присутствует
command -v sshd >/dev/null 2>&1 || die "sshd не найден."

# 3. Проверка authorized_keys
if [[ ! -s /root/.ssh/authorized_keys ]]; then
    warn "У root нет непустого authorized_keys."
    warn "Отключение пароля может лишить вас доступа к серверу!"
    read -r -p "Продолжить? (yes/no): " ans
    [[ "${ans}" == "yes" ]] || die "Отменено."
fi

# 4. Бэкап существующего файла
if [[ -f "${TARGET_CONF}" ]]; then
    cp -a "${TARGET_CONF}" "${TARGET_CONF}${BACKUP_SUFFIX}"
    log "Бэкап: ${TARGET_CONF}${BACKUP_SUFFIX}"
fi

# 5. Запись конфигурации
cat > "${TARGET_CONF}" <<'EOF'
# Отключение входа по паролю (сгенерировано PassOff.sh)
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
chmod 644 "${TARGET_CONF}"
log "Записан ${TARGET_CONF}"

# 6. Проверка синтаксиса
mkdir -p /run/sshd
if ! sshd -t; then
    warn "sshd -t: ошибка синтаксиса. Откат."
    if [[ -f "${TARGET_CONF}${BACKUP_SUFFIX}" ]]; then
        mv -f "${TARGET_CONF}${BACKUP_SUFFIX}" "${TARGET_CONF}"
    else
        rm -f "${TARGET_CONF}"
    fi
    die "Изменения откачены."
fi
log "Синтаксис корректен."

# 7. Перезапуск сокета (и связанной службы)
log "Перезапускаем ${SSH_UNIT} ..."
systemctl daemon-reload
systemctl restart "${SSH_UNIT}"

# 8. Финальная проверка
sleep 1
if ! systemctl is-active --quiet "${SSH_UNIT}"; then
    warn "${SSH_UNIT} не активен после перезапуска! Откат."
    if [[ -f "${TARGET_CONF}${BACKUP_SUFFIX}" ]]; then
        mv -f "${TARGET_CONF}${BACKUP_SUFFIX}" "${TARGET_CONF}"
    else
        rm -f "${TARGET_CONF}"
    fi
    systemctl daemon-reload
    systemctl restart "${SSH_UNIT}" || true
    die "Откат выполнен, ${SSH_UNIT} перезапущен."
fi

if ! sshd -T | grep -qi '^passwordauthentication no$'; then
    warn "После перезапуска sshd -T всё ещё показывает yes."
    warn "Проверьте: grep -r -i passwordauthentication /etc/ssh/sshd_config.d/"
    if [[ -f "${TARGET_CONF}${BACKUP_SUFFIX}" ]]; then
        mv -f "${TARGET_CONF}${BACKUP_SUFFIX}" "${TARGET_CONF}"
    else
        rm -f "${TARGET_CONF}"
    fi
    systemctl daemon-reload
    systemctl restart "${SSH_UNIT}" || true
    die "Откат выполнен."
fi

if ! sshd -T | grep -qi '^kbdinteractiveauthentication no$'; then
    warn "KbdInteractiveAuthentication не отключён — проверьте вручную."
fi

log "Готово. Вход по паролю отключён."
log "Проверка с клиента: ssh -o PreferredAuthentications=password root@<IP>"
log "Ожидается: Permission denied (publickey)."
