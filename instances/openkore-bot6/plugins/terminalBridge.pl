package terminalBridge;

use strict;
use warnings;

use Plugins;
use Commands;
use Log;

use IO::Select;
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use Encode qw(encode_utf8 decode_utf8 FB_DEFAULT);


# ============================================================
# VARIAVEIS
# ============================================================

my $stdin_selector;
my $stdin_buffer = '';

my $main_hook;
my $log_hook;


# ============================================================
# REGISTRA O PLUGIN
# ============================================================

Plugins::register(
    'terminalBridge',
    'Terminal interativo real do OpenKore via Docker TTY',
    \&on_unload
);


# ============================================================
# STDOUT SEM BUFFER
# ============================================================

binmode(STDOUT, ':raw');

my $old = select(STDOUT);
$| = 1;
select($old);


# ============================================================
# ESCREVE DIRETAMENTE NO TERMINAL DO CONTAINER
# ============================================================

sub terminal_write {

    my ($text) = @_;

    return unless defined $text;
    return if $text eq '';

    my $bytes;

    if (utf8::is_utf8($text)) {
        $bytes = encode_utf8($text);
    } else {
        $bytes = $text;
    }

    my $offset = 0;
    my $length = length($bytes);

    while ($offset < $length) {

        my $written = syswrite(
            STDOUT,
            $bytes,
            $length - $offset,
            $offset
        );

        last unless defined $written;
        last if $written <= 0;

        $offset += $written;
    }
}


# ============================================================
# VERIFICA SE O DOMINIO ESTARIA VISIVEL NO CONSOLE
# ============================================================

sub console_enabled {

    my ($type, $domain) = @_;

    $domain = 'console'
        unless defined $domain && $domain ne '';

    if ($type eq 'message') {

        return 0
            if exists $Log::messageConsole{$domain}
            && !$Log::messageConsole{$domain};

    } elsif ($type eq 'warning') {

        return 0
            if exists $Log::warningConsole{$domain}
            && !$Log::warningConsole{$domain};

    } elsif ($type eq 'error') {

        return 0
            if exists $Log::errorConsole{$domain}
            && !$Log::errorConsole{$domain};

    } elsif ($type eq 'debug') {

        return 0
            if exists $Log::debugConsole{$domain}
            && !$Log::debugConsole{$domain};
    }

    return 1;
}


# ============================================================
# CAPTURA AS MENSAGENS DO OPENKORE
#
# Aqui entram:
#
# attackMon
# attacked
# route
# drop
# inventory
# skill
# storage
# connection
# etc.
# ============================================================

sub on_log {

    my (
        $type,
        $domain,
        $level,
        $global_verbosity,
        $message
    ) = @_;


    return unless defined $message;


    # Mesmo filtro de verbosidade usado pelo OpenKore.
    if (
        defined($level)
        && defined($global_verbosity)
        && $level > $global_verbosity
    ) {
        return;
    }


    return unless console_enabled(
        $type,
        $domain
    );


    terminal_write($message);
}


# ============================================================
# PROCESSA COMANDO DIGITADO NO TERMINAL
# ============================================================

sub execute_command {

    my ($raw) = @_;

    return unless defined $raw;


    $raw =~ s/\r?\n$//;


    my $command = decode_utf8(
        $raw,
        FB_DEFAULT
    );


    $command =~ s/^\s+//;
    $command =~ s/\s+$//;


    return if $command eq '';


    my $ok = eval {

        Commands::run($command);

        1;
    };


    if (!$ok) {

        my $error =
            $@
            || 'erro desconhecido';

        terminal_write(
            "[terminalBridge] Erro executando '$command': $error\n"
        );
    }
}


# ============================================================
# LE STDIN DO CONTAINER SEM BLOQUEAR O OPENKORE
# ============================================================

sub on_main_loop {

    return unless $stdin_selector;


    for my $fh ($stdin_selector->can_read(0)) {

        my $data = '';

        my $bytes = sysread(
            $fh,
            $data,
            4096
        );


        if (!defined $bytes) {

            next
                if $!{EAGAIN}
                || $!{EWOULDBLOCK};

            next;
        }


        if ($bytes == 0) {
            next;
        }


        $stdin_buffer .= $data;


        while (
            $stdin_buffer
            =~ s/^(.*?\n)//s
        ) {

            my $line = $1;

            execute_command($line);
        }
    }
}


# ============================================================
# INICIALIZACAO
# ============================================================

sub start_terminal {

    # --------------------------------------------------------
    # STDIN em modo nao bloqueante
    # --------------------------------------------------------

    my $flags =
        fcntl(
            STDIN,
            F_GETFL,
            0
        );


    if (defined $flags) {

        fcntl(
            STDIN,
            F_SETFL,
            $flags | O_NONBLOCK
        );
    }


    $stdin_selector =
        IO::Select->new();


    $stdin_selector->add(
        \*STDIN
    );


    # --------------------------------------------------------
    # Toda iteracao verifica se voce digitou alguma coisa.
    # --------------------------------------------------------

    $main_hook =
        Plugins::addHook(
            'mainLoop_pre',
            \&on_main_loop
        );


    # --------------------------------------------------------
    # Todas as mensagens do OpenKore aparecem no terminal.
    # --------------------------------------------------------

    $log_hook =
        Log::addHook(
            \&on_log
        );


    terminal_write(
        "[terminalBridge] Terminal Docker interativo ativo.\n"
    );
}


# ============================================================
# UNLOAD
# ============================================================

sub on_unload {

    Plugins::delHook(
        $main_hook
    ) if defined $main_hook;


    Log::delHook(
        $log_hook
    ) if defined $log_hook;


    undef $stdin_selector;
    undef $main_hook;
    undef $log_hook;
}


# ============================================================
# START
# ============================================================

start_terminal();

1;