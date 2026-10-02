#########################################################################
#  OpenKore - Packet Receiveing
#  This module contains functions for Receiveing packets to the server.
#
#  This software is open source, licensed under the GNU General Public
#  License, version 2.
#  Basically, this means that you're allowed to modify and distribute
#  this software. However, if you distribute modified versions, you MUST
#  also distribute the source code.
#  See http://www.gnu.org/licenses/gpl.html for the full license.
########################################################################
# Korea (kRO) #bysctnightcore
# The majority of private servers use eAthena, this is a clone of kRO
package Network::Receive::kRO::RagexeRE_2017_09_13b;
use strict;
use base qw(Network::Receive::kRO::RagexeRE_2017_07_26c);



use Globals qw(
	$accountID
	$char
	$messageSender
	$sessionID
);



sub new {
	my ($class) = @_;	
	my $self = $class->SUPER::new(@_);
	
	
	
	
	
	my %packets = (
		'09E7' => ['map_login_trigger', 'a*', [qw(data)]],
	);


	$self->{packet_list}{$_} = $packets{$_} for keys %packets;
	
	$self->{packet_lut}{map_login_trigger} = '09E7';
	
	
	
	
	
	
	print "\n===== PACKETS COM GUILD recive=====\n";

	foreach my $id (keys %{$self->{packet_list}}) {
		my $name = $self->{packet_list}{$id}[0];

		if ($name =~ /guild/i) {
			print "$id => $name\n";
		}
	}

	print "=============================\n";
	
	
	
	
	

	return $self;
}

sub map_login_trigger {
	my ($self, $args) = @_;

	print "========== ENTROU NO HANDLER 09E7 ==========\n";
	print "TAMANHO 09E7: ".length($args->{data})."\n";
	print "RECEBEU 09E7 - enviando MAP LOGIN 0944\n";


	$messageSender->sendMapLogin(
		$accountID,
		$char->{ID},
		$sessionID,
		$char->{sex}
	);

}


1;
