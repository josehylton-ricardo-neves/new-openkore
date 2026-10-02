package pacrManual;

use strict;
use warnings;

use Plugins;
use Commands;
use Globals qw($messageSender);
use Log qw(message warning);
use AI;
use Time::HiRes qw(time);
use IO::Socket::INET;

Plugins::register(
    'pacrManual',
    'Parser PACR 7FF3 + resposta manual.',
    \&unload
);

my $hooks = Plugins::addHooks(
    ['packet/thanatos_pacr', \&on_pacr, undef],
	['mainLoop_pre',         \&check_auto_answer_delay, undef],
);

#my $commands = Commands::register(
#    ['pacr', 'PACR: pacr | pacr <1-8> | pacr clear', \&cmd_pacr],
#);


#my $commands = Commands::register(
#    [
#        'pacr',
#        'PACR: pacr | pacr <1-8> | pacr clear',
#        \&cmd_pacr
#    ],
#    [
#        'pacrtest',
#        'Simula um challenge PACR capturado',
#        \&cmd_pacrtest
#   ],
#);


my $commands = Commands::register(
    [
        'pacr',
        'PACR: pacr | pacr <1-8> | pacr clear',
        \&cmd_pacr
    ],
    [
        'pacrtest',
        'Simula um challenge PACR capturado',
        \&cmd_pacrtest
    ],
    [
        'pacrbuild',
        'Monta resposta PACR sem enviar',
        \&cmd_pacrbuild
    ],
);


my $current;
my $auto_answer_at;

my $pacr_ai_paused = 0;
my $pacr_previous_ai_state;


#sub captcha_alarm {
#    return unless $^O eq 'MSWin32';
#
#    my $ps =
#          '[Console]::Beep(3500,700);' . 'Start-Sleep -Milliseconds 500;'
#        . '[Console]::Beep(3500,700);' . 'Start-Sleep -Milliseconds 500;'
#        . '[Console]::Beep(3500,700);' . 'Start-Sleep -Milliseconds 500;'
#        . '[Console]::Beep(3500,700);' . 'Start-Sleep -Milliseconds 500;'
        #. '[Console]::Beep(3500,700);' . 'Start-Sleep -Milliseconds 1;'
        #. '[Console]::Beep(3500,700);' . 'Start-Sleep -Milliseconds 1;'
        #. '[Console]::Beep(3500,700);' . 'Start-Sleep -Milliseconds 1;'
        #. '[Console]::Beep(3500,700);' . 'Start-Sleep -Milliseconds 1;'
        #. '[Console]::Beep(3500,700);' . 'Start-Sleep -Milliseconds 1;'
        #. '[Console]::Beep(3500,700);' . 'Start-Sleep -Milliseconds 1;'
        #. '[Console]::Beep(3500,700);' . 'Start-Sleep -Milliseconds 1;'
#        . '[Console]::Beep(3500,700);';

#    my $cmd =
#        'start "" powershell.exe '
#      . '-NoProfile '
#      . '-WindowStyle Hidden '
#      . '-Command "'
#      . $ps
#      . '"';
#
#    system(
#        'cmd.exe',
#        '/c',
#        $cmd
#    );
#}


sub captcha_alarm {

    my $sock = IO::Socket::INET->new(
        PeerHost => 'host.docker.internal',
        PeerPort => 18090,
        Proto    => 'tcp',
        Timeout  => 2
    );

    unless ($sock) {
        warning "[PACR] Nao foi possivel acionar o alarme no Windows.\n";
        return;
    }

    $sock->autoflush(1);

    print $sock
        "GET /captcha HTTP/1.1\r\n" .
        "Host: host.docker.internal\r\n" .
        "Connection: close\r\n" .
        "\r\n";

    close $sock;

    message "[PACR] Alarme de CAPTCHA enviado ao Windows.\n", 'success';
}



sub pause_ai_for_pacr {
    # Já pausamos por causa deste PACR.
    # Não sobrescreve o estado original com OFF.
    return if $pacr_ai_paused;

    $pacr_previous_ai_state = AI::state();

    AI::state(AI::OFF);

    $pacr_ai_paused = 1;

    message sprintf("[PACR] AI pausada. Estado anterior=%d\n", $pacr_previous_ai_state), 'success';
	
}

sub resume_ai_after_pacr {
    return unless $pacr_ai_paused;

    if (defined $pacr_previous_ai_state) {
        AI::state($pacr_previous_ai_state);
        message sprintf("[PACR] AI restaurada. Estado=%d\n", $pacr_previous_ai_state), 'success';
    }

    $pacr_ai_paused = 0;
    undef $pacr_previous_ai_state;
}





sub on_pacr {
    my (undef, $args) = @_;

    my $len     = $args->{len}     // 0;
    my $magic   = $args->{magic}   // '';
    my $type    = $args->{type}    // 0;
    my $payload = $args->{payload} // '';

    unless ($magic eq 'PACR') {
        warning sprintf("[PACR] 7FF3 com magic invalido: %s\n", unpack('H*', $magic));
        return;
    }

    message sprintf("[PACR] 7FF3 recebido: len=%u type=%u\n", $len, $type), 'success';


    # ==========================================================
    # TYPE 1 - challenge
    # Total observado: 95 bytes
    # ==========================================================

    if ($type == 1) {

		unless ($len == 95 && length($payload) == 85) {
			warning sprintf("[PACR] Challenge inesperado: len=%u payload=%u\n", $len, length($payload));
			return;
		}
		
		pause_ai_for_pacr();

		# 4 campos iniciais + 9 IDs = 13 uint32
		my @v = unpack(
			'V13',
			substr($payload, 0, 52)
		);

		my $challenge_id = $v[0];
		my $timeout      = $v[1];
		my $flags        = $v[2];
		my $attempts     = $v[3];

		my @ids = @v[4 .. 12];

		my $target  = $ids[0];
		my @options = @ids[1 .. 8];

		my $token = unpack(
			'Z33',
			substr($payload, 52, 33)
		);


		# ==========================================================
		# ALERTA SONORO
		# ==========================================================
		captcha_alarm();


		# Guarda o challenge atual para o comando "pacr"
		$current = {
			challenge_id => $challenge_id,
			timeout      => $timeout,
			flags        => $flags,
			attempts     => $attempts,
			target       => $target,
			options      => \@options,
			token        => $token,
			answered     => 0,
		};


		# ==========================================================
		# MOSTRA NO CONSOLE
		# ==========================================================

		message "\n";
		message "========== CAPTCHA PACR ==========\n", 'success';

		message sprintf("opcode    = 0x%04X\n", 0x7FF3);
		message sprintf("length    = %u\n", $len);
		message sprintf("magic     = %s\n", $magic);
		message sprintf("type      = %u\n\n", $type);
		message sprintf("challenge = %u\n", $challenge_id);
		message sprintf("timeout   = %u\n", $timeout);
		message sprintf("flags     = %u\n", $flags);
		message sprintf("attempts  = %u\n", $attempts);
		message sprintf("target    = %u\n\n", $target);
		message "options:\n";

		for my $i (0 .. $#options) {
			message sprintf("  %d -> %u\n", $i + 1, $options[$i]);
		}
		message "\n";
		message sprintf("token = %s\n", $token);
		message "\n";
		message "Para responder: pacr <1-8>\n";
		message "==================================\n\n";
		
		
		#BLOCO IF NAO ENVIA AUTO_ANSWER SE TIVER DESCOMENTADO PARA O COMANDO pacrtest
		if ($args->{dry_run}) {
			message "[PACR TEST] Dry-run: resposta nao sera enviada.\n";
			return;
		}
		
		auto_ack_answer();
		
		#auto_answer();
		$auto_answer_at = time() + 3.0;
		message "[PACR] Resposta automatica agendada para daqui a 3 segundo.\n";

		return;
	}


    # ==========================================================
    # TYPE 2 - resultado
    # Total observado: 18 bytes
    # ==========================================================

    if ($type == 2) {

        unless ($len == 18 && length($payload) == 8) {
            warning sprintf("[PACR] Resultado inesperado: len=%u payload=%u\n", $len, length($payload));
            return;
        }

        my (
            $challenge_id,
            $result,
            $flags,
            $reserved
        ) = unpack(
            'V v C C',
            substr($payload, 0, 8)
        );

        message sprintf("[PACR] RESULT challenge=%u result=%u flags=%u reserved=%u\n", $challenge_id, $result, $flags, $reserved), 'success';
		
		
		if ($result == 0) {
			
			undef $auto_answer_at;

			message sprintf("[PACR] CAPTCHA ACEITO challenge=%u\n", $challenge_id), 'success';

			if ($current && $current->{challenge_id} == $challenge_id) {
				undef $current;
			}

			resume_ai_after_pacr();

		} else {
			if ($current && $current->{challenge_id} == $challenge_id) {
				$current->{answered} = 0;
			}
			
			warning sprintf("[PACR] CAPTCHA REJEITADO challenge=%u result=%u. AI continua pausada.\n", $challenge_id, $result);
			
			warning "[PACR] POR FAVOR INSIRA O CAPTCHA MANUAL COM O COMANDO pacr <1-8>\n";
		}

        return;
    }


    # ==========================================================
    # TYPE 3 - reconhecido pela DLL
    # Total = 10 bytes
    # ==========================================================

    if ($type == 3) {
        message "[PACR] TYPE 3 recebido. Limpando challenge atual.\n";
		undef $current;

        return;
    }

    warning sprintf("[PACR] Type desconhecido: %u len=%u payload=%s\n", $type, $len, unpack('H*', $payload));
}


sub check_auto_answer_delay {

    return unless defined $auto_answer_at;
    return unless time() >= $auto_answer_at;

    undef $auto_answer_at;

    auto_answer();
}



sub auto_answer {

    return unless $current;
    return if $current->{answered};

    my $selected_item;       # lógica que resolve o captcha
	foreach my $item (@{$current->{options}}) {

        if ($current->{target} == $item) {
            $selected_item = $item;
            last;
        }
    }

    #return unless defined $selected_item;
	unless (defined $selected_item) {
		warning sprintf("[PACR] AUTO: target=%u nao encontrado nas opcoes.\n", $current->{target});
		return;
	}

    $messageSender->sendPACRResponse(
        $current->{challenge_id},
        $selected_item,
        $current->{token}
    );

    $current->{answered} = 1;
}


sub auto_ack_answer {

    return unless $current;

    $messageSender->sendAckPACRResponse($current->{challenge_id}, $current->{token});

}


sub show_current {

    unless ($current) {
        message "[PACR] Nenhum challenge ativo.\n";
        return;
    }

    message "\n";
    message "================ PACR ATUAL ====================\n";
    message sprintf("Challenge ID : %u\n", $current->{challenge_id});
    message sprintf("Timeout      : %u\n", $current->{timeout});
    message sprintf("Tentativas   : %u\n", $current->{attempts});
    message sprintf("Target ID    : %u\n", $current->{target});
    message "\nOpcoes:\n";

    for my $i (0 .. 7) {
        message sprintf("  %d -> %u\n", $i + 1, $current->{options}[$i]);
    }

    message sprintf("\nRespondido: %s\n", $current->{answered} ? 'sim' : 'nao');
    message "================================================\n";
}


sub cmd_pacr {
    my (undef, $args) = @_;

    $args //= '';

    $args =~ s/^\s+//;
    $args =~ s/\s+$//;

    # pacr
    if ($args eq '') {
        show_current();
        return;
    }


    # pacr clear
    if (lc($args) eq 'clear') {
        undef $current;
        message "[PACR] Estado local limpo.\n";
        return;
    }


    # pacr 1 .. pacr 8
    unless ($args =~ /^([1-8])$/) {
        message("[PACR] Uso: pacr | pacr <1-8> | pacr clear\n");
        return;
    }


    unless ($current) {
        warning "[PACR] Nenhum challenge ativo.\n";
        return;
    }


    if ($current->{answered}) {
        warning("[PACR] Esse challenge ja recebeu uma resposta. " . "Aguarde o resultado do servidor.\n");
        return;
    }


    my $choice = int($1);

    my $selected_item_id = $current->{options}[ $choice - 1 ];

    my $token = $current->{token};

    unless (defined $token && length($token) == 32) {
        warning sprintf("[PACR] Token invalido. Comprimento=%d\n", defined($token) ? length($token) : -1);
        return;
    }


    # ----------------------------------------------------------
    # Estrutura observada no cliente oficial:
    #
    # v   opcode          = 0x7FF3
    # v   length          = 51
    # a4  magic           = PACR
    # v   type            = 1
    # V   challenge_id
    # V   selectedItemId
    # Z33 token
    # ----------------------------------------------------------

    my $msg = pack(
        'v v a4 v V V Z33',
        0x7FF3,
        51,
        'PACR',
        1,
        $current->{challenge_id},
        $selected_item_id,
        $token
    );


    unless (length($msg) == 51) {
        warning sprintf("[PACR] ERRO: pacote construido com %d bytes em vez de 51.\n", length($msg));
        return;
    }

    message sprintf("[PACR] Enviando escolha manual %d -> challenge=%u itemID=%u" . " token=$token\n", $choice, $current->{challenge_id}, $selected_item_id), 'success';

    message sprintf("[PACR] RAW=%s\n", unpack('H*', $msg));

    $messageSender->sendToServer($msg);

    $current->{answered} = 1;
}



sub cmd_pacrtest {
    message "\n[PACR TEST] Simulando challenge capturado no Wireshark...\n", 'success';

    my @ids = (
        503,   # target
        517,
        4013,
        503,
        506,
        4009,
        513,
        4003,
        504,
    );

    my $payload = pack(
        'V13 Z33',
        187,        # challenge_id
        60,         # timeout
        0,          # flags
        3,          # attempts

        @ids,

        '69492b75d24059d558b4e63273650812'
    );

    message sprintf("[PACR TEST] payload=%d bytes\n", length($payload));

    my %args = (
        len     => 95,
        magic   => 'PACR',
        type    => 1,
        payload => $payload,
		dry_run => 1,
    );

    on_pacr(
        undef,
        \%args
    );
}




sub cmd_pacrbuild {
    my (undef, $args) = @_;

    $args //= '';
    $args =~ s/^\s+//;
    $args =~ s/\s+$//;

    unless ($args =~ /^([1-8])$/) {
        warning "[PACR] Uso: pacrbuild <1-8>\n";
        return;
    }

    unless ($current) {
        warning "[PACR] Nenhum challenge ativo.\n";
        return;
    }

    my $choice = int($1);

    my $selected_item_id =
        $current->{options}[ $choice - 1 ];

    my $msg = pack(
        'v v a4 v V V Z33',
        0x7FF3,
        51,
        'PACR',
        1,
        $current->{challenge_id},
        $selected_item_id,
        $current->{token}
    );

    message "\n========== PACR BUILD TEST ==========\n", 'success';

    message sprintf("choice           = %d\n", $choice);
    message sprintf("challenge        = %u\n", $current->{challenge_id});
    message sprintf("selected_item_id = %u\n", $selected_item_id);
    message sprintf( "length           = %u\n", length($msg));
    message sprintf("hex              = %s\n", unpack('H*', $msg));

    message "NAO FOI ENVIADO AO SERVIDOR.\n";
    message "=====================================\n\n";
}




sub unload {

    Plugins::delHooks($hooks);

    Commands::unregister($commands)
        if $commands;

    undef $current;
	undef $auto_answer_at;

    message "[PACR] Plugin descarregado.\n";
}

1;