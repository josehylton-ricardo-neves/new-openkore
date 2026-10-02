# Online Guard / Online Watcher

Este pacote implementa o modo guard que consulta a lista de jogadores online do site do oRO por HTTP e publica um JSON compartilhado para OpenKore Docker e OpenKore nativo no Windows.

## Fluxo

1. `vpn-watcher` sobe uma VPN exclusiva do watcher.
2. `online-watcher` consulta:
   `https://o-ro.org/rankings?online=1&tier=all&class=all&guild=all&sort=level`
3. `online-watcher.pl` extrai os nomes de `rk-name-text`.
4. O estado e gravado atomicamente em:
   `runtime/online-watch/online_players.json`
5. Cada OpenKore com `onlineGuard.pl` compara a lista com `onlineGuard_blacklist`.
6. Se houver nome bloqueado, o plugin mantem o Kore desconectado.
7. Depois que os nomes somem, o plugin espera `onlineGuard_clearDelay` continuamente antes de liberar reconexao.

## activation

Edite `watcher/online-watcher.conf`:

```text
# 0 = so os bots
# 1 = always
# 2 = manual
activation=1
```

- `0`: o `okmode` inicia o watcher quando algum bot Docker vai iniciar e para quando o ultimo bot Docker parar.
- `1`: o `okmode` garante que o watcher continue ativo independentemente de haver bot Docker. Este e o modo indicado quando voce tambem usa OpenKore nativo no Windows.
- `2`: `okmode` nao inicia nem para o watcher automaticamente. Use `okwatcher start/stop`.

## Estrutura esperada

```text
openkore-bot\
  onlineGuard.pl
  watcherctl.ps1
  okwatcher.cmd
  compose-online-watcher-snippet.yaml
  watcher\
    online-watcher.pl
    online-watcher.conf
  runtime\
    online-watch\
      online_players.json       (criado automaticamente)
  vpn\
    vpn-watcher\
      protonvpn-watcher.conf    (seu arquivo WireGuard)
```

## Configuracao do watcher

Arquivo `watcher/online-watcher.conf`:

- `activation`: 0, 1 ou 2.
- `interval`: intervalo entre consultas HTTP; minimo efetivo 10 segundos.
- `timeout`: timeout HTTP; minimo efetivo 2 segundos.
- `url`: pagina consultada.
- `output`: caminho do JSON dentro do container.
- `host_output`: caminho equivalente no Windows, usado por `watcherctl.ps1`.
- `etag`: 1 usa `ETag`/`Last-Modified`; 0 desativa condicionais HTTP.
- `user_agent`: User-Agent HTTP.
- `verbose`: 1 mostra logs; 0 reduz logs.

O script agora le de fato `ONLINE_WATCH_CONFIG=/watcher/online-watcher.conf`. Variaveis de ambiente `ONLINE_WATCH_*`, se definidas, sobrescrevem o `.conf`.

## Compose

Mescle o conteudo de `compose-online-watcher-snippet.yaml` no seu `compose.yaml` atual. Nao substitua seu Compose inteiro.

O snippet cria:

- `vpn-watcher`
- `online-watcher`
- rede `vpn-watcher-net`
- bind do `onlineGuard.pl` e do diretorio compartilhado para cada bot

## VPN do watcher

Crie:

```text
vpn\vpn-watcher\protonvpn-watcher.conf
```

Use um `.conf` WireGuard valido do ProtonVPN. O pacote nao inclui sua chave privada.

## Config do onlineGuard no Docker

Copie o conteudo de `config-onlineGuard-docker.txt` para o `control/config.txt` de cada bot que deve usar o guard.

Principal ajuste por bot:

```text
onlineGuard_blacklist Fourmi, Fulano, Ciclano
```

## OpenKore nativo no Windows

Use `onlineGuard.pl` na pasta de plugins do OpenKore nativo e copie o conteudo de `config-onlineGuard-windows.txt` para o `config.txt`.

O caminho recuperado para seu projeto e:

```text
C:/Users/jrneves/Documents/openkore/openkore-bot/runtime/online-watch/online_players.json
```

Assim o OpenKore do Windows usa exatamente o mesmo JSON produzido pelo watcher Docker.

## Integracao com okmode

Nao substitua seu `okmode.ps1` atual. Aplique somente os trechos de `okmode-integration.ps1.txt`, preservando seus checks atuais de preflight, VPN, health e IP.

A integracao usa:

```powershell
& $WatcherCtl bot-start
& $WatcherCtl bot-stop
```

## Comandos do watcher

Na raiz `openkore-bot`:

```bat
okwatcher status
okwatcher start
okwatcher stop
okwatcher reconcile
```

`reconcile` aplica o valor atual de `activation` ao estado existente.

## Comandos no OpenKore

```text
oguard status
oguard check
```

`oguard status` mostra estado, motivo, arquivo, quantidade de jogadores, hits da blacklist, tempo restante de limpeza e se o guard e dono da desconexao.

## Parametros do onlineGuard

Os exemplos recuperados usam:

```text
onlineGuard_checkInterval 2
onlineGuard_staleAfter 70
onlineGuard_startupGrace 90
onlineGuard_clearDelay 1800
onlineGuard_failClosed 1
onlineGuard_disconnect 1
onlineGuard_autoReconnect 1
onlineGuard_caseSensitive 0
```

Com `failClosed 1`, JSON ausente/invalido/stale tambem bloqueia o Kore depois do `startupGrace`.
