package kget;

use strict;
use warnings;

use Plugins;
use Commands;
use Globals;
use Log qw(message warning error);
use AI;
use AI::CoreLogic;

Plugins::register(
    'kget',
    'Retira varios itens da Kafra respeitando o limite de peso',
    \&onUnload
);

my $commands = Commands::register(
    ['kget', 'Retira itens da Kafra ate o limite de peso', \&cmdKget]
);

sub cmdKget {
    my ($cmd, $args) = @_;

    # Storage precisa ter sido aberto
    unless ($char && $char->storage->wasOpenedThisSession()) {
        error "[kget] A Kafra ainda nao foi aberta nesta sessao.\n";
        return;
    }

    # E precisa estar aberto agora
    unless ($char->storage->isReady()) {
        error "[kget] O storage precisa estar aberto.\n";
        return;
    }

    unless (defined $args && $args =~ /\S/) {
        message "Uso:\n";
        message "  kget <item>\n";
        message "  kget <item1> <item2> <item3> ...\n";
        message "\n";
        message "Exemplos:\n";
        message "  kget 3\n";
        message "  kget 3 4\n";
        message "  kget 3 4 7 12\n";
        message "  kget 3,4,7,12\n";
        return;
    }

    # Aceita tanto:
    # kget 3 4 7
    # quanto:
    # kget 3,4,7
    $args =~ s/,/ /g;

    my @indices = grep { /^\d+$/ } split /\s+/, $args;

    unless (@indices) {
        error "[kget] Nenhum indice valido informado.\n";
        return;
    }

    # Remove indices duplicados
    my %seen;
    @indices = grep { !$seen{$_}++ } @indices;

    # Mesmo calculo usado pelo OpenKore:
    # peso livre = peso maximo - peso atual
    my $freeWeight = int(
        $char->{weight_max} - $char->{weight}
    );

    if ($freeWeight <= 0) {
        warning "[kget] Voce nao possui peso livre.\n";
        return;
    }

    message sprintf(
        "[kget] Peso atual: %d/%d | Livre: %d\n",
        $char->{weight},
        $char->{weight_max},
        $freeWeight
    );

    my @transferencias;

    foreach my $index (@indices) {

        my $item = $char->storage->get($index);

        unless ($item) {
            warning "[kget] Item #$index nao existe no storage.\n";
            next;
        }

        my $amount = $item->{amount};

        unless ($amount && $amount > 0) {
            warning "[kget] Item #$index esta sem quantidade.\n";
            next;
        }

        #
        # O OpenKore armazena o peso do item em escala x10.
        # A rotina oficial usa:
        #
        #     $item->weight() / 10
        #
        my $unitWeight = $item->weight() / 10;

        my $qty;

        if (!$unitWeight || $unitWeight <= 0) {

            # Item sem peso conhecido
            $qty = $amount;

        } else {

            # Quantos cabem no peso restante?
            my $maxByWeight = int($freeWeight / $unitWeight);

            if ($maxByWeight <= 0) {
                warning sprintf(
                    "[kget] Sem peso para #%d %s (peso/un: %.1f)\n",
                    $index,
                    $item->{name},
                    $unitWeight
                );

                next;
            }

            # Pega o menor:
            # quantidade na Kafra OU quantidade que cabe
            if ($amount < $maxByWeight) {
                $qty = $amount;
            } else {
                $qty = $maxByWeight;
            }
        }

        next unless $qty && $qty > 0;

        push @transferencias, {
            item   => $item,
            source => 'storage',
            target => 'inventory',
            amount => $qty
        };

        if ($unitWeight > 0) {
            my $pesoUsado = $qty * $unitWeight;

            $freeWeight -= $pesoUsado;

            # Evita erro de arredondamento
            $freeWeight = 0 if $freeWeight < 0;
        }

        message sprintf(
            "[kget] #%d %-30s x %d | peso restante: %.1f\n",
            $index,
            $item->{name},
            $qty,
            $freeWeight
        );
    }

    unless (@transferencias) {
        warning "[kget] Nenhum item pode ser retirado.\n";
        return;
    }

    message "[kget] Iniciando retirada...\n";

    #
    # Cria UMA fila com quantidades individuais.
    #
    AI::queue(
        transferItems => {
            # Um pouco maior para dar tempo do servidor responder
            timeout => 0.5,
            items   => \@transferencias
        }
    );

    # Se transferItems ja estiver no topo,
    # executa imediatamente o primeiro.
    AI::CoreLogic::processTransferItems();
}

sub onUnload {
    Commands::unregister($commands);
}

1;