param(
    [Parameter(Position=0)]
    [ValidateSet('start','stop','status','reconcile','bot-start','bot-stop')]
    [string]$Action = 'status'
)

$ErrorActionPreference = 'Stop'

$OnlineGuardRoot = $PSScriptRoot
$ProjectRoot = Split-Path $OnlineGuardRoot -Parent

$ConfigPath = Join-Path $OnlineGuardRoot 'watcher\online-watcher.conf'

$WatcherService = 'online-watcher'
$VpnService = 'vpn-watcher'

$WatcherContainer = 'openkore-online-watcher'
$VpnContainer = 'vpn-online-watcher'

Set-Location $ProjectRoot

function Read-SimpleConfig {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Arquivo nao encontrado: $Path"
    }

    $cfg = @{}

    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $s = $line.Trim()

        if ($s -eq '' -or $s.StartsWith('#') -or $s.StartsWith(';')) {
            continue
        }

        $parts = $s -split '\s*=\s*', 2

        if ($parts.Count -ne 2) {
            continue
        }

        $cfg[$parts[0].Trim()] = $parts[1].Trim()
    }

    return $cfg
}

function Get-Activation {
    $cfg = Read-SimpleConfig $ConfigPath
    $value = 1

    if ($cfg.ContainsKey('activation')) {
        $value = [int]$cfg['activation']
    }

    if ($value -notin @(0,1,2)) {
        throw "activation invalido em $ConfigPath. Use 0, 1 ou 2."
    }

    return $value
}

function Get-ActivationName {
    param([int]$Activation)

    switch ($Activation) {
        0 { return 'so os bots' }
        1 { return 'always' }
        2 { return 'manual' }
    }
}

function Test-AnyOpenKoreRunning {
    $services = @(
        & docker compose ps --status running --services 2>$null
    )

    foreach ($svc in $services) {
        if ($svc -match '^bot\d+-(gui|console|map)$') {
            return $true
        }
    }

    return $false
}

function Get-ContainerState {
    param([string]$Container)

    $state = cmd.exe /d /s /c "docker inspect --format=""{{.State.Status}}"" ""$Container"" 2>nul"

    if ($LASTEXITCODE -ne 0) {
        return 'absent'
    }

    $value = ($state | Select-Object -First 1)

    if ($null -eq $value -or [string]::IsNullOrWhiteSpace($value)) {
        return 'absent'
    }

    return $value.Trim()
}
























function Get-PublicIp {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Container,

        [int]$Attempts = 3
    )

    for ($i = 1; $i -le $Attempts; $i++) {

        $result = cmd.exe /d /s /c `
            "docker exec ""$Container"" wget -qO- https://api.ipify.org 2>nul"

        if ($LASTEXITCODE -eq 0) {

            $ip = ($result | Select-Object -First 1)

            if ($null -ne $ip) {
                $ip = $ip.Trim()

                if (-not [string]::IsNullOrWhiteSpace($ip)) {

                    $parsed = $null

                    if ([System.Net.IPAddress]::TryParse(
                        $ip,
                        [ref]$parsed
                    )) {
                        return $ip
                    }
                }
            }
        }

        if ($i -lt $Attempts) {
            Start-Sleep -Seconds 2
        }
    }

    return $null
}


function Get-RunningBotVpnContainers {

    $names = cmd.exe /d /s /c `
        "docker ps --filter status=running --format ""{{.Names}}"" 2>nul"

    if ($LASTEXITCODE -ne 0) {
        return @()
    }

    $vpns = @()

    foreach ($name in $names) {

        if ($null -eq $name) {
            continue
        }

        $name = $name.Trim()

        if ($name -match '^vpn-bot\d+$') {
            $vpns += $name
        }
    }

    return $vpns
}


function Test-WatcherIpIsolation {

    $watcherState = Get-ContainerState $VpnContainer

    if ($watcherState -ne 'running') {
        throw "vpn-watcher nao esta rodando."
    }

    Write-Host "[WATCHER] Validando IP publico do watcher..."

    $watcherIp = Get-PublicIp `
        -Container $VpnContainer `
        -Attempts 10

    if (-not $watcherIp) {
        throw "Nao foi possivel obter o IP publico da vpn-watcher."
    }

    Write-Host "[WATCHER] IP publico do watcher: $watcherIp"

    $botVpns = @(Get-RunningBotVpnContainers)

    if ($botVpns.Count -eq 0) {
        Write-Host "[WATCHER] Nenhuma VPN de bot ativa para comparar."
        return $watcherIp
    }

    foreach ($botVpn in $botVpns) {

        $botIp = Get-PublicIp `
            -Container $botVpn `
            -Attempts 3

        if (-not $botIp) {
            throw "Nao foi possivel obter o IP publico de $botVpn."
        }

        Write-Host "[WATCHER] $botVpn IP publico: $botIp"

        if ($botIp -eq $watcherIp) {

            Write-Host ""
            Write-Host "[WATCHER] ERRO: IP PUBLICO REPETIDO!" `
                -ForegroundColor Red

            Write-Host "[WATCHER] $VpnContainer = $watcherIp" `
                -ForegroundColor Red

            Write-Host "[WATCHER] $botVpn = $botIp" `
                -ForegroundColor Red

            throw "A VPN do watcher possui o mesmo IP publico de $botVpn."
        }
    }

    Write-Host "[WATCHER] Isolamento de IP: OK." `
        -ForegroundColor Green

    return $watcherIp
}
























function Start-Watcher {
    $vpnConf = Join-Path $ProjectRoot 'vpn\vpn-watcher\protonvpn-watcher.conf'
    $watcherScript = Join-Path $OnlineGuardRoot 'watcher\online-watcher.pl'

    if (-not (Test-Path -LiteralPath $vpnConf)) {
        throw "VPN do watcher nao encontrada: $vpnConf"
    }

    if (-not (Test-Path -LiteralPath $watcherScript)) {
        throw "Watcher nao encontrado: $watcherScript"
    }

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Config do watcher nao encontrada: $ConfigPath"
    }

    New-Item -ItemType Directory -Force `
        -Path (Join-Path $ProjectRoot 'runtime\online-watch') | Out-Null

    Write-Host "[WATCHER] Iniciando/garantindo vpn-watcher + online-watcher..."

    #cmd.exe /d /s /c "docker compose --profile online-watcher up -d $VpnService $WatcherService"
	#
	#if ($LASTEXITCODE -ne 0) {
	#	throw "Falha ao iniciar o online-watcher."
	#}
	#
    #Write-Host "[WATCHER] online-watcher solicitado com sucesso." -ForegroundColor Green
	
	
	
	cmd.exe /d /s /c "docker compose --profile online-watcher up -d $VpnService $WatcherService"

	if ($LASTEXITCODE -ne 0) {
		throw "Falha ao iniciar o online-watcher."
	}

	Write-Host "[WATCHER] Containers iniciados. Validando isolamento de IP..."

	Test-WatcherIpIsolation | Out-Null

	Write-Host "[WATCHER] online-watcher validado com sucesso." `
		-ForegroundColor Green
	
	
	
	
	
}

function Stop-Watcher {
    Write-Host "[WATCHER] Parando online-watcher + vpn-watcher..."

    cmd.exe /d /s /c "docker compose stop $WatcherService $VpnService"

    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao parar online-watcher + vpn-watcher."
    }

    Write-Host "[WATCHER] online-watcher + vpn-watcher parados." -ForegroundColor Green
}

function Show-WatcherStatus {
    $activation = Get-Activation
    $activationName = Get-ActivationName $activation

    Write-Host ""
    Write-Host "activation=$activation ($activationName)"

    $vpnState = Get-ContainerState $VpnContainer
    $watcherState = Get-ContainerState $WatcherContainer

    Write-Host "vpn-watcher:    $vpnState"
    Write-Host "online-watcher: $watcherState"

    $cfg = Read-SimpleConfig $ConfigPath
    $hostOutput = '.\runtime\online-watch\online_players.json'

    if ($cfg.ContainsKey('host_output') -and $cfg['host_output'] -ne '') {
        $hostOutput = $cfg['host_output']
    }

    #$jsonPath = Join-Path $ProjectRoot $hostOutput
	$jsonPath = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $hostOutput))

    if (Test-Path -LiteralPath $jsonPath) {
        try {
            $data = Get-Content -Raw -LiteralPath $jsonPath -Encoding UTF8 | ConvertFrom-Json
            $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            $updatedAge = $now - [int64]$data.updated
            $successAge = $now - [int64]$data.last_success

            Write-Host "arquivo:        $jsonPath"
            Write-Host "status:         $($data.status)"
            Write-Host "players:        $($data.count)"
            Write-Host "updated_age:    ${updatedAge}s"
            Write-Host "success_age:    ${successAge}s"
			
			
			
			Write-Host ""
			Write-Host "=== IP ISOLATION ==="

			$watcherState = Get-ContainerState $VpnContainer

			if ($watcherState -eq 'running') {

				$watcherIp = Get-PublicIp `
					-Container $VpnContainer `
					-Attempts 2

				if ($watcherIp) {
					Write-Host "watcher: $watcherIp"
				}
				else {
					Write-Host "watcher: IP indisponivel"
				}

				$botVpns = @(Get-RunningBotVpnContainers)

				$duplicate = $false

				foreach ($botVpn in $botVpns) {

					$botIp = Get-PublicIp `
						-Container $botVpn `
						-Attempts 2

					if ($botIp) {

						Write-Host "${botVpn}: $botIp"

						if (
							$watcherIp -and
							$botIp -eq $watcherIp
						) {
							$duplicate = $true
						}
					}
					else {
						Write-Host "${botVpn}: IP indisponivel"
					}
				}

				if ($duplicate) {

					Write-Host "IP isolation: FALHOU - IP REPETIDO" `
						-ForegroundColor Red
				}
				else {

					Write-Host "IP isolation: OK" `
						-ForegroundColor Green
				}
			}
			else {
				Write-Host "watcher: offline"
			}
			
			
			
        }
        catch {
            Write-Warning "Arquivo existe, mas nao foi possivel ler o JSON: $jsonPath"
        }
    }
    else {
        Write-Host "arquivo:        ainda nao criado"
    }
}

$activation = Get-Activation

switch ($Action) {
    'start' {
        Start-Watcher
        exit 0
    }

    'stop' {
        Stop-Watcher
        exit 0
    }

    'status' {
        Show-WatcherStatus
        exit 0
    }

    #'bot-start' {
    #    # 0 = so os bots
    #    # 1 = always
    #    # 2 = manual
    #    if ($activation -eq 0 -or $activation -eq 1) {
    #        Start-Watcher
    #    }
	#
    #    exit 0
    #}
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	'bot-start' {

		if ($activation -eq 0 -or $activation -eq 1) {

			try {
				Start-Watcher
			}
			catch {

				Write-Host ""
				Write-Host "[WATCHER] Falha na validacao do watcher." `
					-ForegroundColor Red

				Write-Host "[WATCHER] O OpenKore NAO deve ser iniciado." `
					-ForegroundColor Red

				# activation=0:
				# se nenhum outro OpenKore estiver rodando,
				# nao deixa o watcher órfao.
				if ($activation -eq 0) {

					if (-not (Test-AnyOpenKoreRunning)) {

						Write-Host `
							"[WATCHER] Nenhum outro bot ativo. Parando watcher..."

						try {
							Stop-Watcher
						}
						catch {
							Write-Warning `
								"Falha ao limpar watcher apos erro."
						}
					}
				}

				throw
			}
		}

		exit 0
	}
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	

    'bot-stop' {
        if ($activation -eq 0) {
            if (-not (Test-AnyOpenKoreRunning)) {
                Stop-Watcher
            }
        }
        elseif ($activation -eq 1) {
            # Always: um bot parar nunca deve derrubar o watcher.
            # Se por algum motivo ele estiver fora do ar, tenta garantir novamente.
            Start-Watcher
        }

        # activation=2: nenhuma acao automatica.
        exit 0
    }

    'reconcile' {
        if ($activation -eq 0) {
            if (Test-AnyOpenKoreRunning) {
                Start-Watcher
            }
            else {
                Stop-Watcher
            }
        }
        elseif ($activation -eq 1) {
            Start-Watcher
        }

        # activation=2: nenhuma acao automatica.
        exit 0
    }
}
