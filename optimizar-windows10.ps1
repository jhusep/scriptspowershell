#requires -version 5.1

[CmdletBinding()]
param(
    [switch]$Diagnostico,
    [switch]$Aplicar,
    [switch]$SoloLimpieza,
    [switch]$Restaurar,
    [switch]$OptimizarDisco,
    [switch]$ServiciosMinimos,
    [switch]$SinSysMain
)

$ErrorActionPreference = 'Stop'
$BaseDir = Join-Path $env:LOCALAPPDATA 'LaptopLigera'
$LogFile = Join-Path $BaseDir 'optimizacion.log'
$TaskName = 'LaptopLigera - Limpieza semanal'
$ServiceBackupDir = Join-Path $env:ProgramData 'LaptopLigera\Servicios'
$ServiceBackupFile = Join-Path $ServiceBackupDir 'ServiciosOriginales.csv'
$ServiciosOpcionales = @('WSearch', 'XblAuthManager', 'XblGameSave', 'XboxNetApiSvc', 'XboxGipSvc')

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

function Guardar-ServiciosOriginales {
    param([string[]]$Nombres)

    New-Item -ItemType Directory -Path $ServiceBackupDir -Force | Out-Null
    $anteriores = @()
    if (Test-Path -LiteralPath $ServiceBackupFile -PathType Leaf) {
        $anteriores = @(Import-Csv -LiteralPath $ServiceBackupFile)
    }
    $servicios = @(Get-CimInstance Win32_Service | Where-Object { $Nombres -contains $_.Name })
    foreach ($servicio in $servicios) {
        if (@($anteriores | Where-Object { $_.Name -eq $servicio.Name }).Count -gt 0) { continue }
        $ruta = 'HKLM:\SYSTEM\CurrentControlSet\Services\{0}' -f $servicio.Name
        $propiedad = Get-ItemProperty -Path $ruta -Name DelayedAutoStart -ErrorAction SilentlyContinue
        $demorado = [int]($propiedad.DelayedAutoStart -eq 1)
        $anteriores += [pscustomobject]@{
            Name = $servicio.Name
            StartMode = $servicio.StartMode
            WasRunning = [int]($servicio.State -eq 'Running')
            DelayedAutoStart = $demorado
        }
    }
    if ($anteriores.Count -gt 0) {
        $anteriores | Export-Csv -LiteralPath $ServiceBackupFile -NoTypeInformation -Encoding UTF8
        Log ('Configuracion original de servicios guardada en {0}' -f $ServiceBackupFile)
    }
}

function Reducir-Servicios {
    param([string[]]$Nombres)

    Guardar-ServiciosOriginales -Nombres $Nombres
    $fallos = 0
    foreach ($nombre in $Nombres) {
        $servicio = Get-Service -Name $nombre -ErrorAction SilentlyContinue
        if (-not $servicio) { continue }
        try {
            Set-Service -Name $nombre -StartupType Disabled -ErrorAction Stop
            if ($servicio.Status -eq 'Running') {
                try {
                    Stop-Service -Name $nombre -ErrorAction Stop
                }
                catch {
                    Log ('{0} quedara detenido tras reiniciar: {1}' -f $nombre, $_.Exception.Message)
                }
            }
            Log ('Servicio desactivado: {0}' -f $nombre)
        }
        catch {
            Log ('No se pudo desactivar {0}: {1}' -f $nombre, $_.Exception.Message)
            $fallos++
        }
    }
    return $fallos
}

function Restaurar-Servicios {
    if (-not (Test-Path -LiteralPath $ServiceBackupFile -PathType Leaf)) {
        Log 'No se encontro respaldo de servicios del perfil ligero.'
        return 1
    }
    $fallos = 0
    $permitidos = @($ServiciosOpcionales) + 'SysMain'
    foreach ($original in (Import-Csv -LiteralPath $ServiceBackupFile)) {
        if ($permitidos -notcontains $original.Name) {
            Log ('Servicio no reconocido en el respaldo; omitido: {0}' -f $original.Name)
            $fallos++
            continue
        }
        if (-not (Get-Service -Name $original.Name -ErrorAction SilentlyContinue)) { continue }
        try {
            switch ($original.StartMode) {
                'Auto' { $inicio = 'Automatic' }
                'Manual' { $inicio = 'Manual' }
                'Disabled' { $inicio = 'Disabled' }
                default { throw ('Modo de inicio desconocido: {0}' -f $original.StartMode) }
            }
            Set-Service -Name $original.Name -StartupType $inicio -ErrorAction Stop
            if ($inicio -eq 'Automatic' -and $original.DelayedAutoStart -eq '1') {
                & sc.exe config $original.Name start= delayed-auto | Out-Null
                if ($LASTEXITCODE -ne 0) { throw 'No se pudo restaurar el inicio automatico demorado.' }
            }
            if ($original.WasRunning -eq '1' -and $inicio -ne 'Disabled') {
                Start-Service -Name $original.Name -ErrorAction Stop
            }
            Log ('Servicio restaurado: {0} ({1})' -f $original.Name, $original.StartMode)
        }
        catch {
            Log ('No se pudo restaurar {0}: {1}' -f $original.Name, $_.Exception.Message)
            $fallos++
        }
    }
    return $fallos
}

if ($OptimizarDisco -and -not $Aplicar) {
    Write-Error 'Usa -OptimizarDisco junto con -Aplicar.'
    exit 1
}

if ($ServiciosMinimos -and -not $Aplicar) {
    Write-Error 'Usa -ServiciosMinimos junto con -Aplicar.'
    exit 1
}

if ($SinSysMain -and (-not $Aplicar -or -not $ServiciosMinimos)) {
    Write-Error 'Usa -SinSysMain junto con -Aplicar -ServiciosMinimos.'
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
    $memoria = Get-CimInstance Win32_OperatingSystem
    $usoMemoria = [math]::Round(100 * (1 - $memoria.FreePhysicalMemory / $memoria.TotalVisibleMemorySize), 1)
    Write-Host ('RAM utilizable: {0} GB | En uso: {1}% | Disponible: {2} GB' -f ([math]::Round($memoria.TotalVisibleMemorySize / 1MB, 2)), $usoMemoria, ([math]::Round($memoria.FreePhysicalMemory / 1MB, 2)))
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

    Write-Host '=== PROCESOS CON MAYOR MEMORIA FISICA ===' -ForegroundColor Cyan
    Get-Process -ErrorAction SilentlyContinue |
        Sort-Object WorkingSet64 -Descending |
        Select-Object -First 12 ProcessName, Id, @{Name='RAM_MB';Expression={ [math]::Round($_.WorkingSet64 / 1MB, 1) }} |
        Format-Table -AutoSize

    Write-Host '=== SERVICIOS DEL PERFIL LIGERO ===' -ForegroundColor Cyan
    Get-CimInstance Win32_Service |
        Where-Object { ($ServiciosOpcionales + 'SysMain') -contains $_.Name } |
        Select-Object Name, State, StartMode, ProcessId |
        Format-Table -AutoSize

    Write-Host 'Diagnostico terminado. No se hicieron cambios.'
    Write-Host 'Para aplicar los ajustes conservadores, usa -Aplicar como administrador.'
    Write-Host 'Para reducir servicios opcionales, usa -Aplicar -ServiciosMinimos como administrador.'
    exit
}

if (-not (Es-Administrador)) {
    Write-Error 'Abre PowerShell como administrador y vuelve a ejecutar el script.'
    exit 1
}

if ($Restaurar) {
    Log 'Restaurando los efectos visuales y ajustes de versiones anteriores...'
    $fallosRestauracion = 0
    $visual = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
    $explorer = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    New-Item -Path $visual -Force | Out-Null
    New-Item -Path $explorer -Force | Out-Null
    New-Item -Path $personalize -Force | Out-Null
    New-ItemProperty -Path $visual -Name VisualFXSetting -PropertyType DWord -Value 0 -Force | Out-Null
    New-ItemProperty -Path $explorer -Name TaskbarAnimations -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path $personalize -Name EnableTransparency -PropertyType DWord -Value 1 -Force | Out-Null
    if (Test-Path -LiteralPath $ServiceBackupFile -PathType Leaf) {
        $fallosRestauracion = Restaurar-Servicios
    }
    else {
        Set-Service SysMain -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service SysMain -ErrorAction SilentlyContinue
        Set-Service WSearch -StartupType Automatic -ErrorAction SilentlyContinue
    }
    $updateKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
    Remove-ItemProperty -Path $updateKey -Name AUOptions -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $updateKey -Name NoAutoUpdate -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Log 'Restauracion terminada. Reinicia Windows.'
    if ($fallosRestauracion -gt 0) { exit 1 }
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
    $fallosServicios = 0
    if ($ServiciosMinimos) {
        $objetivos = @($ServiciosOpcionales)
        if ($SinSysMain) { $objetivos += 'SysMain' }
        $fallosServicios = Reducir-Servicios -Nombres $objetivos
        Log 'Busqueda de archivos y correo puede ser mas lenta. Algunas funciones de Xbox y Game Bar pueden dejar de funcionar.'
    }
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

    if ($fallosServicios -gt 0) {
        Log ('Perfil aplicado parcialmente: {0} servicio(s) no se pudieron configurar. Revisa el registro.' -f $fallosServicios)
        exit 1
    }
    Log 'Perfil aplicado. Reinicia Windows para completar los cambios.'
}
