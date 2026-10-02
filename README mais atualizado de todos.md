# OpenKore + Docker + VPN + Console/Wx/MapViewer + Online Guard

Documentação consolidada do projeto OpenKore com **cinco bots Docker (bot1 a bot5)**, VPN WireGuard/ProtonVPN por instância, modos `wx`, `console` e `map`, validações de segurança no `okmode`, preflight, persistência por bind mount e o sistema **Online Watcher / Online Guard**.

> Diretório raiz esperado:
>
> `C:\Users\jrneves\Documents\openkore\openkore-bot`

---

## Sumário

1. [Objetivo da arquitetura](#1-objetivo-da-arquitetura)
2. [Arquitetura geral](#2-arquitetura-geral)
3. [Estrutura de diretórios](#3-estrutura-de-diretórios)
4. [Bots e modos disponíveis](#4-bots-e-modos-disponíveis)
5. [Uma única imagem Docker](#5-uma-única-imagem-docker)
6. [VPN por bot](#6-vpn-por-bot)
7. [Comando principal: okmode](#7-comando-principal-okmode)
8. [Fluxo seguro de inicialização](#8-fluxo-seguro-de-inicialização)
9. [Preflight e proteções](#9-preflight-e-proteções)
10. [Terminal e docker attach](#10-terminal-e-docker-attach)
11. [Wx, noVNC, VNC e MapViewer](#11-wx-novnc-vnc-e-mapviewer)
12. [Bind mounts e persistência](#12-bind-mounts-e-persistência)
13. [XSTools Linux](#13-xstools-linux)
14. [Online Watcher / Online Guard](#14-online-watcher--online-guard)
15. [Estrutura do Online Guard](#15-estrutura-do-online-guard)
16. [VPN exclusiva do watcher](#16-vpn-exclusiva-do-watcher)
17. [Configuração online-watcher.conf](#17-configuração-online-watcherconf)
18. [activation 0, 1 e 2](#18-activation-0-1-e-2)
19. [Comandos do watcher](#19-comandos-do-watcher)
20. [JSON compartilhado](#20-json-compartilhado)
21. [Instalação do onlineGuard.pl nos bots Docker](#21-instalação-do-onlineguardpl-nos-bots-docker)
22. [OpenKore nativo no Windows](#22-openkore-nativo-no-windows)
23. [Configuração do onlineGuard no config.txt](#23-configuração-do-onlineguard-no-configtxt)
24. [Estados do Online Guard](#24-estados-do-online-guard)
25. [Falhas transitórias do JSON](#25-falhas-transitórias-do-json)
26. [Isolamento de IP do watcher](#26-isolamento-de-ip-do-watcher)
27. [Comandos do Online Guard dentro do OpenKore](#27-comandos-do-online-guard-dentro-do-openkore)
28. [Reload, restart, recreate ou build?](#28-reload-restart-recreate-ou-build)
29. [Alterações de VPN](#29-alterações-de-vpn)
30. [Logs e diagnóstico](#30-logs-e-diagnóstico)
31. [Validação do Compose](#31-validação-do-compose)
32. [Limpeza do Docker](#32-limpeza-do-docker)
33. [Troubleshooting](#33-troubleshooting)
34. [Adicionar novos bots](#34-adicionar-novos-bots)
35. [Checklist antes de commit](#35-checklist-antes-de-commit)
36. [Referência rápida de comandos](#36-referência-rápida-de-comandos)

---

# 1. Objetivo da arquitetura

O projeto foi organizado para:

- executar múltiplas instâncias independentes do OpenKore;
- usar uma VPN separada para cada bot;
- impedir que dois bots usem acidentalmente o mesmo IP público;
- oferecer três modos de execução por bot: `wx`, `console` e `map`;
- manter os arquivos reais do OpenKore editáveis no Windows;
- evitar rebuild da imagem Docker a cada alteração em `config.txt`, plugins ou tabelas;
- manter logs persistentes fora do filesystem interno do Docker;
- validar credenciais, VPN, health e IP antes de liberar o OpenKore;
- executar um watcher HTTP separado para consultar os jogadores online;
- usar uma VPN exclusiva para esse watcher;
- compartilhar um único JSON de jogadores online com todos os bots;
- permitir uma blacklist diferente em cada instância;
- suportar o mesmo Online Guard também no OpenKore executado diretamente no Windows.

---

# 2. Arquitetura geral

## Bots

Cada bot possui:

```text
OpenKore botN
     │
     │ network_mode: service:vpnN
     ▼
vpnN / Gluetun
     │
     ▼
ProtonVPN / WireGuard
     │
     ▼
Internet
```

Exemplo atual com cinco bots:

```text
bot1 ──> vpn1 ──> IP público A
bot2 ──> vpn2 ──> IP público B
bot3 ──> vpn3 ──> IP público C
bot4 ──> vpn4 ──> IP público D
bot5 ──> vpn5 ──> IP público E
```

Os cinco IPs públicos devem ser diferentes entre si.

## Online Watcher

O watcher é independente:

```text
online-watcher
      │
      │ network_mode: service:vpn-watcher
      ▼
vpn-watcher
      │
      ▼
IP público D
      │
      ▼
https://o-ro.org/rankings?online=1...
      │
      ▼
runtime\online-watch\online_players.json
      │
      ├── bot1 / onlineGuard.pl
      ├── bot2 / onlineGuard.pl
      ├── bot3 / onlineGuard.pl
      ├── bot4 / onlineGuard.pl
      ├── bot5 / onlineGuard.pl
      └── OpenKore nativo no Windows
```

O IP público do watcher também deve ser diferente dos IPs dos cinco bots.

---

# 3. Estrutura de diretórios

Estrutura recomendada/atual:

```text
C:\Users\jrneves\Documents\openkore\openkore-bot
│
├── Dockerfile
├── compose.yaml
├── okmode.bat
├── okmode.ps1
├── openkore-entrypoint.sh
├── openkore-mode.sh
├── openkore-preflight.sh
├── vpn-guard-entrypoint.sh
├── dockerMapState.pl
├── .env
├── .dockerignore
├── README.md
│
├── online-guard\
│   ├── watcherctl.ps1
│   ├── okwatcher.cmd
│   │
│   ├── watcher\
│   │   ├── online-watcher.pl
│   │   └── online-watcher.conf
│   │
│   └── docs\
│       └── ... documentação auxiliar ...
│
├── instances\
│   ├── openkore-bot1\
│   │   ├── openkore.pl
│   │   ├── control\
│   │   │   ├── config.txt
│   │   │   └── sys.txt
│   │   ├── plugins\
│   │   │   └── onlineGuard.pl
│   │   ├── tables\
│   │   ├── src\
│   │   └── ...
│   │
│   ├── openkore-bot2\
│   │   ├── control\
│   │   ├── plugins\
│   │   │   └── onlineGuard.pl
│   │   └── ...
│   │
│   ├── openkore-bot3\
│   │   ├── control\
│   │   ├── plugins\
│   │   │   └── onlineGuard.pl
│   │   └── ...
│   │
│   ├── openkore-bot4\
│   │   ├── control\
│   │   ├── plugins\
│   │   │   └── onlineGuard.pl
│   │   └── ...
│   │
│   └── openkore-bot5\
│       ├── control\
│       ├── plugins\
│       │   └── onlineGuard.pl
│       └── ...
│
├── vpn\
│   ├── vpn-bot1\
│   │   └── protonvpn-bot1.conf
│   ├── vpn-bot2\
│   │   └── protonvpn-bot2.conf
│   ├── vpn-bot3\
│   │   └── protonvpn-bot3.conf
│   ├── vpn-bot4\
│   │   └── protonvpn-bot4.conf
│   ├── vpn-bot5\
│   │   └── protonvpn-bot5.conf
│   └── vpn-watcher\
│       └── protonvpn-watcher.conf
│
├── runtime\
│   └── online-watch\
│       └── online_players.json
│
└── logs\
    ├── log-bot1\
    ├── log-bot2\
    ├── log-bot3\
    ├── log-bot4\
    └── log-bot5\
```

## Por que `runtime\online-watch` fica fora de `online-guard`

Porque esse diretório é **estado compartilhado em tempo de execução**.

O mesmo arquivo precisa ser acessível:

- pelo container `online-watcher`;
- pelos containers OpenKore;
- pelo OpenKore executado diretamente no Windows.

Por isso:

```text
runtime\online-watch\online_players.json
```

fica na raiz do projeto.

---

# 4. Bots e modos disponíveis

Cada bot pode executar **somente um modo por vez**.

## `wx`

Executa aproximadamente:

```text
perl openkore.pl --interface=Wx
```

Também utiliza:

```text
Xvfb
Fluxbox
x11vnc
websockify/noVNC
```

É o modo com interface gráfica completa.

Comando:

```bat
okmode 1 wx
okmode 2 wx
okmode 3 wx
okmode 4 wx
okmode 5 wx
```

## `console`

Executa:

```text
perl openkore.pl
```

Sem Wx, Xvfb, Fluxbox, x11vnc ou noVNC.

É o modo mais leve.

```bat
okmode 1 console
okmode 2 console
okmode 3 console
okmode 4 console
okmode 5 console
```

## `map`

Executa o OpenKore Console e, em paralelo, o MapViewer.

```bat
okmode 1 map
okmode 2 map
okmode 3 map
okmode 4 map
okmode 5 map
```

O mapa é visual. Os comandos continuam no terminal do OpenKore.

O plugin `dockerMapState.pl` gera o estado usado pelo `mapview.pl`.

## Não rode dois modos do mesmo bot

Não faça:

```text
bot1-gui + bot1-console
bot1-gui + bot1-map
bot1-console + bot1-map
```

Todos usariam a mesma árvore:

```text
instances\openkore-bot1
```

e poderiam executar dois `openkore.pl` simultaneamente com os mesmos arquivos.

O `okmode` para os outros modos do mesmo bot antes de iniciar o modo solicitado.

É permitido:

```text
bot1 = console
bot2 = wx
bot3 = map
bot4 = console
bot5 = wx
```

---

# 5. Uma única imagem Docker

Os modos utilizam a mesma imagem de runtime:

```text
openkore-runtime-gui:local
```

Não existe uma imagem separada para Console, Wx e MapViewer.

Consequências:

- trocar `wx` para `console` não exige build;
- trocar `console` para `map` não exige build;
- o modo Console continua usando uma imagem que contém bibliotecas gráficas, mas não inicia esses processos;
- plugins e configs continuam vindo do Windows por bind mount.

---

# 6. VPN por bot

Cada bot possui um serviço VPN próprio:

```text
bot1 -> vpn1
bot2 -> vpn2
bot3 -> vpn3
bot4 -> vpn4
bot5 -> vpn5
```

O OpenKore compartilha o namespace de rede da VPN:

```yaml
network_mode: "service:vpn1"
```

ou:

```yaml
network_mode: "service:vpn2"
```

etc.

Isso significa que o OpenKore não escolhe diretamente a interface VPN. Todo o networking daquele container é o networking do Gluetun correspondente.

## Arquivos WireGuard

Exemplo:

```text
vpn\vpn-bot1\protonvpn-bot1.conf
vpn\vpn-bot2\protonvpn-bot2.conf
vpn\vpn-bot3\protonvpn-bot3.conf
vpn\vpn-bot4\protonvpn-bot4.conf
vpn\vpn-bot5\protonvpn-bot5.conf
```

Formato típico:

```ini
[Interface]
PrivateKey = ...
Address = 10.2.0.2/32

[Peer]
PublicKey = ...
Endpoint = servidor:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

### IPv6

Neste setup do Gluetun custom/WireGuard, foi necessário manter o `Address` da interface em IPv4.

Se o arquivo possuir algo como:

```text
2a07:....
```

e o Gluetun informar que IPv6 não é suportado, remova a linha IPv6 desse arquivo usado pelo container.

Nunca publique o `PrivateKey`.

---

# 7. Comando principal: okmode

Use o `okmode` na raiz do projeto:

```bat
cd C:\Users\jrneves\Documents\openkore\openkore-bot
```

## Bot1

```bat
okmode 1 wx
okmode 1 console
okmode 1 map
okmode 1 stop
okmode 1 status
okmode 1 check
```

## Bot2

```bat
okmode 2 wx
okmode 2 console
okmode 2 map
okmode 2 stop
okmode 2 status
okmode 2 check
```

## Bot3

```bat
okmode 3 wx
okmode 3 console
okmode 3 map
okmode 3 stop
okmode 3 status
okmode 3 check
```

## Bot4

```bat
okmode 4 wx
okmode 4 console
okmode 4 map
okmode 4 stop
okmode 4 status
okmode 4 check
```

## Bot5

```bat
okmode 5 wx
okmode 5 console
okmode 5 map
okmode 5 stop
okmode 5 status
okmode 5 check
```

## Watcher

No `okmode.ps1` atual, os comandos do watcher não passam pelo parâmetro `Bot`.
Use o wrapper próprio:

```bat
online-guard\okwatcher status
online-guard\okwatcher start
online-guard\okwatcher stop
online-guard\okwatcher reconcile
```

O `okmode.ps1` continua integrado ao watcher automaticamente ao iniciar/parar bots por meio de:

```powershell
& $WatcherCtl bot-start
& $WatcherCtl bot-stop
```

Portanto, não é necessário iniciar o watcher manualmente no fluxo normal quando `activation=0` ou `activation=1`.

---

# 8. Fluxo seguro de inicialização

O fluxo recomendado de um bot é:

```text
okmode N <modo>
      │
      ▼
valida compose.yaml
      │
      ▼
executa preflight
      │
      ├── config existe?
      ├── username preenchido?
      ├── password preenchido?
      ├── VPN existe?
      ├── VPN é diferente dos outros bots?
      └── credenciais são diferentes?
      │
      ▼
para outros modos do mesmo bot
      │
      ▼
reinicia/inicia vpnN
      │
      ▼
aguarda vpnN ficar healthy
      │
      ▼
obtém IP público da VPN
      │
      ▼
compara com VPNs dos outros bots
      │
      ▼
watcherctl bot-start
      │
      ├── inicia vpn-watcher quando aplicável
      ├── inicia online-watcher quando aplicável
      ├── obtém IP público do watcher
      └── compara watcher x vpn-botN
      │
      ▼
somente se tudo estiver OK:
      │
      ▼
inicia OpenKore
```

O watcher deve ser validado **antes** do OpenKore entrar no servidor quando o Online Guard está sendo usado como proteção.

---

# 9. Preflight e proteções

O projeto possui validações para reduzir erros de configuração.

## Checks estáticos

```bat
okmode 1 check
okmode 2 check
okmode 3 check
okmode 4 check
okmode 5 check
```

Esse modo não deve iniciar o OpenKore.

Ele serve para validar:

- `compose.yaml`;
- existência do `config.txt`;
- credenciais;
- arquivos de VPN;
- diferenças entre configurações dos bots.

## Regras importantes

O preflight deve impedir situações como:

```text
username vazio
password vazio
mesmo username em dois bots
mesma password em dois bots
mesma configuração WireGuard
mesma PrivateKey
arquivo VPN ausente
```

As credenciais não devem ser impressas nos logs.

## Comparação de IP público

Mesmo duas configurações WireGuard diferentes podem acabar no mesmo IP público.

Por isso o `okmode` faz uma checagem real.

Exemplo manual:

```bat
docker exec vpn-bot1 wget -qO- https://api.ipify.org
docker exec vpn-bot2 wget -qO- https://api.ipify.org
docker exec vpn-bot3 wget -qO- https://api.ipify.org
docker exec vpn-bot4 wget -qO- https://api.ipify.org
docker exec vpn-bot5 wget -qO- https://api.ipify.org
```

O esperado:

```text
vpn-bot1 -> IP A
vpn-bot2 -> IP B
vpn-bot3 -> IP C
vpn-bot4 -> IP D
vpn-bot5 -> IP E
```

A, B, C, D e E devem ser diferentes.

---

# 10. Terminal e docker attach

Nos modos `console` e `map`, o `okmode` pode anexar o CMD ao mesmo processo OpenKore.

Exemplo:

```bat
docker attach --sig-proxy=false openkore-bot1-console
```

Ou:

```bat
docker attach --sig-proxy=false openkore-bot1-map
```

## Sair do attach sem matar o OpenKore

Use:

```text
Ctrl+P
Ctrl+Q
```

Não use `Ctrl+C` se não quiser encerrar o processo.

## Comandos comuns do OpenKore

Exemplos:

```text
st
i
eq
skills
s
pl
where
conf attackAuto
conf attackAuto 0
reload config
reload all
plugin
plugin load nome.pl
plugin reload nome
```

---

# 11. Wx, noVNC, VNC e MapViewer

## Bot1

Configurações historicamente usadas:

```text
noVNC: 6080
VNC Windows: 6081
VNC interno: 5900
```

noVNC:

```text
http://localhost:6080/vnc.html?autoconnect=1&resize=scale
```

VNC:

```text
127.0.0.1:6081
```

## Bot2

Configurações historicamente usadas:

```text
noVNC: 6082
VNC Windows: 6083
VNC interno: 5902
```

noVNC:

```text
http://localhost:6082/vnc.html?autoconnect=1&resize=scale
```

VNC:

```text
127.0.0.1:6083
```

## Bot3

```text
noVNC: 6084
VNC Windows: 6085
VNC interno: 5904
Display: 101
```

## Bot4

```text
noVNC: 6086
VNC Windows: 6087
VNC interno: 5906
Display: 102
```

noVNC:

```text
http://localhost:6086/vnc.html?autoconnect=1&resize=scale
```

VNC:

```text
127.0.0.1:6087
```

## Bot5

```text
noVNC: 6088
VNC Windows: 6089
VNC interno: 5908
Display: 103
```

noVNC:

```text
http://localhost:6088/vnc.html?autoconnect=1&resize=scale
```

VNC:

```text
127.0.0.1:6089
```

As portas efetivas sempre podem ser confirmadas com:

```bat
docker compose config
```

## Modo Console

No modo `console`, o stack gráfico não é iniciado.

## Modo Map

O modo `map` usa a pilha gráfica somente para exibir o mapa.

O script `openkore-mode.sh` deve preservar/restaurar `control/sys.txt` quando fizer ajustes temporários para o `dockerMapState`.

Isso evita o problema antigo em que o modo `map` podia sobrescrever o `sys.txt` e remover plugins.

---

# 12. Bind mounts e persistência

A árvore inteira de cada OpenKore é montada do Windows:

```text
Windows:
instances\openkore-bot1

Container:
/opt/openkore
```

Isso significa:

```text
editar no Windows -> container vê a alteração
OpenKore grava -> arquivo do Windows é alterado
```

Exemplo:

```text
conf attackAuto 0
```

pode persistir diretamente em:

```text
instances\openkore-bot1\control\config.txt
```

## Logs

Os logs são persistidos fora do container.

Exemplo:

```text
logs\log-bot1
logs\log-bot2
logs\log-bot3
logs\log-bot4
logs\log-bot5
```

## Estado do Online Watcher

Também é um bind mount:

```text
Windows:
runtime\online-watch

Container:
/shared/online-watch
```

---

# 13. XSTools Linux

O OpenKore fica em bind mount do Windows, mas o container é Linux.

Por isso o `XSTools.so` precisa ser Linux.

O projeto utiliza um filesystem/volume Linux em:

```text
/opt/openkore/src/auto/XSTools
```

para evitar carregar uma biblioteca Linux diretamente do NTFS/Windows.

## Build necessário quando

- código C/C++/XS do XSTools mudou;
- ABI relevante do Perl mudou;
- dependências Linux mudaram;
- Dockerfile mudou de forma que afete o runtime.

## Build não é necessário quando

- `config.txt` mudou;
- `sys.txt` mudou;
- plugin `.pl` mudou;
- `.pm` foi alterado, embora normalmente exija restart do processo;
- tables foram alteradas;
- `compose.yaml` mudou;
- scripts bind-mounted foram alterados.

---

# 14. Online Watcher / Online Guard

O sistema possui **duas partes distintas**.

## Parte 1: Online Watcher

Processo central:

```text
online-watcher.pl
```

Responsabilidades:

1. usar uma VPN exclusiva;
2. fazer a requisição HTTP ao site;
3. extrair nomes de jogadores online;
4. escrever um JSON compartilhado.

## Parte 2: onlineGuard.pl

Plugin dentro de cada OpenKore.

Responsabilidades:

1. ler o JSON;
2. comparar os nomes com a blacklist daquela instância;
3. decidir se o OpenKore pode permanecer conectado;
4. desconectar quando necessário;
5. aguardar o período de segurança;
6. liberar a reconexão quando aplicável.

Ou seja:

```text
online-watcher.pl
        =
produtor do JSON

onlineGuard.pl
        =
consumidor do JSON dentro de cada OpenKore
```

---

# 15. Estrutura do Online Guard

```text
openkore-bot\
│
├── online-guard\
│   ├── watcherctl.ps1
│   ├── okwatcher.cmd
│   └── watcher\
│       ├── online-watcher.pl
│       └── online-watcher.conf
│
├── runtime\
│   └── online-watch\
│       └── online_players.json
│
├── vpn\
│   └── vpn-watcher\
│       └── protonvpn-watcher.conf
│
└── instances\
    ├── openkore-bot1\
    │   └── plugins\
    │       └── onlineGuard.pl
    ├── openkore-bot2\
    │   └── plugins\
    │       └── onlineGuard.pl
    ├── openkore-bot3\
    │   └── plugins\
    │       └── onlineGuard.pl
    ├── openkore-bot4\
    │   └── plugins\
    │       └── onlineGuard.pl
    └── openkore-bot5\
        └── plugins\
            └── onlineGuard.pl
```

## Plugin separado por bot

A decisão atual é **não** usar um único `onlineGuard.pl` central montado sobre todos os bots.

Cada instância possui sua própria cópia:

```text
instances\openkore-bot1\plugins\onlineGuard.pl
instances\openkore-bot2\plugins\onlineGuard.pl
instances\openkore-bot3\plugins\onlineGuard.pl
instances\openkore-bot4\plugins\onlineGuard.pl
instances\openkore-bot5\plugins\onlineGuard.pl
```

Isso permite modificar/testar um bot sem alterar automaticamente os outros.

O `compose.yaml` precisa compartilhar apenas:

```text
runtime\online-watch
```

com os bots.

---

# 16. VPN exclusiva do watcher

Arquivo:

```text
vpn\vpn-watcher\protonvpn-watcher.conf
```

O serviço:

```text
vpn-watcher
```

usa Gluetun.

O serviço:

```text
online-watcher
```

usa:

```yaml
network_mode: "service:vpn-watcher"
```

Portanto:

```text
online-watcher -> vpn-watcher -> Internet
```

A requisição ao ranking não sai pelo IP do Windows nem pela VPN de um bot.

## Ver IP público do watcher

```bat
docker exec vpn-online-watcher wget -qO- https://api.ipify.org
```

---

# 17. Configuração online-watcher.conf

Arquivo:

```text
online-guard\watcher\online-watcher.conf
```

Exemplo recomendado para aproximadamente 1 minuto de tolerância no plugin:

```ini
# ============================================================
# ONLINE WATCHER
# ============================================================

# 0 = com os bots Docker
# 1 = always
# 2 = manual
activation=0

# Consulta o site a cada 20 segundos.
interval=20

# Timeout HTTP por tentativa.
timeout=5

url=https://o-ro.org/rankings?online=1&tier=all&class=all&guild=all&sort=level

# Caminho visto pelo container.
output=/shared/online-watch/online_players.json

# Caminho equivalente visto pelo Windows/watcherctl.
host_output=./runtime/online-watch/online_players.json

# Usa ETag/Last-Modified quando o servidor suportar.
etag=1

# User-Agent semelhante ao Chrome no Windows.
user_agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36

# 1 = logs detalhados; 0 = menos logs.
verbose=1
```

## `interval`

```ini
interval=20
```

Faz uma nova verificação HTTP aproximadamente em:

```text
0s
20s
40s
60s
80s
...
```

Esse valor não é o mesmo que `onlineGuard_checkInterval`.

## `timeout`

```ini
timeout=5
```

Tempo máximo esperado para cada requisição HTTP antes de considerá-la falha.

## `url`

Página usada para extrair os nomes online.

## `output`

Caminho dentro do container do watcher.

## `host_output`

Caminho equivalente no Windows.

O status pode exibir algo como:

```text
C:\...\openkore-bot\.\runtime\online-watch\online_players.json
```

O `\.\` é válido e significa o diretório atual.

Se quiser somente normalizar visualmente no PowerShell:

```powershell
$jsonPath = [System.IO.Path]::GetFullPath(
    (Join-Path $ProjectRoot $hostOutput)
)
```

## `etag`

Com:

```ini
etag=1
```

o watcher pode utilizar:

```text
ETag
If-None-Match
Last-Modified
If-Modified-Since
```

Uma resposta HTTP `304 Not Modified` pode continuar contando como consulta válida.

## `user_agent`

Use um User-Agent de navegador se desejado.

Exemplo:

```ini
user_agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36
```

## `verbose`

```ini
verbose=1
```

Mostra logs do watcher.

```ini
verbose=0
```

reduz as mensagens.

---

# 18. activation 0, 1 e 2

`activation` pertence ao **watcher**, não ao plugin `onlineGuard`.

## `activation=0`

```ini
activation=0
```

Significa:

```text
primeiro bot Docker inicia
        ↓
watcher inicia

outro bot inicia
        ↓
reutiliza o mesmo watcher

um bot para mas outro continua
        ↓
watcher continua

último bot Docker para
        ↓
watcher para
vpn-watcher para
```

Este é o modo ideal quando o watcher deve existir somente enquanto houver bot Docker.

### Atenção ao OpenKore nativo no Windows

`activation=0` atualmente observa **bots Docker**.

Se nenhum bot Docker estiver rodando e você abrir somente um OpenKore nativo do Windows:

```text
watcher pode ficar desligado
        ↓
JSON deixa de ser atualizado
```

Nesse caso existem três opções:

1. usar `activation=1`;
2. usar `activation=2` e iniciar/parar manualmente;
3. manter pelo menos um bot Docker ativo.

## `activation=1`

```ini
activation=1
```

`always`.

O watcher deve permanecer ligado mesmo sem bot Docker.

É o modo mais simples quando o OpenKore nativo do Windows precisa ser protegido a qualquer momento.

## `activation=2`

```ini
activation=2
```

Modo manual.

O `okmode` não decide automaticamente o estado do watcher.

Use:

```bat
online-guard\okwatcher start
online-guard\okwatcher stop
```

---

# 19. Comandos do watcher

## Status

```bat
online-guard\okwatcher status
```

ou:

```bat
online-guard\okwatcher
```

Exemplo de saída:

```text
activation=0 (so os bots)
vpn-watcher:    running
online-watcher: running
arquivo:        C:\...\runtime\online-watch\online_players.json
status:         ok
players:        38
updated_age:    12s
success_age:    12s

=== IP ISOLATION ===
watcher:  <IP-WATCHER>
vpn-bot1: <IP-BOT1>
vpn-bot2: <IP-BOT2>
vpn-bot3: <IP-BOT3>
vpn-bot4: <IP-BOT4>
vpn-bot5: <IP-BOT5>
IP isolation: OK
```

## Iniciar manualmente

```bat
online-guard\okwatcher start
```

## Parar manualmente

```bat
online-guard\okwatcher stop
```

## Reconciliar

```bat
online-guard\okwatcher reconcile
```

`reconcile` aplica o valor atual de `activation`.

### Com activation=0

```text
há bot Docker rodando -> watcher ON
nenhum bot Docker      -> watcher OFF
```

### Com activation=1

```text
watcher ON
```

### Com activation=2

Não altera nada.

## Arquivo auxiliar

Também existe:

```text
online-guard\okwatcher.cmd
```

que pode ser usado diretamente:

```bat
online-guard\okwatcher status
online-guard\okwatcher start
online-guard\okwatcher stop
online-guard\okwatcher reconcile
```

O fluxo preferido, porém, é:

```bat
online-guard\okwatcher ...
```

---

# 20. JSON compartilhado

Arquivo físico no Windows:

```text
C:\Users\jrneves\Documents\openkore\openkore-bot\runtime\online-watch\online_players.json
```

Caminho visto pelos containers OpenKore:

```text
/shared/online-watch/online_players.json
```

Caminho no OpenKore nativo:

```text
C:/Users/jrneves/Documents/openkore/openkore-bot/runtime/online-watch/online_players.json
```

## Exemplo

```json
{
  "version": 1,
  "updated": 1787160000,
  "last_success": 1787160000,
  "status": "ok",
  "http_status": 200,
  "count": 38,
  "online": [
    "Player1",
    "Player2",
    "Doudette"
  ]
}
```

## Campos

### `updated`

Quando o estado foi escrito.

### `last_success`

Quando ocorreu a última consulta HTTP considerada válida.

### `status`

Normalmente:

```text
ok
```

ou:

```text
error
```

### `count`

Quantidade de jogadores extraídos.

### `online`

Lista de nomes.

## Escrita segura

O watcher escreve primeiro em um arquivo temporário:

```text
online_players.json.tmp.<pid>
```

e depois substitui o JSON final.

Isso reduz a chance de um leitor encontrar um JSON parcialmente escrito.

---

# 21. Instalação do onlineGuard.pl nos bots Docker

Cada bot possui seu arquivo:

```text
instances\openkore-bot1\plugins\onlineGuard.pl
instances\openkore-bot2\plugins\onlineGuard.pl
instances\openkore-bot3\plugins\onlineGuard.pl
instances\openkore-bot4\plugins\onlineGuard.pl
instances\openkore-bot5\plugins\onlineGuard.pl
```

Não é necessário montar um `onlineGuard.pl` central pelo Compose se a árvore inteira:

```text
instances\openkore-botN
```

já é montada em:

```text
/opt/openkore
```

## `sys.txt`

Se:

```text
loadPlugins 2
```

adicione `onlineGuard` em:

```text
loadPlugins_list
```

Exemplo:

```text
loadPlugins 2
loadPlugins_list macro,profiles,onlineGuard
```

Use o nome:

```text
onlineGuard
```

e não:

```text
onlineGuard.pl
```

## Verificar se carregou

Dentro do OpenKore:

```text
plugin
```

Deve aparecer:

```text
onlineGuard
```

Se:

```text
oguard status
```

for reconhecido, o plugin foi carregado.

---

# 22. OpenKore nativo no Windows

O mesmo plugin pode ser usado fora do Docker.

Coloque:

```text
<PASTA_DO_OPENKORE_WINDOWS>\plugins\onlineGuard.pl
```

Adicione no `sys.txt` conforme a política de plugins.

## Caminho correto do JSON

No Windows nativo:

```ini
onlineGuard_file C:/Users/jrneves/Documents/openkore/openkore-bot/runtime/online-watch/online_players.json
```

Não use:

```ini
onlineGuard_file /shared/online-watch/online_players.json
```

Esse caminho só existe dentro dos containers.

## Testar

No Windows CMD:

```bat
findstr /I /C:"Doudette" C:\Users\jrneves\Documents\openkore\openkore-bot\runtime\online-watch\online_players.json
```

No OpenKore:

```text
conf onlineGuard
conf onlineGuard_file
conf onlineGuard_blacklist
oguard check
```

---

# 23. Configuração do onlineGuard no config.txt

Exemplo Docker:

```ini
#################################################################################
# ONLINE GUARD
#################################################################################

# 1 = ligado
# 0 = desligado
onlineGuard 1

# Docker:
onlineGuard_file /shared/online-watch/online_players.json

# Nomes separados por virgula
onlineGuard_blacklist Doudette,Lyrics,MIlIlIlM

# Plugin olha o estado do arquivo a cada 2 segundos.
onlineGuard_checkInterval 2

# Aproximadamente 1 minuto sem estado confiavel.
onlineGuard_staleAfter 60

# Tolerancia inicial para o primeiro JSON valido.
onlineGuard_startupGrace 90

# Tempo de seguranca depois que a blacklist desaparece.
# Exemplo atual: 600s = 10 minutos.
onlineGuard_clearDelay 600

# Falha no watcher deve bloquear depois da tolerancia.
onlineGuard_failClosed 1

# Desconecta de fato.
onlineGuard_disconnect 1

# Libera reconexao automaticamente quando o bloqueio termina.
onlineGuard_autoReconnect 1

# 0 = ignora maiusculas/minusculas.
onlineGuard_caseSensitive 0
```

## `onlineGuard`

```ini
onlineGuard 1
```

Liga o plugin.

```ini
onlineGuard 0
```

desliga a lógica.

Não existe `onlineGuard 2 = manual`.

O `0/1/2` pertence a `activation` do watcher.

## `onlineGuard_file`

Docker:

```ini
onlineGuard_file /shared/online-watch/online_players.json
```

Windows:

```ini
onlineGuard_file C:/Users/jrneves/Documents/openkore/openkore-bot/runtime/online-watch/online_players.json
```

## `onlineGuard_blacklist`

```ini
onlineGuard_blacklist Doudette,Lyrics,MIlIlIlM
```

Cada bot pode ter uma lista diferente.

## `onlineGuard_checkInterval`

```ini
onlineGuard_checkInterval 2
```

O plugin verifica o arquivo aproximadamente a cada 2 segundos.

Isso **não** significa uma requisição HTTP a cada 2 segundos.

A requisição HTTP pertence ao watcher e usa:

```ini
interval=20
```

## `onlineGuard_staleAfter`

```ini
onlineGuard_staleAfter 60
```

Se a última informação confiável ultrapassar aproximadamente 60 segundos, o watcher passa a ser considerado inseguro.

Com:

```text
watcher interval = 20s
staleAfter        = 60s
```

temos aproximadamente:

```text
0s  sucesso
20s tentativa
40s tentativa
60s limite de segurança
```

## `onlineGuard_startupGrace`

```ini
onlineGuard_startupGrace 90
```

Ao iniciar o plugin, permite até 90 segundos para o primeiro JSON válido aparecer antes de aplicar fail-closed.

## `onlineGuard_clearDelay`

```ini
onlineGuard_clearDelay 600
```

600 segundos:

```text
10 minutos
```

Exemplo:

```text
Doudette online
     ↓
BLOCKED_PLAYER
     ↓
OpenKore desconecta
     ↓
Doudette sai
     ↓
CLEARING
     ↓
10 minutos continuamente seguro
     ↓
SAFE
```

Se a pessoa reaparecer durante o período, o contador é reiniciado.

## `onlineGuard_failClosed`

```ini
onlineGuard_failClosed 1
```

Significa:

```text
não consigo confiar no watcher
        =
não considero seguro ficar conectado
```

Após as tolerâncias configuradas, entra em:

```text
BLOCKED_WATCHER
```

## `onlineGuard_disconnect`

```ini
onlineGuard_disconnect 1
```

Executa a desconexão quando houver bloqueio.

Para teste sem derrubar a conexão:

```ini
onlineGuard_disconnect 0
```

## `onlineGuard_autoReconnect`

```ini
onlineGuard_autoReconnect 1
```

Permite que o plugin libere automaticamente uma desconexão causada por ele próprio.

## `onlineGuard_caseSensitive`

```ini
onlineGuard_caseSensitive 0
```

Considera equivalentes:

```text
Doudette
doudette
DOUDETTE
```

Com `1`, a caixa precisa coincidir.

---

# 24. Estados do Online Guard

## `STARTUP`

Plugin acabou de iniciar e ainda aguarda uma leitura confiável.

```text
state=STARTUP
reason=aguardando primeira leitura
```

## `SAFE`

Watcher saudável e nenhum nome da blacklist online.

## `BLOCKED_PLAYER`

Um ou mais nomes da blacklist foram encontrados.

Exemplo:

```text
[onlineGuard] BLOCKED_PLAYER: online: Doudette
```

## `BLOCKED_WATCHER`

O estado do watcher deixou de ser confiável além das tolerâncias.

Exemplos:

```text
JSON ausente por tempo excessivo
JSON inválido por tempo excessivo
updated muito antigo
last_success muito antigo
watcher parou
```

## `CLEARING`

O bloqueio deixou de existir, mas ainda está dentro de:

```ini
onlineGuard_clearDelay
```

## `DEGRADED`

Pode ser usado quando:

```ini
onlineGuard_failClosed 0
```

e o watcher tem problema, mas o plugin está configurado para não bloquear.

---

# 25. Falhas transitórias do JSON

Pode aparecer:

```text
[onlineGuard] Falha transitoria lendo JSON:
nao foi possivel abrir /shared/online-watch/online_players.json:
No such file or directory;
usando ultimo estado valido.
```

Isso não significa necessariamente que o watcher morreu.

## Por que pode acontecer

O cenário envolve:

```text
container Linux
     ↕
Docker Desktop
     ↕
bind mount
     ↕
filesystem Windows
```

O watcher substitui periodicamente o arquivo.

Um OpenKore pode tentar acessar o JSON exatamente durante uma pequena janela de atualização/propagação.

## Não é conflito entre vários leitores

Vários OpenKores podem ler o mesmo arquivo simultaneamente.

O ponto crítico é a atualização/substituição feita pelo escritor.

## Comportamento corrigido

O plugin não deve desconectar imediatamente por **uma única falha transitória** se já possui um estado válido recente.

Fluxo:

```text
open/stat falhou
       ↓
existe JSON válido em cache?
       ↓
SIM
       ↓
a informação ainda tem menos que staleAfter?
       ↓
SIM
       ↓
usa último estado válido
       ↓
continua verificando
```

Somente se a informação ultrapassar:

```ini
onlineGuard_staleAfter 60
```

é que uma falha real e persistente deve virar:

```text
BLOCKED_WATCHER
```

## Segurança da blacklist durante o cache

Se o último JSON confiável já continha:

```text
Doudette
```

a falha transitória não deve tornar o estado seguro.

O plugin continua usando o último estado confiável.

---

# 26. Isolamento de IP do watcher

Além de:

```text
bot1 != bot2 != bot3 != bot4 != bot5
```

o watcher também deve ser diferente:

```text
watcher != bot1
watcher != bot2
watcher != bot3
watcher != bot4
watcher != bot5
```

## Status automático

```bat
online-guard\okwatcher status
```

deve mostrar:

```text
=== IP ISOLATION ===
watcher: <IP>
vpn-bot1: <IP>
vpn-bot2: <IP>
vpn-bot3: <IP>
vpn-bot4: <IP>
vpn-bot5: <IP>
IP isolation: OK
```

## Ver manualmente

```bat
docker exec vpn-online-watcher wget -qO- https://api.ipify.org
docker exec vpn-bot1 wget -qO- https://api.ipify.org
docker exec vpn-bot2 wget -qO- https://api.ipify.org
docker exec vpn-bot3 wget -qO- https://api.ipify.org
docker exec vpn-bot4 wget -qO- https://api.ipify.org
docker exec vpn-bot5 wget -qO- https://api.ipify.org
```

## Se houver IP repetido

A inicialização do bot deve ser bloqueada.

Exemplo:

```text
watcher = 37.19.199.137
bot1    = 37.19.199.137
```

Resultado esperado:

```text
ERRO: IP PUBLICO REPETIDO
OpenKore NÃO deve ser iniciado
```

---

# 27. Comandos do Online Guard dentro do OpenKore

## Status

```text
oguard status
```

Mostra informações como:

```text
enabled
state
reason
file
watcher_status
watcher_count
blacklist_hits
clear_remaining
owns_disconnect
```

## Forçar uma verificação

```text
oguard check
```

Força o ciclo e depois exibe status.

## Conferir propriedades

```text
conf onlineGuard
conf onlineGuard_file
conf onlineGuard_blacklist
conf onlineGuard_checkInterval
conf onlineGuard_staleAfter
conf onlineGuard_startupGrace
conf onlineGuard_clearDelay
conf onlineGuard_failClosed
conf onlineGuard_disconnect
conf onlineGuard_autoReconnect
conf onlineGuard_caseSensitive
```

## Ligar/desligar temporariamente

```text
conf onlineGuard 0
```

e:

```text
conf onlineGuard 1
```

## Mensagem do OpenKore ao entrar em offline mode

Pode aparecer:

```text
Openkore will stay disconnected. Type "connect" in order to connect again.
```

Isso significa que o OpenKore entrou em modo que não tenta reconectar sozinho.

O comando:

```text
connect
```

manda o OpenKore tentar conectar manualmente.

### Com Online Guard ativo

Normalmente não é necessário usar `connect`.

O plugin deve liberar a conexão automaticamente depois de:

```text
blacklist ausente
+
watcher saudável
+
clearDelay concluído
```

quando:

```ini
onlineGuard_autoReconnect 1
```

O plugin foi ajustado para não chamar `offlineMode()` repetidamente a cada ciclo, evitando spam contínuo da mensagem.

---

# 28. Reload, restart, recreate ou build?

Esta é uma das partes mais importantes para manutenção.

| Alteração | Ação recomendada |
|---|---|
| `control/config.txt` | `reload config` |
| `sys.txt` | `reload all` ou restart, dependendo do que mudou |
| plugin `.pl` já carregado | `plugin reload nome` |
| plugin `.pl` novo | adicionar no `sys.txt` e restart/reload apropriado |
| tables | `reload all` ou reload específico |
| `.pm` em `src` | restart do container OpenKore |
| `openkore.pl` | restart do container |
| `onlineGuard.pl` | `plugin reload onlineGuard` ou restart |
| `online-watcher.conf` | restart do watcher |
| `online-watcher.pl` | restart do watcher |
| `watcherctl.ps1` | nenhuma build; próxima chamada já usa o arquivo novo |
| `okmode.ps1` | nenhuma build |
| `okmode.bat` | nenhuma build |
| `compose.yaml` | `docker compose config`; recreate quando a definição do container exigir |
| WireGuard conteúdo | restart/recreate da VPN |
| caminho/nome de mount | recreate do serviço |
| Dockerfile | build |
| dependência Linux | build |
| XSTools C/C++/XS | build |

## Reload de config

```text
reload config
```

## Reload geral

```text
reload all
```

## Reload de plugin

```text
plugin reload onlineGuard
```

## Reiniciar container específico

Exemplo:

```bat
docker compose restart bot1-console
```

ou:

```bat
docker compose restart bot1-gui
```

## Recreate

Quando a definição do container mudou:

```bat
docker compose --profile bot1-console up -d --force-recreate vpn1 bot1-console
```

## Build

Quando realmente necessário:

```bat
docker compose build
```

ou o serviço alvo conforme seu Compose.

---

# 29. Alterações de VPN

## Alterou somente o conteúdo do mesmo `.conf`

Exemplo:

```text
vpn\vpn-bot1\protonvpn-bot1.conf
```

Reinicie/recrie a VPN conforme o fluxo do `okmode`.

Uma forma direta:

```bat
docker compose restart vpn1
```

Mas, como o bot compartilha o namespace da VPN, o fluxo mais seguro é usar novamente:

```bat
okmode 1 <modo>
```

para refazer as validações.

## Alterou nome/caminho do arquivo

Se:

```text
protonvpn-bot1.conf
```

virou:

```text
novavpn.conf
```

altere o `source:` no Compose e recrie os serviços afetados.

## VPN do watcher

Arquivo:

```text
vpn\vpn-watcher\protonvpn-watcher.conf
```

Depois de trocar:

```bat
online-guard\okwatcher stop
online-guard\okwatcher start
online-guard\okwatcher status
```

---

# 30. Logs e diagnóstico

## Status geral

```bat
docker compose ps
```

ou:

```bat
docker compose ps -a
```

## Logs do bot

Exemplos:

```bat
docker compose logs -f bot1-gui
docker compose logs -f bot1-console
docker compose logs -f bot1-map
```

## Logs da VPN

```bat
docker compose logs -f vpn1
docker compose logs -f vpn2
docker compose logs -f vpn3
docker compose logs -f vpn4
docker compose logs -f vpn5
```

## Watcher

```bat
docker compose logs -f online-watcher
```

## VPN watcher

```bat
docker compose logs -f vpn-watcher
```

## Últimas 100 linhas

```bat
docker compose logs --tail 100 online-watcher
docker compose logs --tail 100 vpn-watcher
```

## Health

```bat
docker inspect --format="{{.State.Health.Status}}" vpn-bot1
docker inspect --format="{{.State.Health.Status}}" vpn-bot2
docker inspect --format="{{.State.Health.Status}}" vpn-bot3
docker inspect --format="{{.State.Health.Status}}" vpn-bot4
docker inspect --format="{{.State.Health.Status}}" vpn-bot5
docker inspect --format="{{.State.Health.Status}}" vpn-online-watcher
```

## JSON no Windows

```bat
type runtime\online-watch\online_players.json
```

ou:

```bat
findstr /I /C:"Doudette" runtime\online-watch\online_players.json
```

## JSON dentro de bot1-console

```bat
docker compose exec bot1-console sh -lc "ls -l /shared/online-watch && cat /shared/online-watch/online_players.json"
```

## Plugin dentro do container

```bat
docker compose exec bot1-console sh -lc "ls -l /opt/openkore/plugins/onlineGuard.pl"
```

---

# 31. Validação do Compose

Sempre que alterar `compose.yaml`:

```bat
docker compose config
```

Listar serviços:

```bat
docker compose config --services
```

Listar profiles:

```bat
docker compose config --profiles
```

Se houver erro de YAML, corrija antes de iniciar os containers.

## Validação completa sem iniciar os OpenKores

Depois de adicionar bot4 e bot5, execute na raiz do projeto:

### 1. Validar a sintaxe e a expansão do Compose

```bat
docker compose config -q
docker compose config --services
docker compose config --profiles
```

Em `--services` devem existir pelo menos:

```text
vpn4
bot4-gui
bot4-console
bot4-map
vpn5
bot5-gui
bot5-console
bot5-map
```

Em `--profiles` devem existir:

```text
bot4-wx
bot4-console
bot4-map
bot5-wx
bot5-console
bot5-map
```

### 2. Validar a sintaxe do `okmode.ps1`

Este teste usa apenas o parser do PowerShell e não executa o script:

```powershell
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path '.\okmode.ps1'),
    [ref]$tokens,
    [ref]$errors
) | Out-Null

if ($errors.Count) {
    $errors | Format-List
    exit 1
}

Write-Host "okmode.ps1: SINTAXE OK" -ForegroundColor Green
```

### 3. Validar a sintaxe do `watcherctl.ps1`

```powershell
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path '.\online-guard\watcherctl.ps1'),
    [ref]$tokens,
    [ref]$errors
) | Out-Null

if ($errors.Count) {
    $errors | Format-List
    exit 1
}

Write-Host "watcherctl.ps1: SINTAXE OK" -ForegroundColor Green
```

### 4. Confirmar que o watcher reconhece bot4 e bot5

No `watcherctl.ps1` atual não é necessária uma lista fixa como `$AllBots = 1..5`.

A detecção de OpenKores ativos é genérica:

```text
^bot\d+-(gui|console|map)$
```

E a detecção das VPNs ativas dos bots também é genérica:

```text
^vpn-bot\d+$
```

Portanto `bot4`, `bot5` e suas VPNs são reconhecidos automaticamente, sem editar o watcher ao adicionar esses dois bots.

### 5. Executar o preflight de bot4 e bot5 sem subir os bots

```bat
okmode 4 check
okmode 5 check
```

O modo `check`:

```text
valida compose.yaml
valida config.txt
valida username/password
valida arquivo WireGuard
valida PrivateKey/Address
compara bot4/bot5 com os demais bots
```

Ele **não inicia o OpenKore** e **não sobe a VPN para navegação**. O `docker compose run --rm --no-deps` cria somente um container temporário usado para executar o script de preflight e o remove ao terminar.

### 6. Validação opcional direta da sintaxe do shell

Usando a imagem local do projeto, sem iniciar bot ou VPN:

```bat
docker run --rm --entrypoint /bin/sh -v "%CD%:/project:ro" openkore-runtime-gui:local -n /project/openkore-preflight.sh
```

Se terminar sem mensagem de erro, a sintaxe do shell foi aceita.

### Checklist final da expansão bot4/bot5

```text
[ ] instances\openkore-bot4 existe
[ ] instances\openkore-bot5 existe
[ ] vpn\vpn-bot4\protonvpn-bot4.conf existe
[ ] vpn\vpn-bot5\protonvpn-bot5.conf existe
[ ] logs\log-bot4 existe
[ ] logs\log-bot5 existe

[ ] compose.yaml possui x-bot4-volumes e x-bot5-volumes
[ ] compose.yaml possui vpn4 e vpn5
[ ] compose.yaml possui os 3 modos do bot4
[ ] compose.yaml possui os 3 modos do bot5
[ ] compose.yaml possui vpn-bot4-net e vpn-bot5-net
[ ] compose.yaml possui xstools-bot4 e xstools-bot5

[ ] openkore-preflight.sh aceita 1|2|3|4|5
[ ] openkore-preflight.sh usa for OTHER in 1 2 3 4 5

[ ] okmode.ps1 aceita ValidateSet('1','2','3','4','5')
[ ] bot1 compara contra bot2,3,4,5
[ ] bot2 compara contra bot1,3,4,5
[ ] bot3 compara contra bot1,2,4,5
[ ] bot4 compara contra bot1,2,3,5
[ ] bot5 compara contra bot1,2,3,4
[ ] blocos bot4 e bot5 existem no switch

[ ] watcherctl.ps1 detecta bots com ^bot\d+-(gui|console|map)$ e VPNs com ^vpn-bot\d+$
[ ] bot4 possui onlineGuard.pl
[ ] bot5 possui onlineGuard.pl
[ ] sys.txt de bot4 carrega onlineGuard
[ ] sys.txt de bot5 carrega onlineGuard
[ ] bot4/bot5 recebem /shared/online-watch por bind mount

[ ] docker compose config -q passa
[ ] okmode 4 check passa
[ ] okmode 5 check passa
```

---

# 32. Limpeza do Docker

## Uso de disco

```bat
docker system df
```

Detalhado:

```bat
docker system df -v
```

## Cache de build

```bat
docker buildx du
```

Limpar:

```bat
docker buildx prune -a -f
```

## Cuidado

Evite usar indiscriminadamente:

```bat
docker system prune -a
```

em um ambiente que você quer preservar.

## VHDX do Docker Desktop

Depois de grandes limpezas, o espaço pode continuar reservado no VHDX.

Procedimento de compactação deve ser feito somente com entendimento do impacto e Docker parado.

Nunca apague manualmente o `docker_data.vhdx` se quiser preservar o ambiente Docker.

---

# 33. Troubleshooting

## 33.1 `onlineGuard enabled=0`

Se:

```text
oguard status
[onlineGuard] enabled=0
```

o plugin carregou, mas a propriedade não está ativa.

Confira:

```text
conf onlineGuard
```

Ative:

```text
conf onlineGuard 1
```

Depois:

```text
oguard check
```

Confira se o arquivo correto foi editado:

```bat
docker compose exec bot1-console sh -lc "grep -nE '^onlineGuard' /opt/openkore/control/config.txt"
```

---

## 33.2 `Unknown command 'oguard'`

O plugin não foi carregado.

Confira:

```text
plugin
```

Confira:

```text
instances\openkore-botN\plugins\onlineGuard.pl
```

e o `sys.txt`.

---

## 33.3 JSON não existe dentro do Docker

Erro:

```text
No such file or directory:
/shared/online-watch/online_players.json
```

Confirme o bind:

```yaml
- type: bind
  source: ./runtime/online-watch
  target: /shared/online-watch
  read_only: true
```

Confira:

```bat
docker compose exec bot1-console sh -lc "ls -la /shared/online-watch"
```

---

## 33.4 `Falha transitoria lendo JSON`

Mensagem:

```text
Falha transitoria lendo JSON...
usando ultimo estado valido.
```

Uma ocorrência isolada é tolerada pelo cache enquanto o estado anterior ainda estiver dentro de:

```ini
onlineGuard_staleAfter 60
```

Não é necessário matar a conexão imediatamente por uma falha de filesystem de um único ciclo.

---

## 33.5 `BLOCKED_WATCHER`

Confira:

```bat
online-guard\okwatcher status
```

Observe:

```text
status
updated_age
success_age
```

Com:

```ini
onlineGuard_staleAfter 60
```

idades acima desse limite indicam estado velho.

Também confira:

```bat
docker compose logs --tail 100 online-watcher
docker compose logs --tail 100 vpn-watcher
```

---

## 33.6 `BLOCKED_PLAYER`

Exemplo:

```text
[onlineGuard] BLOCKED_PLAYER: online: Doudette
```

Isso é comportamento esperado.

Confira:

```text
oguard status
```

e o JSON:

```bat
findstr /I /C:"Doudette" runtime\online-watch\online_players.json
```

---

## 33.7 OpenKore Windows não detecta

Confira:

```text
conf onlineGuard
conf onlineGuard_file
conf onlineGuard_blacklist
oguard check
```

Caminho correto:

```text
C:/Users/jrneves/Documents/openkore/openkore-bot/runtime/online-watch/online_players.json
```

Também confirme que o watcher está realmente ativo:

```bat
online-guard\okwatcher status
```

Se `activation=0` e não houver nenhum bot Docker, o watcher pode estar desligado.

---

## 33.8 Watcher procura VPN dentro de `online-guard\vpn`

Caminho errado:

```text
...\online-guard\vpn\vpn-watcher\...
```

Caminho correto:

```text
...\openkore-bot\vpn\vpn-watcher\protonvpn-watcher.conf
```

No `watcherctl.ps1`, use a separação:

```powershell
$OnlineGuardRoot = $PSScriptRoot
$ProjectRoot = Split-Path $OnlineGuardRoot -Parent
```

E:

```powershell
$vpnConf = Join-Path $ProjectRoot 'vpn\vpn-watcher\protonvpn-watcher.conf'
$watcherScript = Join-Path $OnlineGuardRoot 'watcher\online-watcher.pl'
```

---

## 33.9 Caminho aparece com `\.\`

Exemplo:

```text
C:\...\openkore-bot\.\runtime\online-watch\online_players.json
```

É válido.

Para normalizar visualmente:

```powershell
$jsonPath = [System.IO.Path]::GetFullPath(
    (Join-Path $ProjectRoot $hostOutput)
)
```

---

## 33.10 `docker inspect: No such object`

Ao executar status antes de o watcher existir, isso deve significar:

```text
absent
```

e não erro fatal.

O `Get-ContainerState` deve tratar container inexistente como estado normal de status.

---

## 33.11 `NativeCommandError` ao fazer `docker compose stop`

O Docker pode escrever mensagens normais em `stderr`:

```text
Container ... Stopping
Container ... Stopped
```

Com:

```powershell
$ErrorActionPreference = 'Stop'
```

PowerShell antigo pode transformar isso em `NativeCommandError`.

Uma solução usada no `watcherctl.ps1` é chamar comandos Docker problemáticos via:

```powershell
cmd.exe /d /s /c "docker compose stop online-watcher vpn-watcher"
```

e depois verificar:

```powershell
$LASTEXITCODE
```

O mesmo pode ser aplicado ao `up -d`.

---

## 33.12 IP isolation falhou

Confira manualmente:

```bat
docker exec vpn-online-watcher wget -qO- https://api.ipify.org
docker exec vpn-bot1 wget -qO- https://api.ipify.org
docker exec vpn-bot2 wget -qO- https://api.ipify.org
docker exec vpn-bot3 wget -qO- https://api.ipify.org
docker exec vpn-bot4 wget -qO- https://api.ipify.org
docker exec vpn-bot5 wget -qO- https://api.ipify.org
```

Se houver IP repetido, troque/reinicie a VPN correspondente.

---

## 33.13 VPN unhealthy

Exemplo:

```bat
docker inspect --format="{{.State.Health.Status}}" vpn-bot1
docker compose logs --tail 100 vpn1
```

Confira especialmente:

- arquivo WireGuard;
- `PrivateKey`;
- `Endpoint`;
- `Address`;
- `/dev/net/tun`;
- `NET_ADMIN`;
- conectividade do Docker.

---

## 33.14 `username do botN está vazio`

O preflight lê o `config.txt` real da instância.

Confira:

```text
instances\openkore-botN\control\config.txt
```

e a linha:

```text
username ...
```

Não basta alterar um arquivo diferente se o container está usando outro bind.

---

## 33.15 Alterei arquivo mas o modo map restaurou versão antiga

O modo `map` possui lógica temporária de `sys.txt`.

A implementação correta deve:

1. fazer backup;
2. alterar temporariamente somente o necessário;
3. preservar plugins existentes;
4. restaurar o arquivo original no cleanup.

Se plugins como `onlineGuard` desaparecerem do `sys.txt`, revise o `openkore-mode.sh`.

---

## 33.16 Spam de `Openkore will stay disconnected`

A função do plugin não deve chamar `offlineMode()` novamente em cada ciclo quando ele já está offline.

Uma ocorrência:

```text
Openkore will stay disconnected. Type "connect" in order to connect again.
```

é suficiente.

---

## 33.17 `Type "connect" in order to connect again`

É uma mensagem padrão do OpenKore.

O comando:

```text
connect
```

tenta conectar manualmente.

Com `onlineGuard_autoReconnect 1`, o fluxo normal é deixar o plugin liberar a conexão depois do `clearDelay`, sem usar `connect` manualmente.

---

# 34. Bot4, bot5 e futuros novos bots

A arquitetura atual suporta **bot1 até bot5**.

A expansão de bot4 e bot5 segue o padrão:

```text
instances\openkore-bot4
instances\openkore-bot5

vpn\vpn-bot4
vpn\vpn-bot5

logs\log-bot4
logs\log-bot5
```

E serviços:

```text
vpn4
bot4-gui
bot4-console
bot4-map

vpn5
bot5-gui
bot5-console
bot5-map
```

O padrão de nomes é importante porque scripts como o watcher detectam bots ativos usando algo equivalente a:

```text
^bot\d+-(gui|console|map)$
```

Também será necessário:

- adicionar VPN específica;
- adicionar rede;
- adicionar volumes/XSTools quando aplicável;
- configurar profiles;
- atualizar o preflight para aceitar `BOT_NUMBER` de 1 a 5 e comparar todos os bots;
- atualizar o `okmode.ps1` para aceitar bot4/bot5 e comparar cada VPN com as outras quatro;
- garantir que `online-guard\watcherctl.ps1` mantenha as detecções genéricas `^bot\\d+-(gui|console|map)$` e `^vpn-bot\\d+$`;
- garantir IP público diferente;
- escolher portas gráficas exclusivas;
- instalar `onlineGuard.pl` em bot4/bot5;
- adicionar `onlineGuard` no `sys.txt` de bot4/bot5;
- adicionar bind do `runtime\online-watch` em bot4/bot5.

Valide:

```bat
docker compose config
docker compose config --services
docker compose config --profiles
```

Depois:

```bat
okmode 4 check
okmode 5 check
```

O modo `check` não inicia o OpenKore nem estabelece a VPN. Ele cria somente um container temporário para executar o preflight e o remove ao terminar.

---

# 35. Checklist antes de commit

Não commite segredos.

Confira principalmente:

```text
.env
vpn\vpn-bot1\protonvpn-bot1.conf
vpn\vpn-bot2\protonvpn-bot2.conf
vpn\vpn-bot3\protonvpn-bot3.conf
vpn\vpn-bot4\protonvpn-bot4.conf
vpn\vpn-bot5\protonvpn-bot5.conf
vpn\vpn-watcher\protonvpn-watcher.conf
```

Esses arquivos podem conter:

```text
username
password
PrivateKey
```

## `.gitignore`

Garanta regras adequadas para segredos.

Exemplo conceitual:

```gitignore
.env
vpn/**/protonvpn-*.conf
runtime/online-watch/online_players.json
logs/
```

Não copie uma chave privada para o README.

---

# 36. Referência rápida de comandos

## Projeto

```bat
cd C:\Users\jrneves\Documents\openkore\openkore-bot
```

## Validar Compose

```bat
docker compose config
docker compose config --services
docker compose config --profiles
```

## Bot1

```bat
okmode 1 check
okmode 1 wx
okmode 1 console
okmode 1 map
okmode 1 status
okmode 1 stop
```

## Bot2

```bat
okmode 2 check
okmode 2 wx
okmode 2 console
okmode 2 map
okmode 2 status
okmode 2 stop
```

## Bot3

```bat
okmode 3 check
okmode 3 wx
okmode 3 console
okmode 3 map
okmode 3 status
okmode 3 stop
```

## Bot4

```bat
okmode 4 check
okmode 4 wx
okmode 4 console
okmode 4 map
okmode 4 status
okmode 4 stop
```

## Bot5

```bat
okmode 5 check
okmode 5 wx
okmode 5 console
okmode 5 map
okmode 5 status
okmode 5 stop
```

## Watcher

```bat
online-guard\okwatcher
online-guard\okwatcher status
online-guard\okwatcher start
online-guard\okwatcher stop
online-guard\okwatcher reconcile
```

## Status Docker

```bat
docker compose ps
docker compose ps -a
```

## IPs

```bat
docker exec vpn-bot1 wget -qO- https://api.ipify.org
docker exec vpn-bot2 wget -qO- https://api.ipify.org
docker exec vpn-bot3 wget -qO- https://api.ipify.org
docker exec vpn-bot4 wget -qO- https://api.ipify.org
docker exec vpn-bot5 wget -qO- https://api.ipify.org
docker exec vpn-online-watcher wget -qO- https://api.ipify.org
```

## Logs

```bat
docker compose logs -f vpn1
docker compose logs -f vpn2
docker compose logs -f vpn3
docker compose logs -f vpn4
docker compose logs -f vpn5
docker compose logs -f bot1-console
docker compose logs -f bot4-console
docker compose logs -f bot5-map
docker compose logs -f vpn-watcher
docker compose logs -f online-watcher
```

## OpenKore / Online Guard

```text
plugin
oguard status
oguard check

conf onlineGuard
conf onlineGuard_file
conf onlineGuard_blacklist

reload config
reload all

plugin reload onlineGuard
```

## Ver JSON

```bat
type runtime\online-watch\online_players.json
```

## Buscar jogador no JSON

```bat
findstr /I /C:"Doudette" runtime\online-watch\online_players.json
```

## Conferir JSON dentro do container

```bat
docker compose exec bot1-console sh -lc "cat /shared/online-watch/online_players.json"
```

## Conferir plugin dentro do container

```bat
docker compose exec bot1-console sh -lc "ls -l /opt/openkore/plugins/onlineGuard.pl"
```

## Attach manual

```bat
docker attach --sig-proxy=false openkore-bot1-console
docker attach --sig-proxy=false openkore-bot1-map
```

Desanexar:

```text
Ctrl+P
Ctrl+Q
```

## Uso de disco Docker

```bat
docker system df
docker system df -v
docker buildx du
```

## Limpar cache de build

```bat
docker buildx prune -a -f
```

---

# Fluxo diário recomendado

Para um bot em Console:

```bat
cd C:\Users\jrneves\Documents\openkore\openkore-bot
okmode 1 console
```

Para outro em Wx:

```bat
okmode 2 wx
```

Para outro em MapViewer:

```bat
okmode 3 map
```

Bot4 e bot5 seguem o mesmo padrão:

```bat
okmode 4 console
okmode 5 map
```

Conferir watcher:

```bat
online-guard\okwatcher status
```

Parar os bots desejados:

```bat
okmode 1 stop
okmode 2 stop
okmode 3 stop
okmode 4 stop
okmode 5 stop
```

Com:

```ini
activation=0
```

o watcher deve parar quando o último bot Docker for encerrado.

Se for usar **somente OpenKore nativo no Windows**, lembre-se de que `activation=0` não mantém o watcher ativo sozinho. Nesse caso use `activation=1` ou controle manual com `activation=2`.

---

# Regra prática para manutenção

Antes de pensar em build, pergunte:

```text
A alteração mudou o runtime Linux/Dockerfile/XSTools?
```

Se a resposta for **não**, normalmente você precisa apenas de:

```text
reload
restart
ou recreate
```

e não de build.

Isso mantém o projeto rápido de editar, evita rebuilds desnecessários e preserva a ideia central da arquitetura: **OpenKore vivo no Windows, runtime Linux reutilizável e VPN isolada por instância**.
