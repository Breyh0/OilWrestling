@echo off
cd /d "%~dp0"
title rojo serve - OilWrestling

REM Si el servidor ya esta corriendo, no arrancar otro
curl -s -m 2 -o nul http://localhost:34872
if %errorlevel%==0 (
  echo rojo serve YA esta corriendo en el puerto 34872.
  echo Puedes cerrar esta ventana y volver a Studio: Rojo - Connect.
  pause
  exit /b
)

set ROJO=C:\dev\bin\rojo.exe
if not exist "%ROJO%" set ROJO=rojo

echo ============================================
echo  Iniciando rojo serve (OilWrestling)
echo  Manten esta ventana abierta mientras trabajes.
echo  Para pararlo: cierra la ventana o Ctrl+C.
echo ============================================
"%ROJO%" serve
pause
