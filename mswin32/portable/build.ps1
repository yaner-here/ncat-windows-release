[CmdletBinding(DefaultParameterSetName = 'Dependencies')]
param(
    [Parameter(ParameterSetName = 'Dependencies')]
    [switch]$DependenciesOnly,

    [Parameter(ParameterSetName = 'Ncat')]
    [switch]$SkipDependencies
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version Latest
$repoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
Set-Location $repoRoot

# Import the x86 MSVC environment into this PowerShell process.
$vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
$vsRoot = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsRoot) { throw 'Visual Studio C++ tools not found' }
$devCmd = Join-Path $vsRoot 'Common7/Tools/VsDevCmd.bat'
& $env:ComSpec /d /s /c "call `"$devCmd`" -no_logo -arch=x86 -host_arch=x64 >nul && set" | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process') }
}
$env:PATH = "C:\Strawberry\perl\bin;C:\Program Files\NASM;$env:PATH"
if (-not (Get-Command nasm -ErrorAction SilentlyContinue)) {
    & choco install nasm --version=2.16.03 --yes --no-progress
}
& perl --version
& nasm -v
Get-Command cl, msbuild, nmake | Select-Object Name, Source | Format-Table

$opensslCommit = '45e844fa2a14ec92d146bd8f5778ac130b6625fb' # openssl-3.5.9
$opensslSource = Join-Path $repoRoot '.portable-build/openssl'
$opensslPrefix = [IO.Path]::GetFullPath((Join-Path $repoRoot '../nmap-mswin32-aux/OpenSSL'))
New-Item -ItemType Directory -Force "$repoRoot/.portable-build" | Out-Null
if (-not $SkipDependencies) {
    if (Test-Path $opensslSource) { throw 'Use a fresh checkout for the OpenSSL build' }
    & git clone --depth 1 --branch openssl-3.5.9 https://github.com/openssl/openssl.git $opensslSource
    if ((& git -C $opensslSource rev-parse HEAD) -ne $opensslCommit) { throw 'Unexpected OpenSSL source commit' }
    Push-Location $opensslSource
    try {
        # Compile both providers into libcrypto and use the static MSVC runtime.
        & perl Configure VC-WIN32 no-shared no-module no-tests --libdir=lib "--prefix=$opensslPrefix"
        & nmake /nologo
        & nmake /nologo install_sw
        Copy-Item ms/applink.c "$opensslPrefix/include/openssl/applink.c" -Force
        & ./apps/openssl.exe version -a
        & ./apps/openssl.exe list -providers -provider default -provider legacy
    } finally { Pop-Location }
}
if ((& git -C $opensslSource rev-parse HEAD) -ne $opensslCommit) { throw 'Unexpected cached OpenSSL source commit' }
if (-not (Test-Path "$opensslPrefix/lib/libcrypto.lib")) { throw 'OpenSSL static libraries are missing' }
if ($DependenciesOnly) { return }

# Adapt only the build configurations in this clean CI checkout.
function Read-ProjectXml([string]$path) {
    $xml = [xml](Get-Content -LiteralPath $path -Raw)
    return ,$xml
}
$namespaceManager = [Xml.XmlNamespaceManager]::new([Xml.NameTable]::new())
$namespaceManager.AddNamespace('m', 'http://schemas.microsoft.com/developer/msbuild/2003')
$luaPath = "$repoRoot/liblua/liblua.vcxproj"
$lua = Read-ProjectXml $luaPath
# Duplicate Release into a genuine Static configuration for project references.
$releaseNodes = @($lua.SelectNodes('//*[@Condition]', $namespaceManager) | Where-Object {
    $_.GetAttribute('Condition') -match "=='Release\|Win32'"
})
foreach ($node in $releaseNodes) {
    $copy = $node.CloneNode($true)
    $copy.SetAttribute('Condition', $node.GetAttribute('Condition').Replace('Release|Win32', 'Static|Win32'))
    foreach ($runtime in $copy.SelectNodes('.//m:RuntimeLibrary', $namespaceManager)) {
        $runtime.InnerText = 'MultiThreaded'
    }
    [void]$node.ParentNode.InsertAfter($copy, $node)
}
$config = $lua.SelectSingleNode('//m:ProjectConfiguration[@Include="Release|Win32"]', $namespaceManager).CloneNode($true)
$config.SetAttribute('Include', 'Static|Win32')
$config.Configuration = 'Static'
[void]$lua.SelectSingleNode('//m:ItemGroup[@Label="ProjectConfigurations"]', $namespaceManager).AppendChild($config)
$lua.Save($luaPath)

$ncatPath = "$repoRoot/ncat/ncat.vcxproj"
$ncat = Read-ProjectXml $ncatPath
$staticNcat = $ncat.SelectSingleNode('//m:ItemDefinitionGroup[contains(@Condition,"Static|Win32")]', $namespaceManager)
$staticNcat.ClCompile.AdditionalIncludeDirectories = '..\liblua;' + $staticNcat.ClCompile.AdditionalIncludeDirectories
$staticNcat.Link.AdditionalDependencies += ';crypt32.lib;liblua.lib'
$staticNcat.Link.AdditionalLibraryDirectories += ';..\liblua'
$ncat.Save($ncatPath)

& msbuild ncat/ncat.vcxproj /m /t:Build /p:Configuration=Static /p:Platform=Win32 /p:PlatformToolset=v143 /p:WindowsTargetPlatformVersion=10.0 /verbosity:minimal
$out = New-Item -ItemType Directory -Force "$repoRoot/portable-output"
Copy-Item ncat/Release/ncat.exe $out
Copy-Item LICENSE "$out/NMAP-LICENSE.txt"
Copy-Item "$opensslSource/LICENSE.txt" "$out/OPENSSL-LICENSE.txt"
Copy-Item docs/licenses/Lua-license.txt "$out/LUA-LICENSE.txt"
$provenance = [ordered]@{
    source_repository = ((& git remote get-url origin) -replace '\.git$', '')
    upstream_repository = 'https://github.com/nmap/nmap'
    source_commit = (& git rev-parse HEAD)
    ncat_version = ((& "$out/ncat.exe" --version 2>&1) | Out-String).Trim()
    openssl_version = '3.5.9'
    openssl_commit = $opensslCommit
    architecture = 'x86'
    runtime = 'MSVC /MT'
    openssl_options = 'VC-WIN32 no-shared no-module no-tests --libdir=lib'
    runner = $env:ImageVersion
    workflow_run = "https://github.com/$env:GITHUB_REPOSITORY/actions/runs/$env:GITHUB_RUN_ID"
    sha256 = (Get-FileHash "$out/ncat.exe" -Algorithm SHA256).Hash.ToLowerInvariant()
}
$provenance | ConvertTo-Json | Set-Content "$out/build-info.json" -Encoding utf8
"$($provenance.sha256)  ncat.exe" | Set-Content "$out/SHA256SUMS.txt" -Encoding ascii
