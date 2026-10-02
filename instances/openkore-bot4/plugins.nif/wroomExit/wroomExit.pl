package wroomExit;

use strict;
use warnings;

use Plugins;
use Globals qw($field $char $messageSender %config);
use Log qw(message warning);
use AI;
use Misc;

Plugins::register(
	'wroomExit',
	'Sai automaticamente do mapa wroom usando a rota capturada do cliente oficial.',
	\&onUnload,
	\&onReload
);

my $hooks = Plugins::addHooks(
	['AI_pre', \&onAIpre, undef],
);

# Rota extraída de oro_cliente_wroom_saida.pcapng.
# Posição inicial observada: 48,46.
# O último ponto, 48,14, ativa o portal para new_1-1.gat (53,111).
my @waypoints = (
	[46, 47],
	[43, 47],
	[37, 48],
	[32, 47],
	[30, 47],
	[29, 46],
	[29, 41],
	[29, 35],
	[29, 29],
	[37, 28],
	[45, 28],
	[48, 27],
	[47, 23],
	[47, 22],
	[48, 14],
);

my $active = 0;
my $index = 0;
my $last_send = 0;
my $retry_count = 0;
my %saved_config;

sub current_map {
	return '' unless $field;

	my $name = eval { $field->baseName() };
	return defined($name) ? $name : '';
}

sub current_position {
	return undef unless $char;

	# calcPosition fornece a posição interpolada enquanto o personagem caminha.
	my $position = eval { Misc::calcPosition($char) };

	if (
		$position
		&& defined($position->{x})
		&& defined($position->{y})
	) {
		return $position;
	}

	# Fallback apenas se calcPosition não estiver disponível.
	for my $key (qw(pos pos_to)) {
		my $candidate = $char->{$key};
		if (
			$candidate
			&& defined($candidate->{x})
			&& defined($candidate->{y})
		) {
			return $candidate;
		}
	}

	return undef;
}

sub save_and_disable {
	for my $key (qw(
		attackAuto
		route_randomWalk
		storageAuto
		lockMap
	)) {
		$saved_config{$key} = {
			existed => exists($config{$key}) ? 1 : 0,
			value   => $config{$key},
		};
	}

	$config{attackAuto} = 0;
	$config{route_randomWalk} = 0;
	$config{storageAuto} = 0;
	$config{lockMap} = '';

	# Cancela rotas ou ações antigas para não competir com a saída do wroom.
	eval { AI::clear() };

	message(
		"[wroomExit] wroom detectado. Iniciando rota capturada; ataque, lockMap e storage foram pausados.\n",
		'wroomExit'
	);
}

sub restore_config {
	for my $key (keys %saved_config) {
		if ($saved_config{$key}{existed}) {
			$config{$key} = $saved_config{$key}{value};
		} else {
			delete $config{$key};
		}
	}

	%saved_config = ();

	message(
		"[wroomExit] Configurações anteriores restauradas.\n",
		'wroomExit'
	);
}

sub start_route {
	$active = 1;
	$index = 0;
	$last_send = 0;
	$retry_count = 0;

	save_and_disable();
}

sub stop_route {
	my ($map) = @_;

	restore_config() if %saved_config;

	$active = 0;
	$index = 0;
	$last_send = 0;
	$retry_count = 0;

	message(
		"[wroomExit] Saída concluída. Mapa atual: $map.\n",
		'wroomExit'
	);
}

sub send_target {
	my ($x, $y) = @_;

	return unless $messageSender;

	$messageSender->sendMove($x, $y);
	$last_send = time();
	$retry_count++;

	message(
		"[wroomExit] Enviado waypoint " .
		($index + 1) . "/" . scalar(@waypoints) .
		": $x,$y (tentativa $retry_count).\n",
		'wroomExit'
	);
}

sub onAIpre {
	my $map = current_map();

	if ($map ne 'wroom') {
		stop_route($map) if $active;
		return;
	}

	start_route() unless $active;

	return unless $char && $messageSender;

	my $position = current_position();
	return unless $position;

	# Todos os waypoints já foram enviados. Enquanto o servidor não trocar
	# o mapa, repete somente o ponto do portal em intervalos seguros.
	if ($index >= scalar(@waypoints)) {
		if (time() - $last_send >= 5) {
			$messageSender->sendMove(48, 14);
			$last_send = time();

			warning(
				"[wroomExit] Ainda em wroom; reenviando o ponto do portal 48,14.\n",
				'wroomExit'
			);
		}
		return;
	}

	my ($target_x, $target_y) = @{$waypoints[$index]};
	my $dx = abs($position->{x} - $target_x);
	my $dy = abs($position->{y} - $target_y);

	# Quando chega ao waypoint, avança para o próximo.
	if ($dx <= 1 && $dy <= 1) {
		message(
			"[wroomExit] Waypoint alcançado: $target_x,$target_y.\n",
			'wroomExit'
		);

		$index++;
		$last_send = 0;
		$retry_count = 0;

		if ($index >= scalar(@waypoints)) {
			message(
				"[wroomExit] Portal alcançado em 48,14; aguardando mudança de mapa.\n",
				'wroomExit'
			);
		}
		return;
	}

	# Primeira tentativa ou reenvio caso o movimento não tenha sido confirmado.
	if ($last_send == 0 || time() - $last_send >= 5) {
		send_target($target_x, $target_y);
	}
}

sub onUnload {
	restore_config() if %saved_config;
	Plugins::delHooks($hooks);

	message(
		"[wroomExit] Plugin descarregado.\n",
		'wroomExit'
	);
}

sub onReload {
	restore_config() if %saved_config;

	$active = 0;
	$index = 0;
	$last_send = 0;
	$retry_count = 0;

	message(
		"[wroomExit] Plugin recarregado.\n",
		'wroomExit'
	);
}

1;
