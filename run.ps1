# Nuvio Boost for Windows: makes sideloaded Nuvio run like the Play Store
# version on Android TV, Google TV, Nvidia Shield and Fire TV.
# https://github.com/Blorp-blorp/nuvio-boost
#
# Wrapped in a script block so nothing runs unless the whole script
# downloaded, and so it never closes your PowerShell window.

& {
  $ErrorActionPreference = 'Continue'
  $ProgressPreference = 'SilentlyContinue'
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  } catch {}

  $AppDir      = Join-Path $env:LOCALAPPDATA 'nuvio-boost'
  $SavedFile   = Join-Path $AppDir 'devices.txt'
  $LocalAdb    = Join-Path $AppDir 'platform-tools\adb.exe'
  $DefaultPort = 5555
  $ctx         = @{ Final = '' }

  function Ok($m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
  function Warn($m) { Write-Host "  [!]  $m" -ForegroundColor Yellow }
  function Fail($m) { Write-Host "  [X]  $m" -ForegroundColor Red }
  function Info($m) { Write-Host "  $m" }

  # Run adb and return its combined output as one trimmed string
  function Invoke-Adb([string[]]$A) {
    $out = & $Adb @A 2>&1 | ForEach-Object { "$_" }
    return (($out -join "`n") -replace "`r", '').Trim()
  }

  Write-Host "`nNuvio Boost`n" -ForegroundColor White

  # ---- Get adb -----------------------------------------------------------
  $cmd = Get-Command adb -ErrorAction SilentlyContinue
  if ($cmd) {
    $Adb = $cmd.Path
    Ok "Using adb already installed at $Adb"
  } elseif (Test-Path $LocalAdb) {
    $Adb = $LocalAdb
    Ok "Using adb from a previous run"
  } else {
    Info "Downloading Android platform-tools (adb) from Google..."
    try {
      New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
      $zip = Join-Path $AppDir 'platform-tools.zip'
      Invoke-WebRequest -UseBasicParsing -Uri 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip' -OutFile $zip
      $ptDir = Join-Path $AppDir 'platform-tools'
      if (Test-Path $ptDir) { Remove-Item -Recurse -Force $ptDir }
      Expand-Archive -Path $zip -DestinationPath $AppDir -Force
      Remove-Item $zip -Force
    } catch {
      Fail "Download failed: $($_.Exception.Message)"
      return
    }
    $Adb = $LocalAdb
    if (-not (Test-Path $Adb)) { Fail "Could not unpack adb."; return }
    Ok "adb ready"
  }

  # Fresh adb server avoids stale connections
  Invoke-Adb @('kill-server')  | Out-Null
  Invoke-Adb @('start-server') | Out-Null

  # ---- Newer Google TV: Wireless debugging + one-time pairing -----------
  function Connect-Wireless {
    Info "On the TV: Developer options > Wireless debugging (turn it on)."
    $main = Read-Host "  IP address & port shown on the Wireless debugging screen (e.g. 192.168.1.50:37123)"
    if (-not $main) { return $false }
    $o = Invoke-Adb @('connect', $main)
    Start-Sleep -Seconds 2
    if ($o -match 'connected to') {
      $st = Invoke-Adb @('-s', $main, 'get-state')
      if ($st -eq 'device') { Ok "Connected"; $ctx.Final = $main; return $true }
    }
    Invoke-Adb @('disconnect', $main) | Out-Null
    Info "This computer needs to be paired with the TV once."
    Info "On the TV: Wireless debugging > Pair device with pairing code."
    $pairAddr = Read-Host "  IP address & port shown in the pairing popup"
    $code     = Read-Host "  Pairing code"
    $o = Invoke-Adb @('pair', $pairAddr, $code)
    if ($o -notmatch 'Successfully paired') { Fail "Pairing failed: $o"; return $false }
    Ok "Paired"
    $o = Invoke-Adb @('connect', $main)
    if ($o -notmatch 'connected to') { Fail "Couldn't connect: $o"; return $false }
    Ok "Connected"
    $ctx.Final = $main
    return $true
  }

  # ---- Boost one TV ------------------------------------------------------
  function Boost-Tv([string]$target) {
    $ctx.Final = $target

    $out = Invoke-Adb @('connect', $target)
    if ($out -match 'connected to') {
      Ok "Connected"
    } else {
      Fail "Couldn't connect: $out"
      Info "Check: the TV is on, the IP is right, and ADB / Network debugging is turned on."
      $yn = Read-Host "  Is this a newer Google TV using 'Wireless debugging'? [y/N]"
      if ($yn -notmatch '^(y|yes)$') { return $false }
      if (-not (Connect-Wireless)) { return $false }
      $target = $ctx.Final
    }

    # Wait for the "Allow debugging?" popup to be accepted
    $state = ''
    $warned = $false
    for ($i = 0; $i -lt 90; $i++) {
      $state = Invoke-Adb @('-s', $target, 'get-state')
      if ($state -eq 'device') { break }
      if (-not $warned) {
        Warn "Look at your TV: allow debugging and tick 'Always allow from this computer'."
        $warned = $true
      }
      Start-Sleep -Seconds 1
    }
    if ($state -ne 'device') {
      Fail "The TV didn't authorize this computer. Run again and accept the popup on the TV."
      return $false
    }

    $list = Invoke-Adb @('-s', $target, 'shell', 'pm', 'list', 'packages')
    $pkgs = @($list -split "`n" | Where-Object { $_ -match 'nuvio' } | ForEach-Object { ($_ -replace '^package:', '').Trim() })
    if ($pkgs.Count -eq 0) { Fail "Nuvio isn't installed on this TV."; return $false }

    $allOk = $true
    foreach ($p in $pkgs) {
      Info "Compiling $p (can take 1-2 minutes)..."
      $res = Invoke-Adb @('-s', $target, 'shell', 'pm', 'compile', '-m', 'speed', '-f', $p)
      if ($res -match 'Success') { Ok "Boosted $p" } else { Fail "Compile failed for ${p}: $res"; $allOk = $false }
    }
    Invoke-Adb @('disconnect', $target) | Out-Null
    return $allOk
  }


  # ---- One-word shortcut for next time -----------------------------------
  # Saves a copy of this script locally and points the shortcut at that file,
  # so the shortcut never downloads-and-runs code (which antivirus rightly flags).
  function Install-Shortcut {
    $dir     = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
    $cmdFile = Join-Path $dir 'nuvioboost.cmd'
    $local   = Join-Path $AppDir 'nuvio-boost.ps1'
    $marker  = Join-Path $AppDir 'no-shortcut'
    $url     = 'https://raw.githubusercontent.com/Blorp-blorp/nuvio-boost/main/run.ps1'
    $line    = '@powershell -NoProfile -ExecutionPolicy RemoteSigned -File "%LOCALAPPDATA%\nuvio-boost\nuvio-boost.ps1"'

    $exists = Test-Path $cmdFile
    $isOld  = $exists -and ((Get-Content $cmdFile -Raw) -match 'iex')

    # Already set up and running from the saved copy: nothing to do
    if ($exists -and -not $isOld -and $PSCommandPath) { return $true }

    if (-not $exists) {
      if ((Test-Path $marker) -or -not (Test-Path $dir)) { return $false }
      Write-Host ""
      $yn = Read-Host "  Create a 'nuvioboost' shortcut so next time you just type nuvioboost? [Y/n]"
      if ($yn -match '^(n|no)$') { New-Item -ItemType File -Force -Path $marker | Out-Null; return $false }
    }

    try {
      $code = Invoke-RestMethod -UseBasicParsing -Uri $url
      Set-Content -Path $local -Value $code -Encoding UTF8
      Set-Content -Path $cmdFile -Value $line -Encoding ASCII
    } catch {
      Warn "Couldn't create the shortcut."
      return $false
    }
    if (-not $exists) { Ok "Shortcut added." } elseif ($isOld) { Ok "Shortcut updated." }
    return $true
  }

  # ---- Which TVs? ----------------------------------------------------------
  $saved = @()
  if (Test-Path $SavedFile) { $saved = @(Get-Content $SavedFile | Where-Object { $_.Trim() }) }
  Write-Host ""
  if ($saved.Count -gt 0) {
    Info "Saved TVs: $($saved -join ' ')"
    $inp = Read-Host "  Press Enter to use these, or type new IP addresses (space-separated)"
    if (-not $inp) { $inp = $saved -join ' ' }
  } else {
    Info "Find your TV's IP address in its Settings > Network (e.g. 192.168.1.50)."
    $inp = Read-Host "  Enter TV IP address(es), separated by spaces"
  }
  if (-not $inp) { Fail "No IP address entered."; return }

  $used = @(); $total = 0; $done = 0
  foreach ($t in ($inp -split '\s+' | Where-Object { $_ })) {
    if ($t -notmatch ':') { $t = "${t}:$DefaultPort" }
    $total++
    Write-Host "`n$t" -ForegroundColor White
    if (Boost-Tv $t) { $done++ }
    $used += $ctx.Final
  }

  New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
  Set-Content -Path $SavedFile -Value $used
  Invoke-Adb @('kill-server') | Out-Null

  $hasShortcut = $false
  if ($done -gt 0) { $hasShortcut = Install-Shortcut }

  Write-Host ""
  if ($done -eq $total) {
    Ok "Done: $done of $total TV(s) boosted."
  } else {
    Warn "Done: $done of $total TV(s) boosted. Fix the issues above and run again."
  }
  if ($hasShortcut) {
    Write-Host "`n  After the next Nuvio update, open PowerShell or Command Prompt and type: nuvioboost" -ForegroundColor White
  } else {
    Info "Run this again after each Nuvio update."
  }
  Write-Host ""
}
