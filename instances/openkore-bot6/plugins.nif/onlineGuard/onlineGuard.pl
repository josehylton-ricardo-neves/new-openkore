package onlineGuard;

use strict;
use warnings;

use Time::HiRes qw(time);
use JSON::PP qw(decode_json);

use Plugins;
use Globals qw(%config $net);
use Log qw(message warning);
use Network;
use Misc qw(offlineMode);
use Commands;
use Settings;

my $PLUGIN = 'onlineGuard';

Plugins::register(
    $PLUGIN,
    'Desconecta/reconecta usando o estado compartilhado do online-watcher',
    \&onUnload
);

my $hooks = Plugins::addHooks(
    ['mainLoop_pre', \&onMainLoop],
);

my $commands = Commands::register(
    ['oguard', 'Mostra o estado do onlineGuard', \&cmdGuard]
);

my $started_at = time;
my $last_check = 0;
my $last_mtime = -1;

my $doc;
my %online;
my @last_hits;

my $state = 'STARTUP';
my $state_reason = 'aguardando primeira leitura';
my $clear_since;
my $owns_disconnect = 0;

my $last_logged_state = '';

sub onUnload {
    Plugins::delHooks($hooks) if $hooks;
    Commands::unregister($commands) if $commands;
}

sub cfg {
    my ($key, $default) = @_;
    return $default if !exists $config{$key};
    return $default if !defined $config{$key};
    return $default if $config{$key} eq '';
    return $config{$key};
}

sub cfg_num {
    my ($key, $default, $min) = @_;
    my $v = cfg($key, $default);

    $v = $default if $v !~ /^\d+(?:\.\d+)?$/;
    $v += 0;

    $v = $min if defined $min && $v < $min;
    return $v;
}

sub cfg_bool {
    my ($key, $default) = @_;
    my $v = cfg($key, $default);
    return $v ? 1 : 0;
}

sub blacklist {
    my $raw = cfg('onlineGuard_blacklist', '');

    my @names = grep { length $_ } map {
        my $v = $_;
        $v =~ s/^\s+|\s+$//g;
        $v;
    } split /\s*,\s*/, $raw;

    return @names;
}

sub normalize_name {
    my ($name) = @_;
    return '' if !defined $name;

    $name =~ s/^\s+|\s+$//g;

    if (!cfg_bool('onlineGuard_caseSensitive', 0)) {
        $name = lc $name;
    }

    return $name;
}

sub set_state {
    my ($new_state, $reason) = @_;
    $reason //= '';

    my $key = "$new_state|$reason";

    $state = $new_state;
    $state_reason = $reason;

    if ($last_logged_state ne $key) {
        message "[onlineGuard] $new_state: $reason\n", 'system';
        $last_logged_state = $key;
    }
}

#sub hold_disconnected {
#    my ($reason) = @_;
#
#    my $already_offline =
#        $Settings::no_connect
#        && (!$net || $net->getState == Network::NOT_CONNECTED);
#
#    if (!$owns_disconnect && !$already_offline) {
#        $owns_disconnect = 1;
#    }
#
#    # Se o guard e dono do bloqueio, ou se o Kore ainda esta tentando
#    # conectar, garante estado offline.
#    if ($owns_disconnect || !$Settings::no_connect) {
#        offlineMode();
#    }
#
#    $clear_since = undef;
#}
















sub hold_disconnected {
    my ($reason) = @_;

    # Se o OpenKore ainda nao esta em modo offline,
    # o Online Guard assume a desconexao e chama offlineMode UMA vez.
    if (!$Settings::no_connect) {
        $owns_disconnect = 1;
        offlineMode();
    }

    # Se ja esta em offlineMode, nao chama novamente.
    # Isso evita:
    # "Openkore will stay disconnected..." repetidamente.

    $clear_since = undef;
}



















sub release_connection {
    return if !cfg_bool('onlineGuard_autoReconnect', 1);
    return if !$owns_disconnect;

    $Settings::no_connect = 0;
    $owns_disconnect = 0;

    message "[onlineGuard] Bloqueio liberado. Reconexao permitida.\n", 'success';
}

sub load_file_if_changed {
    my ($file) = @_;

    #if (!-e $file) {
    #    $doc = undef;
    #    %online = ();
    #    $last_mtime = -1;
    #    return (0, "arquivo nao encontrado: $file");
    #}
	
	if (!-e $file) {
    # Nao apaga o ultimo estado valido.
    # Uma indisponibilidade momentanea do bind mount nao deve
    # destruir o cache que ainda pode estar dentro do staleAfter.
    return (0, "arquivo nao encontrado: $file");
	}

    my @st = stat($file);

    if (!@st) {
        return (0, "stat falhou para: $file");
    }

    my $mtime = $st[9];

    # Quase todos os ciclos param aqui: somente stat(), sem abrir JSON.
    if (defined $doc && $mtime == $last_mtime) {
        return (1, '');
    }

    open my $fh, '<:raw', $file
        or return (0, "nao foi possivel abrir $file: $!");

    local $/;
    my $raw = <$fh>;
    close $fh;

    my $parsed;
    my $ok = eval {
        $parsed = decode_json($raw);
        1;
    };

    if (!$ok || ref($parsed) ne 'HASH') {
        my $e = $@ || 'JSON invalido';
        $e =~ s/\s+$//;
        return (0, "JSON invalido: $e");
    }

    if (ref($parsed->{online}) ne 'ARRAY') {
        return (0, 'campo online ausente ou invalido');
    }

    $doc = $parsed;
    $last_mtime = $mtime;

    %online = ();

    foreach my $name (@{$doc->{online}}) {
        my $n = normalize_name($name);
        $online{$n} = 1 if length $n;
    }

    return (1, '');
}

sub watcher_health {
    my $now = time;

    return (0, 'nenhum JSON valido carregado') if !defined $doc;

    my $updated = int($doc->{updated} // 0);
    my $last_success = int($doc->{last_success} // 0);
    my $status = $doc->{status} // 'unknown';

    my $stale_after = cfg_num('onlineGuard_staleAfter', 70, 10);

    if ($updated <= 0) {
        return (0, 'updated ausente/invalido');
    }

    my $updated_age = $now - $updated;

    if ($updated_age > $stale_after) {
        return (
            0,
            sprintf(
                'watcher stale: updated ha %.0fs (limite %.0fs)',
                $updated_age,
                $stale_after
            )
        );
    }

    if ($last_success <= 0) {
        return (0, 'last_success ausente/invalido');
    }

    my $success_age = $now - $last_success;

    if ($success_age > $stale_after) {
        return (
            0,
            sprintf(
                'sem consulta valida ha %.0fs (limite %.0fs)',
                $success_age,
                $stale_after
            )
        );
    }

    # status=error e tolerado enquanto last_success ainda estiver fresco.
    # Isso evita desconectar por uma unica falha HTTP.
    return (
        1,
        sprintf(
            'watcher OK; status=%s; updated=%.0fs; success=%.0fs',
            $status,
            $updated_age,
            $success_age
        )
    );
}

sub get_hits {
    my @hits;

    foreach my $name (blacklist()) {
        my $normalized = normalize_name($name);
        push @hits, $name if length($normalized) && $online{$normalized};
    }

    return @hits;
}

sub process_safe {
    my ($now) = @_;

    @last_hits = ();

    # Primeira leitura valida e segura: libera sem exigir clearDelay.
    if ($state eq 'STARTUP') {
        $clear_since = undef;
        set_state('SAFE', 'watcher valido e blacklist ausente');
        return;
    }

    if ($state eq 'SAFE') {
        return;
    }

    if (!defined $clear_since) {
        $clear_since = $now;
        set_state('CLEARING', 'blacklist ausente; iniciando tempo de seguranca');
        return;
    }

    my $delay = cfg_num('onlineGuard_clearDelay', 1800, 0);
    my $elapsed = $now - $clear_since;

    if ($elapsed < $delay) {
        # Nao loga contagem regressiva a cada ciclo.
        # Mantem apenas o estado CLEARING.
        $state = 'CLEARING';
        $state_reason = sprintf(
            'aguardando; faltam aproximadamente %ds',
            int($delay - $elapsed)
        );
        return;
    }

    $clear_since = undef;
    set_state('SAFE', "blacklist ausente continuamente por ${delay}s");
    release_connection();
}

sub process_unsafe {
    my ($new_state, $reason) = @_;

    $clear_since = undef;
    set_state($new_state, $reason);

    if (cfg_bool('onlineGuard_disconnect', 1)) {
        hold_disconnected($reason);
    }
}

sub onMainLoop {
    return if !cfg_bool('onlineGuard', 0);

    my $now = time;
    my $interval = cfg_num('onlineGuard_checkInterval', 2, 0.5);

    return if ($now - $last_check) < $interval;
    $last_check = $now;

    my $file = cfg('onlineGuard_file', '');

    if ($file eq '') {
        if (cfg_bool('onlineGuard_failClosed', 1)) {
            process_unsafe('BLOCKED_WATCHER', 'onlineGuard_file nao configurado');
        }
        return;
    }

    my ($loaded, $load_error) = load_file_if_changed($file);

if (!$loaded) {

    # ---------------------------------------------------------
    # Se ja temos um JSON valido anterior, nao bloqueamos
    # imediatamente por uma falha transitoria de filesystem.
    #
    # Continuamos usando o ultimo estado valido enquanto ele
    # estiver dentro de onlineGuard_staleAfter.
    # ---------------------------------------------------------
    if (defined $doc) {
        my ($healthy, $health_reason) = watcher_health();

        if ($healthy) {
            warning "[onlineGuard] Falha transitoria lendo JSON: "
                . "$load_error; usando ultimo estado valido.\n";

            # Nao retorna.
            # Continua abaixo e verifica a blacklist usando
            # o ultimo JSON valido carregado.
        }
        else {
            if (cfg_bool('onlineGuard_failClosed', 1)) {
                process_unsafe(
                    'BLOCKED_WATCHER',
                    "$load_error; $health_reason"
                );
            }
            else {
                set_state(
                    'DEGRADED',
                    "$load_error; $health_reason"
                );
            }

            return;
        }
    }

    # ---------------------------------------------------------
    # Nunca conseguimos carregar nenhum JSON valido ainda.
    # Nesse caso aplica startupGrace normalmente.
    # ---------------------------------------------------------
    else {
        my $grace = cfg_num('onlineGuard_startupGrace', 90, 0);

        if (($now - $started_at) <= $grace) {
            set_state(
                'STARTUP',
                "$load_error; dentro do startupGrace"
            );
            return;
        }

        if (cfg_bool('onlineGuard_failClosed', 1)) {
            process_unsafe(
                'BLOCKED_WATCHER',
                $load_error
            );
        }
        else {
            set_state(
                'DEGRADED',
                $load_error
            );
        }

        return;
    }
}

    my ($healthy, $health_reason) = watcher_health();

    if (!$healthy) {
        if (cfg_bool('onlineGuard_failClosed', 1)) {
            process_unsafe('BLOCKED_WATCHER', $health_reason);
        } else {
            set_state('DEGRADED', $health_reason);
        }

        return;
    }

    my @hits = get_hits();

    if (@hits) {
        @last_hits = @hits;

        process_unsafe(
            'BLOCKED_PLAYER',
            'online: ' . join(', ', @hits)
        );

        return;
    }

    process_safe($now);
}

sub cmdGuard {
    my (undef, $args) = @_;

    $args //= '';
    $args =~ s/^\s+|\s+$//g;

    if ($args eq '' || lc($args) eq 'status') {
        my $file = cfg('onlineGuard_file', '(nao configurado)');
        my $delay = cfg_num('onlineGuard_clearDelay', 1800, 0);
        my $remaining = 0;

        if (defined $clear_since) {
            my $elapsed = time - $clear_since;
            $remaining = int($delay - $elapsed);
            $remaining = 0 if $remaining < 0;
        }

        message "[onlineGuard] enabled=" . cfg_bool('onlineGuard', 0) . "\n", 'list';
        message "[onlineGuard] state=$state\n", 'list';
        message "[onlineGuard] reason=$state_reason\n", 'list';
        message "[onlineGuard] file=$file\n", 'list';

        if (defined $doc) {
            message "[onlineGuard] watcher_status=" . ($doc->{status} // 'unknown') . "\n", 'list';
            message "[onlineGuard] watcher_count=" . int($doc->{count} // 0) . "\n", 'list';
        }

        message "[onlineGuard] blacklist_hits="
            . (@last_hits ? join(', ', @last_hits) : '(nenhum)')
            . "\n", 'list';

        message "[onlineGuard] clear_remaining=${remaining}s\n", 'list';
        message "[onlineGuard] owns_disconnect=$owns_disconnect\n", 'list';
        return;
    }

    if (lc($args) eq 'check') {
        $last_check = 0;
        onMainLoop();
        cmdGuard(undef, 'status');
        return;
    }

    message "Uso: oguard [status|check]\n", 'list';
}

1;
