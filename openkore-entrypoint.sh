#!/bin/sh
set -eu

APP_HOME="${APP_HOME:-/opt/openkore}"
BOT_NAME="${BOT_NAME:-openkore}"
RUNTIME_XSTOOLS_DIR="/opt/openkore-runtime/xstools"
HOST_XSTOOLS_DIR="$APP_HOME/src/auto/XSTools"
CONFIG_FILE="$APP_HOME/control/config.txt"

log() {
    printf '[%s] %s\n' "$BOT_NAME" "$*"
}

# Segurança: username/password têm uma única fonte de verdade:
# control/config.txt. Não permitimos sobrescrever credenciais por ENV,
# pois isso poderia contornar a comparação bot1 x bot2.
if [ -n "${OK_USERNAME:-}" ] || [ -n "${OK_PASSWORD:-}" ]; then
    log "ERRO: OK_USERNAME/OK_PASSWORD por variável de ambiente não são permitidos."
    log "Configure username/password somente em control/config.txt."
    exit 65
fi

# Revalida também no momento exato em que o OpenKore vai iniciar.
# Isso protege inclusive quando a VPN já estava ligada.
if [ -n "${BOT_NUMBER:-}" ] && [ -f /checks/openkore-preflight.sh ]; then
    log "Executando validação cruzada de VPN e credenciais..."
    PREFLIGHT_ROOT="${PREFLIGHT_ROOT:-/preflight-project}" \
    BOT_NUMBER="$BOT_NUMBER" \
        /bin/sh /checks/openkore-preflight.sh || {
            log "ERRO: validação falhou. OpenKore NÃO será iniciado."
            exit 66
        }
fi

if [ ! -f "$APP_HOME/openkore.pl" ]; then
    log "ERRO: $APP_HOME/openkore.pl não existe."
    log "Verifique o bind mount ./instances/openkore-botN -> /opt/openkore."
    exit 1
fi

# XSTools é compilado para Linux na imagem e copiado para um volume Linux
# nomeado montado em /opt/openkore/src/auto/XSTools.
if [ ! -f "$RUNTIME_XSTOOLS_DIR/XSTools.so" ]; then
    log "ERRO: XSTools Linux não existe na imagem. Refaça o build do runtime."
    exit 1
fi

mkdir -p "$HOST_XSTOOLS_DIR"
cp -f "$RUNTIME_XSTOOLS_DIR/XSTools.so" "$HOST_XSTOOLS_DIR/XSTools.so"
cp -f "$RUNTIME_XSTOOLS_DIR/libXSTools.so" "$HOST_XSTOOLS_DIR/libXSTools.so"

# Compatibilidade do OpenKore Wx com wxWidgets 3.2 do Debian.
WX_TITLEBAR="$APP_HOME/src/Interface/Wx/TitleBar.pm"
if [ -f "$WX_TITLEBAR" ] && grep -q 'wxTB_3DBUTTONS' "$WX_TITLEBAR"; then
    log "Aplicando compatibilidade Wx 3.2 em src/Interface/Wx/TitleBar.pm..."
    sed -i 's/[[:space:]]*|[[:space:]]*wxTB_3DBUTTONS//g' "$WX_TITLEBAR"
fi

set_config_value() {
    key="$1"
    value="$2"

    [ -f "$CONFIG_FILE" ] || return 0

    perl - "$CONFIG_FILE" "$key" "$value" <<'PERL'
use strict;
use warnings;
my ($file, $key, $value) = @ARGV;
open my $in, '<:raw', $file or die "Cannot read $file: $!\n";
local $/;
my $content = <$in>;
close $in;
my $newline = ($content =~ /\r\n/) ? "\r\n" : "\n";
my @lines = split /\r?\n/, $content, -1;
my $found = 0;
for my $line (@lines) {
    if (!$found && $line =~ /^\s*\Q$key\E(?:\s+.*)?$/) {
        $line = "$key $value";
        $found = 1;
    }
}
if (!$found) {
    pop @lines if @lines && $lines[-1] eq '';
    push @lines, "$key $value", '';
}
open my $out, '>:raw', $file or die "Cannot write $file: $!\n";
print {$out} join($newline, @lines);
close $out;
PERL
}

# Não imprime credenciais nos logs.
[ -z "${OK_MASTER:-}" ]   || set_config_value master "$OK_MASTER"
if [ "${OK_CHAR+x}" = "x" ] && [ -n "${OK_CHAR}" ]; then
    set_config_value char "$OK_CHAR"
fi

# Não força terminalBridge nem altera a política normal de plugins.

if [ "${WAIT_FOR_VPN:-true}" = "true" ]; then
    URL="${VPN_CHECK_URL:-https://api.ipify.org}"
    ATTEMPTS="${VPN_WAIT_ATTEMPTS:-90}"
    SECONDS="${VPN_WAIT_SECONDS:-2}"

    log "Aguardando acesso à internet pela VPN..."
    attempt=1
    while [ "$attempt" -le "$ATTEMPTS" ]; do
        if curl -fsS --max-time 5 "$URL" >/tmp/public-ip 2>/dev/null; then
            log "VPN conectada."
            log "IP público de saída: $(cat /tmp/public-ip)"
            break
        fi
        if [ "$attempt" -eq "$ATTEMPTS" ]; then
            log "ERRO: VPN não ficou disponível após $ATTEMPTS tentativas."
            exit 1
        fi
        sleep "$SECONDS"
        attempt=$((attempt + 1))
    done
fi

log "Modo: ${OPENKORE_MODE:-não informado}"
log "Diretório da aplicação: $APP_HOME"
log "Executando: $*"

cd "$APP_HOME"
exec "$@"
