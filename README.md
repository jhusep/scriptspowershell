# scriptspowershell

Este script reúne las optimizaciones razonables para una laptop con 4 GB de RAM y HDD:
- Activa aceleración gráfica para Edge/Chrome y aplicaciones compatibles.
- Desactiva SysMain, antes llamado Superfetch.
- Reduce efectos visuales.
- Desactiva aplicaciones UWP en segundo plano.
- Mantiene el archivo de paginación automático.
- Mantiene Defender activo, pero reduce la prioridad de sus análisis.
- Configura Windows Update para notificar y actualizar manualmente.
- Limpia temporales automáticamente cada 7 días.
- Optimiza el HDD.
- No toca Defender, Firewall ni servicios esenciales.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\Downloads\optimizar-windows10.ps1"

Para instalar controladores descargados del fabricante:
pnputil.exe /add-driver "C:\Drivers\*.inf" /subdirs /install
