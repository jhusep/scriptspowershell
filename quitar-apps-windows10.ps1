#requires -version 5.1

[CmdletBinding()]
param(
    [switch]$Aplicar,
    [ValidateSet('Cortana', 'Xbox', 'Office', 'Opcionales')]
    [string[]]$Categorias = @('Cortana', 'Xbox', 'Office', 'Opcionales'),
    [string[]]$Conservar = @()
)

$ErrorActionPreference = 'Stop'

# Nombres exactos: nunca se eliminan paquetes por comodines o por fabricante.
$catalogo = @(
    [pscustomobject]@{ Nombre = 'Microsoft.549981C3F5F10'; Categoria = 'Cortana' }
    [pscustomobject]@{ Nombre = 'Microsoft.XboxApp'; Categoria = 'Xbox' }
    [pscustomobject]@{ Nombre = 'Microsoft.GamingApp'; Categoria = 'Xbox' }
    [pscustomobject]@{ Nombre = 'Microsoft.XboxGameOverlay'; Categoria = 'Xbox' }
    [pscustomobject]@{ Nombre = 'Microsoft.XboxGamingOverlay'; Categoria = 'Xbox' }
    [pscustomobject]@{ Nombre = 'Microsoft.XboxIdentityProvider'; Categoria = 'Xbox' }
    [pscustomobject]@{ Nombre = 'Microsoft.XboxSpeechToTextOverlay'; Categoria = 'Xbox' }
    [pscustomobject]@{ Nombre = 'Microsoft.Xbox.TCUI'; Categoria = 'Xbox' }
    [pscustomobject]@{ Nombre = 'Microsoft.MicrosoftSolitaireCollection'; Categoria = 'Xbox' }
    [pscustomobject]@{ Nombre = 'Microsoft.MicrosoftOfficeHub'; Categoria = 'Office' }
    [pscustomobject]@{ Nombre = 'Microsoft.BingNews'; Categoria = 'Opcionales' }
    [pscustomobject]@{ Nombre = 'Microsoft.BingWeather'; Categoria = 'Opcionales' }
    [pscustomobject]@{ Nombre = 'Microsoft.GetHelp'; Categoria = 'Opcionales' }
    [pscustomobject]@{ Nombre = 'Microsoft.Getstarted'; Categoria = 'Opcionales' }
    [pscustomobject]@{ Nombre = 'Microsoft.Microsoft3DViewer'; Categoria = 'Opcionales' }
    [pscustomobject]@{ Nombre = 'Microsoft.MixedReality.Portal'; Categoria = 'Opcionales' }
    [pscustomobject]@{ Nombre = 'Microsoft.People'; Categoria = 'Opcionales' }
    [pscustomobject]@{ Nombre = 'Microsoft.Print3D'; Categoria = 'Opcionales' }
    [pscustomobject]@{ Nombre = 'Microsoft.SkypeApp'; Categoria = 'Opcionales' }
    [pscustomobject]@{ Nombre = 'Microsoft.WindowsFeedbackHub'; Categoria = 'Opcionales' }
    [pscustomobject]@{ Nombre = 'Microsoft.WindowsMaps'; Categoria = 'Opcionales' }
    [pscustomobject]@{ Nombre = 'Microsoft.YourPhone'; Categoria = 'Opcionales' }
    [pscustomobject]@{ Nombre = 'Microsoft.ZuneMusic'; Categoria = 'Opcionales' }
    [pscustomobject]@{ Nombre = 'Microsoft.ZuneVideo'; Categoria = 'Opcionales' }
    [pscustomobject]@{ Nombre = 'Clipchamp.Clipchamp'; Categoria = 'Opcionales' }
)

function Es-Administrador {
    $identidad = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identidad)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$administrador = Es-Administrador
if ($Aplicar -and -not $administrador) {
    throw 'Abre Windows PowerShell como administrador para usar -Aplicar.'
}

if ($administrador) {
    $instalados = @(Get-AppxPackage -AllUsers)
    $provisionados = @(Get-AppxProvisionedPackage -Online)
}
else {
    Write-Warning 'Se muestran solo las apps de esta cuenta. Abre PowerShell como administrador para ver todos los usuarios y las apps provisionadas.'
    $instalados = @(Get-AppxPackage)
    $provisionados = @()
}

$seleccionados = @($catalogo | Where-Object {
    $Categorias -contains $_.Categoria -and $Conservar -notcontains $_.Nombre
})
$hallazgos = @(
    foreach ($objetivo in $seleccionados) {
        $coincidencias = @($instalados | Where-Object { $_.Name -eq $objetivo.Nombre })
        $bloqueado = @($coincidencias | Where-Object {
            $_.NonRemovable -or $_.IsFramework -or $_.IsResourcePackage
        }).Count -gt 0
        foreach ($paquete in $coincidencias) {
            [pscustomobject]@{
                Categoria = $objetivo.Categoria
                Nombre = $objetivo.Nombre
                Tipo = 'Instalado'
                Paquete = $paquete.PackageFullName
                Removible = -not ($paquete.NonRemovable -or $paquete.IsFramework -or $paquete.IsResourcePackage)
            }
        }
        foreach ($paquete in ($provisionados | Where-Object { $_.DisplayName -eq $objetivo.Nombre })) {
            [pscustomobject]@{
                Categoria = $objetivo.Categoria
                Nombre = $objetivo.Nombre
                Tipo = 'Provisionado'
                Paquete = $paquete.PackageName
                Removible = -not $bloqueado
            }
        }
    }
)

Write-Host "`n=== APLICACIONES DE LA LISTA ENCONTRADAS ===" -ForegroundColor Cyan
if ($hallazgos.Count -gt 0) {
    $hallazgos | Select-Object Categoria, Nombre, Tipo, Removible | Format-Table -AutoSize
}
else {
    Write-Host 'No se encontraron paquetes de las categorias elegidas.'
}

$rutasOffice = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$officeEscritorio = @(
    Get-ItemProperty -Path $rutasOffice -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match '^(Microsoft 365|Microsoft Office|Office 365)' } |
        Select-Object -Property DisplayName, Publisher -Unique
)
if ($officeEscritorio.Count -gt 0) {
    Write-Host "`n=== OFFICE DE ESCRITORIO: REVISION MANUAL ===" -ForegroundColor Yellow
    $officeEscritorio | Format-Table -AutoSize
    Write-Host 'Este script no desinstala Office de escritorio porque podria tener licencia o documentos asociados.'
}

if (-not $Aplicar) {
    Write-Host "`nDiagnostico terminado. Ejecuta -Aplicar para quitar los paquetes mostrados."
    exit
}

if ($hallazgos.Count -eq 0) {
    Write-Host 'No hay paquetes de la lista para quitar.'
    exit
}

$carpeta = Join-Path $env:ProgramData 'LaptopLigera\Apps'
New-Item -ItemType Directory -Path $carpeta -Force | Out-Null
$fecha = Get-Date -Format 'yyyyMMdd-HHmmss'
$inventario = Join-Path $carpeta ("Inventario-{0}.csv" -f $fecha)
$resultado = Join-Path $carpeta ("Resultado-{0}.csv" -f $fecha)
$hallazgos | Export-Csv -LiteralPath $inventario -NoTypeInformation -Encoding UTF8
Write-Host ('Inventario previo: {0}' -f $inventario)

try {
    Checkpoint-Computer -Description 'Antes de quitar apps opcionales' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop | Out-Null
    Write-Host 'Punto de restauracion creado.'
}
catch {
    Write-Warning ('No se pudo crear el punto de restauracion: {0}' -f $_.Exception.Message)
}

$resultados = New-Object 'System.Collections.Generic.List[object]'
foreach ($app in $hallazgos) {
    $estado = 'Eliminado'
    $detalle = ''
    if (-not $app.Removible) {
        $estado = 'Omitido'
        $detalle = 'Windows marca este paquete o su app instalada como no removible, framework o recurso.'
    }
    else {
        try {
            if ($app.Tipo -eq 'Instalado') {
                Remove-AppxPackage -Package $app.Paquete -AllUsers -ErrorAction Stop
            }
            else {
                Remove-AppxProvisionedPackage -Online -PackageName $app.Paquete -ErrorAction Stop | Out-Null
            }
        }
        catch {
            $estado = 'Error'
            $detalle = $_.Exception.Message
        }
    }
    $resultados.Add([pscustomobject]@{
        Categoria = $app.Categoria
        Nombre = $app.Nombre
        Tipo = $app.Tipo
        Paquete = $app.Paquete
        Estado = $estado
        Detalle = $detalle
    })
    Write-Host ('{0}: {1} ({2})' -f $estado, $app.Nombre, $app.Tipo)
}

$resultados | Export-Csv -LiteralPath $resultado -NoTypeInformation -Encoding UTF8
$errores = @($resultados | Where-Object { $_.Estado -eq 'Error' }).Count
Write-Host ('Resultado: {0}. Errores: {1}.' -f $resultado, $errores)
Write-Host 'Reinicia Windows para comprobar el resultado. Office de escritorio se desinstala manualmente desde Aplicaciones y caracteristicas.'
if ($errores -gt 0) { exit 1 }
