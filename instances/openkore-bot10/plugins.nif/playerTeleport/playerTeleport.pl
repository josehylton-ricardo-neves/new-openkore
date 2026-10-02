package playerTeleport;

use strict;
use warnings;

use Plugins;
use Globals qw(%config $playersList $char $field $net %ai_v);
use Log qw(message warning);
use Utils::DataStructures qw(existsInList);
use Misc qw(canUseTeleport);
use AI qw(ai_useTeleport);
use Network;
use Time::HiRes qw(time);

my $PLUGIN_NAME = 'playerTeleport';

my $hooks;
my $plugin_was_enabled = 0;
my $saved_teleportAuto_allPlayers;
my $last_teleport = 0;

Plugins::register(
	$PLUGIN_NAME,
	'Teleporta ao detectar players em todos os mapas ou em mapas configurados',
	\&on_unload,
	\&on_reload
);

$hooks = Plugins::addHooks(
	['AI_pre/manual', \&on_ai_pre_manual],
);

message "[playerTeleport] Plugin carregado.\n", "success";

sub on_unload {
	restore_builtin_teleport();
	Plugins::delHook($hooks) if $hooks;
	message "[playerTeleport] Plugin descarregado.\n", "success";
}

sub on_reload {
	on_unload();
}

sub on_ai_pre_manual {
	my $enabled = $config{playerTeleport_enabled} ? 1 : 0;

	# Quando o plugin esta desativado, devolve o controle ao
	# teleportAuto_allPlayers original.
	if (!$enabled) {
		restore_builtin_teleport();
		return;
	}

	# Enquanto o plugin estiver ativo, desabilita teleportAuto_allPlayers
	# somente em memoria. O valor original e guardado para ser restaurado.
	suppress_builtin_teleport();

	return unless $char;
	return unless $field;
	return unless $playersList;
	return unless $net;
	return unless $net->getState == Network::IN_GAME;
	return if $char->{dead};

	# Nao cria outro teleport se ja existe um em andamento.
	return if AI::inQueue('teleport');

	# Verifica se o mapa atual esta habilitado.
	return unless map_is_enabled();

	# Evita spam de tentativas.
	my $cooldown = get_cooldown();
	return if (time - $last_teleport) < $cooldown;

	my $whitelist = defined $config{teleportAuto_notPlayers}
		? $config{teleportAuto_notPlayers}
		: '';

	for my $player (@$playersList) {
		next unless $player;

		my $name   = defined $player->{name}   ? $player->{name}   : '';
		my $nameID = defined $player->{nameID} ? $player->{nameID} : '';

		# Reaproveita a whitelist padrao do OpenKore.
		next if ($name ne ''   && existsInList($whitelist, $name));
		next if ($nameID ne '' && existsInList($whitelist, "$nameID"));

		my $map = $field->baseName || 'desconhecido';
		my $display_name = $name ne '' ? $name : "nameID=$nameID";

		$last_teleport = time;

		if (canUseTeleport(1)) {
			message "[playerTeleport] Player '$display_name' detectado no mapa '$map'. Teleportando.\n", "teleport";

			# Mesmo mecanismo de teleport aleatorio usado pelo OpenKore.
			ai_useTeleport(1);

			# Da prioridade ao teleport sobre a fila atual da AI.
			$ai_v{temp}{clear_aiQueue} = 1;
		} else {
			warning "[playerTeleport] Player '$display_name' detectado no mapa '$map', mas o OpenKore informou que nao pode usar teleport agora.\n";
		}

		# Um player fora da whitelist ja e suficiente.
		last;
	}
}

sub map_is_enabled {
	my $maps = defined $config{playerTeleport_maps}
		? $config{playerTeleport_maps}
		: 'all';

	$maps =~ s/^\s+//;
	$maps =~ s/\s+$//;

	# "all", "*" ou vazio = qualquer mapa.
	return 1 if $maps eq '';
	return 1 if lc($maps) eq 'all';
	return 1 if $maps eq '*';

	my $current_map = $field->baseName || '';
	return 0 if $current_map eq '';

	# Lista separada por virgulas, por exemplo:
	# gef_fild00,gef_fild01,gl_church
	return existsInList($maps, $current_map);
}

sub get_cooldown {
	my $value = $config{playerTeleport_cooldown};

	return 1 unless defined $value;
	return 1 unless $value =~ /^\d+(?:\.\d+)?$/;

	return 0 + $value;
}

sub suppress_builtin_teleport {
	if (!$plugin_was_enabled) {
		$saved_teleportAuto_allPlayers =
			defined $config{teleportAuto_allPlayers}
			? $config{teleportAuto_allPlayers}
			: 0;

		$plugin_was_enabled = 1;

		message "[playerTeleport] Ativado. teleportAuto_allPlayers padrao foi suspenso em memoria.\n", "success";
	}
	elsif (defined $config{teleportAuto_allPlayers}
		&& $config{teleportAuto_allPlayers} ne ''
		&& $config{teleportAuto_allPlayers} != 0)
	{
		# Se houve reload/config alterado enquanto o plugin estava ativo,
		# guarda o novo valor para restaurar depois.
		$saved_teleportAuto_allPlayers = $config{teleportAuto_allPlayers};
	}

	$config{teleportAuto_allPlayers} = 0;
}

sub restore_builtin_teleport {
	return unless $plugin_was_enabled;

	$config{teleportAuto_allPlayers} =
		defined $saved_teleportAuto_allPlayers
		? $saved_teleportAuto_allPlayers
		: 0;

	message "[playerTeleport] Desativado. teleportAuto_allPlayers padrao restaurado para '$config{teleportAuto_allPlayers}'.\n", "success";

	undef $saved_teleportAuto_allPlayers;
	$plugin_was_enabled = 0;
}

1;
