package storageSellRoutine;

use strict;
use warnings;
use Time::HiRes qw(time);

use Plugins;
use Globals qw($char $field $net $messageSender %config);
use Log qw(message warning error);
use Network;
use AI;
use Commands;
use Misc;

Plugins::register(
    'storageSellRoutine',
    'Orquestra @go alberta -> storage -> sell -> @go alberta.',
    \&unload
);

my $hooks = Plugins::addHooks(
    ['AI_pre',                           \&onAI,                undef],
    ['map_loaded',                       \&onMapLoaded,         undef],
    ['Network::serverConnect/mapserver', \&onMapServerConnect, undef],
    ['AI_storage_auto_completed',        \&onStorageCompleted, undef],
    ['AI_sell_auto_completed',           \&onSellCompleted,    undef],
    ['ai_canStartStorageSellBuy',        \&blockNativeAuto,    undef],
);

my $commands = Commands::register(
    [
        'ssr',
        'Controle do storageSellRoutine: ssr start|reset|restart|status',
        \&cmd_ssr
    ],
);

my $phase          = 'IDLE';
my $phase_since    = 0;
my $reason         = '';
my $startup_pending = 1;
my $death_pending   = 0;
my $last_completed  = 0;

sub cfg {
    my ($key, $default) = @_;
    return $default if !defined $config{$key} || $config{$key} eq '';
    return $config{$key};
}

sub enabled {
    return cfg('storageSellRoutine', 0) ? 1 : 0;
}

sub in_game {
    return 0 unless $net;
    return $net->getState() == Network::IN_GAME ? 1 : 0;
}

sub city_map {
    return cfg('storageSellRoutine_cityMap', 'alberta');
}

sub go_command {
    return cfg('storageSellRoutine_goCommand', '@go alberta');
}

sub set_phase {
    my ($new_phase) = @_;
    $phase = $new_phase;
    $phase_since = time;
}

sub hold_ai {
    AI::clear();
    AI::queue('storageSellRoutineHold', { started => time });
}

sub release_hold {
    AI::clear('storageSellRoutineHold');
}

sub reset_runtime {
    my ($why) = @_;

    $why ||= 'reset manual';

    message "[storageSellRoutine] Resetando ciclo: $why\n", 'success';

    # Avisa os plugins dependentes que todo o ciclo esta sendo resetado.
    Plugins::callHook('storageSellRoutine_manual_reset', {
        reason => $why,
    });

    # Remove qualquer tarefa pertencente ao ciclo.
    AI::clear(
        'storageSellRoutineHold',
        'storageAuto',
        'transferItems',
        'sellAuto',
        'buyAuto',
        'NPC',
        'route',
        'mapRoute',
        'move'
    );

    $phase           = 'IDLE';
    $phase_since     = 0;
    $reason          = '';
    $startup_pending = 0;
    $death_pending   = 0;
    $last_completed  = 0;

    message "[storageSellRoutine] Reset concluido. Estado = IDLE.\n", 'success';
}




sub send_go_alberta {
    my $cmd = go_command();
    message "[storageSellRoutine] Enviando: $cmd\n", 'success';
    $messageSender->sendChat($cmd);
}

sub start_routine {
    my ($why) = @_;
    return unless enabled();
    return unless in_game();
    return unless $char && $field && $messageSender;

    $reason = $why || 'manual';

    message "[storageSellRoutine] Iniciando rotina. Motivo: $reason\n", 'success';

    hold_ai();
    set_phase('GO_STORAGE');
    send_go_alberta();
}


sub start_service_only {
    my ($why) = @_;
    return unless enabled();
    return unless in_game();
    return unless $char && $field && $messageSender;

    $reason = $why || 'recuperacao';

    message "[storageSellRoutine] Indo para Alberta sem storage/sell. Motivo: $reason\n", 'success';

    hold_ai();
    set_phase('GO_SERVICE');
    send_go_alberta();
}

sub finish_service_only {
    return unless $phase eq 'GO_SERVICE';

    release_hold();

    AI::clear(
        'route',
        'mapRoute',
        'move',
        'attack',
        'items_take',
        'items_gather'
    );

    my $finished_reason = $reason;

    $reason = '';
    $last_completed = time;

    set_phase('IDLE');

    message "[storageSellRoutine] Alberta confirmada. Pulando storage/sell e indo para healer.\n", 'success';

    Plugins::callHook('storageSellRoutine_completed', {
        reason       => $finished_reason,
        map          => ($field ? $field->baseName : ''),
        service_only => 1,
    });
}



sub begin_storage {
    return unless $phase eq 'GO_STORAGE';

    release_hold();
    AI::clear('route', 'mapRoute', 'move', 'attack', 'items_take', 'items_gather');

    message "[storageSellRoutine] Alberta confirmada. Iniciando autostorage.\n", 'success';
    Commands::run('autostorage');
    set_phase('STORAGE');
}

sub begin_sell {
    release_hold();
    AI::clear('buyAuto');

    message "[storageSellRoutine] Storage concluido. Iniciando autosell.\n", 'success';
    Commands::run('autosell');
    set_phase('SELL');
}

sub begin_final_go {
    hold_ai();
    set_phase('GO_FINAL');

    message "[storageSellRoutine] Venda concluida. Voltando para Alberta.\n", 'success';
    send_go_alberta();
}

sub finish_and_handoff {
    return unless $phase eq 'GO_FINAL';

    release_hold();
    AI::clear('route', 'mapRoute', 'move');

    my $finished_reason = $reason;
    $reason = '';
    $last_completed = time;
    set_phase('IDLE');

    message "[storageSellRoutine] Storage + sell concluido. Entregando para a rotina pos-servico.\n", 'success';

    Plugins::callHook('storageSellRoutine_completed', {
        reason => $finished_reason,
        map    => ($field ? $field->baseName : ''),
    });
}

sub weight_limit {
    my $limit = $config{'itemsMaxWeight_sellOrStore'};
    if (!defined $limit || $limit eq '' || $limit <= 0) {
        $limit = $config{'itemsMaxWeight'};
    }
    return $limit || 0;
}

sub hp_percent {
    return 100 unless $char && $char->{hp_max};
    return ($char->{hp} * 100) / $char->{hp_max};
}

sub sp_percent {
    return 100 unless $char && $char->{sp_max};
    return ($char->{sp} * 100) / $char->{sp_max};
}

#sub trigger_reason {
#    return unless $char;
#
#    my $weight_max = weight_limit();
#    if ($weight_max > 0) {
#        my $weight = Misc::percent_weight($char);
#        return sprintf('peso %.1f%% >= %.1f%%', $weight, $weight_max)
#            if $weight >= $weight_max;
#    }
#
#    my $hp_limit = cfg('storageSellRoutine_hp', 10);
#    if ($hp_limit > 0) {
#        my $hp = hp_percent();
#        return sprintf('HP %.1f%% <= %.1f%%', $hp, $hp_limit)
#            if $hp <= $hp_limit;
#    }
#
#    my $sp_limit = cfg('storageSellRoutine_sp', 5);
#    if ($sp_limit > 0) {
#        my $sp = sp_percent();
#        return sprintf('SP %.1f%% <= %.1f%%', $sp, $sp_limit)
#            if $sp <= $sp_limit;
#    }
#
#    return;
#}



sub storage_trigger_reason {
    return unless $char;

    my $weight_max = weight_limit();

    if ($weight_max > 0) {
        my $weight = Misc::percent_weight($char);

        return sprintf(
            'peso %.1f%% >= %.1f%%',
            $weight,
            $weight_max
        ) if $weight >= $weight_max;
    }

    return;
}

sub resource_trigger_reason {
    return unless $char;

    my $hp_limit = cfg('storageSellRoutine_hp', 10);

    if ($hp_limit > 0) {
        my $hp = hp_percent();

        return sprintf(
            'HP %.1f%% <= %.1f%%',
            $hp,
            $hp_limit
        ) if $hp <= $hp_limit;
    }

    my $sp_limit = cfg('storageSellRoutine_sp', 5);

    if ($sp_limit > 0) {
        my $sp = sp_percent();

        return sprintf(
            'SP %.1f%% <= %.1f%%',
            $sp,
            $sp_limit
        ) if $sp <= $sp_limit;
    }

    return;
}






sub cmd_ssr {
    my (undef, $args) = @_;

    $args //= '';
    $args =~ s/^\s+//;
    $args =~ s/\s+$//;
    $args = lc($args);

    if ($args eq 'start') {

        unless (enabled()) {
            warning "[storageSellRoutine] Plugin desativado no config: storageSellRoutine 0\n";
            return;
        }

        unless (in_game()) {
            warning "[storageSellRoutine] Nao esta IN_GAME.\n";
            return;
        }

        if ($phase ne 'IDLE') {
            warning "[storageSellRoutine] Ciclo ja esta ativo na fase $phase. Use: ssr restart\n";
            return;
        }

        $startup_pending = 0;
        $death_pending = 0;

        start_routine('comando manual');

        return;
    }

    if ($args eq 'reset') {

        reset_runtime('comando ssr reset');

        return;
    }

    if ($args eq 'restart') {

        unless (enabled()) {
            warning "[storageSellRoutine] Plugin desativado no config: storageSellRoutine 0\n";
            return;
        }

        unless (in_game()) {
            warning "[storageSellRoutine] Nao esta IN_GAME.\n";
            return;
        }

        reset_runtime('comando ssr restart');

        start_routine('restart manual');

        return;
    }

    if ($args eq 'status') {

        my $map = $field ? $field->baseName : '-';

        my $elapsed = 0;
        if ($phase_since) {
            $elapsed = time - $phase_since;
        }

        message sprintf(
            "[storageSellRoutine] STATUS phase=%s map=%s reason='%s' elapsed=%.1fs startup_pending=%d death_pending=%d\n",
            $phase,
            $map,
            ($reason || ''),
            $elapsed,
            $startup_pending ? 1 : 0,
            $death_pending ? 1 : 0,
        ), 'success';

        return;
    }

    message(
        "[storageSellRoutine] Uso: ssr start | ssr reset | ssr restart | ssr status\n",
        'success'
    );
}





sub onAI {
    return unless enabled();
    return unless in_game();
    return unless $char && $field;

    # Se morrer durante qualquer fase, a rotina sera reiniciada depois do respawn.
    if ($char->{dead}) {
        $death_pending = 1;
        return;
    }

    if ($death_pending) {
        $death_pending = 0;
        $startup_pending = 0;
        start_routine('morte/respawn');
        return;
    }

    # Primeira entrada no map server da sessao.
    if ($phase eq 'IDLE' && $startup_pending && cfg('storageSellRoutine_onStart', 1)) {
        $startup_pending = 0;
        start_routine('inicio do jogo');
        return;
    }

    # Fallback para servidores em que @go no mesmo mapa nao gere map_loaded.
    if ($phase eq 'GO_STORAGE'
        && $field->baseName eq city_map()
        && time - $phase_since >= cfg('storageSellRoutine_goSettle', 1.0)) {
        begin_storage();
        return;
    }
	
	if ($phase eq 'GO_SERVICE'
		&& $field->baseName eq city_map()
		&& time - $phase_since >= cfg('storageSellRoutine_goSettle', 1.0)) {

		finish_service_only();
		return;
	}

    if ($phase eq 'GO_FINAL'
        && $field->baseName eq city_map()
        && time - $phase_since >= cfg('storageSellRoutine_goSettle', 1.0)) {
        finish_and_handoff();
        return;
    }

    # Se autostorage nao chegou a ser enfileirado (ex.: storage indisponivel),
    # nao deixa a rotina travada para sempre: segue para a venda.
    if ($phase eq 'STORAGE'
        && time - $phase_since >= cfg('storageSellRoutine_queueGrace', 3)
        && !AI::inQueue('storageAuto')) {
        warning "[storageSellRoutine] storageAuto nao esta mais na fila; seguindo para autosell.\n";
        begin_sell();
        return;
    }

    # Mesmo principio para autosell: finaliza o ciclo em vez de ficar preso.
    if ($phase eq 'SELL'
        && time - $phase_since >= cfg('storageSellRoutine_queueGrace', 3)
        && !AI::inQueue('sellAuto')) {
        warning "[storageSellRoutine] sellAuto nao esta mais na fila; seguindo para o retorno a Alberta.\n";
        begin_final_go();
        return;
    }

    return unless $phase eq 'IDLE';

    my $cooldown = cfg('storageSellRoutine_cooldown', 3);
    return if $last_completed && time - $last_completed < $cooldown;

    #my $why = trigger_reason();
    #start_routine($why) if defined $why;
	
	my $storage_why = storage_trigger_reason();

	# Peso sempre tem prioridade.
	# Se atingiu itemsMaxWeight_sellOrStore, sempre faz storage + sell.
	if (defined $storage_why) {
		start_routine($storage_why);
		return;
	}

	my $resource_why = resource_trigger_reason();

	if (defined $resource_why) {

		# 1 = HP/SP baixo tambem faz storage + sell.
		if (cfg('storageSellRoutine_lowResourceStorage', 0)) {
			start_routine($resource_why);
		}

		# 0 = HP/SP baixo pula storage/sell.
		else {
			start_service_only($resource_why);
		}

		return;
	}
	
	
}

#sub onMapLoaded {
#    return unless enabled();
#    return unless $field;
#
#    if ($phase eq 'GO_STORAGE' && $field->baseName eq city_map()) {
#        begin_storage();
#        return;
#    }
#	
#	if ($phase eq 'GO_SERVICE' && $field->baseName eq city_map()) {
#        finish_service_only();
#        return;
#    }
#
#   if ($phase eq 'GO_FINAL' && $field->baseName eq city_map()) {
#       finish_and_handoff();
#        return;
#    }
#}



sub onMapLoaded {
    return unless enabled();
    return unless $field;

    # O map_loaded ocorre antes de todos os actors/NPCs necessariamente
    # terem sido recebidos. Reiniciamos o timer aqui e deixamos o onAI
    # aguardar storageSellRoutine_goSettle antes de continuar.
    if (
        ($phase eq 'GO_STORAGE'
        || $phase eq 'GO_SERVICE'
        || $phase eq 'GO_FINAL')
        && $field->baseName eq city_map()
    ) {
        $phase_since = time;

        message(
            "[storageSellRoutine] Mapa "
            . city_map()
            . " carregado. Aguardando NPCs/atores estabilizarem.\n",
            'success'
        );

        return;
    }
}




sub onStorageCompleted {
    my (undef, $args) = @_;
    return unless $phase eq 'STORAGE';

    # O CoreLogic normalmente pode encadear sell/buy sozinho.
    # Nesta rotina quem controla a ordem somos nos.
    $args->{return} = 1 if $args;
    begin_sell();
}

sub onSellCompleted {
    my (undef, $args) = @_;
    return unless $phase eq 'SELL';

    # Evita o encadeamento automatico para buyAuto.
    $args->{return} = 1 if $args;
    begin_final_go();
}

sub blockNativeAuto {
    my (undef, $args) = @_;
    return if $phase eq 'IDLE';
    $args->{return} = 1 if $args;
}

sub onMapServerConnect {
    # Nova sessao/login: a rotina de inicio deve rodar outra vez.
    AI::clear('storageSellRoutineHold');
    $phase = 'IDLE';
    $phase_since = 0;
    $reason = '';
    $death_pending = 0;
    $startup_pending = 1;
}

#sub unload {
#    Plugins::delHooks($hooks);
#    AI::clear('storageSellRoutineHold');
#    message "[storageSellRoutine] Plugin descarregado.\n", 'success';
#}

sub unload {
    Plugins::delHooks($hooks);
    Commands::unregister($commands) if $commands;

    AI::clear('storageSellRoutineHold');

    message "[storageSellRoutine] Plugin descarregado.\n", 'success';
}

1;
