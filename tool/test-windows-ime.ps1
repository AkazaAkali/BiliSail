param([switch]$NativeOnly)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$output = Join-Path $repoRoot 'build/ime-test'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$visualStudio) { throw 'Visual Studio C++ tools are required for the native IME tests.' }
$environment = Join-Path $visualStudio 'VC/Auxiliary/Build/vcvars64.bat'
$test = Join-Path $PSScriptRoot 'native_tests/window_ime_context_test.cpp'
$include = Join-Path $repoRoot 'windows/runner'
$compileScript = Join-Path $output 'compile-test.cmd'
@"
@echo off
call "$environment" >nul
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /WX /MT /I"$include" "$test" /Fo"$output/window_ime_context_test.obj" /Fe"$output/window_ime_context_test.exe" /link user32.lib imm32.lib
"@ | Set-Content -LiteralPath $compileScript -Encoding utf8
& cmd /d /c $compileScript
if ($LASTEXITCODE -ne 0) { throw 'Native IME test compilation failed.' }
& "$output/window_ime_context_test.exe"
if ($LASTEXITCODE -ne 0) { throw 'Native IME tests failed.' }
if (!$NativeOnly) {
  Push-Location $repoRoot
  try {
    & flutter test integration_test/windows_ime_shortcuts_test.dart -d windows
    if ($LASTEXITCODE -ne 0) { throw 'Windows IME integration test failed.' }
  } finally { Pop-Location }
}
