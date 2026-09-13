param([switch]$DeviceTests)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
if (Test-Path -LiteralPath 'C:\Program Files\Java\jdk-17.0.5') {
    $env:JAVA_HOME = 'C:\Program Files\Java\jdk-17.0.5'
}
if (-not $env:ANDROID_HOME) { $env:ANDROID_HOME = Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
$gradle = if (Test-Path -LiteralPath 'C:\gradle-8.14.3\bin\gradle.bat') { 'C:\gradle-8.14.3\bin\gradle.bat' } else { '.\gradlew.bat' }
& $gradle :shared:jvmTest :shared:testDebugUnitTest :androidApp:testDebugUnitTest :androidApp:assembleDebug :androidApp:assembleDebugAndroidTest --console=plain
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if ($DeviceTests) {
    & $gradle :androidApp:connectedDebugAndroidTest --console=plain
    exit $LASTEXITCODE
}
Write-Host 'Build and shared tests passed. Android interaction tests and iOS verification are still required.'
