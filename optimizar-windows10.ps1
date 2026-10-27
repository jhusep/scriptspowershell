#requires -version 5.1

[CmdletBinding()]
param(
    [switch]$Diagnostico,
    [switch]$Aplicar,
    [switch]$SoloLimpieza,
    [switch]$Restaurar,
    [switch]$OptimizarDisco
)

$ErrorActionPreference = 'Stop'
$BaseDir = Join-Path $env:LOCALAPPDATA 'LaptopLigera'
$LogFile = Join-Path $BaseDir 'optimizacion.log'
$TaskName = 'LaptopLigera - Limpieza semanal'

function Log {
    param([string]$Texto)
    Write-Host $Texto
    try {
        New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
        Add-Content -Path $LogFile -Value ('{0} - {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Texto)
    }
    catch {
        Write-Warning ('No se pudo guardar el registro: {0}' -f $_.Exception.Message)
    }
}

function Es-Administrador {
    $usuario = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($usuario)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Limpiar-Temporales {
    $limite = (Get-Date).AddDays(-7)
    $eliminados = 0
    Get-ChildItem -LiteralPath $env:TEMP -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $limite } |
        ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path -LiteralPath $_.FullName)) { $eliminados++ }
        }
    Log ('Limpieza de temporales del usuario terminada. Elementos eliminados: {0}' -f $eliminados)
}

if ($OptimizarDisco -and -not $Aplicar) {
    Write-Error 'Usa -OptimizarDisco junto con -Aplicar.'
    exit 1
}

if (-not $Diagnostico -and -not $Aplicar -and -not $SoloLimpieza -and -not $Restaurar) {
    $Diagnostico = $true
}

if ($SoloLimpieza) {
    Limpiar-Temporales
    exit
}

if ($Diagnostico) {
    $sistema = Get-CimInstance Win32_ComputerSystem
    $cpu = Get-CimInstance Win32_Processor
    $gpus = @(Get-CimInstance Win32_VideoController)
    $discos = @(Get-CimInstance Win32_DiskDrive)

    Write-Host '=== PERFIL DEL EQUIPO ===' -ForegroundColor Cyan
    Write-Host ('CPU: {0}' -f $cpu.Name)
    Write-Host ('RAM: {0} GB' -f ([math]::Round($sistema.TotalPhysicalMemory / 1GB, 2)))
    $gpus | Select-Object Name, DriverVersion, @{Name='VRAM_GB_informada';Expression={ [math]::Round($_.AdapterRAM / 1GB, 2) }} | Format-Table -AutoSize
    $discos | Select-Object Model, MediaType, @{Name='Size_GB';Expression={ [math]::Round($_.Size / 1GB, 2) }} | Format-Table -AutoSize

    if ($cpu.Name -notmatch 'Ryzen\s+3\s+3200U') {
        Write-Warning 'No se detecto el Ryzen 3 3200U indicado. Comprueba que estas en el equipo esperado.'
    }
    if (-not ($gpus.Name -match 'Vega.*3') -or -not ($gpus.Name -match 'Radeon.*530')) {
        Write-Warning 'No se detectaron ambas GPU esperadas. Revisa los controladores del fabricante.'
    }
    if (-not ($discos.Model -match 'ST1000LM035')) {
        Write-Warning 'No se detecto el HDD ST1000LM035. El disco puede haberse reemplazado.'
    }

    Write-Host '=== PROGRAMAS DE INICIO ===' -ForegroundColor Cyan
    Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue |
        Select-Object Name, Command, Location |
        Format-Table -Wrap -AutoSize

    Write-Host 'Diagnostico terminado. No se hicieron cambios.'
    Write-Host 'Para aplicar los ajustes conservadores, usa -Aplicar como administrador.'
    exit
}

if (-not (Es-Administrador)) {
    Write-Error 'Abre PowerShell como administrador y vuelve a ejecutar el script.'
    exit 1
}

if ($Restaurar) {
    Log 'Restaurando los efectos visuales y ajustes de versiones anteriores...'
    $visual = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
    $explorer = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    New-Item -Path $visual -Force | Out-Null
    New-Item -Path $explorer -Force | Out-Null
    New-Item -Path $personalize -Force | Out-Null
    New-ItemProperty -Path $visual -Name VisualFXSetting -PropertyType DWord -Value 0 -Force | Out-Null
    New-ItemProperty -Path $explorer -Name TaskbarAnimations -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path $personalize -Name EnableTransparency -PropertyType DWord -Value 1 -Force | Out-Null
    Set-Service SysMain -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service SysMain -ErrorAction SilentlyContinue
    Set-Service WSearch -StartupType Automatic -ErrorAction SilentlyContinue
    $updateKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
    Remove-ItemProperty -Path $updateKey -Name AUOptions -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $updateKey -Name NoAutoUpdate -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Log 'Restauracion terminada. Reinicia Windows.'
    exit
}

if ($Aplicar) {
    Log 'Aplicando perfil conservador de bajo consumo.'
    try {
        Checkpoint-Computer -Description 'Antes de optimizar laptop' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Log 'Punto de restauracion creado.'
    }
    catch {
        Write-Warning ('No se pudo crear el punto de restauracion: {0}' -f $_.Exception.Message)
    }

    try {
        $sistema = Get-CimInstance Win32_ComputerSystem
        if (-not $sistema.AutomaticManagedPagefile) {
            Set-CimInstance -InputObject $sistema -Property @{ AutomaticManagedPagefile = $true } | Out-Null
            Log 'Archivo de paginacion automatico activado.'
        }
        else {
            Log 'Archivo de paginacion automatico ya estaba activado.'
        }

        $visual = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
        $explorer = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        $personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        New-Item -Path $visual -Force | Out-Null
        New-Item -Path $explorer -Force | Out-Null
        New-Item -Path $personalize -Force | Out-Null
        New-ItemProperty -Path $visual -Name VisualFXSetting -PropertyType DWord -Value 2 -Force | Out-Null
        New-ItemProperty -Path $explorer -Name TaskbarAnimations -PropertyType DWord -Value 0 -Force | Out-Null
        New-ItemProperty -Path $personalize -Name EnableTransparency -PropertyType DWord -Value 0 -Force | Out-Null
        Log 'Efectos visuales reducidos.'
    }
    catch {
        Write-Error ('No se pudieron aplicar los ajustes: {0}' -f $_.Exception.Message)
        exit 1
    }

    Limpiar-Temporales
    Log 'No se fuerza la Radeon 530: Windows elige la GPU para cada aplicacion.'
    Log 'Para juegos, elige Radeon 530 por aplicacion en Configuracion > Sistema > Pantalla > Configuracion de graficos.'

    if ($OptimizarDisco) {
        $letra = $env:SystemDrive.TrimEnd(':')
        try {
            Optimize-Volume -DriveLetter $letra -Analyze -ErrorAction Stop | Out-Null
            Optimize-Volume -DriveLetter $letra -Verbose -ErrorAction Stop
            Log 'Optimizacion del disco terminada.'
        }
        catch {
            Write-Error ('No se pudo optimizar el disco: {0}' -f $_.Exception.Message)
            exit 1
        }
    }

    Log 'Perfil aplicado. Reinicia Windows para completar los cambios.'
}
