$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$output = Join-Path $repoRoot 'build/image-export-test'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$visualStudio) { throw 'Visual Studio C++ tools are required.' }
$environment = Join-Path $visualStudio 'VC/Auxiliary/Build/vcvars64.bat'
$flutterRoot = Join-Path $repoRoot 'windows/flutter/ephemeral'
$wrapper = Join-Path $repoRoot 'build/windows/x64/flutter/Release/flutter_wrapper_app.lib'
if (!(Test-Path -LiteralPath $wrapper)) { throw 'Build the Windows Release application before this native test.' }
$test = Join-Path $repoRoot 'windows/tests/image_export_test.cpp'
$include = Join-Path $flutterRoot 'cpp_client_wrapper/include'
$compileScript = Join-Path $output 'compile-test.cmd'
@"
@echo off
call "$environment" >nul
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /WX /MD /I"$include" "$test" /Fo"$output/" /Fe"$output/image_export_test.exe" /link "$wrapper" "$flutterRoot/flutter_windows.dll.lib" user32.lib gdi32.lib ole32.lib oleaut32.lib uuid.lib windowscodecs.lib shlwapi.lib shell32.lib
"@ | Set-Content -LiteralPath $compileScript -Encoding utf8
& cmd /d /c $compileScript
if ($LASTEXITCODE -ne 0) { throw 'Native image export test compilation failed.' }
Copy-Item -LiteralPath (Join-Path $flutterRoot 'flutter_windows.dll') -Destination $output -Force
& (Join-Path $output 'image_export_test.exe') (Join-Path $repoRoot 'assets/branding/app_icon.png')
if ($LASTEXITCODE -ne 0) { throw 'Native image export tests failed.' }
