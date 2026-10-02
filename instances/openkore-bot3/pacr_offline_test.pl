use strict;
use warnings;

# ============================================================
# Challenge real capturado no Wireshark.
# Total: 95 bytes.
# ============================================================

my $hex =
    'f37f5f00'
  . '50414352'
  . '0100'
  . 'bb000000'
  . '3c000000'
  . '00000000'
  . '03000000'
  . 'a30f0000'
  . '05020000'
  . 'ad0f0000'
  . 'f7010000'
  . 'fa010000'
  . 'a90f0000'
  . '01020000'
  . 'a30f0000'
  . 'f8010000'
  . '3639343932623735643234303539643535386234653633323733363530393132'
  . '00';


my $msg = pack(
    'H*',
    $hex
);


print "Tamanho real: " . length($msg) . "\n\n";

die "Esperava 95 bytes\n"
    unless length($msg) == 95;


my (
    $opcode,
    $len,
    $magic,
    $type
) = unpack(
    'v v a4 v',
    substr($msg, 0, 10)
);


print sprintf(
    "opcode = 0x%04X\n",
    $opcode
);

print "length = $len\n";
print "magic  = $magic\n";
print "type   = $type\n\n";


die "Opcode incorreto\n"
    unless $opcode == 0x7FF3;

die "Length incorreto\n"
    unless $len == 95;

die "Magic incorreto\n"
    unless $magic eq 'PACR';

die "Type incorreto\n"
    unless $type == 1;


my $payload =
    substr($msg, 10);


my @v = unpack(
    'V13',
    substr($payload, 0, 52)
);


my $challenge_id = $v[0];
my $timeout      = $v[1];
my $flags        = $v[2];
my $attempts     = $v[3];

my @ids = @v[4 .. 12];

my $target = $ids[0];

my @options =
    @ids[1 .. 8];


my $token = unpack(
    'Z33',
    substr($payload, 52, 33)
);


print "challenge = $challenge_id\n";
print "timeout   = $timeout\n";
print "flags     = $flags\n";
print "attempts  = $attempts\n";
print "target    = $target\n\n";


print "options:\n";

for my $i (0 .. 7) {

    print sprintf(
        "  %d -> %u\n",
        $i + 1,
        $options[$i]
    );
}


print "\ntoken = $token\n\n";


# ============================================================
# Opcional:
# passe 1..8 na linha de comando para construir uma resposta.
#
# Exemplo:
# perl pacr_offline_test.pl 7
# ============================================================

my $choice = shift @ARGV;


if (defined $choice) {

    die "Escolha deve ser 1..8\n"
        unless $choice =~ /^[1-8]$/;


    my $selected =
        $options[$choice - 1];


    my $response = pack(
        'v v a4 v V V Z33',
        0x7FF3,
        51,
        'PACR',
        1,
        $challenge_id,
        $selected,
        $token
    );


    print "\n";
    print "Escolha manual: $choice\n";
    print "selectedItemId: $selected\n";
    print "response length: "
        . length($response)
        . "\n";

    print "response hex:\n";
    print unpack(
        'H*',
        $response
    );
    print "\n";
}