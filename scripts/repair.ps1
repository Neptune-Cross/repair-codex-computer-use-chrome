param(
  [switch]$ForceRepair,
  [switch]$SkipProtocolFix,
  [switch]$SkipChromeNativeHost,
  [switch]$Json
)

$ErrorActionPreference = 'Stop'

function Write-Step {
  param([string]$Message)
  if (-not $Json) {
    Write-Host "[codex-cu-chrome-repair] $Message"
  }
}

function New-BackupDir {
  $dir = Join-Path $script:CodexHome ('backups\computer-use-chrome-skill\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  return $dir
}

function Copy-IfExists {
  param([string]$Path, [string]$DestinationDir)
  if (Test-Path -LiteralPath $Path -PathType Leaf) {
    Copy-Item -LiteralPath $Path -Destination $DestinationDir -Force
  }
}

function Invoke-Capture {
  param([scriptblock]$Script)
  $output = @()
  $ok = $true
  $exitCode = 0
  try {
    $global:LASTEXITCODE = 0
    $output = & $Script *>&1
    $exitCode = $global:LASTEXITCODE
    if ($exitCode -ne 0) {
      $ok = $false
    }
  } catch {
    $ok = $false
    $output += $_
    $exitCode = if ($global:LASTEXITCODE -ne $null) { $global:LASTEXITCODE } else { 1 }
  }
  return [pscustomobject]@{
    Ok = $ok
    ExitCode = $exitCode
    Text = (($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
  }
}

function Get-CodexCliPath {
  $configPath = Join-Path $script:CodexHome 'config.toml'
  if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    $match = Select-String -LiteralPath $configPath -Pattern 'CODEX_CLI_PATH\s*=\s*["'']([^"'']+)["'']' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($match) {
      $configuredPath = [Environment]::ExpandEnvironmentVariables($match.Matches[0].Groups[1].Value)
      if (Test-Path -LiteralPath $configuredPath -PathType Leaf) {
        return (Resolve-Path -LiteralPath $configuredPath).Path
      }
    }
  }

  $binRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
  $candidate = Get-ChildItem -Path $binRoot -Filter codex.exe -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if (-not $candidate) {
    throw "cannot find user-local codex.exe under $binRoot"
  }
  return $candidate.FullName
}

function Get-PluginVersion {
  param([string]$PluginRoot)
  $pluginJson = Join-Path $PluginRoot '.codex-plugin\plugin.json'
  if (-not (Test-Path -LiteralPath $pluginJson -PathType Leaf)) {
    throw "missing plugin manifest: $pluginJson"
  }
  return [string]((Get-Content -Raw -LiteralPath $pluginJson | ConvertFrom-Json).version)
}

function Get-LatestPluginCacheRoot {
  param([string]$PluginName)
  $root = Join-Path $script:CodexHome "plugins\cache\openai-bundled\$PluginName"
  if (-not (Test-Path -LiteralPath $root)) {
    throw "missing plugin cache root: $root"
  }
  $versionDir = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
    Where-Object {
      ($_.Name -ne 'latest') -and
      (Test-Path -LiteralPath (Join-Path $_.FullName '.codex-plugin\plugin.json'))
    } |
    Sort-Object @{
      Expression = {
        try { [version](Get-PluginVersion $_.FullName) } catch { [version]'0.0.0' }
      }
      Descending = $true
    }, LastWriteTime -Descending |
    Select-Object -First 1
  if (-not $versionDir) {
    throw "no versioned cache found for $PluginName under $root"
  }
  return $versionDir.FullName
}

function Get-NodeRuntimeBin {
  $runtimeRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\runtimes\cua_node'
  $candidate = Get-ChildItem -Path $runtimeRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object {
      (Test-Path -LiteralPath (Join-Path $_.FullName 'bin\node.exe') -PathType Leaf) -and
      (Test-Path -LiteralPath (Join-Path $_.FullName 'bin\node_repl.exe') -PathType Leaf)
    } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if (-not $candidate) {
    throw "cannot find local cua_node runtime under $runtimeRoot"
  }
  return (Join-Path $candidate.FullName 'bin')
}

function Ensure-ChromeNativeHost {
  param([string]$CodexCliPath)

  $chromeRoot = Get-LatestPluginCacheRoot 'chrome'
  $latestRoot = Join-Path $script:CodexHome 'plugins\cache\openai-bundled\chrome\latest'
  $installManifest = Join-Path $latestRoot 'scripts\installManifest.mjs'
  if (-not (Test-Path -LiteralPath $installManifest -PathType Leaf)) {
    $installManifest = Join-Path $chromeRoot 'scripts\installManifest.mjs'
  }
  if (-not (Test-Path -LiteralPath $installManifest -PathType Leaf)) {
    throw "missing Chrome installManifest.mjs"
  }

  $nodeBin = Get-NodeRuntimeBin
  $nodePath = Join-Path $nodeBin 'node.exe'
  $nodeReplPath = Join-Path $nodeBin 'node_repl.exe'
  $installUri = ([Uri](Resolve-Path -LiteralPath $installManifest).Path).AbsoluteUri
  $js = "const [codexCliPath,nodePath,nodeReplPath]=process.argv.slice(1); const mod=await import('$installUri'); await mod.install({appServerRuntimePaths:{codexCliPath,nodePath,nodeReplPath}});"

  Write-Step "regenerating Chrome Native Messaging manifest"
  & $nodePath --input-type=module -e $js $CodexCliPath $nodePath $nodeReplPath | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Chrome installManifest.mjs failed"
  }

  $manifestPath = Join-Path $env:LOCALAPPDATA 'OpenAI\extension\com.openai.codexextension.json'
  $hostPath = Join-Path $chromeRoot 'extension-host\windows\x64\extension-host.exe'
  $browserClientPath = Join-Path $chromeRoot 'scripts\browser-client.mjs'
  $hostConfigPath = Join-Path $chromeRoot 'extension-host\windows\x64\extension-host-config.json'

  foreach ($path in @($manifestPath, $hostPath, $browserClientPath, $hostConfigPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      throw "missing Chrome native-host required path: $path"
    }
  }

  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
  $manifest.path = $hostPath
  [System.IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 20) + [Environment]::NewLine), $utf8NoBom)

  $hostConfig = Get-Content -Raw -LiteralPath $hostConfigPath | ConvertFrom-Json
  $hostConfig.browserClientPath = $browserClientPath
  $hostConfig.codexCliPath = $CodexCliPath
  $hostConfig.nodePath = $nodePath
  $hostConfig.nodeReplPath = $nodeReplPath
  [System.IO.File]::WriteAllText($hostConfigPath, (($hostConfig | ConvertTo-Json -Depth 20) + [Environment]::NewLine), $utf8NoBom)

  reg add HKCU\Software\Google\Chrome\NativeMessagingHosts\com.openai.codexextension /ve /t REG_SZ /d $manifestPath /f | Out-Null
}

function Try-EnsureChromeNativeHost {
  param([string]$CodexCliPath, [string]$Phase)

  try {
    Ensure-ChromeNativeHost -CodexCliPath $CodexCliPath
    return [pscustomobject]@{
      Ok = $true
      Text = "Chrome native-host normalized during $Phase"
    }
  } catch {
    $message = $_.Exception.Message
    Write-Step "Chrome native-host normalization skipped during ${Phase}: $message"
    return [pscustomobject]@{
      Ok = $false
      Text = $message
    }
  }
}

function Get-CurrentCodexPackageId {
  $appx = $null
  try {
    $appx = Get-AppxPackage -Name OpenAI.Codex -ErrorAction Stop |
      Sort-Object Version -Descending |
      Select-Object -First 1
  } catch {
    $appx = $null
  }
  if ($appx -and $appx.PackageFullName) {
    return [string]$appx.PackageFullName
  }

  $appxKey = 'HKCU\Software\Classes\AppXybfp6cjpb1wf0pftw0fd4bz59gzn1401\Shell\open'
  $query = Invoke-Capture { reg query $appxKey /v PackageId }
  if ($query.Ok -and $query.Text -match 'PackageId\s+REG_SZ\s+(\S+)') {
    return $Matches[1]
  }

  $windowsApps = 'C:\Program Files\WindowsApps'
  $dir = Get-ChildItem -Path $windowsApps -Directory -Filter 'OpenAI.Codex_*_x64__2p2nqsd0c76g0' -ErrorAction SilentlyContinue |
    Sort-Object @{
      Expression = {
        if ($_.Name -match '^OpenAI\.Codex_([0-9.]+)_') { [version]$Matches[1] } else { [version]'0.0.0' }
      }
      Descending = $true
    }, LastWriteTime -Descending |
    Select-Object -First 1
  if (-not $dir) {
    throw "cannot determine current OpenAI.Codex AppX package id"
  }
  return $dir.Name
}

function Sync-CodexProtocol {
  $packageId = Get-CurrentCodexPackageId
  $icon = "@{$packageId`?ms-resource://OpenAI.Codex/Files/assets/Square44x44Logo.png}"

  Write-Step "syncing codex:// protocol to $packageId"
  reg add HKCU\Software\Classes\codex /ve /t REG_SZ /d 'URL:codex' /f | Out-Null
  New-Item -Path 'HKCU:\Software\Classes\codex' -Force | Out-Null
  New-ItemProperty -Path 'HKCU:\Software\Classes\codex' -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null
  reg add HKCU\Software\Classes\codex\Application /v ApplicationName /t REG_SZ /d Codex /f | Out-Null
  reg add HKCU\Software\Classes\codex\Application /v ApplicationCompany /t REG_SZ /d OpenAI /f | Out-Null
  reg add HKCU\Software\Classes\codex\Application /v ApplicationIcon /t REG_SZ /d $icon /f | Out-Null
  reg add HKCU\Software\Classes\codex\Application /v ApplicationDescription /t REG_SZ /d Codex /f | Out-Null
  reg add HKCU\Software\Classes\codex\Application /v AppUserModelID /t REG_SZ /d 'OpenAI.Codex_2p2nqsd0c76g0!App' /f | Out-Null
  reg add HKCU\Software\Classes\codex\DefaultIcon /ve /t REG_SZ /d $icon /f | Out-Null
  reg add HKCU\Software\Classes\codex\Shell\open /v AppUserModelID /t REG_SZ /d 'OpenAI.Codex_2p2nqsd0c76g0!App' /f | Out-Null
  reg add HKCU\Software\Classes\codex\Shell\open /v PackageRelativeExecutable /t REG_SZ /d 'app\Codex.exe' /f | Out-Null
  reg add HKCU\Software\Classes\codex\Shell\open /v DesktopAppXActivateOptions /t REG_DWORD /d 0x20 /f | Out-Null
  reg add HKCU\Software\Classes\codex\Shell\open /v ContractId /t REG_SZ /d 'Windows.Protocol' /f | Out-Null
  reg add HKCU\Software\Classes\codex\Shell\open /v DesiredInitialViewState /t REG_DWORD /d 0x0 /f | Out-Null
  reg add HKCU\Software\Classes\codex\Shell\open /v PackageId /t REG_SZ /d $packageId /f | Out-Null
  reg add HKCU\Software\Classes\codex\Shell\open\command /v DelegateExecute /t REG_SZ /d '{A56A841F-E974-45C1-8001-7E3F8A085917}' /f | Out-Null

  return $packageId
}

function Test-ChromeScripts {
  $chromeRoot = Get-LatestPluginCacheRoot 'chrome'
  $nodePath = Join-Path (Get-NodeRuntimeBin) 'node.exe'
  $nativeCheck = Join-Path $chromeRoot 'scripts\check-native-host-manifest.js'
  $extensionCheck = Join-Path $chromeRoot 'scripts\check-extension-installed.js'

  $native = Invoke-Capture { & $nodePath $nativeCheck --json }
  $extension = Invoke-Capture { & $nodePath $extensionCheck --json }
  return [pscustomobject]@{
    NativeHostOk = $native.Ok
    NativeHost = $native.Text
    ExtensionOk = $extension.Ok
    Extension = $extension.Text
  }
}

$script:CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$script:CodexHome = (Resolve-Path -LiteralPath $script:CodexHome).Path
$engine = Join-Path $script:CodexHome 'skills\codex-windows-fast-patch\scripts\install-computer-use-local.ps1'
if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) {
  throw "missing repair engine: $engine"
}

$backupDir = New-BackupDir
Copy-IfExists (Join-Path $script:CodexHome 'config.toml') $backupDir
Copy-IfExists (Join-Path $script:CodexHome '.codex-global-state.json') $backupDir
Copy-IfExists (Join-Path $script:CodexHome 'chrome-native-hosts.json') $backupDir
Copy-IfExists (Join-Path $env:LOCALAPPDATA 'OpenAI\extension\com.openai.codexextension.json') $backupDir
reg export HKCU\Software\Google\Chrome\NativeMessagingHosts\com.openai.codexextension (Join-Path $backupDir 'chrome-native-host.reg') /y 2>$null | Out-Null
reg export HKCU\Software\Classes\codex (Join-Path $backupDir 'codex-url-protocol.reg') /y 2>$null | Out-Null

$codexCli = Get-CodexCliPath
Write-Step "using codex.exe: $codexCli"

$nativeHostPreflight = $null
if (-not $SkipChromeNativeHost) {
  $nativeHostPreflight = Try-EnsureChromeNativeHost -CodexCliPath $codexCli -Phase 'preflight'
}

$strictBefore = Invoke-Capture { & $engine -StrictVerifyOnly }
$ranRepair = $false
if ($ForceRepair -or -not $strictBefore.Ok) {
  Write-Step "strict verification failed or repair forced; running -VerifyOnly"
  $repair = Invoke-Capture { & $engine -VerifyOnly }
  if (-not $repair.Ok) {
    throw $repair.Text
  }
  $ranRepair = $true
} else {
  $repair = [pscustomobject]@{ Ok = $true; Text = 'strict verification already ok' }
}

if (-not $SkipChromeNativeHost) {
  if ($ranRepair -or -not $nativeHostPreflight.Ok) {
    Ensure-ChromeNativeHost -CodexCliPath $codexCli
  }
}

$packageId = $null
if (-not $SkipProtocolFix) {
  $packageId = Sync-CodexProtocol
}

$strictAfter = Invoke-Capture { & $engine -StrictVerifyOnly }
if (-not $strictAfter.Ok) {
  throw $strictAfter.Text
}

$marketplace = Invoke-Capture { & $codexCli plugin marketplace list }
$plugins = Invoke-Capture { & $codexCli plugin list }
$chromeChecks = if ($SkipChromeNativeHost) { $null } else { Test-ChromeScripts }

$result = [pscustomobject]@{
  ok = $true
  backupDir = $backupDir
  codexCli = $codexCli
  packageId = $packageId
  nativeHostPreflight = if ($nativeHostPreflight) { $nativeHostPreflight.Text } else { $null }
  repair = $repair.Text
  strictVerification = $strictAfter.Text
  marketplace = $marketplace.Text
  bundledPlugins = (($plugins.Text -split "`r?`n") | Where-Object { $_ -match 'openai-bundled|browser@openai-bundled|chrome@openai-bundled|computer-use@openai-bundled' }) -join [Environment]::NewLine
  chromeNativeHostOk = if ($chromeChecks) { $chromeChecks.NativeHostOk } else { $null }
  chromeExtensionOk = if ($chromeChecks) { $chromeChecks.ExtensionOk } else { $null }
}

if ($Json) {
  $result | ConvertTo-Json -Depth 8
} else {
  Write-Step "backup: $backupDir"
  Write-Step "strict verification: ok"
  Write-Step "bundled plugin status:"
  Write-Host $result.bundledPlugins
  if ($chromeChecks) {
    Write-Step "Chrome native-host check ok: $($chromeChecks.NativeHostOk)"
    Write-Step "Chrome extension check ok: $($chromeChecks.ExtensionOk)"
  }
  Write-Step "done"
}
