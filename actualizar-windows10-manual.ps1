#requires -version 5.1

[CmdletBinding()]
param(
    [switch]$Aplicar,
    [switch]$RestaurarPolitica
)

$ErrorActionPreference = 'Stop'
$RutaPolitica = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
$CarpetaEstado = Join-Path $env:ProgramData 'LaptopLigera\Actualizaciones'
$RespaldoPolitica = Join-Path $CarpetaEstado 'PoliticaOriginal.json'
$Registro = Join-Path $CarpetaEstado 'Historial.log'

function Es-Administrador {
    $identidad = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identidad)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Informar {
    param([string]$Mensaje)
    Write-Host $Mensaje
    if (Test-Path -LiteralPath $CarpetaEstado -PathType Container) {
        try {
            Add-Content -LiteralPath $Registro -Value ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Mensaje)
        }
        catch {
            Write-Warning ('No se pudo escribir el registro: {0}' -f $_.Exception.Message)
        }
    }
}

function Leer-ValorPolitica {
    param([string]$Nombre)
    return (Get-ItemPropertyValue -Path $RutaPolitica -Name $Nombre -ErrorAction SilentlyContinue)
}

function Guardar-PoliticaOriginal {
    New-Item -ItemType Directory -Path $CarpetaEstado -Force | Out-Null
    if (Test-Path -LiteralPath $RespaldoPolitica -PathType Leaf) { return }
    [pscustomobject]@{
        AUOptions = (Leer-ValorPolitica -Nombre 'AUOptions')
        NoAutoUpdate = (Leer-ValorPolitica -Nombre 'NoAutoUpdate')
    } | ConvertTo-Json | Set-Content -LiteralPath $RespaldoPolitica -Encoding UTF8
    Informar ('Politica original guardada en {0}' -f $RespaldoPolitica)
}

function Configurar-AvisoManual {
    Guardar-PoliticaOriginal
    New-Item -Path $RutaPolitica -Force | Out-Null
    New-ItemProperty -Path $RutaPolitica -Name AUOptions -PropertyType DWord -Value 2 -Force | Out-Null
    New-ItemProperty -Path $RutaPolitica -Name NoAutoUpdate -PropertyType DWord -Value 0 -Force | Out-Null
    Informar 'Windows Update configurado para avisar antes de descargar otras actualizaciones.'
}

function Restaurar-Politica {
    if (-not (Test-Path -LiteralPath $RespaldoPolitica -PathType Leaf)) {
        throw 'No existe respaldo de la politica de Windows Update.'
    }
    $original = Get-Content -LiteralPath $RespaldoPolitica -Raw | ConvertFrom-Json
    foreach ($nombre in @('AUOptions', 'NoAutoUpdate')) {
        $valor = $original.$nombre
        if ($null -eq $valor) {
            Remove-ItemProperty -Path $RutaPolitica -Name $nombre -ErrorAction SilentlyContinue
        }
        else {
            New-Item -Path $RutaPolitica -Force | Out-Null
            New-ItemProperty -Path $RutaPolitica -Name $nombre -PropertyType DWord -Value ([int]$valor) -Force | Out-Null
        }
    }
    Informar 'Politica anterior de Windows Update restaurada.'
}

function Hay-ReinicioPendiente {
    return ((Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
        (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'))
}

if ($Aplicar -and $RestaurarPolitica) {
    throw 'Usa -Aplicar o -RestaurarPolitica, no ambos.'
}

$sistema = Get-CimInstance Win32_OperatingSystem
if ($sistema.Caption -notmatch 'Windows 10' -or [int]$sistema.BuildNumber -ge 22000) {
    throw ('Este script solo admite Windows 10. Sistema detectado: {0}, compilacion {1}.' -f $sistema.Caption, $sistema.BuildNumber)
}

if (($Aplicar -or $RestaurarPolitica) -and -not (Es-Administrador)) {
    throw 'Abre Windows PowerShell como administrador para cambiar la politica o instalar la actualizacion.'
}

if ($RestaurarPolitica) {
    Restaurar-Politica
    exit
}

if ($Aplicar) {
    Configurar-AvisoManual
}

Informar ('Sistema: {0} (compilacion {1}). Buscando actualizaciones aplicables...' -f $sistema.Caption, $sistema.BuildNumber)
$sesion = New-Object -ComObject 'Microsoft.Update.Session'
$sesion.ClientApplicationID = 'LaptopLigera - Actualizacion acumulativa unica'
$buscador = $sesion.CreateUpdateSearcher()
$busqueda = $buscador.Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
if ([int]$busqueda.ResultCode -ne 2) {
    throw ('La busqueda de Windows Update no termino correctamente. Codigo: {0}.' -f $busqueda.ResultCode)
}

$pendientes = @()
$candidatas = @()
for ($i = 0; $i -lt $busqueda.Updates.Count; $i++) {
    $actualizacion = $busqueda.Updates.Item($i)
    $kb = @()
    for ($j = 0; $j -lt $actualizacion.KBArticleIDs.Count; $j++) {
        $kb += ('KB{0}' -f $actualizacion.KBArticleIDs.Item($j))
    }
    $entrada = [pscustomobject]@{
        Titulo = [string]$actualizacion.Title
        KB = ($kb -join ', ')
        Fecha = [datetime]$actualizacion.LastDeploymentChangeTime
        Id = [string]$actualizacion.Identity.UpdateID
        Actualizacion = $actualizacion
    }
    $pendientes += $entrada
    if ($entrada.Titulo -match '(?i)(Cumulative Update|Actualizaci.n acumulativa).*Windows 10' -and
        $entrada.Titulo -notmatch '(?i)(Preview|Vista previa|\.NET|Framework|Dynamic Update|Actualizaci.n din.mica|Server)' -and
        -not $actualizacion.IsBeta) {
        $candidatas += $entrada
    }
}

Informar ('Actualizaciones de software pendientes detectadas: {0}.' -f $pendientes.Count)
if ($candidatas.Count -eq 0) {
    Informar 'No se ofrece ninguna actualizacion acumulativa de Windows 10 para este equipo. Puede faltar acceso a ESU o ser necesaria otra version o requisito previo.'
    if ($Aplicar) { Informar 'Las demas actualizaciones quedan en modo de aviso manual.' }
    exit 1
}

$elegida = $candidatas | Sort-Object Fecha -Descending | Select-Object -First 1
Informar ('Seleccionada: {0} | {1} | publicada {2:yyyy-MM-dd}' -f $elegida.Titulo, $elegida.KB, $elegida.Fecha)
$otras = @($pendientes | Where-Object { $_.Id -ne $elegida.Id })
Informar ('Otras actualizaciones pendientes que este script no instalara: {0}.' -f $otras.Count)
foreach ($otra in $otras) {
    Write-Host ('  - {0}' -f $otra.Titulo)
}

if (-not $Aplicar) {
    Informar 'Diagnostico terminado. Ejecuta -Aplicar como administrador para descargar e instalar solo la seleccionada.'
    exit
}

$plan = [pscustomobject]@{
    Fecha = (Get-Date).ToString('s')
    Seleccionada = [pscustomobject]@{ Titulo = $elegida.Titulo; KB = $elegida.KB; Id = $elegida.Id }
    OtrasPendientes = @($otras | ForEach-Object { [pscustomobject]@{ Titulo = $_.Titulo; KB = $_.KB; Id = $_.Id } })
}
$rutaPlan = Join-Path $CarpetaEstado ('Plan-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$plan | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $rutaPlan -Encoding UTF8
Informar ('Plan guardado en {0}' -f $rutaPlan)

if (Hay-ReinicioPendiente) {
    throw 'Hay un reinicio pendiente de Windows. Reinicia y vuelve a ejecutar -Aplicar antes de instalar otra actualizacion.'
}

$paquete = $elegida.Actualizacion
if ($paquete.InstallationBehavior.CanRequestUserInput) {
    throw 'La actualizacion seleccionada requiere interaccion del usuario; instalala desde Configuracion > Windows Update.'
}
if (-not $paquete.EulaAccepted) {
    throw 'La actualizacion seleccionada requiere aceptar una licencia; instalala desde Configuracion > Windows Update.'
}

$coleccion = New-Object -ComObject 'Microsoft.Update.UpdateColl'
$coleccion.Add($paquete) | Out-Null
$instalador = $sesion.CreateUpdateInstaller()
$instalador.Updates = $coleccion
if ($instalador.IsBusy -or $instalador.RebootRequiredBeforeInstallation) {
    throw 'Windows Update esta ocupado o requiere reiniciar antes de instalar. Intenta de nuevo tras reiniciar.'
}

if (-not $paquete.IsDownloaded) {
    Informar 'Descargando solo la actualizacion seleccionada...'
    $descargador = $sesion.CreateUpdateDownloader()
    $descargador.Updates = $coleccion
    $descarga = $descargador.Download()
    if ([int]$descarga.ResultCode -ne 2 -or -not $paquete.IsDownloaded) {
        $detalle = $descarga.GetUpdateResult(0)
        throw ('Fallo la descarga. Codigo {0}; HRESULT {1}.' -f $detalle.ResultCode, $detalle.HResult)
    }
}

Informar 'Instalando solo la actualizacion seleccionada...'
$instalacion = $instalador.Install()
$resultado = $instalacion.GetUpdateResult(0)
if ([int]$resultado.ResultCode -ne 2) {
    throw ('Fallo la instalacion. Codigo {0}; HRESULT {1}.' -f $resultado.ResultCode, $resultado.HResult)
}
Informar ('Instalacion completada: {0}. Reinicio requerido: {1}.' -f $elegida.KB, $instalacion.RebootRequired)
Informar 'Las otras actualizaciones siguen pendientes; Windows Update debe avisar antes de descargarlas.'
