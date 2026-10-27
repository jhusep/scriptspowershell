#requires -version 5.1

param(
    [switch]$Aplicar,
    [switch]$Restaurar
)

$ErrorActionPreference = "SilentlyContinue"

$Base = "C:\ProgramData\DriversFabricante"
$Backup = "$Base\Backup"
$Report = "$Base\Inventario.txt"

New-Item -ItemType Directory -Path $Base -Force | Out-Null
New-Item -ItemType Directory -Path $Backup -Force | Out-Null

function Es-Administrador {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)

    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

if (-not (Es-Administrador)) {
    Write-Host "Ejecuta PowerShell como Administrador."
    exit 1
}

if (-not $Aplicar -and -not $Restaurar) {
    Write-Host "Uso:"
    Write-Host "  .\configurar-drivers-fabricante.ps1 -Aplicar"
    Write-Host "  .\configurar-drivers-fabricante.ps1 -Restaurar"
    exit
}

if ($Aplicar) {
    Write-Host "Creando punto de restauración..."

    Checkpoint-Computer `
        -Description "Antes de configurar controladores" `
        -RestorePointType MODIFY_SETTINGS

    Write-Host "Exportando controladores actuales..."

    pnputil.exe /export-driver * "$Backup"

    Write-Host "Guardando inventario..."

    pnputil.exe /enum-drivers |
        Out-File -FilePath $Report -Encoding UTF8

    Get-PnpDevice -PresentOnly |
        Select-Object Status, Class, FriendlyName, InstanceId |
        Export-Csv "$Base\Dispositivos.csv" `
        -NoTypeInformation `
        -Encoding UTF8

    # Impedir que Windows Update incluya controladores
    $wuKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"

    New-Item -Path $wuKey -Force | Out-Null

    New-ItemProperty `
        -Path $wuKey `
        -Name ExcludeWUDriversInQualityUpdate `
        -PropertyType DWord `
        -Value 1 `
        -Force | Out-Null

    # Windows Update: notificar antes de descargar o instalar
    $auKey = "$wuKey\AU"

    New-Item -Path $auKey -Force | Out-Null

    New-ItemProperty `
        -Path $auKey `
        -Name AUOptions `
        -PropertyType DWord `
        -Value 2 `
        -Force | Out-Null

    New-ItemProperty `
        -Path $auKey `
        -Name NoAutoUpdate `
        -PropertyType DWord `
        -Value 0 `
        -Force | Out-Null

    # Evitar búsqueda automática de controladores en Windows Update
    $searchKey = `
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching"

    New-Item -Path $searchKey -Force | Out-Null

    New-ItemProperty `
        -Path $searchKey `
        -Name SearchOrderConfig `
        -PropertyType DWord `
        -Value 0 `
        -Force | Out-Null

    Set-Service wuauserv `
        -StartupType Manual `
        -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "Configuración terminada." -ForegroundColor Green
    Write-Host "Respaldo: $Backup"
    Write-Host "Inventario: $Report"
    Write-Host "Dispositivos: $Base\Dispositivos.csv"
    Write-Host ""
    Write-Host "Reinicia Windows."
    Write-Host ""
    Write-Host "No se eliminó ningún controlador."
}

if ($Restaurar) {
    $wuKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    $auKey = "$wuKey\AU"
    $searchKey = `
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching"

    Remove-ItemProperty `
        -Path $wuKey `
        -Name ExcludeWUDriversInQualityUpdate `
        -ErrorAction SilentlyContinue

    Remove-ItemProperty `
        -Path $auKey `
        -Name AUOptions `
        -ErrorAction SilentlyContinue

    Remove-ItemProperty `
        -Path $auKey `
        -Name NoAutoUpdate `
        -ErrorAction SilentlyContinue

    New-ItemProperty `
        -Path $searchKey `
        -Name SearchOrderConfig `
        -PropertyType DWord `
        -Value 1 `
        -Force | Out-Null

    Write-Host "Configuración restaurada."
    Write-Host "Windows podrá volver a buscar controladores automáticamente."
}
