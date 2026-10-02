package albertaAfterService;

use strict;
use warnings;
use Time::HiRes qw(time);

use Plugins;
use Globals qw($char $field $net %config);
use Log qw(message warning error);
use Network;
use AI;
use Utils qw(blockDistance);

Plugins::register(
    'albertaAfterService',
    'Apos storage/sell: usa curandeiro duas vezes e teleportador no primeiro destino.',
    \&unload
);

#my $hooks = Plugins::addHooks(
#    ['storageSellRoutine_completed', \&onServiceCompleted, undef],
#    ['AI_pre',                       \&onAI,               undef],
#    ['map_loaded',                   \&onMapLoaded,        undef],
#);

my $hooks = Plugins::addHooks(
    ['storageSellRoutine_completed',    \&onServiceCompleted, undef],
    ['storageSellRoutine_manual_reset', \&onMasterReset,      undef],
    ['AI_pre',                          \&onAI,               undef],
    ['map_loaded',                      \&onMapLoaded,        undef],
);



my $phase       = 'IDLE';
my $phase_since = 0;
my $heal_count  = 0;
my $next_action = 0;
my $healer;
my $teleporter;

sub cfg {
    my ($key, $default) = @_;
    return $default if !defined $config{$key} || $config{$key} eq '';
    return $config{$key};
}

sub enabled {
    return cfg('albertaAfterService', 0) ? 1 : 0;
}

sub in_game {
    return 0 unless $net;
    return $net->getState() == Network::IN_GAME ? 1 : 0;
}

sub city_map {
    return cfg('albertaAfterService_cityMap', 'alberta');
}

sub set_phase {
    my ($new_phase) = @_;
    $phase = $new_phase;
    $phase_since = time;
}

sub parse_npc {
    my ($spec, $label) = @_;
    if (!defined $spec || $spec !~ /^\s*(\S+)\s+(\d+)\s+(\d+)\s*$/) {
        error "[albertaAfterService] Configuracao invalida para $label: '$spec'. Use: mapa x y\n";
        return;
    }

    return {
        map => $1,
        x   => int($2),
        y   => int($3),
    };
}

sub near_npc {
    my ($npc) = @_;
    return 0 unless $npc && $field && $char;
    return 0 unless $field->baseName eq $npc->{map};

    my $pos = $char->{pos_to} || $char->{pos};
    return 0 unless $pos;

    return blockDistance($pos, { x => $npc->{x}, y => $npc->{y} }) <= cfg('albertaAfterService_npcDistance', 4);
}

sub route_to {
    my ($npc, $next_phase, $label) = @_;

    AI::clear();
    message "[albertaAfterService] Indo ate $label em $npc->{map} $npc->{x} $npc->{y}.\n", 'success';

    ai_route(
        $npc->{map},
        $npc->{x},
        $npc->{y},
        attackOnRoute => 0,
        distFromGoal  => cfg('albertaAfterService_npcDistance', 4),
        noSitAuto     => 1,
    );

    set_phase($next_phase);
}

#sub talk_healer {
#    my $steps = cfg('albertaAfterService_healerSteps', 'c');
#
#    AI::clear('route', 'mapRoute', 'move');
#    message "[albertaAfterService] Usando curandeiro (" . ($heal_count + 1) . "/" . cfg('albertaAfterService_healerTimes', 2) . ").\n", 'success';
#
#    ai_talkNPC($healer->{x}, $healer->{y}, $steps);
#    $heal_count++;
#    set_phase('HEAL_TALK');
#}



sub talk_healer {
    AI::clear('route', 'mapRoute', 'move', 'NPC');

    message "[albertaAfterService] Usando curandeiro ("
        . ($heal_count + 1)
        . "/"
        . cfg('albertaAfterService_healerTimes', 2)
        . ").\n", 'success';

    # Este NPC nao possui dialogo/menu:
    # basta clicar nele para receber cura e buffs.
    ai_talkNPC(
        $healer->{x},
        $healer->{y},
        ''
    );

    $heal_count++;

    # Pequeno intervalo apenas para o servidor aplicar os buffs.
    $next_action = time + cfg('albertaAfterService_healerDelay', 0.5);

    set_phase('HEAL_DELAY');
}






sub route_teleporter {
    route_to($teleporter, 'TELE_ROUTE', 'teleportador');
}

sub talk_teleporter {
    # r0 = primeira opcao da lista. O 'c' antes torna a sequencia tolerante
    # a NPCs que mostram uma tela de "continuar" antes do menu.
    my $steps = cfg('albertaAfterService_teleporterSteps', 'c r0');

    AI::clear('route', 'mapRoute', 'move');
    message "[albertaAfterService] Usando teleportador e escolhendo o primeiro destino (r0).\n", 'success';

    ai_talkNPC($teleporter->{x}, $teleporter->{y}, $steps);
    set_phase('TELE_TALK');
}

#sub finish {
#    AI::clear('albertaAfterServiceHold');
#
#    $phase = 'IDLE';
#    $phase_since = 0;
#    $heal_count = 0;
#    $next_action = 0;
#
#    message "[albertaAfterService] Teleporte concluido. IA normal liberada.\n", 'success';
#}



sub finish {
    AI::clear('albertaAfterServiceHold');

    $phase = 'IDLE';
    $phase_since = 0;
    $heal_count = 0;
    $next_action = 0;

    message "[albertaAfterService] Teleporte concluido. IA normal liberada.\n", 'success';

    Plugins::callHook('albertaAfterService_completed', {
        success => 1,
        map     => ($field ? $field->baseName : ''),
    });
}



#sub abort_routine {
#    my ($why) = @_;
#
#    AI::clear('albertaAfterServiceHold');
#    warning "[albertaAfterService] Rotina cancelada: $why. IA normal liberada.\n";
#
#    $phase = 'IDLE';
#    $phase_since = 0;
#    $heal_count = 0;
#    $next_action = 0;
#}


sub abort_routine {
    my ($why) = @_;

    AI::clear('albertaAfterServiceHold');

    warning "[albertaAfterService] Rotina cancelada: $why. IA normal liberada.\n";

    $phase = 'IDLE';
    $phase_since = 0;
    $heal_count = 0;
    $next_action = 0;

    Plugins::callHook('albertaAfterService_completed', {
        success => 0,
        reason  => $why,
        map     => ($field ? $field->baseName : ''),
    });
}


sub onServiceCompleted {
    return unless enabled();
    return unless in_game();
    return unless $field && $char;

    $healer = parse_npc($config{'albertaAfterService_healerNpc'}, 'albertaAfterService_healerNpc');
    return unless $healer;

    $teleporter = parse_npc($config{'albertaAfterService_teleporterNpc'}, 'albertaAfterService_teleporterNpc');
    return unless $teleporter;

    if ($field->baseName ne city_map()) {
        warning "[albertaAfterService] Handoff recebido fora de " . city_map() . ". Ignorando.\n";
        return;
    }

    $heal_count = 0;
    route_to($healer, 'HEAL_ROUTE', 'curandeiro');
}

#sub onAI {
#    return if $phase eq 'IDLE';
#    return unless enabled();
#    return unless in_game();
#    return unless $field && $char;
#
#    my $timeout = cfg('albertaAfterService_timeout', 30);

sub onAI {
    return if $phase eq 'IDLE';
    return unless enabled();
    return unless in_game();
    return unless $field && $char;

    # Se o teleportador ja nos tirou de Alberta,
    # encerra o pos-servico imediatamente.
    if ($phase eq 'TELE_TALK' && $field->baseName ne city_map()) {
        message "[albertaAfterService] Novo mapa detectado: " . $field->baseName . ". Liberando IA imediatamente.\n", 'success';
        finish();
        return;
    }

    my $timeout = cfg('albertaAfterService_timeout', 30);

	if ($timeout > 0 && time - $phase_since > $timeout && !AI::inQueue('NPC')) {
		abort_routine("timeout na fase $phase");
		return;
	}

    if ($phase eq 'HEAL_ROUTE') {
        return if AI::inQueue('route', 'mapRoute', 'move');

        if (near_npc($healer)) {
            talk_healer();
        } else {
            abort_routine('nao conseguiu chegar ao curandeiro');
        }
        return;
    }

    #if ($phase eq 'HEAL_TALK') {
    #    return if AI::inQueue('NPC');
	#
    #    my $times = cfg('albertaAfterService_healerTimes', 2);
    #    if ($heal_count < $times) {
    #        $next_action = time + cfg('albertaAfterService_healerDelay', 1);
    #        set_phase('HEAL_DELAY');
    #    } else {
    #        route_teleporter();
    #    }
    #    return;
    #}
	
	
	
	
	#if ($phase eq 'HEAL_TALK') {
	#
	#	if (AI::inQueue('NPC')) {
	#		my $max_wait = cfg('albertaAfterService_healerTalkMax', 2);
	#
	#		# Dá tempo suficiente para os buffs chegarem,
	#		# mas não fica vários segundos esperando o Task::TalkNPC.
	#		if (time - $phase_since < $max_wait) {
	#			return;
	#		}
	#
	#		warning "[albertaAfterService] Curandeiro ja teve tempo de responder; limpando TalkNPC antigo.\n";
	#		AI::clear('NPC');
	#	}
	#
	#	my $times = cfg('albertaAfterService_healerTimes', 2);
	#
	#	if ($heal_count < $times) {
	#		$next_action = time + cfg('albertaAfterService_healerDelay', 0.2);
	#		set_phase('HEAL_DELAY');
	#	} else {
	#		route_teleporter();
	#	}
	#
	#	return;
	#}
	
	
	
	
	
	
	
	
	
	

    #if ($phase eq 'HEAL_DELAY') {
    #    return if time < $next_action;
	#
    #    if (near_npc($healer)) {
    #        talk_healer();
    #    } else {
    #        route_to($healer, 'HEAL_ROUTE', 'curandeiro');
    #    }
    #    return;
    #}
	
	if ($phase eq 'HEAL_DELAY') {
		return if time < $next_action;

		# O healer ja aplicou os buffs.
		# Nao deixamos um TalkNPC residual segurar a rotina.
		AI::clear('NPC');

		my $times = cfg('albertaAfterService_healerTimes', 2);

		if ($heal_count < $times) {
			if (near_npc($healer)) {
				talk_healer();
			} else {
				route_to($healer, 'HEAL_ROUTE', 'curandeiro');
			}
		} else {
			route_teleporter();
		}

		return;
	}
	
	
	
	
	

    if ($phase eq 'TELE_ROUTE') {
        return if AI::inQueue('route', 'mapRoute', 'move');

        if (near_npc($teleporter)) {
            talk_teleporter();
        } else {
            abort_routine('nao conseguiu chegar ao teleportador');
        }
        return;
    }

    if ($phase eq 'TELE_TALK') {
        # O Task::TalkNPC pode terminar imediatamente quando o NPC teleporta.
        # Enquanto aguardamos map_loaded, deixamos uma acao-hold na fila para
        # lockMap/randomWalk nao retomarem antes da mudanca de mapa.
        if (!AI::inQueue('NPC') && !AI::inQueue('albertaAfterServiceHold')) {
            AI::queue('albertaAfterServiceHold', { started => time });
        }
        return;
    }
}

sub onMapLoaded {
    return unless $phase eq 'TELE_TALK';
    return unless $field;

    # O primeiro destino do teleportador deve nos tirar de Alberta.
    if ($field->baseName ne city_map()) {
        finish();
    }
}




sub onMasterReset {
    my (undef, $args) = @_;

    my $why = $args && $args->{reason}
        ? $args->{reason}
        : 'reset solicitado pelo storageSellRoutine';

    # Cancela conversa/rota do pos-servico.
    AI::clear(
        'albertaAfterServiceHold',
        'NPC',
        'route',
        'mapRoute',
        'move'
    );

    $phase       = 'IDLE';
    $phase_since = 0;
    $heal_count  = 0;
    $next_action = 0;

    undef $healer;
    undef $teleporter;

    message "[albertaAfterService] Reset recebido do storageSellRoutine: $why\n", 'success';
}

sub unload {
    Plugins::delHooks($hooks);
    AI::clear('albertaAfterServiceHold');
    message "[albertaAfterService] Plugin descarregado.\n", 'success';
}


1;
