$port = 18090
$bat = Join-Path $PSScriptRoot "captcha_alarm.bat"

$listener = [System.Net.Sockets.TcpListener]::new(
    [System.Net.IPAddress]::Any,
    $port
)

$listener.Start()

Write-Host ""
Write-Host "=== CAPTCHA ALARM LISTENER ==="
Write-Host "Porta: $port"
Write-Host "BAT:   $bat"
Write-Host ""
Write-Host "Aguardando chamadas..."
Write-Host "CTRL+C para encerrar."
Write-Host ""

try {
    while ($true) {

        $client = $listener.AcceptTcpClient()

        try {
            $stream = $client.GetStream()

            $reader = New-Object System.IO.StreamReader(
                $stream,
                [System.Text.Encoding]::ASCII,
                $false,
                1024,
                $true
            )

            $request = $reader.ReadLine()

            # consome os headers HTTP
            while (($line = $reader.ReadLine()) -ne $null) {
                if ($line -eq "") {
                    break
                }
            }

            Write-Host "Recebido: $request"

            if ($request -match '^GET /captcha(?:\?[^ ]*)? HTTP/') {

                Write-Host "CAPTCHA detectado -> tocando alarme"

                Start-Process `
                    -FilePath "cmd.exe" `
                    -ArgumentList "/c", "`"$bat`"" `
                    -WindowStyle Hidden

                $body = "OK"
                $status = "200 OK"
            }
            else {
                $body = "NOT FOUND"
                $status = "404 Not Found"
            }

            $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)

            $header =
                "HTTP/1.1 $status`r`n" +
                "Content-Type: text/plain`r`n" +
                "Content-Length: $($bytes.Length)`r`n" +
                "Connection: close`r`n" +
                "`r`n"

            $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)

            $stream.Write($headerBytes, 0, $headerBytes.Length)
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush()
        }
        finally {
            $client.Close()
        }
    }
}
finally {
    $listener.Stop()
}