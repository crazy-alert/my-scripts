#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Отключение входа по паролю SSH (с защитой от потери доступа)
# ============================================================

CONF_DIR="/etc/ssh/sshd_config.d"
TARGET_CONF="${CONF_DIR}/01-hardening.conf"
BACKUP_SUFFIX=".bak.$(date +%Y%m%d%H%M%S)"

log()  { echo -e "\033[1;32m[+]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
die()  { echo -e "\033[1;31m[✗]\033[0m $*" >&2; exit 1; }

# 1. Проверка root
if [[ "${EUID}" -ne 0 ]]; then
    die "Скрипт нужно запускать от root."
fi

# 2. Проверка, что sshd установлен и управляется systemd
command -v sshd >/dev/null 2>&1 || die "sshd не найден в PATH."
systemctl list-unit-files | grep -q '^ssh\.service' \
    || systemctl list-unit-files | grep -q '^sshd\.service' \
    || die "Не найден unit ssh.service/sshd.service."

SSH_UNIT="ssh"
systemctl list-unit-files | grep -q '^ssh\.service' || SSH_UNIT="sshd"

# 3. Проверка, что у root уже есть authorized_keys с хотя бы одним ключом
if [[ ! -s /root/.ssh/authorized_keys ]]; then
    warn "У root нет непустого /root/.ssh/authorized_keys."
    warn "Если вы отключите вход по паролю, вы можете потерять доступ к серверу!"
    read -r -p "Продолжить всё равно? (yes/no): " ans
    [[ "${ans}" == "yes" ]] || die "Отменено пользователем."
fi

# 4. Резервная копия целевого файла, если он существует
if [[ -f "${TARGET_CONF}" ]]; then
    cp -a "${TARGET_CONF}" "${TARGET_CONF}${BACKUP_SUFFIX}"
    log "Создана резервная копия: ${TARGET_CONF}${BACKUP_SUFFIX}"
fi

# 5. Запись директив в файл с приоритетом выше 50-cloud-init.conf
cat > "${TARGET_CONF}" <<'EOF'
# Отключение входа по паролю (сгенерировано PassOff.sh)
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF

chmod 644 "${TARGET_CONF}"
log "Записан ${TARGET_CONF}"

# 6. Проверка синтаксиса ПЕРЕД перезапуском (только синтаксис, без проверки значений)
if ! sshd -t; then
    warn "sshd -t обнаружил ошибку синтаксиса. Откатываем изменения."
    if [[ -f "${TARGET_CONF}${BACKUP_SUFFIX}" ]]; then
        mv -f "${TARGET_CONF}${BACKUP_SUFFIX}" "${TARGET_CONF}"
    else
        rm -f "${TARGET_CONF}"
    fi
    die "Изменения откачены, sshd не перезапускался."
fi
log "Синтаксис sshd корректный."

# 7. Перезапуск SSH
log "Перезапускаем ${SSH_UNIT}.service ..."
systemctl restart "${SSH_UNIT}"

# 8. Финальная проверка ПОСЛЕ перезапуска
sleep 1
if ! systemctl is-active --quiet "${SSH_UNIT}"; then
    warn "Служба ${SSH_UNIT} не активна после перезапуска! Попытка отката..."
    if [[ -f "${TARGET_CONF}${BACKUP_SUFFIX}" ]]; then
        mv -f "${TARGET_CONF}${BACKUP_SUFFIX}" "${TARGET_CONF}"
    else
        rm -f "${TARGET_CONF}"
    fi
    systemctl restart "${SSH_UNIT}" || true
    die "Служба не запустилась. Изменения откачены."
fi

if ! sshd -T | grep -qi '^passwordauthentication no$'; then
    warn "После перезапуска sshd -T всё ещё показывает passwordauthentication yes."
    warn "Возможно, есть ещё один файл в ${CONF_DIR} с более высоким приоритетом."
    warn "Проверьте: grep -r -i passwordauthentication /etc/ssh/sshd_config.d/"
    if [[ -f "${TARGET_CONF}${BACKUP_SUFFIX}" ]]; then
        mv -f "${TARGET_CONF}${BACKUP_SUFFIX}" "${TARGET_CONF}"
    else
        rm -f "${TARGET_CONF}"
    fi
    systemctl restart "${SSH_UNIT}" || true
    die "Изменения откачены, sshd перезапущен со старой конфигурацией."
fi

if ! sshd -T | grep -qi '^kbdinteractiveauthentication no$'; then
    warn "KbdInteractiveAuthentication не отключён — вход по паролю через PAM может остаться."
    warn "Проверьте конфигурацию вручную."
fi

log "Готово. Вход по паролю отключён."
log "Проверьте с локальной машины:"
log "  ssh -o PreferredAuthentications=password root@<IP>"
log "Ожидаемый результат: Permission denied (publickey)."
