@echo off
chcp 65001 >nul
echo ========================================
echo   Hi HITA 编译并安装到鸿蒙设备
echo ========================================

set "HDC_PATH=C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
set "NODE_HOME=C:\Program Files\nodejs"
set "DEVECO_SDK_HOME=C:\Program Files\Huawei\DevEco Studio\sdk"

cd /d "%~dp0"

echo [1/3] 编译 HAP...
call "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" --mode module -p product=default assembleHap --no-daemon
if errorlevel 1 (
    echo [错误] 编译失败，请检查报错！
    pause
    exit /b 1
)

echo.
if not exist "entry\build\default\outputs\default\entry-default-signed.hap" (
    echo [提示] 当前只生成了 unsigned HAP：
    echo        entry\build\default\outputs\default\entry-default-unsigned.hap
    echo [提示] 请在 DevEco Studio 打开 Project Structure ^> Signing Configs，配置自动签名，
    echo        然后重新运行本脚本。当前工程已移除过期的默认证书引用。
    pause
    exit /b 0
)

echo [2/3] 检查连接设备...
"%HDC_PATH%" list targets
if errorlevel 1 (
    echo [错误] 未检测到鸿蒙设备，请确认手机已开启 USB 调试并允许连接！
    pause
    exit /b 1
)

echo.
echo [3/3] 安装到真机...
"%HDC_PATH%" install -r "entry\build\default\outputs\default\entry-default-signed.hap"
if errorlevel 1 (
    echo [错误] 安装失败！
    pause
    exit /b 1
)

echo.
echo [提示] 正在启动应用（请先点亮并解锁手机屏幕）...
"%HDC_PATH%" shell power-shell wakeup
"%HDC_PATH%" shell aa start -a EntryAbility -b cn.berry.hitanext

echo.
echo [完成] 应用已安装成功！如果手机处于锁屏状态，请解锁屏幕后在桌面点击 Hi HITA 图标打开。
pause
