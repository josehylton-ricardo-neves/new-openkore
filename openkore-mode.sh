#!/bin/sh
set -eu

APP_HOME="${APP_HOME:-/opt/openkore}"
MODE="${1:-${OPENKORE_MODE:-wx}}"
DISPLAY_NUM="${DISPLAY_NUM:-99}"
SCREEN_WIDTH="${SCREEN_WIDTH:-1280}"
SCREEN_HEIGHT="${SCREEN_HEIGHT:-800}"
SCREEN_DEPTH="${SCREEN_DEPTH:-24}"
VNC_PORT="${VNC_PORT:-5900}"
VNC_LISTEN="${VNC_LISTEN:-0.0.0.0}"
NOVNC_PORT="${NOVNC_PORT:-6080}"

export DISPLAY=":${DISPLAY_NUM}"
export HOME="${HOME:-/tmp/openkore-home}"
mkdir -p "$HOME"

XVFB_PID=""
FLUXBOX_PID=""
VNC_PID=""
NOVNC_PID=""
MAPVIEW_PID=""
SYS_BACKUP=""

log() {
    printf '[MODE:%s] %s\n' "$MODE" "$*"
}

restore_sys() {
    if [ -n "$SYS_BACKUP" ] && [ -f "$SYS_BACKUP" ]; then
        cp -f "$SYS_BACKUP" "$APP_HOME/control/sys.txt" || true
        rm -f "$SYS_BACKUP" || true
        SYS_BACKUP=""
    fi
}

cleanup() {
    [ -z "$MAPVIEW_PID" ] || kill "$MAPVIEW_PID" 2>/dev/null || true
    [ -z "$NOVNC_PID" ]   || kill "$NOVNC_PID" 2>/dev/null || true
    [ -z "$VNC_PID" ]     || kill "$VNC_PID" 2>/dev/null || true
    [ -z "$FLUXBOX_PID" ] || kill "$FLUXBOX_PID" 2>/dev/null || true
    [ -z "$XVFB_PID" ]    || kill "$XVFB_PID" 2>/dev/null || true
    restore_sys
}
trap cleanup EXIT INT TERM

start_x_stack() {
    log "Iniciando Xvfb em $DISPLAY..."
    Xvfb "$DISPLAY" \
        -screen 0 "${SCREEN_WIDTH}x${SCREEN_HEIGHT}x${SCREEN_DEPTH}" \
        -ac \
        -nolisten tcp \
        >/tmp/xvfb.log 2>&1 &
    XVFB_PID=$!

    attempt=0
    while ! xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [ "$attempt" -ge 30 ]; then
            log "ERRO: Xvfb não iniciou."
            cat /tmp/xvfb.log 2>/dev/null || true
            exit 1
        fi
        sleep 1
    done

    fluxbox -display "$DISPLAY" >/tmp/fluxbox.log 2>&1 &
    FLUXBOX_PID=$!
    sleep 1

    x11vnc \
        -display "$DISPLAY" \
        -listen "$VNC_LISTEN" \
        -rfbport "$VNC_PORT" \
        -forever \
        -shared \
        -nopw \
        -noxdamage \
        >/tmp/x11vnc.log 2>&1 &
    VNC_PID=$!
    sleep 1

    if ! kill -0 "$VNC_PID" 2>/dev/null; then
        log "ERRO: x11vnc não iniciou."
        cat /tmp/x11vnc.log 2>/dev/null || true
        exit 1
    fi

    websockify \
        --web=/usr/share/novnc \
        "$NOVNC_PORT" \
        "127.0.0.1:$VNC_PORT" \
        >/tmp/novnc.log 2>&1 &
    NOVNC_PID=$!
    sleep 1

    if ! kill -0 "$NOVNC_PID" 2>/dev/null; then
        log "ERRO: noVNC não iniciou."
        cat /tmp/novnc.log 2>/dev/null || true
        exit 1
    fi

    log "GUI disponível: noVNC interno $NOVNC_PORT / VNC interno $VNC_PORT"
}

enable_map_state_plugin_temporarily() {
    SYS_FILE="$APP_HOME/control/sys.txt"
    PLUGIN_NAME="dockerMapState"

    [ -f "$SYS_FILE" ] || {
        log "ERRO: $SYS_FILE não existe."
        exit 1
    }

    SYS_BACKUP="/tmp/sys.txt.before-map.$$"
    cp -f "$SYS_FILE" "$SYS_BACKUP"

    perl - "$SYS_FILE" "$PLUGIN_NAME" <<'PERL'
use strict;
use warnings;
my ($file, $plugin) = @ARGV;
open my $in, '<:raw', $file or die "Cannot read $file: $!\n";
local $/;
my $content = <$in>;
close $in;
my $nl = ($content =~ /\r\n/) ? "\r\n" : "\n";
my @lines = split /\r?\n/, $content, -1;
my ($mode, $mode_i, $list_i, $skip_i);
for my $i (0 .. $#lines) {
    if ($lines[$i] =~ /^\s*loadPlugins\s+(\d+)/) {
        ($mode, $mode_i) = (int($1), $i);
    } elsif ($lines[$i] =~ /^\s*loadPlugins_list\s*(.*)$/) {
        $list_i = $i;
    } elsif ($lines[$i] =~ /^\s*skipPlugins_list\s*(.*)$/) {
        $skip_i = $i;
    }
}
$mode = 1 unless defined $mode;
if ($mode == 2) {
    my @plugins;
    if (defined $list_i && $lines[$list_i] =~ /^\s*loadPlugins_list\s*(.*)$/) {
        @plugins = grep { length } map { s/^\s+|\s+$//gr } split /,/, $1;
    }
    push @plugins, $plugin unless grep { $_ eq $plugin } @plugins;
    my $new = 'loadPlugins_list ' . join(',', @plugins);
    defined $list_i ? ($lines[$list_i] = $new) : push(@lines, $new);
} elsif ($mode == 3) {
    if (defined $skip_i && $lines[$skip_i] =~ /^\s*skipPlugins_list\s*(.*)$/) {
        my @plugins = grep { length } map { s/^\s+|\s+$//gr } split /,/, $1;
        @plugins = grep { $_ ne $plugin } @plugins;
        $lines[$skip_i] = 'skipPlugins_list ' . join(',', @plugins);
    }
} elsif ($mode == 0) {
    # Map mode precisa deste plugin. Troca temporariamente para modo 2.
    defined $mode_i ? ($lines[$mode_i] = 'loadPlugins 2') : push(@lines, 'loadPlugins 2');
    if (defined $list_i) {
        my ($old) = $lines[$list_i] =~ /^\s*loadPlugins_list\s*(.*)$/;
        my @plugins = grep { length } map { s/^\s+|\s+$//gr } split /,/, ($old || '');
        push @plugins, $plugin unless grep { $_ eq $plugin } @plugins;
        $lines[$list_i] = 'loadPlugins_list ' . join(',', @plugins);
    } else {
        push @lines, "loadPlugins_list $plugin";
    }
}
open my $out, '>:raw', $file or die "Cannot write $file: $!\n";
print {$out} join($nl, @lines);
close $out;
PERL
}

cd "$APP_HOME"

case "$MODE" in
    console)
        log "Iniciando: perl openkore.pl"
        trap - EXIT INT TERM
        exec perl openkore.pl
        ;;

    wx)
        start_x_stack
        log "Iniciando: perl openkore.pl --interface=Wx"
        set +e
        perl openkore.pl --interface=Wx
        status=$?
        set -e
        log "OpenKore encerrou com código $status."
        exit "$status"
        ;;

    map)
        if [ ! -f "$APP_HOME/mapview.pl" ]; then
            log "ERRO: $APP_HOME/mapview.pl não existe nesta árvore do OpenKore."
            exit 1
        fi
        if [ ! -f "$APP_HOME/plugins/dockerMapState.pl" ]; then
            log "ERRO: plugin dockerMapState.pl não está montado."
            exit 1
        fi

        enable_map_state_plugin_temporarily
        rm -f "$APP_HOME/logs/state.yml" "$APP_HOME/logs/state.yml.tmp" 2>/dev/null || true
        start_x_stack

        log "Iniciando mapview.pl (visualização; cliques não controlam o bot neste modo)."
        perl mapview.pl --logs="$APP_HOME/logs" >/tmp/mapview.log 2>&1 &
        MAPVIEW_PID=$!
        sleep 2
        if ! kill -0 "$MAPVIEW_PID" 2>/dev/null; then
            log "ERRO: mapview.pl não iniciou."
            cat /tmp/mapview.log 2>/dev/null || true
            exit 1
        fi

        log "Iniciando OpenKore Console. O terminal continua sendo a interface principal."
        set +e
        perl openkore.pl
        status=$?
        set -e
        log "OpenKore encerrou com código $status."
        exit "$status"
        ;;

    *)
        echo "Uso: openkore-mode {console|wx|map}" >&2
        exit 2
        ;;
esac
