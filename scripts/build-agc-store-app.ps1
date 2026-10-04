# Build AGC upload package: unsigned store assemble, then hap-sign-tool with AGC release Profile.
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ProfilePath = Join-Path $Root 'signing\agc\release.p7b'
$CerPath = Join-Path $Root 'signing\agc\release.cer'
$P12Path = Join-Path $Root 'signing\agc\release.p12'
$PwdPath = Join-Path $Root 'signing\agc\store.pwd'

if (-not ((Test-Path $ProfilePath) -and (Test-Path $CerPath) -and (Test-Path $P12Path))) {
  Write-Host 'Missing signing/agc/release.{p7b,cer,p12}' -ForegroundColor Red
  exit 1
}

$text = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($ProfilePath))
if ($text -notmatch '"type":"release"') {
  Write-Host 'signing/agc/release.p7b is not RELEASE type.' -ForegroundColor Red
  exit 1
}
if ($text -notmatch '"bundle-name":"cn\.berry\.hitanext"') {
  Write-Host 'release.p7b bundle-name must be cn.berry.hitanext.' -ForegroundColor Red
  exit 1
}

$pw = $env:HITANEXT_STORE_PWD
if ([string]::IsNullOrWhiteSpace($pw) -and (Test-Path $PwdPath)) {
  $pw = (Get-Content -Path $PwdPath -Raw).Trim()
}
if ([string]::IsNullOrWhiteSpace($pw)) {
  Write-Host 'Set HITANEXT_STORE_PWD or create signing/agc/store.pwd' -ForegroundColor Red
  exit 1
}

$env:NODE_HOME = 'D:\deveco studio\Deveco studio\tools\node'
$env:DEVECO_SDK_HOME = 'D:\deveco studio\Deveco studio\sdk'
$env:JAVA_HOME = 'D:\deveco studio\Deveco studio\jbr'
$env:PATH = "$env:JAVA_HOME\bin;$env:NODE_HOME;$env:PATH"
Set-Location $Root

& 'D:\deveco studio\Deveco studio\tools\hvigor\bin\hvigorw.bat' `
    --mode project assembleApp -p product=store -p buildMode=release --no-daemon
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$outDir = Join-Path $Root 'build\outputs\store'
$unsigned = Join-Path $outDir 'HITA_NEXT0.1.1-store-unsigned.app'
$signed = Join-Path $outDir 'HITA_NEXT0.1.1-store-signed.app'
$hapIn = Join-Path $Root 'entry\build\store\outputs\default\entry-default-unsigned.hap'
$hapOut = Join-Path $Root 'entry\build\store\outputs\default\entry-default-signed.hap'
$jar = Join-Path $env:DEVECO_SDK_HOME 'default\openharmony\toolchains\lib\hap-sign-tool.jar'
$java = Join-Path $env:JAVA_HOME 'bin\java.exe'

if (-not (Test-Path $unsigned)) {
  Write-Host 'No store unsigned .app' -ForegroundColor Red
  exit 1
}

$signArgs = @(
  '-jar', $jar, 'sign-app',
  '-mode', 'localSign',
  '-keyAlias', 'berry',
  '-appCertFile', $CerPath,
  '-profileFile', $ProfilePath,
  '-signAlg', 'SHA256withECDSA',
  '-keystoreFile', $P12Path,
  '-keystorePwd', $pw,
  '-keyPwd', $pw,
  '-compatibleVersion', '26',
  '-signCode', '1'
)

& $java @signArgs -inFile $hapIn -outFile $hapOut
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# AGC checks the HAP inside the .app. Signing only the outer zip leaves an unsigned HAP (993).
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$packDir = Join-Path $Root 'build\_pack_store'
$packed = Join-Path $outDir 'HITA_NEXT0.1.1-store-packed.app'
if (Test-Path $packDir) { Remove-Item $packDir -Recurse -Force }
New-Item $packDir -ItemType Directory | Out-Null
[IO.Compression.ZipFile]::ExtractToDirectory($unsigned, $packDir)
Copy-Item $hapOut (Join-Path $packDir 'entry-default.hap') -Force
if (Test-Path $packed) { Remove-Item $packed -Force }
$zip = [IO.Compression.ZipFile]::Open($packed, [IO.Compression.ZipArchiveMode]::Create)
foreach ($f in Get-ChildItem $packDir -File) {
  $entry = $zip.CreateEntry($f.Name, [IO.Compression.CompressionLevel]::NoCompression)
  $es = $entry.Open()
  $fs = [IO.File]::OpenRead($f.FullName)
  $fs.CopyTo($es)
  $fs.Dispose()
  $es.Dispose()
}
$zip.Dispose()

& $java @signArgs -inFile $packed -inForm zip -outFile $signed
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$dest = Join-Path $outDir 'AGC_UPLOAD.app'
Copy-Item -Path $signed -Destination $dest -Force

$blob = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($dest))
if ($blob.Contains('"type":"debug"')) {
  Write-Host ('Reject: debug Profile in ' + $dest) -ForegroundColor Red
  exit 1
}
if ($blob -notmatch '"type":"release"') {
  Write-Host ('Reject: no release Profile in ' + $dest) -ForegroundColor Red
  exit 1
}

Write-Host ('Upload to AGC: ' + $dest) -ForegroundColor Green
Write-Host ('Signed app: ' + $signed) -ForegroundColor Green
