package dockerMapState;

use strict;
use warnings;
use Plugins;
use Globals;
use Commands;
use Time::HiRes qw(time);
use Log qw(message warning);

Plugins::register(
    'dockerMapState',
    'Gera logs/state.yml para o mapview.pl no modo Docker map',
    \&onUnload
);

my $hooks = Plugins::addHooks(
    ['mainLoop_post', \&onMainLoop]
);

my $last_write = 0;
my $interval = 0.50;
my $command_file = 'logs/map-command.txt';
my $last_field_key = '';
my $last_map_image = '';

sub onUnload {
    Plugins::delHooks($hooks) if $hooks;
}

sub yaml_quote {
    my ($value) = @_;
    $value = '' unless defined $value;
    $value =~ s/'/''/g;
    return "'$value'";
}

sub actor_pos {
    my ($actor) = @_;
    return unless $actor;
    my $p = $actor->{pos_to} || $actor->{pos};
    return unless $p && defined $p->{x} && defined $p->{y};
    return { x => int($p->{x}), y => int($p->{y}) };
}

sub write_actor_list {
    my ($fh, $name, $list) = @_;
    my @positions;

    if ($list) {
        for my $actor (@{$list->getItems}) {
            my $p = actor_pos($actor);
            push @positions, $p if $p;
        }
    }

    if (!@positions) {
        print {$fh} "  $name: []\n";
        return;
    }

    print {$fh} "  $name:\n";
    for my $p (@positions) {
        print {$fh} "    - x: $p->{x}\n";
        print {$fh} "      y: $p->{y}\n";
    }
}

sub current_map_image {
    return '' unless $field;

    my $key = eval { $field->baseName() } || eval { $field->name() } || '';

    if ($key ne $last_field_key || !$last_map_image || !-f $last_map_image) {
        my $image = eval { $field->image() };

        if ($@ || !$image) {
            warning "[dockerMapState] Falha ao gerar/localizar imagem do mapa '$key': $@\n";
            return '';
        }

        $last_field_key = $key;
        $last_map_image = $image;
    }

    return $last_map_image;
}

sub consume_map_command {
    return unless -f $command_file;

    # Renomeia antes de ler para garantir consumo único.
    my $processing = "$command_file.processing.$$";
    return unless rename $command_file, $processing;

    open my $fh, '<:encoding(UTF-8)', $processing or do {
        unlink $processing;
        return;
    };

    my $line = <$fh>;
    close $fh;
    unlink $processing;

    return unless defined $line;
    $line =~ s/\r?\n$//;

    my ($cmd, $map, $x, $y, $stamp) = split /\t/, $line, 5;

    return unless defined $cmd && $cmd eq 'move';
    return unless defined $map && $map =~ /^[A-Za-z0-9_\@-]+$/;
    return unless defined $x && $x =~ /^\d+$/;
    return unless defined $y && $y =~ /^\d+$/;

    return unless $char && $field;

    my $current_map = eval { $field->baseName() } || '';
    if ($map ne $current_map) {
        warning "[dockerMapState] Clique ignorado: mapa mudou de '$map' para '$current_map'.\n";
        return;
    }

    my $width  = eval { $field->width() }  || 0;
    my $height = eval { $field->height() } || 0;

    if ($x < 0 || $y < 0 || ($width && $x >= $width) || ($height && $y >= $height)) {
        warning "[dockerMapState] Clique ignorado: coordenadas fora do mapa ($x,$y).\n";
        return;
    }

    message "[dockerMapState] Clique no mapa: movendo para $x, $y.\n", 'success';

    # Usa o mesmo comando oficial que seria digitado no Console.
    Commands::run("move $x $y");
}

sub onMainLoop {
    consume_map_command();

    return if time - $last_write < $interval;
    $last_write = time;

    my $log_dir = 'logs';
    my $file = "$log_dir/state.yml";
    my $tmp  = "$file.tmp";

    my $in_game = ($char && $field) ? 1 : 0;
    my $pos = $in_game ? actor_pos($char) : undef;
    $pos ||= { x => 0, y => 0 };

    my $field_name = '';
    my $field_base = '';
    my $field_width = 0;
    my $field_height = 0;
    my $map_image = '';

    if ($in_game) {
        $field_name   = eval { $field->name() }     || '';
        $field_base   = eval { $field->baseName() } || $field_name;
        $field_width  = eval { $field->width() }    || 0;
        $field_height = eval { $field->height() }   || 0;
        $map_image    = current_map_image();
    }

    open my $fh, '>:encoding(UTF-8)', $tmp or do {
        warning "[dockerMapState] Não foi possível gravar $tmp: $!\n";
        return;
    };

        print {$fh} "---\n";
        print {$fh} "connectionState: " . yaml_quote($in_game ? 'in game' : 'not in game') . "\n";
        print {$fh} "fieldName: "       . yaml_quote($field_name) . "\n";
        print {$fh} "fieldBaseName: "   . yaml_quote($field_base) . "\n";
        print {$fh} "fieldWidth: "      . int($field_width) . "\n";
        print {$fh} "fieldHeight: "     . int($field_height) . "\n";
        print {$fh} "mapImage: "        . yaml_quote($map_image) . "\n";
        print {$fh} "x: $pos->{x}\n";
        print {$fh} "y: $pos->{y}\n";
        print {$fh} "bus:\n";
        print {$fh} "  host: ''\n";
        print {$fh} "  port: 0\n";
        print {$fh} "  clientID: ''\n";
        print {$fh} "actors:\n";
        write_actor_list($fh, 'NPC',     $npcsList);
        write_actor_list($fh, 'Monster', $monstersList);
        write_actor_list($fh, 'Player',  $playersList);
        close $fh;

    rename $tmp, $file
        or warning "[dockerMapState] Não foi possível substituir $file: $!\n";
}

1;