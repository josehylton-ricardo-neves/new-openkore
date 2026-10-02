#########################################################################
# OpenKore - oRO receive profile (experimental v3)
#########################################################################
package Network::Receive::kRO::RagexeRE_oRO_2026_08_04;

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
	delete $self->{packet_lut}{map_login_trigger};

	$self->{oro_received_sync_count} = 0;
	$self->{oro_blocking_cancel_sent} = 0;

	# 09FF remains inherited until its oRO field layout is confirmed.
	return $self;
}

sub received_sync {
	my ($self, $args) = @_;
	$self->SUPER::received_sync($args);

	$self->{oro_received_sync_count}++;
	#print "oRO RECV 007F received_sync count=$self->{oro_received_sync_count}\n";

	if ($self->{oro_received_sync_count} >= 2 && !$self->{oro_blocking_cancel_sent}) {
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

	message "oRO RECV 084B item_appeared ID=$hex len=$len nameID=$nameID x=$x y=$y\n", 'drop';

	if (defined($id) && length($id) == 4) {
		$ORO_GROUND_ITEM_IDS{$id} = time;
	}

	$self->SUPER::item_appeared($args);
}

1;
