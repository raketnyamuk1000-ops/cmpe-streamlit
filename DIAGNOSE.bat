@echo off
title CMPE DIAGNOSTIC
echo ==========================================
echo    DIAGNOSTIC MODE - Do not close this window
echo ==========================================
call venv\Scripts\activate.bat
echo.
echo Starting Streamlit... if you see an error below, screenshot it.
echo.
venv\Scripts\streamlit.exe run app.py
echo.
echo If you see "SyntaxError" above, your app.py is corrupted.
pause