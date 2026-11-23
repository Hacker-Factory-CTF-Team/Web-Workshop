#Requires -Version 5.1
<#
.SYNOPSIS
    Punto de entrada del gestor del laboratorio en Windows (equivalente a ./manager en Linux).
.DESCRIPTION
    Busca Python 3.10 o superior y ejecuta el paquete src/pentestlab con los argumentos recibidos.
    Ejemplos:
        .\manager.ps1 list
        .\manager.ps1 start dvwa
        .\manager.ps1 --help
#>
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Find-Python {
    # The Microsoft Store stub (WindowsApps\python.exe) fails the version test, so it is skipped.
    $candidates = @(@('py', '-3'), @('python'), @('python3'))
    foreach ($c in $candidates) {
        if (-not (Get-Command $c[0] -ErrorAction SilentlyContinue)) { continue }
        $pre = @()
        if ($c.Count -gt 1) { $pre = $c[1..($c.Count - 1)] }
        & $c[0] @pre -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>$null
        if ($LASTEXITCODE -eq 0) {
            $found = @($c[0]) + $pre
            return , $found
        }
    }
    return $null
}

$py = Find-Python
if (-not $py) {
    [Console]::Error.WriteLine('ERROR: se necesita Python 3.10 o superior.')
    [Console]::Error.WriteLine('Cómo solucionarlo: winget install -e --id Python.Python.3.12 (y abre una terminal nueva).')
    exit 4
}

$env:PYTHONPATH = (Join-Path $here 'src') + $(if ($env:PYTHONPATH) { ";$env:PYTHONPATH" } else { '' })
$env:PYTHONUTF8 = '1'
$exe = $py[0]
$pre = @()
if ($py.Count -gt 1) { $pre = $py[1..($py.Count - 1)] }
& $exe @pre -m pentestlab @args
exit $LASTEXITCODE
