@echo off
cd /d "Z:\Godot Projects\MY TURN"
echo ======================================
echo     Subiendo cambios a GitHub...
echo ======================================

set /p msg=Escribe el mensaje del commit: 

git add .
git commit -m "%msg%"
git push

echo --------------------------------------
echo  Cambios subidos correctamente
pause
