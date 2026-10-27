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

## Controladores

AMD recomienda instalar los controladores del fabricante del portatil para ambas GPU cuando se usan graficos conmutables. Si ya descargaste controladores `.inf` del fabricante en `C:\Drivers`, puedes instalarlos desde una consola de administrador con:

```powershell
pnputil.exe /add-driver "C:\Drivers\*.inf" /subdirs /install
```

## Criterios y fuentes

- [AMD: Ryzen 3 3200U](https://www.amd.com/en/support/downloads/drivers.html/processors/ryzen/ryzen-3000-series/amd-ryzen-3-3200u.html): CPU de 2 nucleos y 4 hilos con Vega 3 integrada.
- [AMD: preferencias graficas en portatiles Windows 10](https://www.amd.com/en/resources/support-articles/faqs/GPU-110.html): la GPU integrada ahorra energia y la dedicada se puede elegir por aplicacion.
- [AMD: graficos conmutables](https://www.amd.com/en/resources/support-articles/faqs/DH-017.html): recomienda controladores compatibles para ambas GPU, preferentemente del fabricante del portatil.
- [Seagate: manual ST1000LM035](https://www.seagate.com/www-content/product-content/seagate-laptop-fam/mobile-hdd/en-us/docs/100775165b.pdf): HDD de 5400 rpm.
- [Microsoft: mejorar el rendimiento del PC](https://support.microsoft.com/en-au/windows/experience/performance-optimization/tips-to-improve-pc-performance-in-windows): programas de inicio, espacio libre y efectos visuales son puntos de revision utiles.
- [Microsoft: optimizar unidades](https://support.microsoft.com/en-us/windows/experience/storage-filemanagement/defragment-optimize-your-data-drives-in-windows): Windows optimiza las unidades automaticamente; `-OptimizarDisco` queda opcional.
- [Sophia Script para Windows 10](https://github.com/farag2/Sophia-Script-for-Windows): referencia de ajustes reversibles por funcion. [WinUtil](https://github.com/ChrisTitusTech/winutil) inspira la separacion entre ajustes basicos y avanzados, pero su documentacion actual indica que Windows 10 ya no esta soportado.

Estos proyectos no aportan una medicion de mejora para este equipo concreto. Para valorar el resultado, compara tiempos de arranque y uso de disco/RAM en el Administrador de tareas antes y despues de aplicar el perfil.

Windows 10 Home y Pro terminaron su soporte general el 14 de octubre de 2025; el script no sustituye las actualizaciones de seguridad ni un programa ESU. Consulta la [informacion de versiones de Microsoft](https://learn.microsoft.com/en-us/windows/release-health/release-information).
