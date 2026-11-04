param([switch]$SkipTests)
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectDirectory
try {
    dart run tool/generate_styles.dart
    if ($LASTEXITCODE -ne 0) { throw 'CSS generation failed.' }
    flutter analyze --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Flutter analysis failed.' }
    if (-not $SkipTests) {
        flutter test --no-pub
        if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed.' }
    }
    flutter build apk --release --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'APK build failed.' }
} finally {
    Pop-Location
}
