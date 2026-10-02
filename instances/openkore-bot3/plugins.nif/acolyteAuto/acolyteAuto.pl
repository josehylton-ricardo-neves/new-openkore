package acolyteAuto;

use strict;
use warnings;

use Time::HiRes qw(time);

use Plugins;
use Commands;
use Globals qw(
    $char $field $net $messageSender $questList
    %config %monsters
);
use Log qw(message warning error);
use AI;
use Network;
use Skill;
use Utils qw(blockDistance);

# -----------------------------------------------------------------------------
# acolyteAuto
#
# Fluxo automático:
#   Novice abaixo do Job 10
#     -> equipa itens iniciais encontrados
#     -> distribui pontos apenas em NV_BASIC
#     -> treina em prt_fild08 sem atacar Creamy
#   Novice Job 10 + NV_BASIC 9
#     -> executa a quest clássica de Acolyte do rAthena
#     -> também tenta funcionar na versão Renewal simplificada
#   Acolyte
#     -> volta para prt_fild08
#     -> treina até Job 12 sem distribuir pontos
#     -> restaura as configurações anteriores e finaliza
#
# O plugin não grava alterações no config.txt. As mudanças são somente em memória.
# -----------------------------------------------------------------------------

my $PLUGIN_NAME = 'acolyteAuto';
my $TRAIN_MAP   = 'prt_fild08';
my $TARGET_ACOLYTE_JOB = 12;
my $CREAMY_ID = 1018;

my %QUEST_ROUTE = (
    1001 => {
        label    => 'Father Rubalkabara',
        map      => 'prt_fild03',
        x        => 365,
        y        => 255,
        sequence => 'c c c c c c n',
    },
    1002 => {
        label    => 'Mother Mathilda',
        map      => 'moc_fild07',
        x        => 41,
        y        => 355,
        sequence => 'c c c n',
    },
    1003 => {
        label    => 'Father Yosuke',
        map      => 'prt_fild00',
        x        => 208,
        y        => 218,
        sequence => 'c c c c n',
    },
);

# Nomes comuns em inglês e português. O plugin tenta equipar apenas itens que
# parecem ser equipamentos iniciais de Novice/Aprendiz.
my @NOVICE_GEAR_PATTERNS = (
    qr/novice/i,
    qr/aprendiz/i,
    qr/^knife(?:\s|\[|$)/i,
    qr/^faca(?:\s|\[|$)/i,
    qr/cotton shirt/i,
    qr/camisa de algod/i,
    qr/main[- ]gauche/i,
    qr/escudo.*aprendiz/i,
    qr/novice guard/i,
    qr/sand[aá]lia/i,
    qr/slippers/i,
    qr/false eggshell/i,
    qr/casca de ovo/i,
    qr/armlet/i,
    qr/bra[çc]adeira.*aprendiz/i,
);

my @RUNTIME_KEYS = qw(
    attackAuto
    attackAuto_party
    attackAuto_followTarget
    attackUseWeapon
    route_randomWalk
    lockMap
    lockMap_x
    lockMap_y
    lockMap_randX
    lockMap_randY
    itemsTakeAuto
    itemsGatherAuto
    teleportAuto_idle
    equipAuto
    npcWrongStepsMethod
);

my %original_config;
my %original_exists;
my $config_snapshotted = 0;
my $mode = '';

my $enabled = 1;
my $phase = 'WAIT_LOGIN';
my $next_tick = 0;
my $next_skill_attempt = 0;
my $next_equip_attempt = 0;
my $next_move_attempt = 0;
my $next_talk_attempt = 0;
my $last_log_key = '';
my $dialog_context = '';
my $dialog_started_at = 0;
my $visited_ascetic = 0;
my $quest_started_at = 0;
my $login_ready_at = time + 5;

Plugins::register(
    $PLUGIN_NAME,
    'Cria um Acolyte automaticamente e treina ate Job 12',
    \&on_unload,
);

my $hooks = Plugins::addHooks(
    ['start3',                 \&on_start3,                 undef],
    ['AI_pre',                 \&on_ai_pre,                 undef],
    ['job_level_changed',      \&on_wakeup,                 undef],
    ['job_changed',            \&on_job_changed,            undef],
    ['quest_added',            \&on_wakeup,                 undef],
    ['quest_all_list_end',     \&on_wakeup,                 undef],
    ['npc_talk_done',          \&on_npc_talk_done,          undef],
    ['checkMonsterAutoAttack', \&on_check_monster_attack,   undef],
);

my $commands = Commands::register(
    ['acolyteAuto', 'Controle do plugin acolyteAuto', \&command_handler],
    ['acoauto',     'Controle do plugin acolyteAuto', \&command_handler],
);

message "[acolyteAuto] Plugin carregado. O processo iniciara automaticamente quando entrar no mapa.\n", 'success';
message "[acolyteAuto] Comandos: acolyteAuto status | start | stop | reset\n", 'info';

sub on_unload {
    stop_process(1);
    Plugins::delHooks($hooks) if $hooks;
    Commands::unregister($commands) if $commands;
    message "[acolyteAuto] Plugin descarregado.\n", 'system';
}

sub on_start3 {
    $login_ready_at = time + 5;
    $next_tick = 0;
}

sub on_wakeup {
    $next_tick = 0;
}

sub on_job_changed {
    my ($hook, $args) = @_;
    $next_tick = 0;

    return unless $enabled;
    return unless $args && defined $args->{new_job};

    if ($args->{new_job} == 4) {
        $dialog_context = '';
        $visited_ascetic = 1;
        set_phase('TRAIN_ACOLYTE', 'Mudanca de classe confirmada: Acolyte.');
    }
}

sub on_npc_talk_done {
    return unless $enabled;
    return unless $dialog_context;

    if ($dialog_context eq 'VISIT_ASCETIC') {
        $visited_ascetic = 1;
        set_phase('QUEST_RETURN', 'Visita concluida. Voltando para a igreja de Prontera.');
    } elsif ($dialog_context eq 'SIGNUP') {
        $quest_started_at = time;
        log_once('signup_done', 'Conversa de inscricao concluida. Verificando a rota da quest.');
    } elsif ($dialog_context eq 'FINAL') {
        log_once('final_done', 'Conversa final concluida. Aguardando confirmacao da mudanca de classe.');
    }

    $dialog_context = '';
    $dialog_started_at = 0;
    $next_tick = time + 1;
}

sub on_check_monster_attack {
    my ($hook, $args) = @_;
    return unless $enabled;
    return unless is_training_phase();
    return unless $args && $args->{monster};

    if (is_creamy($args->{monster})) {
        $args->{return} = 0;
    }
}

sub on_ai_pre {
    return unless $enabled;
    return unless time >= $next_tick;

    $next_tick = time + 0.75;

    return unless in_game();
    return unless $char && $field;
    return if time < $login_ready_at;

    recover_stuck_dialog();
    abort_current_creamy_attack();
    process_state();
}

sub process_state {
    my $job_id = defined $char->{jobID} ? $char->{jobID} : -1;
    my $job_lv = defined $char->{lv_job} ? $char->{lv_job} : 0;

    if ($job_id == 4) {
        if ($job_lv >= $TARGET_ACOLYTE_JOB) {
            finish_success();
            return;
        }

        set_phase('TRAIN_ACOLYTE', "Acolyte Job $job_lv/$TARGET_ACOLYTE_JOB. Treinando sem distribuir pontos.");
        apply_training_mode();
        ensure_training_map();
        return;
    }

    if ($job_id != 0) {
        error "[acolyteAuto] Classe inesperada (jobID=$job_id). O plugin funciona apenas com Novice ou Acolyte.\n";
        stop_process(0);
        return;
    }

    
    distribute_novice_basic_skill();

    my $basic_level = novice_basic_level();

    if ($job_lv < 10) {
        set_phase('TRAIN_NOVICE', "Novice Job $job_lv/10. NV_BASIC $basic_level/9.");
        apply_training_mode();
        ensure_training_map();
        return;
    }

    if ($basic_level < 9) {
        set_phase('PREPARE_NOVICE', "Job 10 atingido. Distribuindo NV_BASIC: $basic_level/9.");
        apply_quest_mode();

        if (($char->{points_skill} // 0) <= 0) {
            warning "[acolyteAuto] Job 10, mas NV_BASIC esta em $basic_level e nao ha pontos de habilidade disponiveis. Verifique se algum ponto foi gasto em outra habilidade.\n";
        }
        return;
    }

    run_acolyte_quest();
}

sub run_acolyte_quest {
    apply_quest_mode();

    my $quest_id = active_acolyte_quest_id();

    if ($quest_id && !$visited_ascetic) {
        my $route = $QUEST_ROUTE{$quest_id};
        set_phase('QUEST_VISIT', "Rota detectada: $route->{label}.");

        if (go_to($route->{map}, $route->{x}, $route->{y}, 6)) {
            start_talk(
                'VISIT_ASCETIC',
                $route->{x},
                $route->{y},
                $route->{sequence},
                "Falando com $route->{label}",
            );
        }
        return;
    }

    if ($visited_ascetic) {
        set_phase('QUEST_RETURN', 'Voltando para Father Mareusis para concluir a quest.');

        if (go_to('prt_church', 184, 41, 6)) {
            # Pre-renewal: escolhe a primeira opcao e percorre as telas finais.
            # Renewal: npcWrongStepsMethod=1 faz o TalkNPC ignorar passos extras.
            start_talk(
                'FINAL',
                184,
                41,
                'c r0 c c c c c n',
                'Falando novamente com Father Mareusis',
            );
        }
        return;
    }

    set_phase('QUEST_SIGNUP', 'Indo para a igreja de Prontera iniciar a quest de Acolyte.');

    if (go_to('prt_church', 184, 41, 6)) {
        # Sequencia principal da versao pre-renewal. Na versao Renewal, o passo
        # r0 adicional e ignorado porque npcWrongStepsMethod fica em 1.
        start_talk(
            'SIGNUP',
            184,
            41,
            'c r0 c r0 c c c n',
            'Falando com Father Mareusis para iniciar a quest',
        );
    }
}

sub apply_training_mode {
    return if $mode eq 'TRAINING';

    snapshot_config();
    clear_plugin_ai();

    set_runtime_config('attackAuto',              2);
    set_runtime_config('attackAuto_party',        0);
    set_runtime_config('attackAuto_followTarget', 0);
    set_runtime_config('attackUseWeapon',         1);
    set_runtime_config('route_randomWalk',        1);
    set_runtime_config('lockMap',                 $TRAIN_MAP);
    set_runtime_config('lockMap_x',               '');
    set_runtime_config('lockMap_y',               '');
    set_runtime_config('lockMap_randX',           '');
    set_runtime_config('lockMap_randY',           '');
    set_runtime_config('itemsTakeAuto',           2);
    set_runtime_config('itemsGatherAuto',         0);
    set_runtime_config('teleportAuto_idle',       0);
    set_runtime_config('equipAuto',               0);
    set_runtime_config('npcWrongStepsMethod',     1);

    $mode = 'TRAINING';
    $next_move_attempt = 0;
}

sub apply_quest_mode {
    return if $mode eq 'QUEST';

    snapshot_config();
    clear_plugin_ai();

    set_runtime_config('attackAuto',              0);
    set_runtime_config('attackAuto_party',        0);
    set_runtime_config('attackAuto_followTarget', 0);
    set_runtime_config('route_randomWalk',        0);
    set_runtime_config('lockMap',                 '');
    set_runtime_config('itemsTakeAuto',           0);
    set_runtime_config('itemsGatherAuto',         0);
    set_runtime_config('teleportAuto_idle',       0);
    set_runtime_config('equipAuto',               0);
    set_runtime_config('npcWrongStepsMethod',     1);

    $mode = 'QUEST';
    $next_move_attempt = 0;
    $next_talk_attempt = 0;
}

sub ensure_training_map {
    return if current_map() eq $TRAIN_MAP;
    return if time < $next_move_attempt;
    return if AI::inQueue(qw(mapRoute route move NPC));

    $next_move_attempt = time + 10;
    message "[acolyteAuto] Indo para $TRAIN_MAP.\n", 'info';
    Commands::run("move $TRAIN_MAP");
}

sub go_to {
    my ($map, $x, $y, $distance) = @_;
    $distance //= 5;

    my $current_map = current_map();
    my $position = $char->{pos_to} || $char->{pos};

    if ($current_map eq $map && $position) {
        my $target = {x => $x, y => $y};
        return 1 if blockDistance($position, $target) <= $distance;
    }

    return 0 if time < $next_move_attempt;
    return 0 if AI::inQueue(qw(mapRoute route move NPC));

    $next_move_attempt = time + 8;
    message "[acolyteAuto] Movendo para $map ($x, $y).\n", 'info';
    Commands::run("move $map $x $y");
    return 0;
}

sub start_talk {
    my ($context, $x, $y, $sequence, $description) = @_;

    return if $dialog_context;
    return if time < $next_talk_attempt;
    return if AI::inQueue(qw(NPC));

    $next_talk_attempt = time + 15;
    $dialog_context = $context;
    $dialog_started_at = time;
    message "[acolyteAuto] $description.\n", 'info';
    Commands::run("talknpc $x $y $sequence");
}

sub recover_stuck_dialog {
    return unless $dialog_context;
    return unless $dialog_started_at;
    return if time - $dialog_started_at < 45;

    warning "[acolyteAuto] O dialogo '$dialog_context' excedeu 45 segundos. Cancelando e tentando novamente.\n";
    AI::clear('NPC');
    $dialog_context = '';
    $dialog_started_at = 0;
    $next_talk_attempt = time + 2;
}

sub distribute_novice_basic_skill {
    return unless $char;
    return unless ($char->{jobID} // -1) == 0;
    return if time < $next_skill_attempt;

    my $points = $char->{points_skill} // 0;
    my $level = novice_basic_level();
    return if $points <= 0 || $level >= 9;

    my $skill = eval { Skill->new(handle => 'NV_BASIC') };
    if (!$skill || !defined $skill->getIDN()) {
        warning "[acolyteAuto] Nao foi possivel localizar a habilidade NV_BASIC nas tabelas.\n";
        $next_skill_attempt = time + 10;
        return;
    }

    $next_skill_attempt = time + 2;
    message "[acolyteAuto] Adicionando um ponto em NV_BASIC ($level/9).\n", 'info';
    $messageSender->sendAddSkillPoint($skill->getIDN());
}

sub novice_basic_level {
    return 0 unless $char;
    my $skill = eval { Skill->new(handle => 'NV_BASIC') };
    return 0 unless $skill;
    return $char->getSkillLevel($skill) || 0;
}

sub equip_one_novice_item {
    return unless $char && $char->inventory;
    return if time < $next_equip_attempt;

    for my $item (@{$char->inventory}) {
        next unless $item;
        next unless eval { $item->equippable };
        next if $item->{equipped};

        my $name = $item->{name} // '';
        next unless novice_gear_name($name);

        $next_equip_attempt = time + 2;
        message "[acolyteAuto] Equipando item inicial: $name.\n", 'info';
        eval { $item->equip(); 1 } or warning "[acolyteAuto] Falha ao tentar equipar $name: $@\n";
        return;
    }

    $next_equip_attempt = time + 15;
}

sub novice_gear_name {
    my ($name) = @_;
    return 0 unless defined $name && length $name;

    for my $pattern (@NOVICE_GEAR_PATTERNS) {
        return 1 if $name =~ $pattern;
    }
    return 0;
}

sub active_acolyte_quest_id {
    return 0 unless $questList && ref($questList) eq 'HASH';

    for my $quest_id (1001, 1002, 1003) {
        return $quest_id if exists $questList->{$quest_id};
    }
    return 0;
}

sub abort_current_creamy_attack {
    return unless is_training_phase();
    return unless AI::is('attack');

    my $args = AI::args();
    return unless $args && $args->{ID};

    my $monster = $monsters{$args->{ID}};
    return unless $monster && is_creamy($monster);

    $monster->{ignore} = 1;
    AI::clear('attack');
    log_once('creamy_blocked', 'Creamy detectado: ataque cancelado.');
}

sub is_creamy {
    my ($monster) = @_;
    return 0 unless $monster;

    my $name = lc($monster->{name} // '');
    my $id = $monster->{nameID} // 0;
    return $id == $CREAMY_ID || $name eq 'creamy';
}

sub is_training_phase {
    return $phase eq 'TRAIN_NOVICE' || $phase eq 'TRAIN_ACOLYTE';
}

sub current_map {
    return '' unless $field;
    return eval { $field->baseName } || '';
}

sub in_game {
    return 0 unless $net;
    return $net->getState() == Network::IN_GAME;
}

sub snapshot_config {
    return if $config_snapshotted;

    for my $key (@RUNTIME_KEYS) {
        $original_exists{$key} = exists $config{$key} ? 1 : 0;
        $original_config{$key} = $config{$key} if exists $config{$key};
    }
    $config_snapshotted = 1;
}

sub set_runtime_config {
    my ($key, $value) = @_;
    $config{$key} = $value;
}

sub restore_config {
    return unless $config_snapshotted;

    for my $key (@RUNTIME_KEYS) {
        if ($original_exists{$key}) {
            $config{$key} = $original_config{$key};
        } else {
            delete $config{$key};
        }
    }

    %original_config = ();
    %original_exists = ();
    $config_snapshotted = 0;
    $mode = '';
}

sub clear_plugin_ai {
    AI::clear(qw(attack route mapRoute move NPC randomWalk));
}

sub finish_success {
    return if $phase eq 'DONE';

    clear_plugin_ai();
    restore_config();
    $enabled = 0;
    $phase = 'DONE';
    $dialog_context = '';
    $dialog_started_at = 0;

    my $job_lv = $char->{lv_job} // '?';
    message "[acolyteAuto] Processo concluido com sucesso.\n", 'success';
    message "[acolyteAuto] Personagem: Acolyte Job $job_lv. Pontos de Acolyte nao foram distribuidos.\n", 'success';
    message "[acolyteAuto] Configuracoes anteriores restauradas.\n", 'success';
}

sub stop_process {
    my ($unloading) = @_;

    clear_plugin_ai() if in_game();
    restore_config();
    $enabled = 0;
    $phase = 'STOPPED' unless $phase eq 'DONE';
    $dialog_context = '';
    $dialog_started_at = 0;

    message "[acolyteAuto] Processo interrompido e configuracoes restauradas.\n", 'warning' unless $unloading;
}

sub reset_process {
    clear_plugin_ai() if in_game();
    restore_config();

    $enabled = 1;
    $phase = 'WAIT_LOGIN';
    $mode = '';
    $dialog_context = '';
    $dialog_started_at = 0;
    $visited_ascetic = 0;
    $quest_started_at = 0;
    $next_tick = 0;
    $next_skill_attempt = 0;
    $next_equip_attempt = 0;
    $next_move_attempt = 0;
    $next_talk_attempt = 0;
    $last_log_key = '';
    $login_ready_at = time + 2;

    message "[acolyteAuto] Estado reiniciado. O processo sera reavaliado automaticamente.\n", 'success';
}

sub set_phase {
    my ($new_phase, $text) = @_;
    if ($phase ne $new_phase) {
        $phase = $new_phase;
        $last_log_key = '';
    }
    log_once("phase:$new_phase:$text", $text) if defined $text && length $text;
}

sub log_once {
    my ($key, $text) = @_;
    return if defined $last_log_key && $last_log_key eq $key;
    $last_log_key = $key;
    message "[acolyteAuto] $text\n", 'info';
}

sub command_handler {
    my ($command, $args) = @_;
    $args //= '';
    $args =~ s/^\s+|\s+$//g;
    my ($action) = split /\s+/, lc($args), 2;
    $action //= 'status';

    if ($action eq 'start') {
        if ($enabled) {
            message "[acolyteAuto] O processo ja esta ativo.\n", 'info';
        } else {
            reset_process();
        }
    } elsif ($action eq 'stop') {
        stop_process(0);
    } elsif ($action eq 'reset') {
        reset_process();
    } elsif ($action eq 'status') {
        print_status();
    } else {
        message "Uso: acolyteAuto [start|stop|status|reset]\n", 'info';
    }
}

sub print_status {
    my $state = $enabled ? 'ATIVO' : 'INATIVO';
    my $map = current_map() || '-';
    my $job_id = $char ? ($char->{jobID} // '-') : '-';
    my $job_lv = $char ? ($char->{lv_job} // '-') : '-';
    my $basic = $char ? novice_basic_level() : '-';
    my $quest = active_acolyte_quest_id() || '-';

    message "---------- acolyteAuto ----------\n", 'list';
    message "Estado: $state\n", 'list';
    message "Fase: $phase\n", 'list';
    message "Mapa: $map\n", 'list';
    message "jobID: $job_id | Job Level: $job_lv\n", 'list';
    message "NV_BASIC: $basic | Quest: $quest\n", 'list';
    message "Visitou asceta: " . ($visited_ascetic ? 'sim' : 'nao') . "\n", 'list';
    message "---------------------------------\n", 'list';
}

1;
