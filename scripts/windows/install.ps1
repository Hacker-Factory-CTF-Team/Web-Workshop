#Requires -Version 5.1
<#
.SYNOPSIS
    Instalador del laboratorio en Windows 11 (Docker Desktop + VirtualBox). NO PROBADO.
.DESCRIPTION
    Sin -Phase: detección (solo lectura) y, después, pregunta por cada fase.
    Fases:
      Detect     detección del sistema (solo lectura)
      Deps       comprueba Docker Desktop, Python y VirtualBox; ofrece instalarlos con winget
      Network    crea o reutiliza la red Host-only de VirtualBox con DHCP (administrador)
      Firewall   crea las reglas del grupo PentestLab del Firewall de Windows (administrador)
      Images     descarga las imágenes fijadas (.\manager.ps1 install all)
      Validate   diagnóstico (.\manager.ps1 diagnose)
      Uninstall  deshace lo registrado en state\installer.json (administrador)
    Todo lo que se crea queda registrado en state\installer.json.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\windows\install.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\windows\install.ps1 -Phase Network -LabIp 192.168.57.1
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive installer with coloured output')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Script parameters are read inside the phase functions')]
[CmdletBinding()]
param(
    [ValidateSet('Detect', 'Deps', 'Network', 'Firewall', 'Images', 'Validate', 'Uninstall')]
    [string]$Phase,
    [string]$LabIp = '192.168.57.1',
    [ValidateRange(16, 29)]
    [int]$Prefix = 24,
    [switch]$Yes
)
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Manager = Join-Path $Root 'manager.ps1'
$Record = Join-Path $Root 'state\installer.json'
$FwGroup = 'PentestLab'

# ------------------------------------------------------------------ output ---
function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text) { Write-Host "  [OK]    $Text" -ForegroundColor Green }
function Write-Info([string]$Text) { Write-Host "          $Text" }
function Write-Caution([string]$Text) { Write-Host "  [AVISO] $Text" -ForegroundColor Yellow }
function Write-Fail([string]$Text) { Write-Host "  [FALLO] $Text" -ForegroundColor Red }
function Exit-WithError([string]$Text, [string]$Hint = '', [int]$Code = 1) {
    Write-Host "ERROR: $Text" -ForegroundColor Red
    if ($Hint) { Write-Host "Cómo solucionarlo: $Hint" }
    exit $Code
}

function Confirm-Choice([string]$Question, [bool]$Default = $true) {
    if ($Yes) { return $true }
    $suffix = if ($Default) { '[S/n]' } else { '[s/N]' }
    $ans = Read-Host "$Question $suffix"
    if ([string]::IsNullOrWhiteSpace($ans)) { return $Default }
    return $ans.Trim().ToLower() -in @('s', 'si', 'sí', 'y', 'yes')
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Admin([string]$What) {
    if (-not (Test-IsAdmin)) {
        Exit-WithError "la fase $What necesita permisos de administrador" `
            'Abre PowerShell con "Ejecutar como administrador" y repite el comando.' 5
    }
}

# ---------------------------------------------------------------- helpers ---
function Invoke-Manager {
    # Runs .\manager.ps1 in a child process so its 'exit' does not end this script.
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Manager @args
    $code = $LASTEXITCODE
    return [pscustomobject]@{ Output = ($out -join "`n"); Code = $code }
}

function Invoke-ManagerVisible {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Manager @args
    return $LASTEXITCODE
}

function Get-VBoxManage {
    $cmd = Get-Command VBoxManage -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cand = Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe'
    if (Test-Path $cand) { return $cand }
    return $null
}

function Get-InstallRecord {
    if (Test-Path $Record) {
        $data = Get-Content $Record -Raw | ConvertFrom-Json
        $h = @{}
        foreach ($p in $data.PSObject.Properties) { $h[$p.Name] = $p.Value }
        return $h
    }
    return @{}
}

function Add-InstallRecord([string]$Key, [string]$Value) {
    $h = Get-InstallRecord
    $h[$Key] = $Value
    New-Item -ItemType Directory -Force -Path (Split-Path $Record) | Out-Null
    $h | ConvertTo-Json | Set-Content -Path $Record -Encoding UTF8
}

function ConvertTo-UInt32([string]$Ip) {
    $b = ([System.Net.IPAddress]::Parse($Ip)).GetAddressBytes()
    [Array]::Reverse($b)
    return [BitConverter]::ToUInt32($b, 0)
}

function ConvertFrom-UInt32([uint32]$Value) {
    $b = [BitConverter]::GetBytes($Value)
    [Array]::Reverse($b)
    return ([System.Net.IPAddress]::new($b)).ToString()
}

function Get-NetMask([int]$Bits) {
    return ConvertFrom-UInt32 ([uint32]([math]::Pow(2, 32) - [math]::Pow(2, 32 - $Bits)))
}

function Get-NthHost([string]$Ip, [int]$Bits, [int]$N) {
    $mask = ConvertTo-UInt32 (Get-NetMask $Bits)
    return ConvertFrom-UInt32 ([uint32](((ConvertTo-UInt32 $Ip) -band $mask) + $N + 1))
}

function Test-SubnetOverlap([string]$IpA, [int]$BitsA, [string]$IpB, [int]$BitsB) {
    $bits = [math]::Min($BitsA, $BitsB)
    $mask = ConvertTo-UInt32 (Get-NetMask $bits)
    return (((ConvertTo-UInt32 $IpA) -band $mask) -eq ((ConvertTo-UInt32 $IpB) -band $mask))
}

function Get-HostOnlyInterface([string]$VBox) {
    # Parses 'VBoxManage list hostonlyifs' into objects with Name and IPAddress.
    $items = @()
    $cur = $null
    foreach ($line in (& $VBox list hostonlyifs)) {
        if ($line -match '^Name:\s+(.+)$') { $cur = [pscustomobject]@{ Name = $Matches[1].Trim(); IPAddress = '' }; $items += $cur }
        elseif ($cur -and $line -match '^IPAddress:\s+(\S+)') { $cur.IPAddress = $Matches[1] }
    }
    return $items
}

# ----------------------------------------------------------------- phases ---
function Invoke-PhaseDetect {
    Write-Step 'Detección (solo lectura)'
    $os = Get-CimInstance Win32_OperatingSystem
    if ([int]$os.BuildNumber -ge 22000) { Write-Ok "$($os.Caption) (build $($os.BuildNumber))" }
    else { Write-Caution "$($os.Caption) (build $($os.BuildNumber)): el laboratorio está pensado para Windows 11" }
    if (Test-IsAdmin) { Write-Info 'Sesión con permisos de administrador' } else { Write-Info 'Sesión sin permisos de administrador (Network, Firewall y Uninstall los necesitan)' }
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    if ($cpu.VirtualizationFirmwareEnabled -eq $false) { Write-Caution 'la virtualización está desactivada en la BIOS/UEFI' }

    if (Get-Command docker -ErrorAction SilentlyContinue) {
        $ver = & docker version --format '{{.Server.Version}}' 2>$null
        if ($LASTEXITCODE -eq 0) {
            $osName = & docker info --format '{{.OperatingSystem}}' 2>$null
            Write-Ok "Docker Engine $ver ($osName)"
            if ($osName -notmatch 'Docker Desktop') { Write-Caution 'en Windows solo se soporta Docker Desktop (con WSL2)' }
            $compose = & docker compose version --short 2>$null
            if ($LASTEXITCODE -eq 0) { Write-Ok "Docker Compose $compose" } else { Write-Fail 'falta Docker Compose v2' }
        } else { Write-Caution 'Docker Desktop instalado pero parado (inícialo y espera a "Engine running")' }
    } else { Write-Caution 'Docker Desktop no está instalado' }

    $r = Invoke-Manager --version
    if ($r.Code -eq 0) { Write-Ok "Python y gestor: $($r.Output)" } else { Write-Caution 'Python 3.10+ no disponible (fase Deps)' }

    $vbox = Get-VBoxManage
    if ($vbox) {
        Write-Ok "VirtualBox $(& $vbox --version)"
        foreach ($i in (Get-HostOnlyInterface $vbox)) { Write-Info "Host-only: $($i.Name) $($i.IPAddress)" }
    } else { Write-Caution 'VirtualBox no está instalado' }

    foreach ($p in (Get-NetFirewallProfile)) {
        if ($p.Enabled) { Write-Ok "Firewall de Windows, perfil $($p.Name): activo" } else { Write-Fail "Firewall de Windows, perfil $($p.Name): DESACTIVADO" }
    }
    $free = (Get-PSDrive -Name $env:SystemDrive.TrimEnd(':')).Free / 1GB
    Write-Info ("Espacio libre en {0}: {1:N1} GB (las imágenes ocupan ~5 GB, más la VM de Kali)" -f $env:SystemDrive, $free)
}

function Invoke-PhaseDependency {
    Write-Step 'Dependencias'
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    $missing = @()
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { $missing += @{ Name = 'Docker Desktop'; Id = 'Docker.DockerDesktop' } }
    if ((Invoke-Manager --version).Code -ne 0) { $missing += @{ Name = 'Python 3.12'; Id = 'Python.Python.3.12' } }
    if (-not (Get-VBoxManage)) { $missing += @{ Name = 'VirtualBox'; Id = 'Oracle.VirtualBox' } }
    if ($missing.Count -eq 0) { Write-Ok 'Docker Desktop, Python y VirtualBox presentes'; return }
    foreach ($m in $missing) {
        Write-Caution "falta $($m.Name)"
        if ($winget -and (Confirm-Choice "¿Instalar $($m.Name) con winget ($($m.Id))?")) {
            & winget install -e --id $m.Id --accept-package-agreements --accept-source-agreements
            if ($LASTEXITCODE -ne 0) { Write-Fail "winget no pudo instalar $($m.Name)" }
        } else {
            Write-Info "Instálalo con: winget install -e --id $($m.Id)"
        }
    }
    Write-Info 'Docker Desktop necesita WSL2 ("wsl --install" como administrador) y reiniciar la sesión.'
    Write-Info 'Después de instalar, abre una terminal nueva para que se actualice el PATH.'
}

function Invoke-PhaseNetwork {
    Assert-Admin 'Network'
    Write-Step "Red de laboratorio (Host-only de VirtualBox, $LabIp/$Prefix)"
    $vbox = Get-VBoxManage
    if (-not $vbox) { Exit-WithError 'VirtualBox no está instalado' 'Ejecuta la fase Deps.' }
    $mask = Get-NetMask $Prefix
    $existing = Get-HostOnlyInterface $vbox | Where-Object { $_.IPAddress -eq $LabIp } | Select-Object -First 1
    $name = $null
    if ($existing) {
        $name = $existing.Name
        Write-Ok "se reutiliza la interfaz Host-only existente '$name' ($LabIp)"
    }
    $ownAlias = $null
    if ($name) { $ownAlias = (Get-NetAdapter -InterfaceDescription $name -ErrorAction SilentlyContinue).Name }
    $conflicts = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
        $_.InterfaceAlias -ne $ownAlias -and $_.IPAddress -notlike '127.*' -and
        (Test-SubnetOverlap $_.IPAddress $_.PrefixLength $LabIp $Prefix)
    }
    if ($conflicts) {
        Exit-WithError ("la subred $LabIp/$Prefix se solapa con: " + (($conflicts | ForEach-Object { "$($_.InterfaceAlias) ($($_.IPAddress)/$($_.PrefixLength))" }) -join ', ')) `
            'Elige otra subred privada libre con -LabIp (p. ej. 192.168.58.1).'
    }
    if (-not $name) {
        if (-not (Confirm-Choice "Se creará una interfaz Host-only nueva con IP $LabIp/$Prefix y DHCP. ¿Continuar?")) { Exit-WithError 'cancelado' '' 5 }
        $out = (& $vbox hostonlyif create 2>&1) -join "`n"
        if ($LASTEXITCODE -ne 0 -or $out -notmatch "Interface '([^']+)'") { Exit-WithError "no se pudo crear la interfaz: $out" }
        $name = $Matches[1]
        & $vbox hostonlyif ipconfig $name --ip $LabIp --netmask $mask
        if ($LASTEXITCODE -ne 0) { Exit-WithError "no se pudo configurar la IP de '$name'" }
        Add-InstallRecord 'vbox_hostonlyif' $name
        Write-Ok "creada '$name' con $LabIp/$Prefix"
    }
    # DHCP for Kali: server .2, pool .100-.199, no router (3) / DNS (6) option so
    # Kali keeps its default route on the NAT adapter.
    $dhcp = (& $vbox list dhcpservers) -join "`n"
    if ($dhcp -match [regex]::Escape("HostInterfaceNetworking-$name")) {
        Write-Ok "servidor DHCP de VirtualBox ya configurado para '$name' (no se modifica)"
    } else {
        $srv = Get-NthHost $LabIp $Prefix 1; $lo = Get-NthHost $LabIp $Prefix 99; $hi = Get-NthHost $LabIp $Prefix 198
        & $vbox dhcpserver add "--interface=$name" "--server-ip=$srv" "--netmask=$mask" "--lower-ip=$lo" "--upper-ip=$hi" `
            '--suppress-opt=3' '--suppress-opt=6' --enable
        if ($LASTEXITCODE -ne 0) { Exit-WithError "no se pudo activar el DHCP en '$name'" }
        Add-InstallRecord 'vbox_dhcp' $name
        Write-Ok "DHCP activado en '$name': $lo - $hi"
    }
    $alias = (Get-NetAdapter -InterfaceDescription $name -ErrorAction SilentlyContinue).Name
    if (-not $alias) { Exit-WithError "Windows no muestra el adaptador '$name'" 'Reinicia el equipo (el controlador de VirtualBox se instala al crear la interfaz) y repite la fase.' }
    # VirtualBox NAT is userspace (no host bridge): no --nat-interface. Note that
    # PowerShell 5.1 drops empty-string arguments to native programs.
    $r = Invoke-Manager config set-network --platform windows-virtualbox --ip $LabIp --prefix $Prefix --interface $alias
    if ($r.Code -ne 0) { Exit-WithError "no se pudo guardar la configuración: $($r.Output)" }
    Write-Ok "configuración guardada: interfaz '$alias' ($name)"
    Write-Info "Kali: adaptador 1 'Adaptador solo-anfitrión' -> '$name'; adaptador 2 'NAT' (docs/installation/windows.md)."
}

function Invoke-PhaseFirewall {
    Assert-Admin 'Firewall'
    Write-Step "Reglas del Firewall de Windows (grupo $FwGroup)"
    $r = Invoke-Manager config firewall-spec
    if ($r.Code -ne 0) { Exit-WithError "no se pudo obtener la especificación de reglas: $($r.Output)" 'Ejecuta antes la fase Network.' }
    $spec = $r.Output | ConvertFrom-Json
    $old = @(Get-NetFirewallRule -Group $FwGroup -ErrorAction SilentlyContinue)
    if ($old.Count -gt 0) {
        $old | Remove-NetFirewallRule
        Write-Info "eliminadas $($old.Count) reglas anteriores del grupo"
    }
    foreach ($rule in $spec) {
        $p = @{
            DisplayName = $rule.name; Group = $rule.group; Direction = $rule.direction; Action = $rule.action
            Profile = $rule.profile; Protocol = $rule.protocol; Enabled = 'True'
            LocalAddress = @($rule.local_address); RemoteAddress = @($rule.remote_address)
        }
        if ($rule.protocol -in @('TCP', 'UDP') -and @($rule.local_port)[0] -ne 'Any') { $p.LocalPort = @($rule.local_port) }
        if ($rule.protocol -eq 'ICMPv4' -and $rule.icmp_type -ne 'Any') { $p.IcmpType = $rule.icmp_type }
        if ($rule.interface_alias -ne 'Any') { $p.InterfaceAlias = $rule.interface_alias }
        New-NetFirewallRule @p | Out-Null
        Write-Ok $rule.name
    }
    Add-InstallRecord 'firewall_group' $FwGroup
    Write-Info 'El gestor verifica estas reglas en cada inicio. Si cambias puertos o la red, repite esta fase.'
}

function Invoke-PhaseImage {
    Write-Step 'Imágenes y recursos'
    if ((Invoke-ManagerVisible install all) -ne 0) { Exit-WithError 'la descarga no se completó' 'Comprueba la conexión y que Docker Desktop está en marcha; repite la fase.' }
}

function Invoke-PhaseValidate {
    Write-Step 'Validación'
    Invoke-ManagerVisible diagnose | Out-Null
    Write-Info 'Siguiente: .\manager.ps1 start y .\manager.ps1 network-check.'
    Write-Info 'Antes del primer uso, ejecuta la prueba de red: scripts\windows\poc-network.ps1 (docs/installation/windows.md).'
}

function Invoke-PhaseUninstall {
    Assert-Admin 'Uninstall'
    Write-Step 'Desinstalación (solo elementos creados por este instalador)'
    Write-Info 'Los laboratorios se detienen, pero sus volúmenes de datos no se borran (.\manager.ps1 reset para eso).'
    if (-not (Confirm-Choice '¿Continuar?' $false)) { Exit-WithError 'cancelado' '' 5 }
    Invoke-ManagerVisible stop all | Out-Null
    $rec = Get-InstallRecord
    if ($rec.firewall_group) {
        Get-NetFirewallRule -Group $rec.firewall_group -ErrorAction SilentlyContinue | Remove-NetFirewallRule
        Write-Ok "reglas del grupo $($rec.firewall_group) eliminadas"
    }
    $vbox = Get-VBoxManage
    if ($vbox -and $rec.vbox_dhcp) {
        & $vbox dhcpserver remove "--interface=$($rec.vbox_dhcp)"
        if ($LASTEXITCODE -eq 0) { Write-Ok "DHCP de '$($rec.vbox_dhcp)' eliminado" }
    }
    if ($vbox -and $rec.vbox_hostonlyif) {
        & $vbox hostonlyif remove $rec.vbox_hostonlyif
        if ($LASTEXITCODE -eq 0) { Write-Ok "interfaz '$($rec.vbox_hostonlyif)' eliminada" }
    }
    if (Test-Path $Record) { Remove-Item $Record }
    Write-Info "Las imágenes Docker se conservan: 'docker image ls' / 'docker image rm' para borrarlas."
}

function Invoke-Phase([string]$Name) {
    switch ($Name) {
        'Detect' { Invoke-PhaseDetect }
        'Deps' { Invoke-PhaseDependency }
        'Network' { Invoke-PhaseNetwork }
        'Firewall' { Invoke-PhaseFirewall }
        'Images' { Invoke-PhaseImage }
        'Validate' { Invoke-PhaseValidate }
        'Uninstall' { Invoke-PhaseUninstall }
    }
}

# ------------------------------------------------------------------- main ---
if ($env:WSL_DISTRO_NAME) { Exit-WithError 'no ejecutes el instalador dentro de WSL' 'Usa PowerShell de Windows.' }
if ($Phase) { Invoke-Phase $Phase; exit 0 }

Write-Host 'Instalador del laboratorio (Windows 11, NO PROBADO). Fase 1: detección' -ForegroundColor Cyan
Invoke-PhaseDetect
foreach ($p in @('Deps', 'Network', 'Firewall', 'Images', 'Validate')) {
    if (Confirm-Choice "¿Ejecutar la fase '$p'?") { Invoke-Phase $p } else { Write-Info "fase '$p' omitida" }
}
