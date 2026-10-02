package trainingGround;

# v3: adiciona caminhada automática de new_1-1 até o portal de new_1-2.

use strict;
use warnings;

use Plugins;
use Globals qw($field $char %config %talk $npcsList);
use Log qw(message warning error);
use Commands;
use AI;
use Misc;
use Time::HiRes qw(time);
use File::Basename qw(dirname);
use File::Spec;

Plugins::register(
	'trainingGround',
	'Completa o treinamento inicial e usa a Kafra para ir a Prontera.',
	\&onUnload,
	\&onReload
);

my $hooks = Plugins::addHooks(
	['AI_pre',                    \&onAIpre,       undef],
	['npc_talk',                  \&onTalkEvent,   undef],
	['packet/npc_talk_continue',  \&onTalkEvent,   undef],
	['npc_talk_responses',        \&onTalkEvent,   undef],
	['packet/npc_talk_text',      \&onTalkEvent,   undef],
	['npc_talk_done',             \&onTalkDone,    undef],
	['Network::Receive::map_changed', \&onMapChanged, undef],
);

# Cada etapa usa:
# - map: mapa em que a conversa deve ocorrer
# - stand: posição observada do personagem
# - npc: posições candidatas do NPC
# - sequence: sequência Task::TalkNPC
#
# __CHAR__ é substituído pelo nome atual do personagem.
my @steps = (
	{
		label    => 'NPC 1',
		map      => 'new_1-1',
		stand    => [53, 111],
		npc      => [[53, 113]],
		sequence => 'c c c c r0 c c c c n',
	},
	{
		label    => 'NPC 2',
		map      => 'new_1-1',
		stand    => [53, 111],
		npc      => [[53, 113]],
		sequence => 'c c c n',
	},
	{
		label    => 'NPC 3',
		map      => 'new_1-2',
		stand    => [14, 114],
		# A anotação forneceu 14,114 e também 53,113.
		# O plugin procura primeiro um NPC visível perto de 14,114
		# e mantém 53,113 como alternativa.
		npc      => [[14, 114], [53, 113]],
		sequence => 'c t="__CHAR__" c c r0 c c n',
	},
	{
		label    => 'NPC 4',
		map      => 'new_1-2',
		stand    => [99, 103],
		npc      => [[99, 105]],
		sequence => 'c c c r0 c c c c c c c c c c c c c c c c c c c c n',
	},
	{
		label    => 'NPC 5',
		map      => 'new_1-2',
		stand    => [85, 111],
		npc      => [[83, 111]],
		sequence => 'c r0 c c c c c c c c c c c c c c c c r0 n',
	},
	{
		label    => 'NPC 6',
		map      => 'new_1-2',
		stand    => [111, 111],
		npc      => [[115, 111]],
		sequence => 'c r0 c c c c c c c c c c c c c c c c r0 c c n',
	},
	{
		label    => 'NPC 7',
		map      => 'new_1-2',
		stand    => [21, 179],
		npc      => [[16, 182]],
		sequence => 'c c c r0 c c c c c c c c c c c c r3 n',
	},
	{
		label    => 'Kafra',
		map      => 'new_1-2',
		stand    => [116, 108],
		npc      => [[118, 108]],
		sequence => 'c c c r0 r1 n',
	},
);

my $active = 0;
my $completed = 0;
my $state = 0;
my $state_loaded_for = '';
my $move_sent_at = 0;
my $talk_sent_at = 0;
my $talk_seen = 0;
my $talk_done = 0;
my $talk_done_at = 0;
my $last_status_at = 0;
my $npc_wait_started = 0;
my $training_map_seen = '';
my $training_map_seen_at = 0;

# Transição após o NPC 2:
# new_1-1 (53,111) -> portal em 148,112 -> new_1-2.
my $portal_target_x = 148;
my $portal_target_y = 112;
my $portal_move_sent_at = 0;
my $portal_last_position_log_at = 0;

my %saved_config;

sub enabled {
	return 1 unless exists $config{trainingGroundAuto};
	return $config{trainingGroundAuto} ? 1 : 0;
}

sub current_map {
	return '' unless $field;

	my $map = eval { $field->baseName() };
	return defined($map) ? $map : '';
}

sub current_position {
	return undef unless $char;

	my $position = eval { Misc::calcPosition($char) };
	if (
		$position
		&& defined($position->{x})
		&& defined($position->{y})
	) {
		return $position;
	}

	for my $key (qw(pos_to pos)) {
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

sub character_name {
	return '' unless $char;
	return defined($char->{name}) ? $char->{name} : '';
}

sub safe_character_name {
	my $name = character_name();
	$name = 'unknown' unless length $name;
	$name =~ s/[^A-Za-z0-9_.-]+/_/g;
	return $name;
}

sub state_file {
	return File::Spec->catfile(
		dirname(__FILE__),
		'trainingGround_' . safe_character_name() . '.state'
	);
}

sub load_state {
	my $name = safe_character_name();
	return if $state_loaded_for eq $name;

	$state_loaded_for = $name;
	$state = 0;

	my $file = state_file();
	if (open my $fh, '<', $file) {
		my $value = <$fh>;
		close $fh;

		if (defined($value) && $value =~ /^\s*(\d+)\s*$/) {
			$state = int($1);
			$state = 0 if $state < 0;
			$state = scalar(@steps) if $state > scalar(@steps);

			message(
				"[trainingGround] Estado retomado do arquivo: $state.\n",
				'trainingGround'
			);
		}
	}
}

sub save_state {
	my $file = state_file();

	if (open my $fh, '>', $file) {
		print {$fh} $state . "\n";
		close $fh;
	} else {
		warning(
			"[trainingGround] Não foi possível salvar o estado em $file: $!\n",
			'trainingGround'
		);
	}
}

sub clear_state_file {
	my $file = state_file();
	unlink $file if -e $file;
}

sub save_and_pause_normal_ai {
	return if %saved_config;

	for my $key (qw(
		attackAuto
		route_randomWalk
		storageAuto
		lockMap
		autoTalkCont
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
	$config{autoTalkCont} = 0;

	eval { AI::clear() };

	message(
		"[trainingGround] IA normal pausada durante o treinamento.\n",
		'trainingGround'
	);
}

sub enforce_pause_normal_ai {
	# Outro plugin pode restaurar as configurações no mesmo instante da troca
	# de mapa. Enquanto o treinamento estiver ativo, garante que a IA normal
	# continue realmente pausada.
	my $changed = 0;

	if (!defined($config{attackAuto}) || $config{attackAuto} ne '0') {
		$config{attackAuto} = 0;
		$changed = 1;
	}

	if (!defined($config{route_randomWalk}) || $config{route_randomWalk} ne '0') {
		$config{route_randomWalk} = 0;
		$changed = 1;
	}

	if (!defined($config{storageAuto}) || $config{storageAuto} ne '0') {
		$config{storageAuto} = 0;
		$changed = 1;
	}

	if (defined($config{lockMap}) && length($config{lockMap})) {
		$config{lockMap} = '';
		$changed = 1;
	}

	if (!defined($config{autoTalkCont}) || $config{autoTalkCont} ne '0') {
		$config{autoTalkCont} = 0;
		$changed = 1;
	}

	# Não apaga a Task::TalkNPC em andamento. O clear é necessário apenas
	# quando uma rota concorrente já foi criada antes da pausa.
	if ($changed && !$talk_sent_at) {
		eval { AI::clear() };
		message(
			"[trainingGround] Configuração concorrente detectada; IA normal pausada novamente.\n",
			'trainingGround'
		);
	}
}

sub restore_normal_ai {
	return unless %saved_config;

	for my $key (keys %saved_config) {
		if ($saved_config{$key}{existed}) {
			$config{$key} = $saved_config{$key}{value};
		} else {
			delete $config{$key};
		}
	}

	%saved_config = ();

	message(
		"[trainingGround] Configurações anteriores restauradas.\n",
		'trainingGround'
	);
}

sub reset_runtime_flags {
	$move_sent_at = 0;
	$talk_sent_at = 0;
	$talk_seen = 0;
	$talk_done = 0;
	$talk_done_at = 0;
	$npc_wait_started = 0;
	$portal_move_sent_at = 0;
	$portal_last_position_log_at = 0;
}

sub activate_training {
	return if $active;

	$active = 1;
	$completed = 0;
	load_state();
	save_and_pause_normal_ai();
	reset_runtime_flags();

	message(
		"[trainingGround] Treinamento detectado. Iniciando na etapa $state/" .
		scalar(@steps) . ".\n",
		'trainingGround'
	);
}

sub complete_training {
	return if $completed;

	$completed = 1;
	$active = 0;
	$state = scalar(@steps);
	$training_map_seen = '';
	$training_map_seen_at = 0;
	clear_state_file();
	restore_normal_ai();
	reset_runtime_flags();

	message(
		"[trainingGround] Prontera detectada. Treinamento concluído.\n",
		'trainingGround'
	);
}

sub distance_chebyshev {
	my ($a, $b) = @_;
	return 999999 unless $a && $b;

	my $dx = abs($a->{x} - $b->{x});
	my $dy = abs($a->{y} - $b->{y});
	return $dx > $dy ? $dx : $dy;
}

sub actor_position {
	my ($actor) = @_;
	return undef unless $actor;

	my $position = $actor->{pos_to} || $actor->{pos};
	return undef unless $position;
	return undef unless defined($position->{x}) && defined($position->{y});

	return {
		x => $position->{x},
		y => $position->{y},
	};
}

sub find_visible_npc {
	my ($step) = @_;
	return undef unless $npcsList;

	my @actors = eval { @{$npcsList->getItems()} };
	return undef if $@;

	my $char_pos = current_position();
	my $best;
	my $best_distance = 999999;

	# Primeiro procura perto das coordenadas esperadas.
	for my $actor (@actors) {
		my $pos = actor_position($actor);
		next unless $pos;

		for my $candidate (@{$step->{npc}}) {
			my $expected = {x => $candidate->[0], y => $candidate->[1]};
			my $distance = distance_chebyshev($pos, $expected);

			if ($distance <= 10 && $distance < $best_distance) {
				$best = $actor;
				$best_distance = $distance;
			}
		}
	}

	return $best if $best;

	# Fallback: NPC visível mais próximo do personagem, limitado a 8 células.
	for my $actor (@actors) {
		my $pos = actor_position($actor);
		next unless $pos;

		my $distance = distance_chebyshev($pos, $char_pos);
		if ($distance <= 8 && $distance < $best_distance) {
			$best = $actor;
			$best_distance = $distance;
		}
	}

	return $best;
}

sub quoted_character_name {
	my $name = character_name();
	$name =~ s/\\/\\\\/g;
	$name =~ s/"/\\"/g;
	return $name;
}

sub sequence_for {
	my ($step) = @_;
	my $sequence = $step->{sequence};
	my $name = quoted_character_name();
	$sequence =~ s/__CHAR__/$name/g;
	return $sequence;
}

sub move_to_standpoint {
	my ($step) = @_;

	my ($x, $y) = @{$step->{stand}};
	Commands::run("move $x $y");

	$move_sent_at = time();
	$npc_wait_started = 0;

	message(
		"[trainingGround] " . $step->{label} .
		": movendo para $x,$y em " . $step->{map} . ".\n",
		'trainingGround'
	);
}

sub start_talking {
	my ($step, $npc) = @_;
	my $pos = actor_position($npc);

	unless ($pos) {
		warning(
			"[trainingGround] " . $step->{label} .
			": NPC encontrado sem posição válida.\n",
			'trainingGround'
		);
		return;
	}

	my $sequence = sequence_for($step);
	Commands::run(
		"talknpc $pos->{x} $pos->{y} $sequence"
	);

	$talk_sent_at = time();
	$talk_seen = 0;
	$talk_done = 0;
	$talk_done_at = 0;

	message(
		"[trainingGround] " . $step->{label} .
		": conversa iniciada com NPC em $pos->{x},$pos->{y}; sequência '$sequence'.\n",
		'trainingGround'
	);
}

sub advance_state {
	my ($reason) = @_;

	$state++;
	$state = scalar(@steps) if $state > scalar(@steps);
	save_state();
	reset_runtime_flags();
	eval { AI::clear() };

	message(
		"[trainingGround] Etapa concluída ($reason). Próximo estado: $state.\n",
		'trainingGround'
	);
}

sub sync_state_with_map {
	my ($map) = @_;

	# A saída do NPC 2 leva de new_1-1 para new_1-2.
	if ($map eq 'new_1-2' && $state < 2) {
		$state = 2;
		save_state();
		reset_runtime_flags();
		eval { AI::clear() };

		message(
			"[trainingGround] Mudança para new_1-2 detectada; avançando para o NPC 3.\n",
			'trainingGround'
		);
	}
}

sub walk_to_new_1_2_portal {
	my $position = current_position();
	return unless $position;

	my $target = {
		x => $portal_target_x,
		y => $portal_target_y,
	};

	my $distance = distance_chebyshev($position, $target);

	# Ao chegar na área do portal, reenvia o ponto exato em intervalos curtos
	# até o servidor confirmar a mudança para new_1-2.
	if ($distance <= 2) {
		if (!$portal_move_sent_at || time() - $portal_move_sent_at >= 4) {
			Commands::run("move $portal_target_x $portal_target_y");
			$portal_move_sent_at = time();

			message(
				"[trainingGround] Portal alcançado em new_1-1 " .
				"($portal_target_x,$portal_target_y); aguardando new_1-2.\n",
				'trainingGround'
			);
		}
		return;
	}

	# O mapa new_1-1 possui Field normal, portanto o comando move calcula
	# o caminho caminhável até o portal. Reenvia apenas se a rota parar.
	if (!$portal_move_sent_at || time() - $portal_move_sent_at >= 20) {
		Commands::run("move $portal_target_x $portal_target_y");
		$portal_move_sent_at = time();

		message(
			"[trainingGround] NPC 2 concluído; caminhando para o portal " .
				"new_1-1 ($portal_target_x,$portal_target_y). " .
				"Posição atual: $position->{x},$position->{y}.\n",
			'trainingGround'
		);
		return;
	}

	if (time() - $portal_last_position_log_at >= 10) {
		$portal_last_position_log_at = time();

		message(
			"[trainingGround] A caminho do portal: " .
				"$position->{x},$position->{y} -> " .
				"$portal_target_x,$portal_target_y.\n",
			'trainingGround'
		);
	}
}

sub onTalkEvent {
	return unless $active;
	return unless $talk_sent_at;

	$talk_seen = 1;
}

sub onTalkDone {
	return unless $active;
	return unless $talk_sent_at;

	$talk_seen = 1;
	$talk_done = 1;
	$talk_done_at = time();
}

sub onMapChanged {
	return unless enabled();

	my $map = current_map();
	if ($map eq 'prontera') {
		complete_training();
		return;
	}

	sync_state_with_map($map) if $active;
}

sub onAIpre {
	return unless enabled();
	return unless $char && $field;

	my $map = current_map();
	return unless length $map;

	if ($map eq 'prontera') {
		complete_training() if $active;
		return;
	}

	my $is_training_map = ($map eq 'new_1-1' || $map eq 'new_1-2');
	return unless $is_training_map;

	# Aguarda um curto intervalo após a troca de mapa. Isso permite que o
	# wroomExit restaure as configurações antigas antes de este plugin salvá-las.
	unless ($active) {
		if ($training_map_seen ne $map) {
			$training_map_seen = $map;
			$training_map_seen_at = time();
			return;
		}

		return if time() - $training_map_seen_at < 2.0;
		activate_training();
	}

	enforce_pause_normal_ai();
	sync_state_with_map($map);

	return if $state >= scalar(@steps);

	# Estado 2 significa que os dois diálogos com Shion foram concluídos.
	# Enquanto ainda estiver em new_1-1, caminhe até o portal em 148,112.
	# A mudança para new_1-2 mantém o estado 2 e inicia o NPC 3.
	if ($state == 2 && $map eq 'new_1-1') {
		walk_to_new_1_2_portal();
		return;
	}

	my $step = $steps[$state];

	# Para outros casos, aguarda o mapa esperado.
	if ($map ne $step->{map}) {
		if (time() - $last_status_at >= 10) {
			$last_status_at = time();
			message(
				"[trainingGround] Aguardando mapa " . $step->{map} .
				"; mapa atual: $map; estado: $state.\n",
				'trainingGround'
			);
		}
		return;
	}

	# Só avança após o servidor fechar a conversa. Enquanto aguarda os 1,5
	# segundos, retorna imediatamente para não abrir o mesmo NPC outra vez.
	if ($talk_done) {
		if (time() - $talk_done_at >= 1.5) {
			advance_state($step->{label});
		}
		return;
	}

	# Conversa enviada, mas ainda não iniciada.
	if ($talk_sent_at && !$talk_seen) {
		if (time() - $talk_sent_at >= 15) {
			warning(
				"[trainingGround] " . $step->{label} .
				": NPC não iniciou conversa em 15 segundos; tentando novamente.\n",
				'trainingGround'
			);
			$talk_sent_at = 0;
			eval { AI::clear() };
		}
		return;
	}

	# Conversa em andamento.
	if ($talk_sent_at && $talk_seen && !$talk_done) {
		if (time() - $talk_sent_at >= 150 && time() - $last_status_at >= 15) {
			$last_status_at = time();
			warning(
				"[trainingGround] " . $step->{label} .
				": conversa ainda não terminou. Verifique o último pedido do NPC no console.\n",
				'trainingGround'
			);
		}
		return;
	}

	my $position = current_position();
	return unless $position;

	my ($stand_x, $stand_y) = @{$step->{stand}};
	my $stand = {x => $stand_x, y => $stand_y};
	my $distance = distance_chebyshev($position, $stand);

	if ($distance > 2) {
		if (!$move_sent_at || time() - $move_sent_at >= 20) {
			move_to_standpoint($step);
		}
		return;
	}

	# Já chegou. Espera o NPC aparecer na lista antes de conversar.
	my $npc = find_visible_npc($step);
	if ($npc) {
		start_talking($step, $npc);
		return;
	}

	$npc_wait_started = time() unless $npc_wait_started;

	if (time() - $npc_wait_started >= 12 && time() - $last_status_at >= 8) {
		$last_status_at = time();
		warning(
			"[trainingGround] " . $step->{label} .
			": nenhum NPC compatível está visível perto de $stand_x,$stand_y. " .
			"Use 'nl' para conferir as coordenadas.\n",
			'trainingGround'
		);
	}
}

sub onUnload {
	restore_normal_ai();
	Plugins::delHooks($hooks);

	message(
		"[trainingGround] Plugin descarregado.\n",
		'trainingGround'
	);
}

sub onReload {
	restore_normal_ai();

	$active = 0;
	$completed = 0;
	$state = 0;
	$state_loaded_for = '';
	$last_status_at = 0;
	$training_map_seen = '';
	$training_map_seen_at = 0;
	reset_runtime_flags();

	message(
		"[trainingGround] Plugin recarregado.\n",
		'trainingGround'
	);
}

1;
