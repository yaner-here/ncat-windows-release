$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$repoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
Set-Location $repoRoot
$out = "$repoRoot/portable-output"
$vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
$vsRoot = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$dumpbin = Get-ChildItem "$vsRoot/VC/Tools/MSVC/*/bin/Hostx64/x86/dumpbin.exe" | Sort-Object FullName | Select-Object -Last 1
$dependencies = & $dumpbin.FullName /dependents "$out/ncat.exe"
$dependencies | Set-Content "$out/dependencies.txt"
$dlls = @($dependencies | Where-Object { $_ -match '^\s+[\w.-]+\.dll\s*$' } | ForEach-Object { $_.Trim().ToLowerInvariant() })
if ($dlls.Count -eq 0) { throw 'Could not parse PE import dependencies' }
$allowed = @('kernel32.dll', 'user32.dll', 'gdi32.dll', 'advapi32.dll', 'ws2_32.dll', 'iphlpapi.dll', 'crypt32.dll', 'bcrypt.dll', 'secur32.dll', 'ntdll.dll', 'shell32.dll', 'ole32.dll')
foreach ($dll in $dlls) {
    if ($dll -notin $allowed) { throw "Unexpected dependency: $dll" }
}
& python mswin32/portable/smoke.py --exe "$out/ncat.exe" --openssl "$repoRoot/.portable-build/openssl/apps/openssl.exe" --report "$out/tests.json"
Copy-Item mswin32/portable/README.md "$out/README.md"
