# OpenKore + Docker + VPN + Console / Wx / MapViewer

Projeto Docker para executar até duas instâncias independentes do OpenKore, cada uma com sua própria VPN, usando a mesma imagem Linux e três modos de execução por bot:

- `console` — OpenKore somente no terminal;
- `wx` — interface gráfica completa do OpenKore;
- `map` — OpenKore Console + MapViewer gráfico com clique para movimentar.

Diretório raiz esperado:

```text
C:\Users\jrneves\Documents\openkore\openkore-bot
```

> Cada bot deve executar apenas **um modo por vez**. BOT1 e BOT2 podem executar modos diferentes simultaneamente.

---

## 1. Arquitetura atual

Cada bot possui:

- árvore própria do OpenKore em `instances`;
- VPN própria via Gluetun + WireGuard/ProtonVPN;
- volume Linux próprio para XSTools;
- credenciais próprias;
- três serviços possíveis: Console, Wx e Map;
- logs dentro da própria árvore do OpenKore.

```text
BOT1
├── vpn1
└── um modo:
    ├── bot1-console
    ├── bot1-gui
    └── bot1-map

BOT2
├── vpn2
└── um modo:
    ├── bot2-console
    ├── bot2-gui
    └── bot2-map
```

Todos os modos do BOT1 usam:

```yaml
network_mode: "service:vpn1"
```

Todos os modos do BOT2 usam:

```yaml
network_mode: "service:vpn2"
```

Trocar Console/Wx/MapViewer não altera a rota de saída para a internet.

---

## 2. Estrutura do projeto

```text
openkore-bot
│
├── .env
├── .env.example
├── .gitignore
├── Dockerfile
├── compose.yaml
├── README.md
│
├── okmode.bat
├── okmode.ps1
├── openkore-entrypoint.sh
├── openkore-mode.sh
├── openkore-preflight.sh
├── vpn-guard-entrypoint.sh
├── dockerMapState.pl
│
├── tools
│   └── TightVNC
│       └── tvnviewer.exe
│
├── instances
│   ├── openkore-bot1
│   │   ├── control
│   │   ├── fields
│   │   ├── logs
│   │   ├── map
│   │   ├── plugins
│   │   ├── src
│   │   ├── tables
│   │   ├── mapview.pl
│   │   └── openkore.pl
│   │
│   └── openkore-bot2
│       └── ... árvore completa do OpenKore ...
│
└── vpn
    ├── vpn-bot1
    │   ├── protonvpn-bot1.conf
    │   └── protonvpn-bot1.conf.example
    └── vpn-bot2
        ├── protonvpn-bot2.conf
        └── protonvpn-bot2.conf.example
```

### Logs

Os logs ficam somente em:

```text
instances\openkore-bot1\logs
instances\openkore-bot2\logs
```

Não é mais necessário manter:

```text
logs\log-bot1
logs\log-bot2
```

O bind principal já monta `instances\openkore-botN` em `/opt/openkore`, incluindo `/opt/openkore/logs`.

---

## 3. Uma única imagem Docker

Os três modos usam:

```text
openkore-runtime-gui:local
```

Não existem imagens diferentes para Console, Wx e MapViewer.

O modo Console usa a mesma imagem, mas não inicia os componentes gráficos.

---

## 4. Modos disponíveis

### `console`

Executa:

```text
perl openkore.pl
```

Não inicia Xvfb, Fluxbox, x11vnc, noVNC, Wx ou MapViewer.

```bat
okmode 1 console
okmode 2 console
```

### `wx`

Executa:

```text
perl openkore.pl --interface=Wx
```

Também inicia:

```text
Xvfb
Fluxbox
x11vnc
websockify/noVNC
```

```bat
okmode 1 wx
okmode 2 wx
```

O `okmode` abre automaticamente o TightVNC Viewer quando disponível. O noVNC permanece como fallback.

### `map`

Executa:

```text
perl openkore.pl
```

e em paralelo:

```text
mapview.pl
```

```bat
okmode 1 map
okmode 2 map
```

O terminal continua sendo a interface principal do OpenKore.

O MapViewer mostra mapa, posição, NPCs, monstros e jogadores.

### Clique para movimentar

O modo `map` aceita clique no mapa:

```text
clique no MapViewer
        ↓
logs/map-command.txt
        ↓
dockerMapState.pl
        ↓
Commands::run("move X Y")
        ↓
OpenKore calcula a rota
```

O MapViewer não cria outra conexão com o Ragnarok.

---

## 5. MapViewer Docker

O plugin:

```text
dockerMapState.pl
```

gera:

```text
instances\openkore-bot1\logs\state.yml
```

Exemplo:

```yaml
---
connectionState: 'in game'
fieldName: 'pay_dun00'
fieldBaseName: 'pay_dun00'
fieldWidth: 200
fieldHeight: 200
mapImage: 'map/pay_dun00.xpm'
x: 126
y: 130
```

O OpenKore principal já possui o `Field` correto carregado e gera/localiza a imagem, por exemplo:

```text
instances\openkore-bot1\map\pay_dun00.xpm
```

O `mapview.pl` Docker usa essa imagem e um parser simples próprio para o `state.yml`, evitando incompatibilidades do `Data::YAML::Reader`.

Diagnóstico:

```bat
docker exec openkore-bot1-map sh -lc "cat /tmp/mapview.log"
docker exec openkore-bot1-map sh -lc "cat /opt/openkore/logs/state.yml"
docker exec openkore-bot1-map sh -lc "ps -ef | grep '[m]apview.pl'"
```

---

## 6. TightVNC como acesso principal

Local recomendado:

```text
tools\TightVNC\tvnviewer.exe
```

BOT1 TightVNC:

```text
127.0.0.1::6081
```

BOT1 TigerVNC:

```text
127.0.0.1:6081
```

BOT1 noVNC:

```text
http://localhost:6080/vnc.html?autoconnect=1&resize=scale
```

BOT2 TightVNC:

```text
127.0.0.1::6083
```

BOT2 TigerVNC:

```text
127.0.0.1:6083
```

BOT2 noVNC:

```text
http://localhost:6082/vnc.html?autoconnect=1&resize=scale
```

O TightVNC é usado como cliente nativo preferencial; noVNC continua disponível como fallback.

---

## 7. Portas

| Bot | noVNC Windows | VNC Windows | VNC interno |
|---|---:|---:|---:|
| BOT1 | `6080` | `6081` | `5900` |
| BOT2 | `6082` | `6083` | `5902` |

As portas são publicadas em `127.0.0.1`, para acesso local.

---

## 8. Comando principal: `okmode`

BOT1:

```bat
okmode 1 wx
okmode 1 console
okmode 1 map
okmode 1 stop
okmode 1 status
```

BOT2:

```bat
okmode 2 wx
okmode 2 console
okmode 2 map
okmode 2 stop
okmode 2 status
```

O `okmode` para os outros modos do mesmo bot antes de iniciar o solicitado.

---

## 9. Fluxo do `okmode`

```text
validar compose.yaml
        ↓
executar preflight
        ↓
parar outros modos do mesmo bot
        ↓
reiniciar/iniciar VPN
        ↓
aguardar healthcheck
        ↓
obter IP público
        ↓
comparar com a outra VPN, se ativa
        ↓
bloquear conflito
        ↓
iniciar OpenKore
        ↓
abrir TightVNC em wx/map
        ↓
docker attach em console/map
```

O OpenKore não deve iniciar antes da VPN estar validada.

---

## 10. VPN e isolamento

Cada bot usa uma configuração distinta:

```text
vpn\vpn-bot1\protonvpn-bot1.conf
vpn\vpn-bot2\protonvpn-bot2.conf
```

Imagem VPN:

```text
qmcgaw/gluetun:v3.41.1
```

Configuração:

```text
VPN_SERVICE_PROVIDER=custom
VPN_TYPE=wireguard
```

O arquivo é montado em:

```text
/gluetun/wireguard/wg0.conf
```

Use endereço WireGuard IPv4 compatível, por exemplo:

```ini
Address = 10.2.0.2/32
```

O preflight também valida que BOT1 e BOT2 não reutilizem indevidamente credenciais/VPN e o `okmode` compara os IPs públicos quando aplicável.

---

## 11. Credenciais do OpenKore

As credenciais reais ficam no arquivo local:

```text
.env
```

Exemplo:

```env
BOT1_MASTER=oRO
BOT1_USERNAME=usuario_bot1
BOT1_PASSWORD=senha_bot1
BOT1_CHAR=0

BOT2_MASTER=oRO
BOT2_USERNAME=usuario_bot2
BOT2_PASSWORD=senha_bot2
BOT2_CHAR=0
```

O `.env` não deve ir para o Git.

Modelo versionável:

```text
.env.example
```

```env
BOT1_MASTER=oRO
BOT1_USERNAME=
BOT1_PASSWORD=
BOT1_CHAR=

BOT2_MASTER=oRO
BOT2_USERNAME=
BOT2_PASSWORD=
BOT2_CHAR=
```

O `openkore-entrypoint.sh` injeta `username` e `password` no `control/config.txt` durante a inicialização sem imprimir as credenciais nos logs.

---

## 12. Git e arquivos sensíveis

`.gitignore` recomendado:

```gitignore
/.env
/vpn/vpn-bot1/protonvpn-bot1.conf
/vpn/vpn-bot2/protonvpn-bot2.conf
```

Arquivos que podem ser versionados:

```text
.env.example
vpn\vpn-bot1\protonvpn-bot1.conf.example
vpn\vpn-bot2\protonvpn-bot2.conf.example
```

Os `.conf.example` nunca devem conter a `PrivateKey` real.

Exemplo:

```ini
[Interface]
PrivateKey = COLOQUE_SUA_CHAVE_PRIVADA_AQUI
Address = 10.2.0.2/32

[Peer]
PublicKey = COLOQUE_A_CHAVE_PUBLICA_DO_SERVIDOR
Endpoint = ENDPOINT_DO_SERVIDOR:51820
AllowedIPs = 0.0.0.0/0
```

### `config.txt` antes do commit

Não há sanitização automática configurada.

Antes de cada commit, verifique manualmente:

```text
instances\openkore-bot1\control\config.txt
instances\openkore-bot2\control\config.txt
```

e deixe:

```text
username
password
```

sem valores reais.

Depois que o bot iniciar novamente, o entrypoint pode preencher os valores usando o `.env`.

Se um arquivo sensível já estiver sendo rastreado:

```bat
git rm --cached vpn\vpn-bot1\protonvpn-bot1.conf
git rm --cached vpn\vpn-bot2\protonvpn-bot2.conf
git rm --cached .env
```

Adicionar ao `.gitignore` não remove segredo de commits antigos. Se uma credencial já foi publicada, rotacione-a.

---

## 13. Terminal interativo

Nos modos `console` e `map`, o `okmode` usa `docker attach`.

Exemplo:

```bat
docker attach --sig-proxy=false openkore-bot1-console
```

ou:

```bat
docker attach --sig-proxy=false openkore-bot1-map
```

Para sair sem parar o OpenKore:

```text
Ctrl+P
Ctrl+Q
```

---

## 14. `terminalBridge` desabilitado

`terminalBridge` não faz parte do fluxo atual.

Quando estava ativo junto com a interface Console, duplicava a saída do terminal.

O terminal atual funciona diretamente por:

```text
docker attach
```

Não reative `terminalBridge` para o fluxo normal.

---

## 15. Persistência

```text
instances\openkore-bot1
```

é montado em:

```text
/opt/openkore
```

Logo alterações em `control`, `plugins`, `tables`, `map`, `logs`, Perl e configurações persistem no Windows.

O mesmo vale para BOT2.

---

## 16. Logs

BOT1:

```text
instances\openkore-bot1\logs
```

BOT2:

```text
instances\openkore-bot2\logs
```

Logs Docker:

```bat
docker compose logs -f bot1-gui
docker compose logs -f bot1-console
docker compose logs -f bot1-map
docker compose logs -f vpn1
```

MapViewer:

```bat
docker exec openkore-bot1-map sh -lc "cat /tmp/mapview.log"
```

---

## 17. XSTools

Volumes Linux:

```text
openkore-xstools-bot1
openkore-xstools-bot2
```

Montados em:

```text
/opt/openkore/src/auto/XSTools
```

O entrypoint copia os binários Linux da imagem para o volume:

```text
XSTools.so
libXSTools.so
```

A árvore geral do OpenKore continua editável no Windows.

---

## 18. Preparar BOT2

BOT2 não é necessário para buildar/testar BOT1.

Quando quiser criar:

```bat
xcopy /E /I /H instances\openkore-bot1 instances\openkore-bot2
```

Depois altere credenciais e VPN.

Copiar BOT1 para BOT2 não exige rebuild.

---

## 19. Perfis Compose

```text
bot1-wx
bot1-console
bot1-map
bot2-wx
bot2-console
bot2-map
```

Verificar:

```bat
docker compose config --profiles
```

Serviços:

```text
vpn1
bot1-gui
bot1-console
bot1-map
vpn2
bot2-gui
bot2-console
bot2-map
```

Verificar:

```bat
docker compose --profile "*" config --services
```

---

## 20. Compose sem `okmode`

BOT1 Wx:

```bat
docker compose --profile bot1-wx up -d vpn1 bot1-gui
```

BOT1 Console:

```bat
docker compose --profile bot1-console up -d vpn1 bot1-console
docker attach --sig-proxy=false openkore-bot1-console
```

BOT1 Map:

```bat
docker compose --profile bot1-map up -d vpn1 bot1-map
docker attach --sig-proxy=false openkore-bot1-map
```

BOT2 segue o mesmo padrão com `vpn2` e serviços `bot2-*`.

O uso do `okmode` continua recomendado por causa das validações extras.

---

## 21. Não execute dois modos do mesmo bot

Não execute:

```text
bot1-gui + bot1-console
bot1-gui + bot1-map
bot1-console + bot1-map
```

Cada serviço inicia um `openkore.pl` real usando a mesma pasta.

É permitido, por exemplo:

```text
BOT1 = map
BOT2 = console
```

---

## 22. Verificar VPN

```bat
docker exec vpn-bot1 wget -qO- https://api.ipify.org
docker exec openkore-bot1-console curl -s https://api.ipify.org
docker exec openkore-bot1-gui curl -s https://api.ipify.org
docker exec openkore-bot1-map curl -s https://api.ipify.org
```

O IP do OpenKore deve corresponder à saída da VPN correspondente.

---

## 23. Reload, restart, recreate e build

### Não precisa build

Alterações em:

```text
control\config.txt
control\items_control.txt
control\mon_control.txt
control\sys.txt
plugins\*.pl
tables\*
src\*.pm
mapview.pl
dockerMapState.pl
openkore-mode.sh
openkore-entrypoint.sh
okmode.ps1
okmode.bat
compose.yaml
```

não exigem rebuild da imagem.

### Alteração de configuração OpenKore

Use reload quando existir comando apropriado. Caso contrário, reinicie somente o modo.

### Alterou `compose.yaml`

Não precisa build, mas alterações de volumes, portas, environment, command, entrypoint, profiles ou network exigem recriação do container.

O `docker compose up` usado pelo `okmode` normalmente recria quando detecta mudança.

### Alterou VPN `.conf`

Não precisa build. Reinicie/recrie VPN e bot.

### Precisa build

Build é necessário para:

```text
Dockerfile
dependências Linux da imagem
XSTools C/C++/XS
ABI/runtime de binários nativos
```

Evite `--no-cache` sem necessidade.

---

## 24. Remoção dos logs externos

A configuração antiga tinha:

```yaml
source: ./logs/log-bot1
target: /opt/openkore/logs
```

e equivalente para BOT2.

Esses mounts eram redundantes porque:

```text
./instances/openkore-botN -> /opt/openkore
```

já inclui `/opt/openkore/logs`.

A configuração atual usa somente:

```text
instances\openkore-botN\logs
```

Essa mudança de Compose não exige build; somente recriação do container.

---

## 25. Validação

```bat
docker compose config
docker compose config --profiles
docker compose --profile "*" config --services
```

---

## 26. Diagnóstico rápido

```bat
docker compose ps
docker logs --tail 100 vpn-bot1
docker logs --tail 100 openkore-bot1-map
docker exec openkore-bot1-map sh -lc "cat /tmp/mapview.log"
docker exec openkore-bot1-map sh -lc "ps -ef | grep '[o]penkore.pl'"
docker exec openkore-bot1-map sh -lc "ps -ef | grep '[m]apview.pl'"
docker exec openkore-bot1-map sh -lc "head -n 20 /opt/openkore/logs/state.yml"
```

---

## 27. Servidor/OpenKore atual

Configuração base utilizada:

```text
serverType kRO_RagexeRE_2021_11_03
serverEncoding Western
addTableFolders translated/kRO_english;kRO/pre-re;kRO
charBlockSize 147
charDeleteDateType 1
rankingSystemType 1
itemListType 1
pinCode 0
```

Existem ajustes locais de protocolo específicos do servidor atual, incluindo `map_login` customizado.

Não substitua automaticamente arquivos Send/Receive locais por upstream sem testar.

Alterações em `.pm` não exigem build; apenas reinicie o OpenKore.

---

## 28. Storage/Kafra

Exemplo para armazenar ao atingir aproximadamente 50% de peso:

```ini
sellAuto 0
storageAuto 1
storageAuto_onStart 0
storageAuto_npc pay_arche 55 123
storageAuto_distance 5
storageAuto_npc_type 1
storageAuto_type 0
storageAuto_keepOpen 0
storageAuto_notAfterDeath 1
minStorageZeny 0
itemsMaxWeight 89
itemsMaxWeight_sellOrStore 50
itemsMaxNum_sellOrStore 99
```

Exemplo de `items_control.txt`:

```ini
all 0 1 0
```

Não exige build.

---

## 29. Fluxo diário recomendado

Iniciar BOT1 Map:

```bat
cd C:\Users\jrneves\Documents\openkore\openkore-bot
okmode 1 map
```

Esperado:

```text
preflight
VPN healthy
IP validado
bot1-map iniciado
TightVNC aberto
terminal anexado
```

Parar:

```bat
okmode 1 stop
```

Trocar de modo:

```bat
okmode 1 console
```

ou:

```bat
okmode 1 wx
```

---

## 30. Checklist antes do commit

Como não há sanitização automática:

1. `.env` deve estar ignorado.
2. `protonvpn-bot1.conf` deve estar ignorado.
3. `protonvpn-bot2.conf` deve estar ignorado.
4. `.conf.example` não pode conter `PrivateKey` real.
5. `config.txt` do BOT1 não pode conter username/password real.
6. `config.txt` do BOT2 não pode conter username/password real.
7. Verifique se não há segredos em scripts ou documentação.
8. Execute `docker compose config`.
9. Confira exatamente o staging.

```bat
git status
git diff --cached
```

Procure especialmente por:

```text
username
password
PrivateKey
```

---

## 31. Consumo de recursos

```text
Console           -> menor consumo
Console + MapView -> intermediário
Wx completo       -> maior consumo
```

Todos usam a mesma imagem Docker.

---

## 32. Referências

- OpenKore: `https://github.com/OpenKore/openkore`
- Docker Compose profiles: `https://docs.docker.com/compose/how-tos/profiles/`
- Docker Compose services: `https://docs.docker.com/reference/compose-file/services/`
- Gluetun: `https://github.com/qdm12/gluetun`
- TightVNC: `https://www.tightvnc.com/`
