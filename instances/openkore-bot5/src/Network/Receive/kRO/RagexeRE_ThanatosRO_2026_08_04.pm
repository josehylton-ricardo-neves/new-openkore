#########################################################################
# OpenKore - oRO receive profile (experimental v3)
#########################################################################
package Network::Receive::kRO::RagexeRE_ThanatosRO_2026_08_04;

use strict;
use base qw(Network::Receive::kRO::RagexeRE_2017_06_14b);
use Globals qw($messageSender);
use Log qw(message warning);

our %ORO_GROUND_ITEM_IDS;

sub new {
	my ($class) = @_;
	my $self = $class->SUPER::new(@_);

	# An ancestor (RagexeRE_2013_03_20) forces this object flag to 1.
	# Receive.pm tests config OR this flag, so config value 0 alone cannot
	# suppress the two premature 0447 packets.
	$self->{blockingPlayerCancel} = 0;

	$self->{packet_list}{'09E7'} = ['unread_rodex', 'C', [qw(show)]];
	$self->{packet_lut}{unread_rodex} = '09E7';
	
	# ThanatosRO - lista de personagens moderna.
	# Pacote total observado: 179 bytes.
	# 4 bytes de header + 175 bytes de charInfo.
	$self->{packet_list}{'0B72'} = ['received_characters', 'v a*', [qw(len charInfo)]];
	# ThanatosRO - inventory expansion result.
	# Pacote observado: 0B18 00 00 (4 bytes no total).
	$self->{packet_list}{'0B18'} = ['inventory_expansion_result', 'v', [qw(result)]];
	
	$self->{packet_list}{'0298'} = ['rental_time', 'V V', [qw(nameID seconds)]];
	$self->{packet_list}{'0B1B'} = ['load_confirm'];
	$self->{packet_list}{'0B08'} = ['item_list_start', 'v C Z*', [qw(len type name)]];
	$self->{packet_list}{'0B09'} = ['item_list_stackable', 'v C a*', [qw(len type itemInfo)]];
	$self->{packet_list}{'0B39'} = ['item_list_nonstackable', 'v C a*', [qw(len type itemInfo)]];
	$self->{packet_list}{'0B0B'} = ['item_list_end', 'C2', [qw(type flag)]];
	# 0B44 - item adicionado ao storage.
	# Tamanho total: 58 bytes.
	$self->{packet_list}{'0B44'} = ['storage_item_added', 'a2 V V C3 a16 a25 C2', [qw(ID amount nameID type identified broken cards options upgrade grade)]];
	$self->{packet_list}{'0B20'} = ['hotkeys', 'C v a*', [qw(rotate tab hotkeys)]];
	
	
	#$self->{packet_list}{'0ADD'} = ['item_appeared', 'a4 v2 C v2 C2 v C v', [qw(ID nameID type identified x y subx suby amount show_effect effect_type)]];
	$self->{packet_list}{'0ADD'} = ['item_appeared', 'a4 V v C v2 C2 v C v', [qw(ID nameID type identified x y subx suby amount show_effect effect_type)]]; # 24
	
	$self->{packet_list}{'0B41'} = ['inventory_item_added', 'a2 v V C2 a16 V C2 a4 v a25 C v C2', [qw(ID amount nameID identified broken cards type_equip type fail expire unknown options favorite viewID upgrade grade)]];
	
	
	$self->{packet_list}{'009D'} = ['item_exists', 'a4 V C v3 C2', [qw(ID nameID identified x y amount subx suby)]];
	
	
	
	# 0B1A - USESKILL_ACK / skill_cast moderno
	$self->{packet_list}{'0B1A'} = ['skill_cast', 'a4 a4 v5 V C V', [qw(sourceID targetID x y skillID unknown type wait dispose unknow)]];

	# 0BF6 - observado com 10 bytes.
	# Estrutura observada:
	# opcode(v) + len(v) + timestamp(V) + unknown(v)
	$self->{packet_list}{'0BF6'} = ['thanatos_server_time', 'v V v', [qw(len timestamp unknown)]];

	# 0BEA - 43 bytes observados.
	# Ainda não vamos inventar a semantica; consumimos o frame corretamente.
	#$self->{packet_list}{'0BEA'} = ['thanatos_0bea', 'a41', [qw(raw)]];
	#$self->{packet_list}{'0BEA'} = ['thanatos_0bea', 'a42', [qw(raw)]];
	#$self->{packet_list}{'0BEA'} = ['thanatos_0bea', 'a8', [qw(raw)]];
	$self->{packet_list}{'0BEA'} = ['thanatos_0bea', 'a4 v v', [qw(ID unknown1 unknown2)]];
	
	
	$self->{packet_list}{'0B8D'} = ['repute_info', 'v C a*', [qw(len sucess reputeInfo)]];
	
	$self->{packet_list}{'0B47'} = ['char_emblem_update', 'a4 a4', [qw(guildID emblemID accountID)]];
	
	# ============================================================
	# Actor packets modernos - layout usado pelo ThanatosRO
	# Corrige 09FD/09FE/09FF herdados do Sakexe_0 antigo.
	# ============================================================
	#$self->{packet_list}{'09FD'} = ['actor_moved', 'v C a4 a4 v3 V v2 V2 v V v6 a4 a2 v V C2 a6 C2 v2 V2 C v Z*', [qw(len object_type ID charID walk_speed opt1 opt2 option type hair_style weapon shield lowhead tick tophead midhead hair_color clothes_color head_dir costume guildID emblemID manner opt3 stance sex coords xSize ySize lv font maxHP HP isBoss opt4 name)]];
	$self->{packet_list}{'09FD'} = ['actor_moved', 'v C a4 a4 v3 V v2 V2 v V v6 a4 a2 v V C2 a6 C2 v2 V2 C v Z*', [qw(len object_type ID charID walk_speed opt1 opt2 option type hair_style weapon shield lowhead tick tophead midhead hair_color clothes_color head_dir costume guildID emblemID manner opt3 stance sex coords xSize ySize lv font maxHP HP isBoss opt4 name)]];
	$self->{packet_list}{'09FE'} = ['actor_connected', 'v C a4 a4 v3 V v2 V2 v7 a4 a2 v V C2 a3 C2 v2 V2 C v Z*', [qw( len object_type ID charID walk_speed opt1 opt2 option type hair_style weapon shield lowhead tophead midhead hair_color clothes_color head_dir costume guildID emblemID manner opt3 stance sex coords xSize ySize lv font maxHP HP isBoss opt4 name)]];
	#$self->{packet_list}{'09FF'} = ['actor_exists', 'v C a4 a4 v3 V v2 V2 v7 a4 a2 v V C2 a3 C3 v2 V2 C v Z*', [qw(len object_type ID charID walk_speed opt1 opt2 option type hair_style weapon shield lowhead tophead midhead hair_color clothes_color head_dir costume guildID emblemID manner opt3 stance sex coords xSize ySize act lv font maxHP HP isBoss opt4 name)]];
	$self->{packet_list}{'09FF'} = ['actor_exists', 'v C a4 a4 v3 V v2 V2 v7 a4 a2 v V C2 a3 C3 v2 V2 C v Z*', [qw(len object_type ID charID walk_speed opt1 opt2 option type hair_style weapon shield lowhead tophead midhead hair_color clothes_color head_dir costume guildID emblemID manner opt3 stance sex coords xSize ySize act lv font maxHP HP isBoss opt4 name)]];
	
	$self->{packet_list}{'0ADF'} = ['actor_info', 'a4 a4 Z24 Z24', [qw(ID charID name prefix_name)]];
	
	
	$self->{packet_list}{'0100'} = ['thanatos_0100'];
	
	
	
	
	#RESPONSAVEL PELO CAPTCHA E TEM FUNCAO LA EM BAIXO TBM 
	$self->{packet_list}{'7FF3'} = ['thanatos_pacr', 'v a4 v a*', [qw(len magic type payload)]];
	
	
	
	delete $self->{packet_lut}{map_login_trigger};

	$self->{oro_received_sync_count} = 0;
	$self->{oro_blocking_cancel_sent} = 0;

	return $self;
}

sub received_sync {
	my ($self, $args) = @_;
	$self->SUPER::received_sync($args);

	$self->{oro_received_sync_count}++;

	#if ($self->{oro_received_sync_count} >= 2 && !$self->{oro_blocking_cancel_sent}) {
	if ($self->{oro_received_sync_count} >= 1 && !$self->{oro_blocking_cancel_sent}) {
		$self->{oro_blocking_cancel_sent} = 1;
		$messageSender->sendOROBlockingPlayerCancel();
	}
}


# Record the exact four-byte ground-item IDs before the generic handler can
# trigger auto-pickup. sendTake() accepts only IDs recorded here.
sub item_appeared {
	my ($self, $args) = @_;

	my $id = $args->{ID};
	my $len = defined($id) ? length($id) : -1;
	my $hex = (defined($id) && $len > 0) ? unpack('H*', $id) : '<undefined>';
	my $nameID = defined($args->{nameID}) ? $args->{nameID} : '<undefined>';
	my $x = defined($args->{x}) ? $args->{x} : '<undefined>';
	my $y = defined($args->{y}) ? $args->{y} : '<undefined>';

	if (defined($id) && length($id) == 4) {
		$ORO_GROUND_ITEM_IDS{$id} = time;
	}

	$self->SUPER::item_appeared($args);
}







sub thanatos_server_time {
	my ($self, $args) = @_;

	my $timestamp = $args->{timestamp} || 0;
	my $unknown   = $args->{unknown}   || 0;

	my $formatted = $timestamp
		? scalar(localtime($timestamp))
		: '<invalid>';

	message("[ThanatosRO] 0BF6 server_time " . "timestamp=$timestamp ($formatted) " . "unknown=$unknown\n");
}

#sub thanatos_0bea {
#	my ($self, $args) = @_;
#
#	my $raw = $args->{raw} // '';
#
#	message("[ThanatosRO] 0BEA recebido len=" . (2 + length($raw)) . " data=" . unpack('H*', $raw) . "\n");
#}


sub thanatos_0bea {
    my ($self, $args) = @_;

    #message("[ThanatosRO] 0BEA ID=" . unpack('H*', $args->{ID}) . " unknown1=$args->{unknown1}" . " unknown2=$args->{unknown2}\n");
}



sub thanatos_0100 {
	my ($self, $args) = @_;

	#message "[ThanatosRO] 0100 recebido\n";
}


#FUNCAO DO CAPTCHA
sub thanatos_pacr {
    my ($self, $args) = @_;

    # O processamento real fica no plugin pacrManual.pl.
    # Esse handler existe para o OpenKore reconhecer formalmente o pacote.
}

1;
