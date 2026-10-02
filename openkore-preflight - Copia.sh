#!/bin/sh
set -eu

ROOT="${PREFLIGHT_ROOT:-/project}"
BOT="${BOT_NUMBER:-}"

log() {
    printf '[PREFLIGHT] %s\n' "$*"
}

fail() {
    printf '[PREFLIGHT] ERRO: %s\n' "$*" >&2
    exit 64
}

#case "$BOT" in
#    1)
#        OTHER=2
#        ;;
#    2)
#        OTHER=1
#        ;;
#    *)
#        fail "BOT_NUMBER deve ser 1 ou 2."
#        ;;
#esac
#
#CFG="$ROOT/instances/openkore-bot${BOT}/control/config.txt"
#OTHER_CFG="$ROOT/instances/openkore-bot${OTHER}/control/config.txt"
#
#VPN="$ROOT/vpn/vpn-bot${BOT}/protonvpn-bot${BOT}.conf"
#OTHER_VPN="$ROOT/vpn/vpn-bot${OTHER}/protonvpn-bot${OTHER}.conf"

case "$BOT" in
    1|2|3)
        ;;
    *)
        fail "BOT_NUMBER deve ser 1, 2 ou 3."
        ;;
esac

CFG="$ROOT/instances/openkore-bot${BOT}/control/config.txt"
VPN="$ROOT/vpn/vpn-bot${BOT}/protonvpn-bot${BOT}.conf"




[ -f "$CFG" ] || fail "config.txt do bot${BOT} não existe: $CFG"
[ -s "$CFG" ] || fail "config.txt do bot${BOT} está vazio."

[ -f "$VPN" ] || fail "arquivo VPN do bot${BOT} não existe: $VPN"
[ -s "$VPN" ] || fail "arquivo VPN do bot${BOT} está vazio."

config_value() {
    file="$1"
    key="$2"

    awk -v wanted="$key" '
        /^[[:space:]]*#/ { next }
        NF == 0 { next }
        $1 == wanted {
            $1=""
            sub(/^[[:space:]]+/, "")
            sub(/[[:space:]]+$/, "")
            print
            exit
        }
    ' "$file"
}

wg_value() {
    file="$1"
    key="$2"

    awk -F= -v wanted="$key" '
        /^[[:space:]]*#/ { next }
        {
            left=$1
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", left)
            if (left == wanted) {
                val=$0
                sub(/^[^=]*=/, "", val)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
                print val
                exit
            }
        }
    ' "$file"
}

normalized_vpn_hash() {
    file="$1"

    # Remove comentários, linhas vazias, CRLF e espaços nas pontas.
    # Assim uma cópia do mesmo arquivo com formatação diferente
    # continua sendo detectada.
    sed \
        -e 's/\r$//' \
        -e '/^[[:space:]]*#/d' \
        -e '/^[[:space:]]*$/d' \
        -e 's/^[[:space:]]*//' \
        -e 's/[[:space:]]*$//' \
        "$file" | sha256sum | awk '{print $1}'
}

#USERNAME="$(config_value "$CFG" username || true)"
#PASSWORD="$(config_value "$CFG" password || true)"
#
#[ -n "$USERNAME" ] || fail "username do bot${BOT} está vazio no config.txt."
#[ -n "$PASSWORD" ] || fail "password do bot${BOT} está vazio no config.txt."
#
# Nunca imprime username/password.
#log "Credenciais do bot${BOT}: presentes."
#
#if [ -f "$OTHER_CFG" ] && [ -s "$OTHER_CFG" ]; then
#    OTHER_USERNAME="$(config_value "$OTHER_CFG" username || true)"
#    OTHER_PASSWORD="$(config_value "$OTHER_CFG" password || true)"
#
#    if [ -n "$OTHER_USERNAME" ] && [ "$USERNAME" = "$OTHER_USERNAME" ]; then
#        fail "username do bot${BOT} é IGUAL ao username do bot${OTHER}. Inicialização bloqueada."
#    fi
#
#   if [ -n "$OTHER_PASSWORD" ] && [ "$PASSWORD" = "$OTHER_PASSWORD" ]; then
#        fail "password do bot${BOT} é IGUAL ao password do bot${OTHER}. Inicialização bloqueada."
#    fi
#
#    if [ -n "$OTHER_USERNAME" ] && [ -n "$OTHER_PASSWORD" ]; then
#        log "Credenciais bot${BOT} x bot${OTHER}: diferentes."
#    else
#        log "Bot${OTHER} ainda não possui username/password completos; comparação parcial."
#    fi
#else
#    log "Bot${OTHER} ainda não está configurado; comparação de credenciais ignorada por enquanto."
#fi
#
# Validação estática das VPNs.
#PRIVATE_KEY="$(wg_value "$VPN" PrivateKey || true)"
#ADDRESS="$(wg_value "$VPN" Address || true)"
#
#[ -n "$PRIVATE_KEY" ] || fail "PrivateKey não encontrada na VPN do bot${BOT}."
#[ -n "$ADDRESS" ] || fail "Address não encontrado na VPN do bot${BOT}."
#
#if [ -f "$OTHER_VPN" ] && [ -s "$OTHER_VPN" ]; then
#    HASH1="$(normalized_vpn_hash "$VPN")"
#    HASH2="$(normalized_vpn_hash "$OTHER_VPN")"
#
#    if [ "$HASH1" = "$HASH2" ]; then
#        fail "VPN do bot${BOT} é a MESMA configuração da VPN do bot${OTHER}. Inicialização bloqueada."
#    fi
#
#    OTHER_PRIVATE_KEY="$(wg_value "$OTHER_VPN" PrivateKey || true)"
#
#    if [ -n "$OTHER_PRIVATE_KEY" ] && [ "$PRIVATE_KEY" = "$OTHER_PRIVATE_KEY" ]; then
#        fail "PrivateKey WireGuard do bot${BOT} é IGUAL à do bot${OTHER}. Inicialização bloqueada."
#    fi
#
    # Não comparamos Address/Endpoint isoladamente:
    # provedores podem reutilizar endereço interno ou servidor
    # com chaves de cliente diferentes. O okmode também compara
    # o IP público real quando a outra VPN está ativa.
#    log "VPN bot${BOT} x bot${OTHER}: configurações estáticas diferentes."
#else
#    log "VPN do bot${OTHER} ainda não está configurada; comparação estática ignorada por enquanto."
#fi
#
#log "VALIDAÇÃO OK para bot${BOT}."
#exit 0


USERNAME="$(config_value "$CFG" username || true)"
PASSWORD="$(config_value "$CFG" password || true)"

[ -n "$USERNAME" ] || fail "username do bot${BOT} está vazio no config.txt."
[ -n "$PASSWORD" ] || fail "password do bot${BOT} está vazio no config.txt."

# Nunca imprime username/password.
log "Credenciais do bot${BOT}: presentes."


# ============================================================
# VPN DO BOT ATUAL
# ============================================================

PRIVATE_KEY="$(wg_value "$VPN" PrivateKey || true)"
ADDRESS="$(wg_value "$VPN" Address || true)"

[ -n "$PRIVATE_KEY" ] || fail "PrivateKey não encontrada na VPN do bot${BOT}."
[ -n "$ADDRESS" ] || fail "Address não encontrado na VPN do bot${BOT}."


# ============================================================
# COMPARA COM TODOS OS OUTROS BOTS
# ============================================================

for OTHER in 1 2 3; do

    # Não compara o bot com ele mesmo.
    [ "$OTHER" = "$BOT" ] && continue

    OTHER_CFG="$ROOT/instances/openkore-bot${OTHER}/control/config.txt"
    OTHER_VPN="$ROOT/vpn/vpn-bot${OTHER}/protonvpn-bot${OTHER}.conf"


    # ========================================================
    # CREDENCIAIS
    # ========================================================

    if [ -f "$OTHER_CFG" ] && [ -s "$OTHER_CFG" ]; then

        OTHER_USERNAME="$(config_value "$OTHER_CFG" username || true)"
        OTHER_PASSWORD="$(config_value "$OTHER_CFG" password || true)"

        if [ -n "$OTHER_USERNAME" ] && [ "$USERNAME" = "$OTHER_USERNAME" ]; then
            fail "username do bot${BOT} é IGUAL ao username do bot${OTHER}. Inicialização bloqueada."
        fi

        if [ -n "$OTHER_PASSWORD" ] && [ "$PASSWORD" = "$OTHER_PASSWORD" ]; then
            fail "password do bot${BOT} é IGUAL ao password do bot${OTHER}. Inicialização bloqueada."
        fi

        if [ -n "$OTHER_USERNAME" ] && [ -n "$OTHER_PASSWORD" ]; then
            log "Credenciais bot${BOT} x bot${OTHER}: diferentes."
        else
            log "Bot${OTHER} ainda não possui username/password completos; comparação parcial."
        fi

    else
        log "Bot${OTHER} ainda não está configurado; comparação de credenciais ignorada."
    fi


    # ========================================================
    # VPN
    # ========================================================

    if [ -f "$OTHER_VPN" ] && [ -s "$OTHER_VPN" ]; then

        HASH1="$(normalized_vpn_hash "$VPN")"
        HASH2="$(normalized_vpn_hash "$OTHER_VPN")"

        if [ "$HASH1" = "$HASH2" ]; then
            fail "VPN do bot${BOT} é a MESMA configuração da VPN do bot${OTHER}. Inicialização bloqueada."
        fi

        OTHER_PRIVATE_KEY="$(wg_value "$OTHER_VPN" PrivateKey || true)"

        if [ -n "$OTHER_PRIVATE_KEY" ] && [ "$PRIVATE_KEY" = "$OTHER_PRIVATE_KEY" ]; then
            fail "PrivateKey WireGuard do bot${BOT} é IGUAL à do bot${OTHER}. Inicialização bloqueada."
        fi

        log "VPN bot${BOT} x bot${OTHER}: configurações estáticas diferentes."

    else
        log "VPN do bot${OTHER} ainda não está configurada; comparação estática ignorada."
    fi

done


log "VALIDAÇÃO OK para bot${BOT}."
exit 0