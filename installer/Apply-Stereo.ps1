param([string]$GamePath,[ValidateSet('Apply','Restore')][string]$Action='Apply')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
try {
 if(-not $GamePath) {$GamePath=(Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'installed-location.json')|ConvertFrom-Json).gamePath}
 $GamePath=(Resolve-Path -LiteralPath $GamePath).Path
 if(-not(Test-Path -LiteralPath (Join-Path $GamePath 're2.exe'))) {throw 're2.exe missing.'}
 if(Get-Process -Name re2 -ErrorAction SilentlyContinue) {throw 'Close RE2 before changing stereo renderer.'}
 $stateDir=Join-Path $GamePath '.re2ivr'
 $install=Get-Content -Raw -LiteralPath (Join-Path $stateDir 'setup.json')|ConvertFrom-Json
 if($install.branch -ne 'RT') {Write-Output 'NonRT: existing stereo renderer preserved.';exit 0}
 $path=Join-Path $GamePath 're2_fw_config.txt'
 $statePath=Join-Path $stateDir 'stereo-afr-084.json'
 $key='VR_AlternateFrameRendering'
 $pattern='(?m)^'+$key+'=[^\r\n]*'
 $text=$(if(Test-Path -LiteralPath $path){[IO.File]::ReadAllText($path)}else{''})
 $state=$null
 if(Test-Path -LiteralPath $statePath) {$state=Get-Content -Raw -LiteralPath $statePath|ConvertFrom-Json}
 if($Action -eq 'Restore') {
  if(-not $state) {throw 'No saved stereo profile.'}
  $text=[regex]::Replace($text,$pattern,'')
  if($state.original -ne $null) {$text+="`r`n"+$key+'='+$state.original+"`r`n"}
  [IO.File]::WriteAllText($path,$text,(New-Object Text.UTF8Encoding($false)))
  $state.disabled=$true
  $state|ConvertTo-Json|Set-Content -LiteralPath $statePath -Encoding UTF8
  Write-Output 'Previous AFR setting restored; automatic AFR workaround disabled.';exit 0
 }
 if($state -and $state.disabled) {Write-Output 'Stereo workaround was explicitly restored; preserving user choice.';exit 0}
 if(-not $state) {
  $match=[regex]::Match($text,$pattern)
  $original=$(if($match.Success){$match.Value.Substring(($key+'=').Length)}else{$null})
  $state=@{schema=1;original=$original;disabled=$false}
  $state|ConvertTo-Json|Set-Content -LiteralPath $statePath -Encoding UTF8
 }
 if($text -match $pattern) {$text=[regex]::Replace($text,$pattern,$key+'=true')}
 else {$text+="`r`n"+$key+'=true'+"`r`n"}
 [IO.File]::WriteAllText($path,$text,(New-Object Text.UTF8Encoding($false)))
 Write-Output 'RT stereo compatibility: AFR enabled automatically. Eye geometry, resolution and async mode unchanged. Actual body visibility requires headset testing.'
} catch {Write-Error $_;exit 1}
