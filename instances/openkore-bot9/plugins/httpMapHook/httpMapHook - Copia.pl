package httpMapHook;

use strict;
use warnings;

use Plugins;
use Settings;
use Log qw(message warning error);
use JSON::PP qw(decode_json);
use HTTP::Tiny;
use Time::HiRes qw(usleep);

Plugins::register(
	'httpMapHook',
	'Executa duas requisicoes HTTP apos entrar no mapa',
	\&onUnload
);

message "[httpMapHook] Plugin carregado e registrado.\n";

my $already_ran = 0;

my $hooks = Plugins::addHooks(
	#['map_loaded',   \&onMapLoaded,  undef],
	['packet/sendMapLoaded', \&onMapLoaded,  undef],
	['disconnected', \&onDisconnect, undef],
);

sub onUnload {
	Plugins::delHooks($hooks);
	message "[httpMapHook] Plugin descarregado.\n";
}

sub onDisconnect {
	$already_ran = 0;
	message "[httpMapHook] Reset apos disconnect.\n";
}

sub loadConfig {
	my $file = Settings::getControlFilename('httpMapHook.json');

	open(my $fh, '<:encoding(UTF-8)', $file)
		or die "Nao consegui abrir $file: $!";

	local $/;
	my $json = <$fh>;
	close($fh);

	return decode_json($json);
}

sub validateLocalURL {
	my ($url) = @_;

	return 1 if $url =~ m{^http://127\.0\.0\.1(?::\d+)?/}i;
	return 1 if $url =~ m{^http://localhost(?::\d+)?/}i;

	return 0;
}

sub doRequest {
	my ($http, $cfg, $name) = @_;

	my $method  = uc($cfg->{method} || 'GET');
	my $url     = $cfg->{url} || '';
	my $headers = $cfg->{headers} || {};
	my $body    = defined $cfg->{body} ? $cfg->{body} : '';

	unless (validateLocalURL($url)) {
		error "[httpMapHook] $name recusado: somente localhost/127.0.0.1 neste plugin de teste.\n";
		return;
	}

	message "[httpMapHook] $name\n";
	message "[httpMapHook] $method $url\n";

	my %options = (
		headers => $headers,
	);

	# GET pode ter body tecnicamente, embora seja incomum.
	if (length($body)) {
		$options{content} = $body;
	}

	my $res = $http->request(
		$method,
		$url,
		\%options
	);

	message sprintf(
		"[httpMapHook] HTTP %s %s\n",
		$res->{status} || '?',
		$res->{reason} || ''
	);

	if (defined $res->{content}) {
		message "[httpMapHook] Response body:\n";
		message $res->{content} . "\n";
	}

	return $res;
}

sub onMapLoaded {
	return if $already_ran;

	my $cfg;

	eval {
		$cfg = loadConfig();
	};

	if ($@) {
		error "[httpMapHook] Erro lendo configuracao: $@\n";
		return;
	}

	return unless $cfg->{enabled};

	# Evita rodar novamente quando trocar de mapa.
	$already_ran = 1;

	message "[httpMapHook] Primeira entrada no mapa detectada.\n";

	my $http = HTTP::Tiny->new(
		timeout => $cfg->{timeout_seconds} || 5,
	);

	my $r1 = doRequest(
		$http,
		$cfg->{request1},
		'Request #1'
	);

	my $delay = $cfg->{delay_ms} || 0;

	if ($delay > 0) {
		message "[httpMapHook] Delay: ${delay}ms\n";
		usleep($delay * 1000);
	}

	my $r2 = doRequest(
		$http,
		$cfg->{request2},
		'Request #2'
	);

	message "[httpMapHook] Sequencia HTTP concluida.\n";
}

1;