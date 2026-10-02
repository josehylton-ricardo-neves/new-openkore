package httpMapHook;

use strict;
use warnings;

use Plugins;
use Settings;
use Log qw(message warning error);

use JSON::PP qw(decode_json);
use HTTP::Tiny;
use Time::HiRes qw(time usleep);

Plugins::register(
	'httpMapHook',
	'Executa ciclos HTTP periodicos apos entrar no mapa',
	\&onUnload
);

message "[httpMapHook] Plugin carregado e registrado.\n";

# ============================================================
# ESTADO
# ============================================================

my $session_active = 0;

# Momento em que o próximo ciclo deverá executar.
my $next_run_at = 0;

# Índice do body atualmente usado.
my $body_index = 0;

# Evita iniciar outro ciclo enquanto um já está executando.
my $cycle_running = 0;

# ============================================================
# HOOKS
# ============================================================

my $hooks = Plugins::addHooks(
	['packet/sendMapLoaded', \&onMapLoaded,  undef],
	['AI_pre',               \&onAI,         undef],
	['disconnected',         \&onDisconnect, undef],
);

# ============================================================
# UNLOAD
# ============================================================

sub onUnload {
	Plugins::delHooks($hooks);

	$session_active = 0;
	$cycle_running  = 0;
	$next_run_at    = 0;
	$body_index     = 0;

	message "[httpMapHook] Plugin descarregado.\n";
}

# ============================================================
# DISCONNECT
# ============================================================

sub onDisconnect {
	$session_active = 0;
	$cycle_running  = 0;
	$next_run_at    = 0;
	$body_index     = 0;

	message "[httpMapHook] Reset apos disconnect.\n";
}

# ============================================================
# CONFIG
# ============================================================

sub loadConfig {
	my $file = Settings::getControlFilename(
		'httpMapHook.json'
	);

	open(
		my $fh,
		'<:encoding(UTF-8)',
		$file
	) or die "Nao consegui abrir $file: $!";

	local $/;

	my $json = <$fh>;

	close($fh);

	my $cfg = decode_json($json);

	return $cfg;
}

# ============================================================
# VALIDACAO URL
# ============================================================

sub validateLocalURL {
	my ($url) = @_;

	return 0 unless defined $url;

	return 1
		if $url =~ m{
			^http://127\.0\.0\.1
			(?::\d+)?
			(?:/|$)
		}ix;

	return 1
		if $url =~ m{
			^http://localhost
			(?::\d+)?
			(?:/|$)
		}ix;

	return 0;
}

# ============================================================
# BODY ROTATION
# ============================================================

sub getNextBody {
	my ($cfg) = @_;

	my $bodies = $cfg->{bodies};

	unless (
		ref($bodies) eq 'ARRAY'
		&& scalar(@{$bodies}) > 0
	) {
		error "[httpMapHook] Nenhum body configurado.\n";
		return;
	}

	# Caso o JSON tenha sido alterado e agora tenha menos bodies.
	if ($body_index >= scalar(@{$bodies})) {
		$body_index = 0;
	}

	my $entry = $bodies->[$body_index];

	my $current_index = $body_index;

	my $name;
	my $body;

	if (ref($entry) eq 'HASH') {
		$name = $entry->{name};
		$body = $entry->{body};
	}
	else {
		$name = "body_$current_index";
		$body = $entry;
	}

	$name = "body_$current_index"
		unless defined($name) && length($name);

	$body = ''
		unless defined $body;

	# Prepara próximo body.
	$body_index++;

	if ($body_index >= scalar(@{$bodies})) {
		$body_index = 0;
	}

	return {
		index => $current_index,
		name  => $name,
		body  => $body,
	};
}

# ============================================================
# REQUEST HTTP
# ============================================================

sub doRequest {
	my (
		$http,
		$request,
		$name,
		$body
	) = @_;

	unless (ref($request) eq 'HASH') {
		error "[httpMapHook] $name sem configuracao.\n";
		return;
	}

	my $method = uc(
		$request->{method} || 'GET'
	);

	my $url = $request->{url} || '';

	my $headers = $request->{headers};

	$headers = {}
		unless ref($headers) eq 'HASH';

	#unless (validateLocalURL($url)) {
	#	error(
	#		"[httpMapHook] $name recusado: " .
	#		"somente localhost/127.0.0.1.\n"
	#	);
	#
	#	return;
	#}

	message "[httpMapHook] $name\n";
	message "[httpMapHook] $method $url\n";

	my %options = (
		headers => $headers,
	);

	# POST e GET do mesmo ciclo recebem exatamente
	# o mesmo body selecionado.
	if (
		defined($body)
		&& length($body)
	) {
		$options{content} = $body;
	}

	my $res;

	eval {
		$res = $http->request(
			$method,
			$url,
			\%options
		);
	};

	if ($@) {
		error(
			"[httpMapHook] $name falhou: $@\n"
		);

		return;
	}

	unless ($res) {
		error(
			"[httpMapHook] $name nao retornou resposta.\n"
		);

		return;
	}

	message sprintf(
		"[httpMapHook] HTTP %s %s\n",
		defined($res->{status})
			? $res->{status}
			: '?',
		defined($res->{reason})
			? $res->{reason}
			: ''
	);

	if (
		defined($res->{content})
		&& length($res->{content})
	) {
		message "[httpMapHook] Response body:\n";
		message $res->{content} . "\n";
	}

	return $res;
}

# ============================================================
# CICLO
#
# request1
# delay
# request2
# ============================================================

sub runCycle {
	my (
		$cfg,
		$bodyInfo
	) = @_;

	return if $cycle_running;

	$cycle_running = 1;

	my $ok = eval {

		message sprintf(
			"[httpMapHook] Iniciando ciclo body #%d (%s)\n",
			$bodyInfo->{index},
			$bodyInfo->{name}
		);

		my $timeout =
			$cfg->{timeout_seconds};

		$timeout = 5
			unless defined($timeout)
			&& $timeout > 0;

		my $http = HTTP::Tiny->new(
			timeout => $timeout,
		);

		# --------------------------------------------
		# REQUEST 1
		# --------------------------------------------

		my $r1 = doRequest(
			$http,
			$cfg->{request1},
			'Request #1',
			$bodyInfo->{body}
		);

		# --------------------------------------------
		# DELAY ENTRE REQUEST 1 E REQUEST 2
		# --------------------------------------------

		my $delay =
			$cfg->{delay_ms};

		$delay = 0
			unless defined($delay)
			&& $delay >= 0;

		if ($delay > 0) {

			message sprintf(
				"[httpMapHook] Delay: %dms\n",
				$delay
			);

			usleep(
				$delay * 1000
			);
		}

		# --------------------------------------------
		# REQUEST 2
		# --------------------------------------------

		my $r2 = doRequest(
			$http,
			$cfg->{request2},
			'Request #2',
			$bodyInfo->{body}
		);

		message sprintf(
			"[httpMapHook] Ciclo body #%d (%s) concluido.\n",
			$bodyInfo->{index},
			$bodyInfo->{name}
		);

		1;
	};

	if (!$ok) {
		error(
			"[httpMapHook] Erro executando ciclo: $@\n"
		);
	}

	$cycle_running = 0;
}

# ============================================================
# MAP LOADED
# ============================================================

#sub onMapLoaded {
#
#	# packet/sendMapLoaded pode ocorrer novamente quando
#	# troca de mapa. Não queremos reiniciar a sessão.
#	return if $session_active;
#
#	my $cfg;
#
#	eval {
#		$cfg = loadConfig();
#	};
#
#	if ($@) {
#		error(
#			"[httpMapHook] Erro lendo configuracao: $@\n"
#		);
#
#		return;
#	}
#
#	return unless $cfg->{enabled};
#
#	$session_active = 1;
#	$cycle_running  = 0;
#	$body_index     = 0;
#
#	my $start_delay =
#		$cfg->{start_delay_seconds};
#
#	$start_delay = 0
#		unless defined($start_delay)
#		&& $start_delay >= 0;
#
#	$next_run_at =
#		time() + $start_delay;
#
#	message(
#		"[httpMapHook] Primeira entrada no mapa detectada.\n"
#	);
#
#	message sprintf(
#		"[httpMapHook] Primeiro ciclo em %.2f segundos.\n",
#		$start_delay
#	);
#}









sub onMapLoaded {

    # packet/sendMapLoaded também ocorre em trocas normais de mapa.
    # O primeiro ciclo HTTP deve ocorrer somente uma vez por sessão.
    return if $session_active;

    my $cfg;

    eval {
        $cfg = loadConfig();
    };

    if ($@) {
        error(
            "[httpMapHook] Erro lendo configuracao: $@\n"
        );
        return;
    }

    return unless $cfg->{enabled};

    $session_active = 1;
    $cycle_running  = 0;
    $body_index     = 0;

    message(
        "[httpMapHook] Primeira entrada no mapa detectada.\n"
    );

    message(
        "[httpMapHook] Executando primeiro ciclo IMEDIATAMENTE.\n"
    );

    # --------------------------------------------------------
    # PRIMEIRO BODY
    # --------------------------------------------------------

    my $bodyInfo = getNextBody($cfg);

    unless ($bodyInfo) {
        error(
            "[httpMapHook] Nao foi possivel obter body para o primeiro ciclo.\n"
        );

        $session_active = 0;
        return;
    }

    # --------------------------------------------------------
    # PRIMEIRO CICLO
    #
    # IMPORTANTE:
    # executa dentro do proprio packet/sendMapLoaded.
    # Portanto POST /set-auth e GET /get-auth-status acontecem
    # ANTES de o OpenKore continuar o restante do login.
    # --------------------------------------------------------

    runCycle(
        $cfg,
        $bodyInfo
    );

    # --------------------------------------------------------
    # PROXIMOS CICLOS
    # --------------------------------------------------------

    my $interval =
        $cfg->{interval_seconds};

    $interval = 120
        unless defined($interval)
        && $interval > 0;

    $next_run_at =
        time() + $interval;

    message sprintf(
        "[httpMapHook] Proximo ciclo em %d segundos.\n",
        $interval
    );
}















# ============================================================
# LOOP PRINCIPAL
# ============================================================

sub onAI {

	return unless $session_active;
	return if $cycle_running;

	my $now = time();

	return if $now < $next_run_at;

	my $cfg;

	eval {
		$cfg = loadConfig();
	};

	if ($@) {

		error(
			"[httpMapHook] Erro lendo configuracao: $@\n"
		);

		# Evita tentar ler o JSON em todo tick da IA.
		$next_run_at =
			time() + 5;

		return;
	}

	unless ($cfg->{enabled}) {

		message(
			"[httpMapHook] Plugin desabilitado pelo JSON.\n"
		);

		$session_active = 0;

		return;
	}

	# --------------------------------------------
	# INTERVALO
	# --------------------------------------------

	my $interval =
		$cfg->{interval_seconds};

	$interval = 120
		unless defined($interval)
		&& $interval > 0;

	# --------------------------------------------
	# VALIDA URLs ANTES DE EXECUTAR
	# --------------------------------------------

	for my $requestName (
		qw(request1 request2)
	) {

		my $request =
			$cfg->{$requestName};

		unless (
			ref($request) eq 'HASH'
		) {

			error(
				"[httpMapHook] $requestName inexistente.\n"
			);

			$next_run_at =
				time() + $interval;

			return;
		}

		my $url =
			$request->{url} || '';

		#unless (validateLocalURL($url)) {
		#	error(
		#		"[httpMapHook] $requestName recusado: " .
		#		"somente localhost/127.0.0.1.\n"
		#	);
		#
		#	$next_run_at =
		#		time() + $interval;
		#
		#	return;
		#}
	}

	# --------------------------------------------
	# BODY
	# --------------------------------------------

	my $bodyInfo =
		getNextBody($cfg);

	unless ($bodyInfo) {

		$next_run_at =
			time() + $interval;

		return;
	}

	# --------------------------------------------
	# EXECUTA CICLO
	# --------------------------------------------

	runCycle(
		$cfg,
		$bodyInfo
	);

	# O intervalo começa DEPOIS de o ciclo terminar.
	#
	# Exemplo:
	# POST 100ms
	# delay 120ms
	# GET 100ms
	# terminou
	# +120 segundos
	# próximo ciclo
	#
	# Isso evita "atraso acumulado" estranho.
	$next_run_at =
		time() + $interval;

	message sprintf(
		"[httpMapHook] Proximo ciclo em %d segundos.\n",
		$interval
	);
}

1;