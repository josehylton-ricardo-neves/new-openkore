param(
    [Parameter(Position=0, Mandatory=$true)]
    [ValidateSet('1','2','3')]
    [string]$Bot,

    [Parameter(Position=1, Mandatory=$true)]
    [ValidateSet('wx','console','map','stop','status','check')]
    [string]$Mode
)

$ErrorActionPreference = 'Continue'

# Windows PowerShell 5.1: UTF-8 output.
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding

Set-Location $PSScriptRoot

$WatcherCtl = Join-Path $PSScriptRoot 'online-guard\watcherctl.ps1'

function Fail([string]$Message, [int]$Code = 1) {
    Write-Host ""
    Write-Host "ERRO: $Message" -ForegroundColor Red
    exit $Code
}

function Run-ComposeConfigCheck {
    Write-Host "[CHECK] Validando compose.yaml..."
    $output = & docker compose config 2>&1
    if ($LASTEXITCODE -ne 0) {
        $output | ForEach-Object { Write-Host $_ }
        Fail "compose.yaml inválido. Nada foi iniciado."
    }
    Write-Host "[CHECK] compose.yaml: OK." -ForegroundColor Green
}

function Get-ContainerState([string]$Container) {
    $state = & docker inspect --format '{{.State.Status}}' $Container 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return ($state | Select-Object -First 1).Trim()
}

function Get-ContainerHealth([string]$Container) {
    $health = & docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' $Container 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return ($health | Select-Object -First 1).Trim()
}

function Get-VpnPublicIp([string]$Container) {
    $ip = & docker exec $Container wget -qO- --timeout=8 https://api.ipify.org 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    $value = ($ip | Select-Object -First 1).Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    return $value
}

#function abrir no tightViewer
function Get-TightVncViewer {
    $candidates = @(
        (Join-Path $PSScriptRoot "tools\TightVNC\tvnviewer.exe"),
        (Join-Path $env:ProgramFiles "TightVNC\tvnviewer.exe")
    )

    if (${env:ProgramFiles(x86)}) {
        $candidates += Join-Path ${env:ProgramFiles(x86)} "TightVNC\tvnviewer.exe"
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    return $null
}

#if ($Bot -eq '1') {
#    $vpn = 'vpn1'
#    $vpnContainer = 'vpn-bot1'
#    $otherVpnContainer = 'vpn-bot2'
#
#    $wx = 'bot1-gui'
#    $console = 'bot1-console'
#    $map = 'bot1-map'
#
#    $wxProfile = 'bot1-wx'
#    $consoleProfile = 'bot1-console'
#    $mapProfile = 'bot1-map'
#
#    $wxContainer = 'openkore-bot1-gui'
#    $consoleContainer = 'openkore-bot1-console'
#    $mapContainer = 'openkore-bot1-map'

#    $novnc = 'http://localhost:6080/vnc.html?autoconnect=1&resize=scale'
#    $vncTiger = '127.0.0.1:6081'
#    $vncTight = '127.0.0.1::6081'
#} else {
#    $vpn = 'vpn2'
#    $vpnContainer = 'vpn-bot2'
#    $otherVpnContainer = 'vpn-bot1'
#
#    $wx = 'bot2-gui'
#    $console = 'bot2-console'
#    $map = 'bot2-map'
#
#    $wxProfile = 'bot2-wx'
#    $consoleProfile = 'bot2-console'
#    $mapProfile = 'bot2-map'
#
#    $wxContainer = 'openkore-bot2-gui'
#    $consoleContainer = 'openkore-bot2-console'
#    $mapContainer = 'openkore-bot2-map'
#
#    $novnc = 'http://localhost:6082/vnc.html?autoconnect=1&resize=scale'
#    $vncTiger = '127.0.0.1:6083'
#    $vncTight = '127.0.0.1::6083'
#}



switch ($Bot) {
    '1' {
        $vpn = 'vpn1'
        $vpnContainer = 'vpn-bot1'
        $otherVpnContainers = @('vpn-bot2', 'vpn-bot3')

        $wx = 'bot1-gui'
        $console = 'bot1-console'
        $map = 'bot1-map'

        $wxProfile = 'bot1-wx'
        $consoleProfile = 'bot1-console'
        $mapProfile = 'bot1-map'

        $wxContainer = 'openkore-bot1-gui'
        $consoleContainer = 'openkore-bot1-console'
        $mapContainer = 'openkore-bot1-map'

        $novnc = 'http://localhost:6080/vnc.html?autoconnect=1&resize=scale'
        $vncTiger = '127.0.0.1:6081'
        $vncTight = '127.0.0.1::6081'
    }

    '2' {
        $vpn = 'vpn2'
        $vpnContainer = 'vpn-bot2'
        $otherVpnContainers = @('vpn-bot1', 'vpn-bot3')

        $wx = 'bot2-gui'
        $console = 'bot2-console'
        $map = 'bot2-map'

        $wxProfile = 'bot2-wx'
        $consoleProfile = 'bot2-console'
        $mapProfile = 'bot2-map'

        $wxContainer = 'openkore-bot2-gui'
        $consoleContainer = 'openkore-bot2-console'
        $mapContainer = 'openkore-bot2-map'

        $novnc = 'http://localhost:6082/vnc.html?autoconnect=1&resize=scale'
        $vncTiger = '127.0.0.1:6083'
        $vncTight = '127.0.0.1::6083'
    }

    '3' {
        $vpn = 'vpn3'
        $vpnContainer = 'vpn-bot3'
        $otherVpnContainers = @('vpn-bot1', 'vpn-bot2')

        $wx = 'bot3-gui'
        $console = 'bot3-console'
        $map = 'bot3-map'

        $wxProfile = 'bot3-wx'
        $consoleProfile = 'bot3-console'
        $mapProfile = 'bot3-map'

        $wxContainer = 'openkore-bot3-gui'
        $consoleContainer = 'openkore-bot3-console'
        $mapContainer = 'openkore-bot3-map'

        $novnc = 'http://localhost:6084/vnc.html?autoconnect=1&resize=scale'
        $vncTiger = '127.0.0.1:6085'
        $vncTight = '127.0.0.1::6085'
    }
}



# Docker Desktop / Engine
& docker info >$null 2>$null
if ($LASTEXITCODE -ne 0) {
    Fail "Docker Desktop/Engine não está disponível."
}

Run-ComposeConfigCheck

if ($Mode -eq 'status') {
    docker compose ps -a
    exit $LASTEXITCODE
}

if ($Mode -eq 'stop') {
    Write-Host "[STOP] Parando bot$Bot em qualquer modo..."
    & docker compose stop $wx $console $map 2>$null

    Write-Host "[STOP] Parando $vpn..."
    & docker compose stop $vpn 2>$null

    Write-Host "bot$Bot parado: OpenKore + VPN." -ForegroundColor Green
	
	& $WatcherCtl bot-stop
	
    exit 0
}

switch ($Mode) {
    'wx' {
        $service = $wx
        $profile = $wxProfile
        $container = $wxContainer
    }
    'console' {
        $service = $console
        $profile = $consoleProfile
        $container = $consoleContainer
    }
    'map' {
        $service = $map
        $profile = $mapProfile
        $container = $mapContainer
    }
    'check' {
        # Usa o perfil wx apenas para habilitar a definição do vpnN;
        # não inicia nenhum serviço.
        $service = $null
        $profile = $wxProfile
        $container = $null
    }
}

# ============================================================
# 1) PREFLIGHT ESTÁTICO
# ============================================================

Write-Host ""
Write-Host "[CHECK] Validando credenciais e arquivos VPN do bot$Bot..."

& docker compose --profile $profile run --rm --no-deps `
    --entrypoint /bin/sh `
    $vpn /checks/openkore-preflight.sh

if ($LASTEXITCODE -ne 0) {
    Fail "preflight do bot$Bot falhou. VPN e OpenKore NÃO serão iniciados."
}

if ($Mode -eq 'check') {
    Write-Host ""
    Write-Host "Todos os checks estáticos do bot$Bot passaram." -ForegroundColor Green

    #$otherState = Get-ContainerState $otherVpnContainer
    #if ($otherState -eq 'running') {
    #    Write-Host "A outra VPN está ativa; a igualdade de IP público só é testada quando você iniciar este bot."
    #}
	
	foreach ($otherVpnContainer in $otherVpnContainers) {
    $otherState = Get-ContainerState $otherVpnContainer

    if ($otherState -eq 'running') {
        Write-Host "$otherVpnContainer está ativa; o IP público será comparado quando você iniciar este bot."
    }
}
    exit 0
}

# ============================================================
# 2) GARANTE APENAS UM MODO DO MESMO BOT
# ============================================================

Write-Host ""
Write-Host "[MODE] Parando outros modos do bot$Bot..."
& docker compose stop $wx $console $map 2>$null

# Reinicia a VPN do próprio bot de forma limpa.
Write-Host "[VPN] Reiniciando $vpn..."
& docker compose stop $vpn 2>$null

# ============================================================
# 3) SOBE SOMENTE A VPN
# ============================================================

Write-Host "[VPN] Iniciando $vpn..."
& docker compose --profile $profile up -d $vpn

if ($LASTEXITCODE -ne 0) {
    Fail "Docker não conseguiu criar/iniciar $vpn. O bot NÃO será iniciado."
}

# ============================================================
# 4) AGUARDA HEALTHY
# ============================================================

$maxWaitSeconds = 75
$elapsed = 0
$lastHealth = ''

while ($elapsed -lt $maxWaitSeconds) {
    $state = Get-ContainerState $vpnContainer
    $health = Get-ContainerHealth $vpnContainer

    if ($health -ne $lastHealth) {
        Write-Host "[VPN] Estado: container=$state health=$health"
        $lastHealth = $health
    }

    if ($state -eq 'running' -and $health -eq 'healthy') {
        break
    }

    if ($state -eq 'exited' -or $state -eq 'dead') {
        break
    }

    Start-Sleep -Seconds 2
    $elapsed += 2
}

$state = Get-ContainerState $vpnContainer
$health = Get-ContainerHealth $vpnContainer

if ($state -ne 'running' -or $health -ne 'healthy') {
    Write-Host ""
    Write-Host "================ LOGS DA VPN ================" -ForegroundColor Yellow
    & docker compose logs --tail 100 $vpn
    Write-Host "=============================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "IMPOSSÍVEL subir o bot$Bot sem a VPN$Bot estar funcionando." -ForegroundColor Red
    Write-Host "Estado final: container=$state health=$health" -ForegroundColor Red

    & docker compose stop $vpn 2>$null
    exit 20
}

$targetIp = Get-VpnPublicIp $vpnContainer
if ([string]::IsNullOrWhiteSpace($targetIp)) {
    & docker compose logs --tail 80 $vpn
    & docker compose stop $vpn 2>$null
    Fail "$vpn está healthy, mas não foi possível confirmar o IP público. Bot bloqueado." 21
}

Write-Host "[VPN] $vpn OK. IP público confirmado: $targetIp" -ForegroundColor Green

# ============================================================
# 5) GARDA DINÂMICA: VPN1 E VPN2 NÃO PODEM TER O MESMO IP
# ============================================================

#$otherState = Get-ContainerState $otherVpnContainer
#if ($otherState -eq 'running') {
#    $otherHealth = Get-ContainerHealth $otherVpnContainer
#
#    if ($otherHealth -eq 'healthy') {
#        $otherIp = Get-VpnPublicIp $otherVpnContainer
#
#        if (-not [string]::IsNullOrWhiteSpace($otherIp)) {
#            Write-Host "[VPN] Outra VPN ativa: $otherVpnContainer -> $otherIp"
#
#            if ($targetIp -eq $otherIp) {
#                Write-Host ""
#                Write-Host "BLOQUEADO: VPN1 e VPN2 estão saindo pelo MESMO IP público ($targetIp)." -ForegroundColor Red
#                Write-Host "O OpenKore do bot$Bot NÃO será iniciado." -ForegroundColor Red
#                Write-Host "Troque a configuração ProtonVPN de um dos bots." -ForegroundColor Yellow
#
#                & docker compose stop $vpn 2>$null
#                exit 22
#            }
#        }
#    }
#}



foreach ($otherVpnContainer in $otherVpnContainers) {

    $otherState = Get-ContainerState $otherVpnContainer

    if ($otherState -eq 'running') {

        $otherHealth = Get-ContainerHealth $otherVpnContainer

        if ($otherHealth -eq 'healthy') {

            $otherIp = Get-VpnPublicIp $otherVpnContainer

            if (-not [string]::IsNullOrWhiteSpace($otherIp)) {

                Write-Host "[VPN] Outra VPN ativa: $otherVpnContainer -> $otherIp"

                if ($targetIp -eq $otherIp) {

                    Write-Host ""
                    Write-Host "BLOQUEADO: $vpnContainer e $otherVpnContainer estão saindo pelo MESMO IP público ($targetIp)." -ForegroundColor Red
                    Write-Host "O OpenKore do bot$Bot NÃO será iniciado." -ForegroundColor Red
                    Write-Host "Troque a configuração ProtonVPN de um dos bots." -ForegroundColor Yellow

                    & docker compose stop $vpn 2>$null

                    exit 22
                }
            }
        }
    }
}







# ============================================================
# ONLINE WATCHER
# ============================================================

& $WatcherCtl bot-start

# ============================================================
# 6) SÓ AGORA SOBE O OPENKORE
# ============================================================

Write-Host ""
Write-Host "[BOT] VPN validada. Iniciando $service..."
& docker compose --profile $profile up -d $service

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "================ LOGS DO BOT ================" -ForegroundColor Yellow
    & docker compose logs --tail 100 $service
    Write-Host "=============================================" -ForegroundColor Yellow
	
	& $WatcherCtl bot-stop
	
    Fail "falha ao iniciar $service."
}

Start-Sleep -Seconds 2
$botState = Get-ContainerState $container

if ($botState -ne 'running') {
    Write-Host ""
    & docker compose logs --tail 100 $service
    Fail "$service não permaneceu em execução. Estado: $botState"
}

Write-Host "[BOT] bot$Bot iniciado em modo $Mode." -ForegroundColor Green

if ($Mode -eq 'wx') {
	
	#-------------abrir no navegador-------------------
    #Write-Host ""
    #Write-Host "noVNC:       $novnc"
    #Write-Host "TigerVNC:    $vncTiger"
    #Write-Host "TightVNC:    $vncTight"
    #exit 0
	
	
	#-------------abrir no tightViewer-----------------
	$tightViewer = Get-TightVncViewer
    if ($tightViewer) {
        Write-Host "[WX] Abrindo interface no TightVNC Viewer..."
        Start-Process -FilePath $tightViewer -ArgumentList $vncTight
    }
    else {
        Write-Host "[WX] TightVNC Viewer não encontrado. Abrindo noVNC..."
        Start-Process $novnc
    }
    exit 0
	
	
}

if ($Mode -eq 'map') {
    Write-Host ""
    Write-Host "MapViewer noVNC: $novnc"
    Write-Host "TigerVNC:         $vncTiger"
    Write-Host "TightVNC:         $vncTight"
	
	#-------------abrir no navegador-------------------
    #Write-Host "[MAP] Abrindo MapViewer no navegador..."
    #Start-Process $novnc
	
	#-------------abrir no tightViewer-----------------
	$tightViewer = Get-TightVncViewer
	if ($tightViewer) {
		Write-Host "[MAP] Abrindo MapViewer no TightVNC Viewer..."
		Start-Process -FilePath $tightViewer -ArgumentList $vncTight
	}
	else {
		Write-Host "[MAP] TightVNC Viewer não encontrado. Abrindo noVNC..."
		Start-Process $novnc
	}
	
	
}

Write-Host ""
Write-Host "Anexando ao terminal do OpenKore..."
Write-Host "Para sair do attach SEM parar: Ctrl+P e depois Ctrl+Q"
Start-Sleep -Seconds 1

& docker attach --sig-proxy=false $container
