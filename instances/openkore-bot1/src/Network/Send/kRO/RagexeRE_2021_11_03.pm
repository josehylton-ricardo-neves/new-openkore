#########################################################################
#  OpenKore - Packet sending
#  This module contains functions for sending packets to the server.
#
#  This software is open source, licensed under the GNU General Public
#  License, version 2.
#  Basically, this means that you're allowed to modify and distribute
#  this software. However, if you distribute modified versions, you MUST
#  also distribute the source code.
#  See http://www.gnu.org/licenses/gpl.html for the full license.
########################################################################
#  by alisonrag
package Network::Send::kRO::RagexeRE_2021_11_03;

use strict;
use base qw(Network::Send::kRO::RagexeRE_2020_07_23);
use Log qw(debug);
use Utils qw(getTickCount);
use Data::Dumper;

sub new {
	my ($class) = @_;
	
	#print "### CARREGOU SEND RagexeRE_2021_11_03 ###\n";
	
	my $self = $class->SUPER::new(@_);

	my %packets = (
		'0944' => ['map_login', 'a4 a4 a4 V C', [qw(accountID charID sessionID tick sex)]],#23
	);

	$self->{packet_list}{$_} = $packets{$_} for keys %packets;
	
	$self->{packet_lut}{map_login} = '0944';
	#print Dumper($self->{packet_lut}{map_login});

	return $self;
}

# 0x0436,23
sub sendMapLogin {
	my ($self, $accountID, $charID, $sessionID, $sex) = @_;

	$sex = 0 if ($sex > 1 || $sex < 0);

	my $tick = getTickCount();

	my $msg = pack(
		'v a4 a4 a4 V C',
		0x0944,
		$accountID,
		$charID,
		$sessionID,
		$tick,
		$sex
	);

	#print "MAP LOGIN SIZE=" . length($msg) . "\n";
	#print unpack("H*", $msg) . "\n";

	$self->sendToServer($msg);

	#print "### MAP LOGIN ENVIADO ###\n";
}

1;
