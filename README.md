# OpenKore + Docker + VPN + Console/Wx/MapViewer

Projeto Docker para executar duas instâncias independentes do OpenKore, cada uma com sua própria VPN, usando a mesma imagem Linux e três modos de execução por bot.

Diretório esperado:

```text
C:\Users\jrneves\Documents\openkore\openkore-bot
```

## 1. Modos disponíveis

Cada bot pode executar apenas **um modo por vez**.

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

É o modo gráfico completo, com os menus e controles da interface Wx.

### `console`

Executa somente:

```text
perl openkore.pl
```

Não inicia Xvfb, Fluxbox, VNC, noVNC ou Wx. É o modo mais leve em execução.

### `map`

Executa:

```text
perl openkore.pl
```

como interface principal no terminal e, em paralelo:

```text
mapview.pl
```

O mapa é exibido por noVNC/VNC. Nesta primeira versão ele é **somente visualização**; os comandos continuam sendo digitados no Console.

O plugin `dockerMapState.pl` gera o arquivo `logs/state.yml` usado pelo `mapview.pl`.

## 2. Uma única imagem Docker

Os três modos usam:

```text
openkore-runtime-gui:local
```

Não são criadas imagens separadas para Console/Wx/MapViewer.

Isso significa que trocar de modo não duplica Wx, Perl ou as dependências Linux no disco.

O modo Console continua usando uma imagem que contém Wx, mas simplesmente não inicia os processos gráficos.

## 3. Estrutura atual

```text
openkore-bot
│
├── Dockerfile
├── compose.yaml
├── openkore-entrypoint.sh
├── openkore-mode.sh
├── dockerMapState.pl
├── okmode.ps1
├── okmode.bat
├── README.md
│
├── instances
│   ├── openkore-bot1
│   │   └── ... árvore completa do OpenKore ...
│   └── openkore-bot2
│       └── ... árvore completa do OpenKore ...
│
├── vpn
│   ├── vpn-bot1
│   │   └── protonvpn-bot1.conf
│   └── vpn-bot2
│       └── protonvpn-bot2.conf
│
└── logs
    ├── log-bot1
    └── log-bot2
```

`openkore-gui.sh` antigo pode continuar na pasta, mas o Compose multimodo passa a usar `openkore-mode.sh`.

## 4. Serviços Docker

BOT1:

```text
vpn1
bot1-gui       -> Wx
bot1-console   -> Console
bot1-map       -> Console + MapViewer
```

BOT2:

```text
vpn2
bot2-gui       -> Wx
bot2-console   -> Console
bot2-map       -> Console + MapViewer
```

O serviço `bot1-gui` foi mantido com o nome antigo para compatibilidade.

## 5. VPN

Todos os modos do bot1 usam:

```yaml
network_mode: "service:vpn1"
```

Todos os modos do bot2 usam:

```yaml
network_mode: "service:vpn2"
```

Portanto trocar Console/Wx/MapViewer não muda a rota de saída do OpenKore.

## 6. Portas

| Bot | noVNC | VNC nativo | VNC interno |
|---|---:|---:|---:|
| bot1 | 6080 | 6081 | 5900 |
| bot2 | 6082 | 6083 | 5902 |

BOT1 noVNC:

```text
http://localhost:6080/vnc.html?autoconnect=1&resize=scale
```

BOT1 VNC:

```text
127.0.0.1:6081
```

BOT2 noVNC:

```text
http://localhost:6082/vnc.html?autoconnect=1&resize=scale
```

BOT2 VNC:

```text
127.0.0.1:6083
```

No modo `console`, nada escuta nessas portas gráficas, embora a VPN continue com os mapeamentos configurados.

## 7. Comando recomendado: `okmode`

### BOT1 Wx

```bat
okmode 1 wx
```

### BOT1 Console

```bat
okmode 1 console
```

### BOT1 Console + mapa

```bat
okmode 1 map
```

### Parar BOT1 + VPN

```bat
okmode 1 stop
```

### Status

```bat
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

O `okmode` para os três serviços possíveis daquele bot antes de iniciar o modo solicitado.

## 8. Terminal no modo Console

Ao executar:

```bat
okmode 1 console
```

o script inicia o container em background e executa:

```bat
docker attach --sig-proxy=false openkore-bot1-console
```

Assim o terminal fica ligado ao mesmo processo:

```text
perl openkore.pl
```

Para sair do `docker attach` sem parar o OpenKore:

```text
Ctrl+P
Ctrl+Q
```

## 9. Terminal no modo MapViewer

```bat
okmode 1 map
```

O terminal continua sendo o OpenKore Console.

O mapa fica em:

```text
http://localhost:6080
```

ou:

```text
127.0.0.1:6081
```

O `mapview.pl` não é uma segunda conexão ao Ragnarok; ele apenas lê o estado gerado pelo plugin `dockerMapState.pl`.

## 10. Não execute dois modos do mesmo bot

Não faça:

```text
bot1-gui + bot1-console
bot1-gui + bot1-map
bot1-console + bot1-map
```

porque cada serviço inicia um `openkore.pl` real usando a mesma pasta `instances/openkore-bot1`.

O `okmode` foi criado justamente para evitar isso.

É permitido, por exemplo:

```text
bot1 = console
bot2 = wx
```

ou:

```text
bot1 = map
bot2 = console
```

## 11. Instalar/preparar BOT2

A pasta precisa conter uma árvore completa do OpenKore:

```text
instances\openkore-bot2
```

Se o bot2 vai usar a mesma versão do OpenKore do bot1, você pode copiar a árvore e depois alterar as configurações/credenciais específicas do bot2.

Também coloque a configuração WireGuard correspondente em:

```text
vpn\vpn-bot2\protonvpn-bot2.conf
```

E configure as variáveis do bot2 no `.env`, se estiver usando-as:

```text
BOT2_MASTER=
BOT2_USERNAME=
BOT2_PASSWORD=
BOT2_CHAR=
```

Tenha cuidado ao copiar o bot1: `control/config.txt` pode conter usuário/senha do bot1. Garanta que as credenciais do bot2 estejam corretas antes de iniciar.

## 12. XSTools

BOT1:

```text
openkore-xstools-bot1
```

BOT2:

```text
openkore-xstools-bot2
```

Ambos são volumes Linux nomeados montados em:

```text
/opt/openkore/src/auto/XSTools
```

Isso evita carregar `XSTools.so` diretamente do bind mount do Windows.

## 13. Alteração dos scripts sem build

Estes arquivos são bind-mounted:

```text
openkore-entrypoint.sh
openkore-mode.sh
dockerMapState.pl
```

Portanto esta atualização multimodo **não exige rebuild** da imagem atual.

Depois de substituir os arquivos e o `compose.yaml`, valide:

```bat
docker compose config
```

## 14. Primeira aplicação da mudança

Na raiz do projeto:

```bat
cd C:\Users\jrneves\Documents\openkore\openkore-bot
```

Pare o bot1 antigo:

```bat
docker compose stop bot1-gui vpn1
```

Valide:

```bat
docker compose config
```

Depois escolha um modo, por exemplo Wx:

```bat
okmode 1 wx
```

ou Console:

```bat
okmode 1 console
```

## 15. Comandos Compose sem `okmode`

### BOT1 Wx

```bat
docker compose --profile bot1-wx up -d vpn1 bot1-gui
```

### BOT1 Console

```bat
docker compose --profile bot1-console up -d vpn1 bot1-console
docker attach --sig-proxy=false openkore-bot1-console
```

### BOT1 MapViewer

```bat
docker compose --profile bot1-map up -d vpn1 bot1-map
docker attach --sig-proxy=false openkore-bot1-map
```

### BOT2 Wx

```bat
docker compose --profile bot2-wx up -d vpn2 bot2-gui
```

### BOT2 Console

```bat
docker compose --profile bot2-console up -d vpn2 bot2-console
docker attach --sig-proxy=false openkore-bot2-console
```

### BOT2 MapViewer

```bat
docker compose --profile bot2-map up -d vpn2 bot2-map
docker attach --sig-proxy=false openkore-bot2-map
```

## 16. Verificar a VPN

BOT1:

```bat
docker exec vpn-bot1 wget -qO- https://api.ipify.org
```

No modo Wx:

```bat
docker exec openkore-bot1-gui curl -s https://api.ipify.org
```

No modo Console:

```bat
docker exec openkore-bot1-console curl -s https://api.ipify.org
```

No modo MapViewer:

```bat
docker exec openkore-bot1-map curl -s https://api.ipify.org
```

O IP do OpenKore deve coincidir com o IP visto no `vpn1`.

## 17. Logs

Persistência:

```text
logs\log-bot1
logs\log-bot2
```

Container Wx:

```bat
docker compose logs -f bot1-gui
```

Console:

```bat
docker compose logs -f bot1-console
```

Map:

```bat
docker compose logs -f bot1-map
```

Diagnóstico do MapViewer:

```bat
docker exec openkore-bot1-map sh -lc "cat /tmp/mapview.log"
```

## 18. Impacto de recursos

Em execução, a ordem esperada é:

```text
Console           -> menor consumo
Console + MapView -> intermediário
Wx completo       -> maior consumo
```

Em disco, todos continuam usando a mesma imagem Docker.

## 19. Build

Trocar de modo:

```text
NÃO precisa build
```

Alterar `compose.yaml`, `openkore-mode.sh`, `openkore-entrypoint.sh` ou `dockerMapState.pl`:

```text
NÃO precisa build
```

Build continua necessário quando houver alteração real em:

```text
Dockerfile
dependências Linux
XSTools C/C++/XS
ABI/versão relevante do runtime
```

## 20. Referências

- OpenKore: https://github.com/OpenKore/openkore
- Docker Compose profiles: https://docs.docker.com/compose/how-tos/profiles/
- Docker Compose services: https://docs.docker.com/reference/compose-file/services/

---

# Segurança de inicialização — VPN e credenciais

A configuração atual adiciona validações antes de qualquer OpenKore iniciar.

## Regras obrigatórias

1. `vpn-bot1` precisa ficar `healthy` antes do BOT1 iniciar.
2. `vpn-bot2` precisa ficar `healthy` antes do BOT2 iniciar.
3. Os arquivos WireGuard de BOT1 e BOT2 não podem ser clones da mesma configuração.
4. `PrivateKey` WireGuard de BOT1 e BOT2 não pode ser igual.
5. Quando as duas VPNs estão ativas, `okmode` compara os IPs públicos. Se forem iguais, o segundo bot é bloqueado.
6. `username` do BOT1 e BOT2 não pode ser igual.
7. `password` do BOT1 e BOT2 não pode ser igual.
8. `username/password` são lidos exclusivamente de:
   - `instances/openkore-bot1/control/config.txt`
   - `instances/openkore-bot2/control/config.txt`
9. `OK_USERNAME` e `OK_PASSWORD` por variável de ambiente são bloqueados pelo entrypoint.

As credenciais nunca são impressas pela validação.

## Arquivos adicionais

```text
openkore-preflight.sh
vpn-guard-entrypoint.sh
```

`openkore-preflight.sh` compara os dois bots e as duas configurações VPN.

`vpn-guard-entrypoint.sh` roda a validação antes de entregar o processo ao Gluetun.

O `openkore-entrypoint.sh` também executa a validação novamente imediatamente antes de iniciar o OpenKore.

## Testar somente o YAML/Compose

Na raiz:

```bat
docker compose config
```

Se retornar a configuração resolvida sem erro, a estrutura YAML/Compose foi aceita.

Listar serviços:

```bat
docker compose config --services
```

Listar profiles:

```bat
docker compose config --profiles
```

## Executar somente os checks estáticos

BOT1:

```bat
okmode 1 check
```

BOT2:

```bat
okmode 2 check
```

Isso verifica arquivos VPN, `PrivateKey`, `username` e `password` sem iniciar o OpenKore.

## Teste real BOT1

Wx:

```bat
okmode 1 wx
```

Console:

```bat
okmode 1 console
```

Console + mapa:

```bat
okmode 1 map
```

O fluxo é:

```text
preflight
   ↓
inicia vpn1
   ↓
aguarda vpn-bot1 = healthy
   ↓
confirma IP público
   ↓
se vpn2 estiver ativa, compara IP público
   ↓
somente então inicia OpenKore
```

## Teste real BOT2

```bat
okmode 2 wx
```

ou:

```bat
okmode 2 console
```

ou:

```bat
okmode 2 map
```

## Exemplos de bloqueio

Credencial igual:

```text
[PREFLIGHT] ERRO: username do bot2 é IGUAL ao username do bot1.
Inicialização bloqueada.
```

VPN clonada:

```text
[PREFLIGHT] ERRO: VPN do bot2 é a MESMA configuração da VPN do bot1.
Inicialização bloqueada.
```

PrivateKey igual:

```text
[PREFLIGHT] ERRO: PrivateKey WireGuard do bot2 é IGUAL à do bot1.
Inicialização bloqueada.
```

VPN não saudável:

```text
IMPOSSÍVEL subir o bot2 sem a VPN2 estar funcionando.
```

Mesmo IP público:

```text
BLOQUEADO: VPN1 e VPN2 estão saindo pelo MESMO IP público.
O OpenKore do bot2 NÃO será iniciado.
```

## Diagnóstico manual

Status:

```bat
docker compose ps -a
```

VPN1:

```bat
docker inspect --format="{{.State.Health.Status}}" vpn-bot1
docker compose logs --tail 100 vpn1
```

VPN2:

```bat
docker inspect --format="{{.State.Health.Status}}" vpn-bot2
docker compose logs --tail 100 vpn2
```

IPs:

```bat
docker exec vpn-bot1 wget -qO- https://api.ipify.org
docker exec vpn-bot2 wget -qO- https://api.ipify.org
```

Os dois IPs devem ser diferentes quando os dois bots estiverem ativos.

## Observação sobre build

As validações, o `compose.yaml` e os scripts são bind-mounted.

Trocar estes arquivos não exige rebuild imediato:

```text
compose.yaml
openkore-entrypoint.sh
openkore-mode.sh
openkore-preflight.sh
vpn-guard-entrypoint.sh
dockerMapState.pl
okmode.ps1
okmode.bat
```

O Dockerfile novo deve ser usado no próximo build do runtime.

