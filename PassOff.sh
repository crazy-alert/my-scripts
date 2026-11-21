#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Отключение входа по паролю SSH (socket-activation edition)
# ============================================================

CONF_DIR="/etc/ssh/sshd_config.d"
TARGET_CONF="${CONF_DIR}/01-hardening.conf"
BACKUP_SUFFIX=".bak.$(date +%Y%m%d%H%M%S)"
SSH_UNIT=""

log()  { echo -e "\033[1;32m[+]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
die()  { echo -e "\033[1;31m[✗]\033[0m $*" >&2; exit 1; }

stop_ssh_units() {
    local unit
    for unit in ssh.socket ssh.service sshd.service; do
        systemctl stop "$unit" 2>/dev/null || true
    done
}

fail_closed() {
    warn "$*"
    warn "Оставляем SSH остановленным, чтобы парольный вход не оставался доступным."
    stop_ssh_units
    if command -v pkill >/dev/null 2>&1; then
        pkill -x sshd 2>/dev/null || true
    fi
    die "Проверьте сервер через консоль провайдера. Конфигурация не откачена."
}

select_ssh_unit() {
    local unit
    # Prefer the unit configured to start at boot. A package may install
    # both socket and service units even though only one is in use.
    for unit in ssh.socket ssh.service sshd.service; do
        if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
            SSH_UNIT="$unit"
            return 0
        fi
    done
    for unit in ssh.socket ssh.service sshd.service; do
        if systemctl is-active --quiet "$unit" 2>/dev/null; then
            SSH_UNIT="$unit"
            return 0
        fi
    done
    for unit in ssh.socket ssh.service sshd.service; do
        if systemctl cat "$unit" >/dev/null 2>&1; then
            SSH_UNIT="$unit"
            return 0
        fi
    done
    return 1
}

password_auth_is_disabled() {
    local config
    config="$(sshd -T 2>/dev/null)" || return 1
    grep -qi '^passwordauthentication no$' <<<"${config}" &&
        grep -qi '^kbdinteractiveauthentication no$' <<<"${config}" &&
        grep -qi '^permitrootlogin prohibit-password$' <<<"${config}"
}

# 1. Root
[[ "${EUID}" -eq 0 ]] || die "Запускать от root."

# 2. sshd присутствует
command -v sshd >/dev/null 2>&1 || die "sshd не найден."
command -v systemctl >/dev/null 2>&1 || die "systemctl не найден: этот скрипт требует systemd."
systemctl is-system-running >/dev/null 2>&1 || warn "systemd работает не в штатном режиме; продолжим с проверкой unit."
select_ssh_unit || fail_closed "Не найден unit ssh.socket, ssh.service или sshd.service."

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
mkdir -p "${CONF_DIR}" /run/sshd
if ! sshd -t; then
    fail_closed "sshd -t: ошибка синтаксиса. Новая конфигурация оставлена, SSH будет остановлен."
fi
log "Синтаксис корректен."

if ! password_auth_is_disabled; then
    fail_closed "sshd -T не подтвердил запрет пароля, keyboard-interactive и root-входа по паролю."
fi

# 7. Перезапуск сокета (и связанной службы)
log "Перезапускаем ${SSH_UNIT} ..."
systemctl daemon-reload
if ! systemctl restart "${SSH_UNIT}"; then
    fail_closed "Не удалось перезапустить ${SSH_UNIT}."
fi

# 8. Финальная проверка
sleep 1
if ! systemctl is-active --quiet "${SSH_UNIT}"; then
    fail_closed "${SSH_UNIT} не активен после перезапуска."
fi

if ! password_auth_is_disabled; then
    fail_closed "После перезапуска sshd -T не подтвердил запрет парольной аутентификации."
fi

log "Готово. Вход по паролю отключён."
log "Проверка с клиента: ssh -o PreferredAuthentications=password root@<IP>"
log "Ожидается: Permission denied (publickey)."
