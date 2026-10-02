use strict;
use warnings;

sub captcha_alarm {
    return unless $^O eq 'MSWin32';

    my $ps =
          '[Console]::Beep(3500,700);'
        . 'Start-Sleep -Milliseconds 1;'
        . '[Console]::Beep(3500,700);'
        . 'Start-Sleep -Milliseconds 1;'
        . '[Console]::Beep(3500,700);'
        . 'Start-Sleep -Milliseconds 1;'
        . '[Console]::Beep(3500,700);'
        . 'Start-Sleep -Milliseconds 1;'
        . '[Console]::Beep(3500,700);'
        . 'Start-Sleep -Milliseconds 1;'
        . '[Console]::Beep(3500,700);'
        . 'Start-Sleep -Milliseconds 1;'
        . '[Console]::Beep(3500,700);'
        . 'Start-Sleep -Milliseconds 1;'
        . '[Console]::Beep(3500,700);'
        . 'Start-Sleep -Milliseconds 1;'
        . '[Console]::Beep(3500,700);'
        . 'Start-Sleep -Milliseconds 1;'
        . '[Console]::Beep(3500,700);'
        . 'Start-Sleep -Milliseconds 1;'
        . '[Console]::Beep(3500,700);'
        . 'Start-Sleep -Milliseconds 1;'
        . '[Console]::Beep(3500,700);';

    my $cmd =
        'start "" powershell.exe '
      . '-NoProfile '
      . '-WindowStyle Hidden '
      . '-Command "'
      . $ps
      . '"';

    system(
        'cmd.exe',
        '/c',
        $cmd
    );
}

print "Chamando alarme...\n";

captcha_alarm();

print "O Perl continuou normalmente.\n";
print "O som deve continuar em paralelo.\n";

sleep 2;

print "OpenKore continuaria executando normalmente aqui.\n";
print "Pressione ENTER para fechar...\n";

<STDIN>;