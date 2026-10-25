param([switch]$Integration)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$output = Join-Path $repoRoot 'build/window-size-test'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$visualStudio) { throw 'Visual Studio C++ tools are required for the window-size test.' }
$environment = Join-Path $visualStudio 'VC/Auxiliary/Build/vcvars64.bat'
$test = Join-Path $repoRoot 'windows/tests/window_size_constraints_test.cpp'
$probe = Join-Path $output 'window_size_constraints_test.exe'
$compileScript = Join-Path $output 'compile-test.cmd'
@"
@echo off
call "$environment" >nul
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /WX /MT /DNOMINMAX "$test" /Fo"$output/" /Fe"$probe" user32.lib
"@ | Set-Content -LiteralPath $compileScript -Encoding utf8
& cmd /d /c $compileScript
if ($LASTEXITCODE -ne 0) { throw 'Window-size test compilation failed.' }
& $probe
if ($LASTEXITCODE -ne 0) { throw 'Window-size unit test failed.' }
if ($Integration) {
  Push-Location $repoRoot
  try {
    & flutter test --no-pub integration_test/windows_dpi_constraints_test.dart -d windows "--dart-define=WINDOW_DPI_PROBE=$probe" --reporter expanded
    if ($LASTEXITCODE -ne 0) { throw 'Windows runner minimum-size regression failed.' }
  } finally { Pop-Location }
}
