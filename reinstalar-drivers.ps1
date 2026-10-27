#requires -version 5.1

[CmdletBinding()]
param(
    [ValidateSet('Preparar', 'Reinstalar', 'Recuperar')]
    [string]$Accion = 'Preparar',
    [string]$CarpetaDrivers,
    [string]$CarpetaTrabajo = "$env:ProgramData\DriversFabricante\Reinstalacion",
    [switch]$ConfirmarBorrado
)

$ErrorActionPreference = 'Stop'
$respaldo = Join-Path $CarpetaTrabajo 'Respaldo'
$inventario = Join-Path $CarpetaTrabajo 'Inventario.csv'
$dispositivos = Join-Path $CarpetaTrabajo 'Dispositivos.csv'
$registro = Join-Path $CarpetaTrabajo 'Operaciones.log'
$estadoFinal = Join-Path $CarpetaTrabajo 'DispositivosDespues.csv'

# Clases que pueden ser necesarias para iniciar Windows o conservar acceso local.
$clasesProtegidas = @(
    'System', 'Net', 'HDC', 'SCSIAdapter', 'DiskDrive', 'Volume',
    'Keyboard', 'Mouse', 'HIDClass', 'USB', 'USBDevice', 'USBController',
    'Computer', 'Firmware', 'SecurityDevices', 'Battery'
)

function Registrar {
    param([string]$Mensaje)
    Write-Host $Mensaje
    Add-Content -LiteralPath $registro -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Mensaje)
}

function Invocar-PnpUtil {
    param([string[]]$Argumentos)
    $salida = & pnputil.exe @Argumentos 2>&1
    $codigo = $LASTEXITCODE
    foreach ($linea in $salida) { Registrar ([string]$linea) }
    return $codigo
}

function Instalar-DesdeCarpeta {
    param([string]$Ruta)
    if (-not (Test-Path -LiteralPath $Ruta -PathType Container)) {
        throw ('No existe la carpeta de controladores: {0}' -f $Ruta)
    }
    $inf = @(Get-ChildItem -LiteralPath $Ruta -Filter '*.inf' -Recurse -File)
    if ($inf.Count -eq 0) {
        throw ('No se encontraron archivos .inf en {0}' -f $Ruta)
    }
    Registrar ('Instalando {0} paquetes INF desde {1}' -f $inf.Count, $Ruta)
    $patron = Join-Path $Ruta '*.inf'
    $codigo = Invocar-PnpUtil -Argumentos @('/add-driver', $patron, '/subdirs', '/install')
    if ($codigo -ne 0) { throw ('PnPUtil no pudo instalar los controladores (codigo {0}).' -f $codigo) }
}

$identidad = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identidad)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Abre PowerShell como administrador.'
}

New-Item -ItemType Directory -Path $CarpetaTrabajo -Force | Out-Null

if ($Accion -eq 'Preparar') {
    if (Test-Path -LiteralPath $inventario -PathType Leaf) {
        throw ('Ya existe un inventario en {0}. Usa otra -CarpetaTrabajo para una preparacion nueva.' -f $CarpetaTrabajo)
    }
    New-Item -ItemType Directory -Path $respaldo -Force | Out-Null
    Registrar 'Creando inventario de controladores de terceros...'
    $paquetes = @(Get-WindowsDriver -Online | Where-Object { $_.Driver -match '^oem\d+\.inf$' })
    if ($paquetes.Count -eq 0) { throw 'No se encontraron paquetes OEM para inventariar.' }

    $paquetes | Sort-Object Driver | ForEach-Object {
        $eliminar = 'Si'
        if ($clasesProtegidas -contains $_.ClassName) { $eliminar = 'No' }
        [pscustomobject]@{
            Driver = $_.Driver
            Clase = $_.ClassName
            Proveedor = $_.ProviderName
            ArchivoOriginal = $_.OriginalFileName
            Eliminar = $eliminar
        }
    } | Export-Csv -LiteralPath $inventario -NoTypeInformation -Encoding UTF8

    Get-PnpDevice -PresentOnly | Select-Object Status, Class, FriendlyName, InstanceId |
        Export-Csv -LiteralPath $dispositivos -NoTypeInformation -Encoding UTF8

    Registrar 'Exportando los controladores de terceros actuales...'
    $codigo = Invocar-PnpUtil -Argumentos @('/export-driver', '*', $respaldo)
    if ($codigo -ne 0) { throw ('No se pudo completar el respaldo (codigo {0}).' -f $codigo) }
    if (@(Get-ChildItem -LiteralPath $respaldo -Filter '*.inf' -Recurse -File).Count -eq 0) {
        throw 'El respaldo no contiene archivos INF. No continues con Reinstalar.'
    }

    try {
        Checkpoint-Computer -Description 'Antes de reinstalar controladores OEM' -RestorePointType MODIFY_SETTINGS | Out-Null
        Registrar 'Punto de restauracion creado.'
    }
    catch {
        Registrar ('No se pudo crear el punto de restauracion: {0}' -f $_.Exception.Message)
    }
    Registrar ('Inventario para revisar: {0}' -f $inventario)
    Registrar ('Respaldo: {0}' -f $respaldo)
    Registrar 'Descarga antes los controladores del fabricante y extrae sus archivos INF.'
    exit
}

if ($Accion -eq 'Recuperar') {
    Instalar-DesdeCarpeta -Ruta $respaldo
    Registrar 'Respaldo reinstalado. Reinicia Windows y comprueba el Administrador de dispositivos.'
    exit
}

if (-not $ConfirmarBorrado) {
    throw 'Para reinstalar, usa -ConfirmarBorrado despues de revisar Inventario.csv y preparar los INF nuevos.'
}
if (-not (Test-Path -LiteralPath $inventario -PathType Leaf)) {
    throw 'Falta Inventario.csv. Ejecuta primero -Accion Preparar.'
}
if (-not $CarpetaDrivers) { throw 'Indica -CarpetaDrivers con los INF nuevos del fabricante.' }
$carpetaNueva = (Resolve-Path -LiteralPath $CarpetaDrivers).ProviderPath
if (@(Get-ChildItem -LiteralPath $carpetaNueva -Filter '*.inf' -Recurse -File).Count -eq 0) {
    throw 'La carpeta de instaladores nuevos no contiene archivos INF.'
}
if (@(Get-ChildItem -LiteralPath $respaldo -Filter '*.inf' -Recurse -File).Count -eq 0) {
    throw 'Falta el respaldo exportado. Ejecuta primero -Accion Preparar.'
}

$seleccion = @(Import-Csv -LiteralPath $inventario | Where-Object { $_.Eliminar -eq 'Si' })
if ($seleccion.Count -eq 0) { throw 'Inventario.csv no tiene paquetes marcados con Eliminar=Si.' }
$actuales = @{}
Get-WindowsDriver -Online | ForEach-Object { $actuales[$_.Driver] = $_ }
$fallos = 0

foreach ($paquete in $seleccion) {
    if ($paquete.Driver -notmatch '^oem\d+\.inf$') {
        Registrar ('Nombre de paquete no valido; omitido: {0}' -f $paquete.Driver)
        $fallos++
        continue
    }
    if (-not $actuales.ContainsKey($paquete.Driver)) {
        Registrar ('Ya no esta instalado; omitido: {0}' -f $paquete.Driver)
        continue
    }
    $claseActual = $actuales[$paquete.Driver].ClassName
    if ([string]::IsNullOrWhiteSpace($claseActual) -or $clasesProtegidas -contains $claseActual) {
        Registrar ('Clase protegida; omitido: {0} ({1})' -f $paquete.Driver, $claseActual)
        continue
    }
    Registrar ('Desinstalando {0} ({1})' -f $paquete.Driver, $claseActual)
    $codigo = Invocar-PnpUtil -Argumentos @('/delete-driver', $paquete.Driver, '/uninstall')
    if ($codigo -ne 0) {
        Registrar ('No se pudo quitar {0} (codigo {1}).' -f $paquete.Driver, $codigo)
        $fallos++
    }
}

try {
    Instalar-DesdeCarpeta -Ruta $carpetaNueva
}
catch {
    Registrar ('Fallo la instalacion nueva: {0}' -f $_.Exception.Message)
    Registrar 'Intentando recuperar desde el respaldo...'
    Instalar-DesdeCarpeta -Ruta $respaldo
    throw 'Se recuperaron los paquetes del respaldo. Revisa el registro antes de reiniciar.'
}

Registrar ('Proceso terminado. Paquetes que no se pudieron quitar: {0}' -f $fallos)
Get-PnpDevice -PresentOnly | Select-Object Status, Class, FriendlyName, InstanceId |
    Export-Csv -LiteralPath $estadoFinal -NoTypeInformation -Encoding UTF8
Registrar ('Inventario posterior: {0}' -f $estadoFinal)
Registrar 'Reinicia Windows y comprueba todos los dispositivos. Los instaladores EXE del fabricante se ejecutan por separado.'
