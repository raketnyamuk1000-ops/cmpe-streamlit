HOW TO INSTALL ON YOUR WINDOWS PC
==================================

1. COPY this entire folder to your D: drive:
   Example: D:\CMPE-Local\

2. DOUBLE-CLICK "START-CMPE.bat"

3. WAIT for first-time setup (2-3 minutes).
   It will download libraries automatically.

4. YOUR BROWSER will open automatically at:
   http://localhost:8501

5. TO RUN AGAIN later:
   Just double-click START-CMPE.bat again.

TROUBLESHOOTING
===============
- "Python not found" -> Install Python from python.org
- "Add to PATH" must be checked during install
- Port 8501 in use -> Edit START-CMPE.bat last line to:
     streamlit run app.py --server.port 8502