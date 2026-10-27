#requires -version 5.1

param(
    [switch]$Diagnostico,
    [switch]$Aplicar,
    [switch]$SoloLimpieza,
    [switch]$Restaurar
)

$ErrorActionPreference = "SilentlyContinue"

$BaseDir = "$env:ProgramData\LaptopLigera"
$LogFile = "$BaseDir\optimización.log"
$TaskName = "LaptopLigera - Limpieza semanal"
$ManagedScript = "$BaseDir\optimizar-windows10.ps1"

New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null

function Log {
    param([string]$Texto)

    $linea = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Texto"
    Add-Content -Path $LogFile -Value $linea
    Write-Host $Texto
}

function Es-Administrador {
    $usuario = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($usuario)

    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Limpiar-Temporales {
    Log "Limpiando archivos temporales..."

    $rutas = @(
        "$env:WINDIR\Temp"
    )

    $usuarios = Get-ChildItem "$env:SystemDrive\Users" -Directory

    foreach ($usuario in $usuarios) {
        $rutas += "$($usuario.FullName)\AppData\Local\Temp"
    }

    foreach ($ruta in $rutas) {
        if (Test-Path $ruta) {
            Get-ChildItem $ruta -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Start-Process cleanmgr.exe `
        -ArgumentList "/VERYLOWDISK" `
        -Wait `
        -WindowStyle Hidden `
        -ErrorAction SilentlyContinue

    Log "Limpieza terminada."
}

if (-not $Diagnostico -and -not $Aplicar -and -not $SoloLimpieza -and -not $Restaurar) {
    $Diagnostico = $true
}

if ($SoloLimpieza) {
    Limpiar-Temporales
    exit
}

if ($Diagnostico) {
    Write-Host "`n=== INFORMACIÓN DEL EQUIPO ===" -ForegroundColor Cyan

    Get-CimInstance Win32_ComputerSystem |
        Select-Object Manufacturer, Model,
        @{Name="RAM_GB";Expression={
            [math]::Round($_.TotalPhysicalMemory / 1GB, 2)
        }} |
        Format-List

    Write-Host "=== PROCESADOR ===" -ForegroundColor Cyan

    Get-CimInstance Win32_Processor |
        Select-Object Name, NumberOfCores, NumberOfLogicalProcessors |
        Format-List

    Write-Host "=== TARJETAS GRÁFICAS ===" -ForegroundColor Cyan

    Get-CimInstance Win32_VideoController |
        Select-Object Name,
        @{Name="VRAM_GB";Expression={
            [math]::Round($_.AdapterRAM / 1GB, 2)
        }},
        DriverVersion |
        Format-List

    Write-Host "=== DISCOS ===" -ForegroundColor Cyan

    Get-CimInstance Win32_DiskDrive |
        Select-Object Model, MediaType,
        @{Name="Size_GB";Expression={
            [math]::Round($_.Size / 1GB, 2)
        }} |
        Format-Table -AutoSize

    Write-Host "=== PROGRAMAS DE INICIO ===" -ForegroundColor Cyan

    Get-CimInstance Win32_StartupCommand |
        Select-Object Name, Command, Location |
        Format-Table -Wrap -AutoSize

    Write-Host "`nDiagnóstico terminado. No se hicieron cambios."
    exit
}

if (-not (Es-Administrador)) {
    Write-Host "Abre PowerShell como Administrador y vuelve a ejecutar el script."
    exit 1
}

if ($Restaurar) {
    Log "Restaurando configuraciones principales..."

    Set-Service SysMain -StartupType Automatic
    Start-Service SysMain

    Set-Service WSearch -StartupType Automatic

    $visual = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    Set-ItemProperty $visual -Name VisualFXSetting -Value 0

    $background = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
    Set-ItemProperty $background -Name GlobalUserDisabled -Value 0

    $updateKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"

    Remove-ItemProperty `
        -Path $updateKey `
        -Name AUOptions `
        -ErrorAction SilentlyContinue

    Remove-ItemProperty `
        -Path $updateKey `
        -Name NoAutoUpdate `
        -ErrorAction SilentlyContinue

    Unregister-ScheduledTask `
        -TaskName $TaskName `
        -Confirm:$false `
        -ErrorAction SilentlyContinue

    Log "Restauración terminada. Reinicia el equipo."
    exit
}

if ($Aplicar) {
    Log "Iniciando optimización."

    try {
        Checkpoint-Computer `
            -Description "Antes de optimizar laptop" `
            -RestorePointType MODIFY_SETTINGS

        Log "Punto de restauración creado."
    }
    catch {
        Log "No se pudo crear el punto de restauración."
    }

    # Guardar una copia del script para la tarea automática
    if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
        Copy-Item `
            -Path $PSCommandPath `
            -Destination $ManagedScript `
            -Force
    }

    # Asegurar archivo de paginación automático
    $sistema = Get-CimInstance Win32_ComputerSystem
    $sistema.AutomaticManagedPagefile = $true
    Set-CimInstance -InputObject $sistema

    # Reducir efectos visuales
    Log "Reduciendo efectos visuales..."

    $visual = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    New-Item $visual -Force | Out-Null
    New-ItemProperty -Path $visual -Name VisualFXSetting -PropertyType DWord -Value 2 -Force | Out-Null

    $desktop = "HKCU:\Control Panel\Desktop"
    Set-ItemProperty $desktop -Name MenuShowDelay -Value "50"

    $explorer = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    New-Item $explorer -Force | Out-Null
    New-ItemProperty -Path $explorer -Name TaskbarAnimations -PropertyType DWord -Value 0 -Force | Out-Null
    New-ItemProperty -Path $explorer -Name ListviewAlphaSelect -PropertyType DWord -Value 0 -Force | Out-Null
    New-ItemProperty -Path $explorer -Name ListviewShadow -PropertyType DWord -Value 0 -Force | Out-Null

    $personalize = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    New-Item $personalize -Force | Out-Null
    New-ItemProperty -Path $personalize -Name EnableTransparency -PropertyType DWord -Value 0 -Force | Out-Null

    # Desactivar aplicaciones modernas en segundo plano
    Log "Limitando aplicaciones en segundo plano..."

    $background = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
    New-Item $background -Force | Out-Null
    New-ItemProperty -Path $background -Name GlobalUserDisabled -PropertyType DWord -Value 1 -Force | Out-Null

    # Desactivar SysMain/Superfetch
    Log "Desactivando SysMain/Superfetch..."

    Stop-Service SysMain -Force
    Set-Service SysMain -StartupType Disabled

    # Reducir actividad de búsqueda en HDD, sin desinstalarla
    Log "Configurando Windows Search en modo manual..."

    Stop-Service WSearch -Force
    Set-Service WSearch -StartupType Manual

    # Aceleración gráfica de Edge y Chrome
    Log "Activando aceleración gráfica de navegadores..."

    $edgePolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    New-Item $edgePolicy -Force | Out-Null
    New-ItemProperty `
        -Path $edgePolicy `
        -Name HardwareAccelerationModeEnabled `
        -PropertyType DWord `
        -Value 1 `
        -Force | Out-Null

    $chromePolicy = "HKLM:\SOFTWARE\Policies\Google\Chrome"
    New-Item $chromePolicy -Force | Out-Null
    New-ItemProperty `
        -Path $chromePolicy `
        -Name HardwareAccelerationModeEnabled `
        -PropertyType DWord `
        -Value 1 `
        -Force | Out-Null

    # Preferir GPU de alto rendimiento para aplicaciones compatibles
    $gpuKey = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
    New-Item $gpuKey -Force | Out-Null

    $programasGPU = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft Office\root\Office16\WINWORD.EXE",
        "$env:ProgramFiles\Microsoft Office\root\Office16\EXCEL.EXE",
        "$env:ProgramFiles\Microsoft Office\root\Office16\POWERPNT.EXE",
        "$env:WINDIR\System32\mspaint.exe"
    )

    foreach ($programa in $programasGPU) {
        if (Test-Path $programa) {
            New-ItemProperty -Path $gpuKey -Name $programa -PropertyType String -Value 'GpuPreference=2;' -Force -ErrorAction Stop | Out-Null

            Log ('GPU configurada: {0}' -f $programa)
        }
    }

    # Defender activo, con análisis de menor prioridad
    Log "Ajustando Defender sin desactivarlo..."

    try {
        Set-MpPreference -DisableRealtimeMonitoring $false
        Set-MpPreference -ScanOnlyIfIdleEnabled $true
        Set-MpPreference -EnableLowCpuPriority $true
        Set-MpPreference -DisableCpuThrottleOnIdleScans $false
        Set-MpPreference -ScanAvgCPULoadFactor 20
        Set-MpPreference -EnableFullScanOnBatteryPower $false
        Set-MpPreference `
            -ScanScheduleDay Sunday `
            -ScanScheduleTime 03:00:00 `
            -RandomizeScheduleTaskTimes $true

        Log "Defender permanece activo."
    }
    catch {
        Log "Defender no permitió cambiar alguna configuración."
    }

    # Windows Update en modo notificación/manual
    Log "Configurando Windows Update en modo manual..."

    $updateKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    New-Item $updateKey -Force | Out-Null

    # 2 = notificar antes de descargar e instalar
    New-ItemProperty `
        -Path $updateKey `
        -Name AUOptions `
        -PropertyType DWord `
        -Value 2 `
        -Force | Out-Null

    New-ItemProperty `
        -Path $updateKey `
        -Name NoAutoUpdate `
        -PropertyType DWord `
        -Value 0 `
        -Force | Out-Null

    Set-Service wuauserv -StartupType Manual

    # Limpieza inmediata
    Limpiar-Temporales

    # Crear tarea de limpieza automática cada domingo a las 03:00
    if (Test-Path $ManagedScript) {
        Log "Creando limpieza automática semanal..."

        $powershell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

        $argumentos = "-NoProfile -ExecutionPolicy Bypass -File `"$ManagedScript`" -SoloLimpieza"

        $accion = New-ScheduledTaskAction `
            -Execute $powershell `
            -Argument $argumentos

        $hora = Get-Date -Hour 3 -Minute 0 -Second 0

        $disparador = New-ScheduledTaskTrigger `
            -Weekly `
            -DaysOfWeek Sunday `
            -At $hora

        $principal = New-ScheduledTaskPrincipal `
            -UserId "SYSTEM" `
            -LogonType ServiceAccount `
            -RunLevel Highest

        Register-ScheduledTask `
            -TaskName $TaskName `
            -Action $accion `
            -Trigger $disparador `
            -Principal $principal `
            -Force | Out-Null

        Log "Limpieza semanal configurada."
    }

    # Optimizar el HDD
    Log "Optimizando el disco del sistema. Esto puede tardar..."

    $letra = $env:SystemDrive.TrimEnd(":")

    try {
        Optimize-Volume -DriveLetter $letra -Defrag -Verbose -ErrorAction Stop

        Log "Optimización terminada. Reinicia Windows."
        Write-Host ''
        Write-Host 'Proceso terminado. Reinicia el equipo.' -ForegroundColor Green
    }
    catch {
        Log "No se pudo optimizar el disco: $($_.Exception.Message)"
        exit 1
    }
}
