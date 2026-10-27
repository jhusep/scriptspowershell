# Perfil Windows 10: Ryzen 3 3200U y HDD ST1000LM035

Perfil conservador para un portatil con Ryzen 3 3200U, Radeon Vega 3 integrada, Radeon 530 dedicada y disco Seagate ST1000LM035. El script detecta la RAM y los componentes instalados; no presupone que sigan siendo los mismos. Se guarda en UTF-8 con BOM para Windows PowerShell 5.1.

## Que hace

- Sin parametros: muestra CPU, RAM, GPU, discos y programas de inicio. No modifica nada.
- `-Aplicar`: intenta crear un punto de restauracion, conserva la paginacion automatica, reduce algunos efectos visuales y borra temporales del usuario con mas de 7 dias.
- `-Aplicar -OptimizarDisco`: ademas analiza y optimiza la unidad del sistema segun el tipo de medio que detecte Windows. Es opcional porque Windows ya programa la optimizacion de unidades.
- `-SoloLimpieza`: limpia solo temporales antiguos de la cuenta actual.
- `-Restaurar`: restablece efectos visuales y revierte ajustes de servicios, Windows Update y tarea programada de versiones anteriores del script.

El perfil prioriza autonomia: no fuerza Chrome, Office ni otras aplicaciones a usar la Radeon 530. Para un juego concreto, selecciona **Alto rendimiento** en Configuracion > Sistema > Pantalla > Configuracion de graficos. Las tareas ligeras pueden seguir usando la Vega 3.

No desactiva Defender, Windows Update, SysMain ni Windows Search. Tampoco instala controladores ni cambia el plan de energia. Revisa los programas de inicio del diagnostico y desactiva manualmente los que no necesites.

## Uso

Descarga la version actual. Ejecuta esta linea completa en PowerShell y pulsa Enter:

```powershell
Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/jhusep/scriptspowershell/main/optimizar-windows10.ps1' -OutFile "$env:USERPROFILE\Downloads\optimizar-windows10.ps1"
```

Para diagnosticar, ejecuta esta linea por separado:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\Downloads\optimizar-windows10.ps1"
```

Para aplicar el perfil, abre PowerShell **como administrador** y ejecuta:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\Downloads\optimizar-windows10.ps1" -Aplicar
```

Si quieres optimizar el disco en esta ejecucion, agrega `-OptimizarDisco` al final del comando anterior. Reinicia Windows despues de aplicar cambios.

## Quitar aplicaciones preinstaladas

El script [quitar-apps-windows10.ps1](quitar-apps-windows10.ps1) revisa una lista **exacta** de aplicaciones opcionales de Windows 10: Cortana, apps de Xbox y Solitario, el acceso promocional Microsoft Office Hub, y apps como Noticias, Clima, Mapas, Skype, Visor 3D y Clipchamp. Sin `-Aplicar` solo muestra lo encontrado. Con `-Aplicar`, quita esos paquetes de las cuentas existentes y su aprovisionamiento para cuentas nuevas. Guarda un inventario y un resultado en `C:\ProgramData\LaptopLigera\Apps` e intenta crear un punto de restauracion.

El script conserva Microsoft Store, Defender, Windows Update, busqueda de Windows, Fotos, Calculadora, Paint, OneDrive, controladores y servicios. No desinstala Office/Microsoft 365 de escritorio: muestra las instalaciones detectadas para revisarlas en **Configuracion > Aplicaciones > Aplicaciones y caracteristicas**, porque pueden ser versiones con licencia. Tampoco borra programas del fabricante sin identificar, archivos personales ni carpetas `WindowsApps`.

Descarga la version actual ejecutando esta linea completa en PowerShell:

```powershell
Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/jhusep/scriptspowershell/main/quitar-apps-windows10.ps1' -OutFile "$env:USERPROFILE\Downloads\quitar-apps-windows10.ps1"
```

Abre PowerShell **como administrador** y ejecuta primero el diagnostico:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\Downloads\quitar-apps-windows10.ps1"
```

Si la lista coincide con lo que quieres quitar, ejecuta por separado:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\Downloads\quitar-apps-windows10.ps1" -Aplicar
```

Puedes limitar la limpieza, por ejemplo, con `-Aplicar -Categorias Cortana,Office`. Las categorias disponibles son `Cortana`, `Xbox`, `Office` y `Opcionales`. Para conservar una app concreta dentro de una categoria, agrega su nombre exacto, por ejemplo `-Conservar Microsoft.YourPhone`. La desinstalacion puede borrar datos locales de esas apps y afectar a otras cuentas del equipo; revisa el diagnostico antes de aplicar. Algunas apps se pueden reinstalar desde Microsoft Store si siguen disponibles, y algunas pueden regresar con actualizaciones.

Microsoft documenta la [desinstalacion de paquetes para todas las cuentas](https://learn.microsoft.com/en-us/powershell/module/appx/remove-appxpackage) y la [eliminacion del aprovisionamiento para cuentas nuevas](https://learn.microsoft.com/en-us/powershell/module/dism/remove-appxprovisionedpackage). Para Office de escritorio, sigue la [desinstalacion oficial de Microsoft 365 u Office](https://support.microsoft.com/en-us/office/lifecycle/officeinstall/uninstall-microsoft-365-or-office-from-a-pc).

## Controladores

AMD recomienda instalar los controladores del fabricante del portatil para ambas GPU cuando se usan graficos conmutables. Si ya descargaste controladores `.inf` del fabricante en `C:\Drivers`, puedes instalarlos desde una consola de administrador con:

```powershell
pnputil.exe /add-driver "C:\Drivers\*.inf" /subdirs /install
```

### Desinstalacion de controladores de terceros

El script [reinstalar-drivers.ps1](reinstalar-drivers.ps1) prepara un respaldo de **todos los paquetes OEM** (`oem*.inf`), crea un inventario y **desinstala los paquetes que marques**. La accion `Desinstalar` no instala ningun controlador: tu los instalaras manualmente despues. Los controladores integrados de Windows no se eliminan. Las clases de arranque, disco, red y entrada vienen protegidas porque quitarlas en bloque puede impedir que el equipo funcione. El script no usa `/force` ni bloquea Windows Update.

Descarga el script antes de usarlo:

```powershell
Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/jhusep/scriptspowershell/main/reinstalar-drivers.ps1' -OutFile "$env:USERPROFILE\Downloads\reinstalar-drivers.ps1"
```

1. Descarga y extrae antes los controladores para **tu modelo exacto de portatil** en una carpeta local, por ejemplo `C:\Drivers`. Deben existir archivos `.inf`; los instaladores `.exe` se ejecutan por separado. Para las dos GPU AMD, usa preferentemente el conjunto del fabricante del portatil.
   Si antes ejecutaste `configurar-drivers-fabricante.ps1 -Aplicar`, usa su opcion `-Restaurar` para permitir de nuevo la busqueda de controladores en Windows Update.
2. En PowerShell como administrador, prepara respaldo e inventario:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\Downloads\reinstalar-drivers.ps1" -Accion Preparar
```

3. Revisa `C:\ProgramData\DriversFabricante\Reinstalacion\Inventario.csv`. La columna `Eliminar` viene en `Si` para paquetes de clases no protegidas y en `No` para clases protegidas. Cambia a `No` cualquier paquete adicional que quieras conservar. Copia la carpeta `Respaldo` a otra unidad antes de continuar.
4. Con los controladores nuevos ya descargados localmente, desinstala los paquetes marcados:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\Downloads\reinstalar-drivers.ps1" -Accion Desinstalar -ConfirmarBorrado
```

5. Instala manualmente los controladores del fabricante desde sus instaladores `.exe`, o desde el Administrador de dispositivos si tienes archivos `.inf`. Para instalar todos los `.inf` de `C:\Drivers` manualmente desde una consola de administrador, puedes usar el comando `pnputil` mostrado arriba.

Para intentar quitar tambien las clases protegidas, cambia sus filas a `Eliminar=Si` en `Inventario.csv` y agrega `-IncluirClasesProtegidas` al comando de desinstalacion. Hazlo solo si tienes acceso fisico al equipo y los instaladores locales: puedes perder teclado, raton, red o la capacidad de iniciar Windows. Aun asi, `pnputil` puede rechazar paquetes en uso. No es posible garantizar que Windows quede sin controladores mediante un script ejecutado dentro del propio sistema.

Si necesitas volver a instalar los paquetes exportados del respaldo:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\Downloads\reinstalar-drivers.ps1" -Accion Recuperar
```

El inventario, el respaldo y el registro quedan en `C:\ProgramData\DriversFabricante\Reinstalacion`. Revisa `Operaciones.log` y el Administrador de dispositivos despues de reiniciar. [Windows puede volver a detectar el hardware e instalar otro controlador disponible](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/using-device-manager-to-uninstall-devices-and-driver-packages). Para una reinstalacion total del sistema y sus controladores integrados, usa una [instalacion limpia de Windows con el medio oficial](https://support.microsoft.com/en-us/windows/deployment/install-upgrade/reinstall-windows-with-the-installation-media).

## Criterios y fuentes

- [AMD: Ryzen 3 3200U](https://www.amd.com/en/support/downloads/drivers.html/processors/ryzen/ryzen-3000-series/amd-ryzen-3-3200u.html): CPU de 2 nucleos y 4 hilos con Vega 3 integrada.
- [AMD: preferencias graficas en portatiles Windows 10](https://www.amd.com/en/resources/support-articles/faqs/GPU-110.html): la GPU integrada ahorra energia y la dedicada se puede elegir por aplicacion.
- [AMD: graficos conmutables](https://www.amd.com/en/resources/support-articles/faqs/DH-017.html): recomienda controladores compatibles para ambas GPU, preferentemente del fabricante del portatil.
- [Microsoft: PnPUtil](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil-command-syntax): exportacion, desinstalacion e instalacion de paquetes OEM.
- [Seagate: manual ST1000LM035](https://www.seagate.com/www-content/product-content/seagate-laptop-fam/mobile-hdd/en-us/docs/100775165b.pdf): HDD de 5400 rpm.
- [Microsoft: mejorar el rendimiento del PC](https://support.microsoft.com/en-au/windows/experience/performance-optimization/tips-to-improve-pc-performance-in-windows): programas de inicio, espacio libre y efectos visuales son puntos de revision utiles.
- [Microsoft: optimizar unidades](https://support.microsoft.com/en-us/windows/experience/storage-filemanagement/defragment-optimize-your-data-drives-in-windows): Windows optimiza las unidades automaticamente; `-OptimizarDisco` queda opcional.
- [Sophia Script para Windows 10](https://github.com/farag2/Sophia-Script-for-Windows): referencia de ajustes reversibles por funcion. [WinUtil](https://github.com/ChrisTitusTech/winutil) inspira la separacion entre ajustes basicos y avanzados, pero su documentacion actual indica que Windows 10 ya no esta soportado.

Estos proyectos no aportan una medicion de mejora para este equipo concreto. Para valorar el resultado, compara tiempos de arranque y uso de disco/RAM en el Administrador de tareas antes y despues de aplicar el perfil.

Windows 10 Home y Pro terminaron su soporte general el 14 de octubre de 2025; el script no sustituye las actualizaciones de seguridad ni un programa ESU. Consulta la [informacion de versiones de Microsoft](https://learn.microsoft.com/en-us/windows/release-health/release-information).
