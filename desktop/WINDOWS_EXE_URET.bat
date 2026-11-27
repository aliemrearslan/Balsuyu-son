@echo off
chcp 65001 >nul
echo ============================================================
echo BALSUYU MTAL - WINDOWS TEK DOSYA (.EXE) URETICI
echo ARSLANOGLU GROUP YAZILIM SISTEMLERI
echo ============================================================
echo.
python --version >nul 2>&1
if errorlevel 1 (
  echo [HATA] Python bulunamadi! Lutfen python.org adresinden Python 3.12 kurun
  echo (Kurulumda "Add Python to PATH" kutusunu isaretleyin).
  pause
  exit /b 1
)
echo [1/3] Gerekli paketler yukleniyor...
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
echo.
echo [2/3] Uygulama ikonu hazirlaniyor...
python make_icons.py
echo.
echo [3/3] Tek dosya Windows EXE derleniyor...
pyinstaller --noconfirm --clean --onefile --windowed ^
  --name "Balsuyu_MTAL_Yonetim_Windows" ^
  --icon "app_icon.ico" ^
  --add-data "app_icon.ico;." ^
  --collect-all customtkinter ^
  yonetim.py
echo.
echo ============================================================
echo TAMAMLANDI! Program hazir: dist\Balsuyu_MTAL_Yonetim_Windows.exe
echo ============================================================
pause
