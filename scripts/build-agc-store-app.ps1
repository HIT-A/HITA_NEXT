# Build and verify an AppGallery release using an existing local signing configuration.
param(
  [string]$DevEcoHome = (Join-Path $env:ProgramFiles 'Huawei\DevEco Studio'),
  [string]$SigningConfig = 'online',
  [string]$Product = 'default'
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$ConfigPath = Join-Path $Root 'build-profile.json5'
$OriginalConfig = [IO.File]::ReadAllBytes($ConfigPath)
$Node = (Get-Command node -ErrorAction Stop).Source
$Java = Join-Path $DevEcoHome 'jbr\bin\java.exe'
if (-not (Test-Path -LiteralPath $Java)) { $Java = (Get-Command java -ErrorAction Stop).Source }
$Hvigor = Join-Path $DevEcoHome 'tools\hvigor\bin\hvigorw.bat'
$Jar = Join-Path $DevEcoHome 'sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar'
$OldNodePath = $env:NODE_PATH
$OldNodeHome = $env:NODE_HOME
$OldSdkHome = $env:DEVECO_SDK_HOME
$OldJavaHome = $env:JAVA_HOME
$env:NODE_PATH = Join-Path $DevEcoHome 'sdk\default\openharmony\ets\build-tools\ets-loader\node_modules'

Add-Type -AssemblyName System.Security.Cryptography.Pkcs
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Read-Profile([string]$Path) {
  $Cms = [System.Security.Cryptography.Pkcs.SignedCms]::new()
  $Cms.Decode([IO.File]::ReadAllBytes($Path))
  $Cms.CheckSignature($true)
  return [Text.Encoding]::UTF8.GetString($Cms.ContentInfo.Content) | ConvertFrom-Json
}
function Assert-ReleaseProfile($Profile, [string]$BundleName) {
  if ($Profile.type -ne 'release' -or $Profile.'app-distribution-type' -ne 'app_gallery') {
    throw 'A RELEASE app_gallery profile is required. Debug/ad-hoc profiles cannot be uploaded.'
  }
  if ($Profile.'bundle-info'.'bundle-name' -ne $BundleName) {
    throw 'Signing profile does not match the application bundle name.'
  }
  $Now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  if ($Now -lt $Profile.validity.'not-before' -or $Now -gt $Profile.validity.'not-after') {
    throw 'Signing profile is not currently valid.'
  }
}
try {
  $ConfigJson = & $Node -e "process.stdout.write(JSON.stringify(require('json5').parse(require('fs').readFileSync(process.argv[1],'utf8'))))" $ConfigPath
  if ($LASTEXITCODE -ne 0) { throw 'Cannot read build-profile.json5.' }
  $Config = $ConfigJson | ConvertFrom-Json
  $Signing = @($Config.app.signingConfigs | Where-Object name -EQ $SigningConfig)
  if ($Signing.Count -ne 1) { throw "Missing local signing configuration: $SigningConfig" }
  $App = Get-Content -LiteralPath (Join-Path $Root 'AppScope\app.json5') -Raw | ConvertFrom-Json
  $Profile = Read-Profile $Signing[0].material.profile
  Assert-ReleaseProfile $Profile $App.app.bundleName
  $env:NODE_HOME = Split-Path -Parent $Node
  $env:DEVECO_SDK_HOME = Join-Path $DevEcoHome 'sdk'
  $env:JAVA_HOME = Split-Path -Parent (Split-Path -Parent $Java)

  # Change only the selected product for this build; restore the exact original bytes below.
  & $Node -e "const fs=require('fs'),j=require('json5'),p=process.argv[1],c=j.parse(fs.readFileSync(p,'utf8'));const product=c.app.products.find(x=>x.name===process.argv[2]);if(!product)throw Error('Unknown product');product.signingConfig=process.argv[3];product.buildOption??={};product.buildOption.packOptions={...product.buildOption.packOptions,buildAppSkipSignHap:false,appWithSignedPkg:true};fs.writeFileSync(p,JSON.stringify(c,null,2)+'\n')" $ConfigPath $Product $SigningConfig
  if ($LASTEXITCODE -ne 0) { throw 'Cannot select the release signing configuration.' }
  Push-Location $Root
  try {
    $BuildStarted = [DateTime]::UtcNow
    & $Hvigor --mode project -p "product=$Product" -p buildMode=release clean assembleApp --no-daemon
    if ($LASTEXITCODE -ne 0) { throw 'Release build failed.' }
  } finally { Pop-Location }

  $OutDir = Join-Path $Root "build\outputs\$Product"
  $Packages = @(Get-ChildItem -LiteralPath $OutDir -Filter '*-all-signed.app' | Where-Object {
    $_.LastWriteTimeUtc -ge $BuildStarted
  })
  if ($Packages.Count -ne 1) { throw 'Expected exactly one freshly built signed app package.' }
  $Package = $Packages[0].FullName
  $VerifyDir = Join-Path $OutDir ('verification-' + [Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $VerifyDir | Out-Null
  $Zip = [IO.Compression.ZipFile]::OpenRead($Package)
  try {
    $InfoEntry = $Zip.GetEntry('pack.info')
    if ($null -eq $InfoEntry) { throw 'Missing app package identity.' }
    $Reader = [IO.StreamReader]::new($InfoEntry.Open())
    try { $Info = $Reader.ReadToEnd() | ConvertFrom-Json } finally { $Reader.Dispose() }
    if ($Info.summary.app.bundleName -ne $App.app.bundleName -or
      $Info.summary.app.version.code -ne $App.app.versionCode -or
      $Info.summary.app.version.name -ne $App.app.versionName) {
      throw 'Built package identity/version does not match AppScope/app.json5.'
    }
    $Haps = @($Zip.Entries | Where-Object { $_.Name.EndsWith('.hap') })
    if ($Haps.Count -eq 0) { throw 'No HAP module inside the app package.' }
    for ($i = 0; $i -lt $Haps.Count; $i++) {
      [IO.Compression.ZipFileExtensions]::ExtractToFile($Haps[$i], (Join-Path $VerifyDir "module-$i.hap"))
    }
  } finally { $Zip.Dispose() }
  $VerifyFiles = @($Package) + @(Get-ChildItem -LiteralPath $VerifyDir -Filter '*.hap' | Select-Object -ExpandProperty FullName)
  for ($i = 0; $i -lt $VerifyFiles.Count; $i++) {
    $VerifiedProfile = Join-Path $VerifyDir "verified-$i.p7b"
    & $Java -jar $Jar verify-app -inFile $VerifyFiles[$i] -inForm zip `
      -outCertChain (Join-Path $VerifyDir "verified-$i.cer") -outProfile $VerifiedProfile
    if ($LASTEXITCODE -ne 0) { throw "Signature verification failed: $($VerifyFiles[$i])" }
    Assert-ReleaseProfile (Read-Profile $VerifiedProfile) $App.app.bundleName
  }
  $Destination = Join-Path $OutDir ("HITA-NEXT-" + $App.app.versionName + '-AGC-signed.app')
  Copy-Item -LiteralPath $Package -Destination $Destination -Force
  Write-Host "Verified AGC release: $Destination"
  Write-Host ("SHA256: " + (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash)
} finally {
  [IO.File]::WriteAllBytes($ConfigPath, $OriginalConfig)
  $env:NODE_PATH = $OldNodePath
  $env:NODE_HOME = $OldNodeHome
  $env:DEVECO_SDK_HOME = $OldSdkHome
  $env:JAVA_HOME = $OldJavaHome
}
