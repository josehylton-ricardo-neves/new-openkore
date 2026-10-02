#!/usr/bin/env perl
use strict;
use warnings;

use Encode qw(decode);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use HTTP::Tiny;
use JSON::PP;
use POSIX qw(strftime);
use Time::HiRes qw(time sleep);

my $CONFIG = $ENV{ONLINE_WATCH_CONFIG} // '/watcher/online-watcher.conf';

sub read_simple_config {
    my ($path) = @_;
    my %cfg;

    return %cfg if !defined($path) || $path eq '' || !-f $path;

    open my $fh, '<:encoding(UTF-8)', $path
        or die "nao foi possivel abrir config $path: $!";

    while (my $line = <$fh>) {
        $line =~ s/\r?\n$//;
        $line =~ s/^\s+|\s+$//g;
        next if $line eq '' || $line =~ /^[#;]/;

        my ($key, $value) = split /\s*=\s*/, $line, 2;
        next if !defined $value;

        $key   =~ s/^\s+|\s+$//g;
        $value =~ s/^\s+|\s+$//g;
        $cfg{$key} = $value if $key ne '';
    }

    close $fh;
    return %cfg;
}

my %CFG = read_simple_config($CONFIG);

sub cfg {
    my ($key, $default) = @_;
    return $CFG{$key} if exists($CFG{$key}) && defined($CFG{$key}) && $CFG{$key} ne '';
    return $default;
}

# Variaveis de ambiente, quando definidas, ganham do arquivo .conf.
my $URL = $ENV{ONLINE_WATCH_URL}
    // cfg('url', 'https://o-ro.org/rankings?online=1&tier=all&class=all&guild=all&sort=level');

my $INTERVAL = int($ENV{ONLINE_WATCH_INTERVAL} // cfg('interval', 20));
my $TIMEOUT  = int($ENV{ONLINE_WATCH_TIMEOUT}  // cfg('timeout', 5));
my $OUTPUT   = $ENV{ONLINE_WATCH_OUTPUT}
    // cfg('output', '/shared/online-watch/online_players.json');

my $VERBOSE = ($ENV{ONLINE_WATCH_VERBOSE} // cfg('verbose', 1)) ne '0';
my $USE_ETAG = ($ENV{ONLINE_WATCH_ETAG} // cfg('etag', 1)) ne '0';
my $USER_AGENT = $ENV{ONLINE_WATCH_USER_AGENT}
    // cfg('user_agent', 'openkore-online-watcher/1.0');

$INTERVAL = 10 if $INTERVAL < 10;
$TIMEOUT  = 2  if $TIMEOUT  < 2;

my $output_dir = dirname($OUTPUT);
make_path($output_dir) if !-d $output_dir;

my $http = HTTP::Tiny->new(
    timeout    => $TIMEOUT,
    verify_SSL => 1,
    agent      => $USER_AGENT,
);

my $json = JSON::PP->new
    ->utf8(1)
    ->canonical(1)
    ->pretty(1);

my $etag;
my $last_modified;
my @players;
my $last_success = 0;
my $last_signature = '';
my $last_status = '';

sub logmsg {
    return if !$VERBOSE;
    my ($msg) = @_;
    my $stamp = strftime('%Y-%m-%d %H:%M:%S', localtime);
    print "[$stamp] $msg\n";
}

sub decode_html_entities {
    my ($s) = @_;

    $s =~ s/&#(\d+);/chr($1)/ge;
    $s =~ s/&#x([0-9a-fA-F]+);/chr(hex($1))/ge;

    my %named = (
        amp  => '&',
        lt   => '<',
        gt   => '>',
        quot => '"',
        apos => "'",
        nbsp => ' ',
    );

    $s =~ s/&([A-Za-z]+);/
        exists $named{lc($1)} ? $named{lc($1)} : '&' . $1 . ';'
    /gex;

    return $s;
}

sub extract_players {
    my ($bytes) = @_;

    my $html = decode('UTF-8', $bytes, 1);
    my @found;

    while (
        $html =~ m{
            <span
            \s+
            class=(["'])
            [^"']*\brk-name-text\b[^"']*
            \1
            [^>]*>
            (.*?)
            </span>
        }gxis
    ) {
        my $name = $2;

        # A célula esperada contém texto simples, mas removemos tags por segurança.
        $name =~ s/<[^>]+>//g;
        $name = decode_html_entities($name);
        $name =~ s/^\s+|\s+$//g;

        push @found, $name if length $name;
    }

    # Remove duplicados preservando a ordem.
    my %seen;
    @found = grep { !$seen{$_}++ } @found;

    return @found;
}

sub write_state {
    my (%extra) = @_;

    my $now = int(time);

    my %state = (
        version      => 1,
        updated      => $now,
        last_success => $last_success || undef,
        status       => $extra{status} // 'unknown',
        count        => scalar(@players),
        online       => \@players,
    );

    $state{http_status} = $extra{http_status} if defined $extra{http_status};
    $state{error}       = $extra{error}       if defined $extra{error};

    my $tmp = "$OUTPUT.tmp.$$";
    open my $fh, '>:raw', $tmp
        or die "nao foi possivel criar $tmp: $!";

    print {$fh} $json->encode(\%state);
    close $fh
        or die "erro fechando $tmp: $!";

    rename $tmp, $OUTPUT
        or die "nao foi possivel substituir $OUTPUT: $!";
}

sub signature {
    return join("\0", @players);
}

logmsg("online-watcher iniciado");
logmsg("config=$CONFIG");
logmsg("url=$URL");
logmsg("intervalo=${INTERVAL}s timeout=${TIMEOUT}s");
logmsg("saida=$OUTPUT");

while (1) {
    my %headers = (
        accept => 'text/html,application/xhtml+xml',
    );

    if ($USE_ETAG) {
        $headers{'if-none-match'}     = $etag          if defined $etag && length $etag;
        $headers{'if-modified-since'} = $last_modified if defined $last_modified && length $last_modified;
    }

    my $res;

    eval {
        $res = $http->get($URL, { headers => \%headers });
        1;
    } or do {
        my $err = $@ || 'erro desconhecido';
        chomp $err;

        write_state(
            status => 'error',
            error  => $err,
        );

        logmsg("erro HTTP: $err") if $last_status ne 'error';
        $last_status = 'error';
        sleep($INTERVAL);
        next;
    };

    my $status = $res->{status} // 0;

    if ($status == 304) {
        $last_success = int(time);

        write_state(
            status      => 'ok',
            http_status => 304,
        );

        if ($last_status ne 'ok') {
            logmsg("HTTP 304; cache valido; " . scalar(@players) . " jogador(es) online");
        }

        $last_status = 'ok';
        sleep($INTERVAL);
        next;
    }

    if (!$res->{success}) {
        my $reason = $res->{reason} // 'falha HTTP';

        write_state(
            status      => 'error',
            http_status => $status,
            error       => $reason,
        );

        if ($last_status ne 'error') {
            logmsg("HTTP $status: $reason");
        }

        $last_status = 'error';
        sleep($INTERVAL);
        next;
    }

    my @new_players = extract_players($res->{content} // '');

    # Se a estrutura da pagina mudar, evita publicar silenciosamente uma lista vazia.
    if (!@new_players && ($res->{content} // '') !~ /id=["']rk-tbody["']/i) {
        write_state(
            status      => 'error',
            http_status => $status,
            error       => 'estrutura HTML esperada nao encontrada',
        );

        if ($last_status ne 'error') {
            logmsg("HTML inesperado: rk-tbody/rk-name-text nao encontrado");
        }

        $last_status = 'error';
        sleep($INTERVAL);
        next;
    }

    @players = @new_players;
    $last_success = int(time);

    $etag = $res->{headers}{etag}
        if defined $res->{headers}{etag};

    $last_modified = $res->{headers}{'last-modified'}
        if defined $res->{headers}{'last-modified'};

    write_state(
        status      => 'ok',
        http_status => $status,
    );

    my $sig = signature();

    if ($sig ne $last_signature || $last_status ne 'ok') {
        logmsg(
            "HTTP $status; "
            . scalar(@players)
            . " jogador(es) online: "
            . join(', ', @players)
        );

        $last_signature = $sig;
    }

    $last_status = 'ok';
    sleep($INTERVAL);
}
