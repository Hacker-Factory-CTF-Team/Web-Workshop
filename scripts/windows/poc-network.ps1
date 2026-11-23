#Requires -Version 5.1
<#
.SYNOPSIS
    Prueba de concepto de red para Docker Desktop en Windows 11 (NO PROBADO).
.DESCRIPTION
    Responde con conexiones reales a las preguntas de diseño que no se han podido
    verificar sin un equipo Windows:
      1. ¿Docker Desktop publica un puerto SOLO en la IP Host-only (no en 0.0.0.0)?
      2. Alternativa: publicar en 127.0.0.1 y reenviar con 'netsh interface portproxy'.
      3. ¿Una red 'internal' bloquea la salida a Internet y el DNS externo?
      4. ¿Qué alcanza una red no interna (como la del proxy edge)? Riesgo residual.
      5. ¿Se llega al anfitrión (host.docker.internal) desde cada red?
      6. Con dns: 127.0.0.1, ¿se resuelven los nombres internos y no los externos?
    Solo crea recursos temporales con el prefijo plab-poc y los elimina al terminar.
    La salida completa se guarda en state\windows-poc.log.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\windows\poc-network.ps1
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive report with coloured output')]
[CmdletBinding()]
param(
    [string]$LabIp
)
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
New-Item -ItemType Directory -Force -Path (Join-Path $Root 'state') | Out-Null
Start-Transcript -Path (Join-Path $Root 'state\windows-poc.log') -Force | Out-Null

$Results = New-Object System.Collections.ArrayList
function Add-Result([string]$Question, [string]$Outcome, [string]$Expected, [bool]$Good) {
    $null = $Results.Add([pscustomobject]@{ Pregunta = $Question; Resultado = $Outcome; Esperado = $Expected; OK = $Good })
    $color = if ($Good) { 'Green' } else { 'Yellow' }
    Write-Host ("  {0,-60} {1}" -f $Question, $Outcome) -ForegroundColor $color
}

function Test-Tcp([string]$HostName, [int]$Port, [int]$TimeoutMs = 3000) {
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $task = $c.ConnectAsync($HostName, $Port)
        return ($task.Wait($TimeoutMs) -and $c.Connected)
    } catch { return $false } finally { $c.Dispose() }
}

function Get-ListenAddress([int]$Port) {
    return @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue | ForEach-Object { $_.LocalAddress } | Sort-Object -Unique)
}

function Invoke-Docker {
    $out = & docker @args 2>&1
    return [pscustomobject]@{ Output = ($out -join "`n"); Code = $LASTEXITCODE }
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ------------------------------------------------------------- prerequisites ---
Write-Host "`n==> Requisitos" -ForegroundColor Cyan
if ((Invoke-Docker info --format '{{.OperatingSystem}}').Output -notmatch 'Docker Desktop') {
    Write-Host 'ERROR: Docker Desktop no está en marcha.' -ForegroundColor Red; Stop-Transcript | Out-Null; exit 4
}
if (-not $LabIp) {
    $local = Join-Path $Root 'config\local.json'
    $LabIp = '192.168.57.1'
    if (Test-Path $local) {
        $cfg = Get-Content $local -Raw | ConvertFrom-Json
        if ($cfg.network.lab_host_ip) { $LabIp = $cfg.network.lab_host_ip }
    }
}
if (-not (Get-NetIPAddress -IPAddress $LabIp -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: ninguna interfaz tiene la IP $LabIp (ejecuta la fase Network del instalador)." -ForegroundColor Red
    Stop-Transcript | Out-Null; exit 4
}
$lanIp = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1).IPv4Address.IPAddress
$versions = Get-Content (Join-Path $Root 'config\versions.json') -Raw | ConvertFrom-Json
$h = $versions.images.HELPER_IMAGE
$img = "$($h.repository):$($h.tag)@$($h.digest)"
if ((Invoke-Docker image inspect $img).Code -ne 0) {
    Write-Host "  descargando $($h.repository):$($h.tag) ..."
    if ((Invoke-Docker pull $img).Code -ne 0) { Write-Host 'ERROR: no se pudo descargar la imagen auxiliar.' -ForegroundColor Red; Stop-Transcript | Out-Null; exit 4 }
}
Write-Host "  IP de laboratorio: $LabIp   IP LAN del anfitrión: $lanIp   imagen: $($h.repository):$($h.tag)"

$names = @('plab-poc-pub', 'plab-poc-pp', 'plab-poc-target')
$nets = @('plab-poc-int', 'plab-poc-ext')
function Clear-PocResource {
    foreach ($n in $names) { Invoke-Docker rm -f $n | Out-Null }
    foreach ($n in $nets) { Invoke-Docker network rm $n | Out-Null }
}
Clear-PocResource
$listener = $null

try {
    # ------------------------------------------------ 1. publish on lab IP ---
    Write-Host "`n==> 1. Publicación directa en la IP de laboratorio" -ForegroundColor Cyan
    $p1 = 18080
    $r = Invoke-Docker run -d --name plab-poc-pub -p "${LabIp}:${p1}:8080" $img httpd -f -p 8080 -h /tmp
    if ($r.Code -ne 0) {
        Add-Result 'Docker acepta publicar en la IP Host-only' "NO: $($r.Output)" 'sí' $false
    } else {
        Start-Sleep -Seconds 2
        Add-Result 'Docker acepta publicar en la IP Host-only' 'sí' 'sí' $true
        $addrs = Get-ListenAddress $p1
        $onlyLab = ($addrs.Count -gt 0) -and -not ($addrs | Where-Object { $_ -ne $LabIp })
        Add-Result "Sockets en escucha en el puerto $p1" ($addrs -join ', ') "solo $LabIp" $onlyLab
        Add-Result "Conexión a ${LabIp}:$p1" $(if (Test-Tcp $LabIp $p1) { 'abierta' } else { 'cerrada' }) 'abierta' (Test-Tcp $LabIp $p1)
        $lo = Test-Tcp '127.0.0.1' $p1
        Add-Result "Conexión a 127.0.0.1:$p1 (no publicado ahí)" $(if ($lo) { 'abierta' } else { 'cerrada' }) 'cerrada' (-not $lo)
        if ($lanIp) {
            $lan = Test-Tcp $lanIp $p1
            Add-Result "Conexión a la IP LAN ${lanIp}:$p1" $(if ($lan) { 'abierta' } else { 'cerrada' }) 'cerrada' (-not $lan)
        }
    }

    # --------------------------------------------- 2. netsh portproxy alternative ---
    Write-Host "`n==> 2. Alternativa: 127.0.0.1 + netsh interface portproxy" -ForegroundColor Cyan
    if (Test-IsAdmin) {
        $p2 = 18081
        $r = Invoke-Docker run -d --name plab-poc-pp -p "127.0.0.1:${p2}:8080" $img httpd -f -p 8080 -h /tmp
        & netsh interface portproxy add v4tov4 "listenaddress=$LabIp" "listenport=$p2" connectaddress=127.0.0.1 "connectport=$p2" | Out-Null
        Start-Sleep -Seconds 2
        $pp = Test-Tcp $LabIp $p2
        Add-Result "portproxy ${LabIp}:$p2 -> 127.0.0.1:$p2" $(if ($pp) { 'funciona' } else { 'no funciona' }) 'informativo' $true
        Add-Result "Sockets en escucha en el puerto $p2" ((Get-ListenAddress $p2) -join ', ') 'informativo' $true
        & netsh interface portproxy delete v4tov4 "listenaddress=$LabIp" "listenport=$p2" | Out-Null
    } else {
        Add-Result 'netsh portproxy' 'omitido (requiere administrador)' 'informativo' $true
    }

    # ---------------------------------------------- 3-5. egress and host access ---
    Write-Host "`n==> 3-5. Salida a Internet y acceso al anfitrión desde las redes Docker" -ForegroundColor Cyan
    Invoke-Docker network create --internal plab-poc-int | Out-Null
    Invoke-Docker network create plab-poc-ext | Out-Null
    $hp = 18090
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $hp)
    $listener.Start()
    $probe = "if nc -z -w 3 1.1.1.1 443; then echo EGRESS=abierta; else echo EGRESS=cerrada; fi; " +
             "if nslookup example.com >/dev/null 2>&1; then echo DNS=abierto; else echo DNS=cerrado; fi; " +
             "if nc -z -w 3 host.docker.internal $hp; then echo HOST=abierto; else echo HOST=cerrado; fi"
    foreach ($n in $nets) {
        $out = (Invoke-Docker run --rm --network $n $img sh -c $probe).Output
        $eg = if ($out -match 'EGRESS=(\w+)') { $Matches[1] } else { '?' }
        $dn = if ($out -match 'DNS=(\w+)') { $Matches[1] } else { '?' }
        $ho = if ($out -match 'HOST=(\w+)') { $Matches[1] } else { '?' }
        if ($n -eq 'plab-poc-int') {
            Add-Result 'Red interna: salida TCP a Internet' $eg 'cerrada' ($eg -eq 'cerrada')
            Add-Result 'Red interna: DNS externo' $dn 'cerrado' ($dn -eq 'cerrado')
            Add-Result "Red interna: host.docker.internal:$hp (127.0.0.1 del anfitrión)" $ho 'cerrado' ($ho -eq 'cerrado')
        } else {
            Add-Result 'Red no interna (como el proxy): salida TCP' $eg 'riesgo residual documentado' $true
            Add-Result 'Red no interna: DNS externo (sin dns: 127.0.0.1)' $dn 'informativo' $true
            Add-Result "Red no interna: host.docker.internal:$hp" $ho 'cerrado' ($ho -eq 'cerrado')
        }
    }

    # ------------------------------------------------- 6. dns: 127.0.0.1 ---
    Write-Host "`n==> 6. DNS embebido con dns: 127.0.0.1 (red no interna)" -ForegroundColor Cyan
    Invoke-Docker run -d --name plab-poc-target --network plab-poc-ext $img sleep 120 | Out-Null
    $out = (Invoke-Docker run --rm --network plab-poc-ext --dns 127.0.0.1 $img sh -c `
            "if nslookup plab-poc-target >/dev/null 2>&1; then echo INT=si; else echo INT=no; fi; if nslookup example.com >/dev/null 2>&1; then echo EXT=si; else echo EXT=no; fi").Output
    $int = if ($out -match 'INT=(\w+)') { $Matches[1] } else { '?' }
    $ext = if ($out -match 'EXT=(\w+)') { $Matches[1] } else { '?' }
    Add-Result 'dns 127.0.0.1: resuelve nombres internos' $int 'si' ($int -eq 'si')
    Add-Result 'dns 127.0.0.1: resuelve nombres externos' $ext 'no' ($ext -eq 'no')
} finally {
    if ($listener) { $listener.Stop() }
    Clear-PocResource
}

Write-Host "`n==> Resumen" -ForegroundColor Cyan
$Results | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
$bad = @($Results | Where-Object { -not $_.OK })
if ($bad.Count -eq 0) { Write-Host 'Todas las respuestas son las esperadas.' -ForegroundColor Green }
else { Write-Host "$($bad.Count) respuestas distintas de las esperadas: envía state\windows-poc.log a los mantenedores." -ForegroundColor Yellow }
Stop-Transcript | Out-Null
exit $(if ($bad.Count -eq 0) { 0 } else { 1 })
