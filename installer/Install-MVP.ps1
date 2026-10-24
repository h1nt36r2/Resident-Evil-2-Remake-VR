param([string]$GamePath,[ValidateSet('Auto','RT','NonRT')][string]$Branch='Auto',[string]$FrameworkArchive)
$ErrorActionPreference='Stop'
try {
    $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Setup.ps1'),'-Action','Install','-Branch',$Branch)
    if($GamePath) {$arguments+=@('-GamePath',$GamePath)}
    if($FrameworkArchive) {$arguments+=@('-FrameworkArchive',$FrameworkArchive)}
    & powershell.exe @arguments
    if($LASTEXITCODE -ne 0) {exit $LASTEXITCODE}
    $location=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'installed-location.json')|ConvertFrom-Json
    $config=Join-Path $location.gamePath 're2_fw_config.txt'
    $backup=Join-Path $location.gamePath '.re2ivr\config-before-mvp.txt'
    $text=''
    if(Test-Path -LiteralPath $config) {
        if(-not(Test-Path -LiteralPath $backup)) {Copy-Item -LiteralPath $config -Destination $backup}
        $text=[IO.File]::ReadAllText($config)
    }
    # Only camera/weapon essentials; preserve the user's game graphics and SteamVR resolution.
    if($text -match '(?m)^FirstPerson_Enabled=.*$') {$text=[regex]::Replace($text,'(?m)^FirstPerson_Enabled=.*$','FirstPerson_Enabled=true')}
    else {$text+="`r`nFirstPerson_Enabled=true`r`n"}
    foreach($entry in @(@('FirstPerson_HideJointMesh','true'),@('VR_ForceFPS','false'))) {
        $key=$entry[0];$value=$entry[1]
        if($text -match ('(?m)^'+$key+'=.*$')) {$text=[regex]::Replace($text,'(?m)^'+$key+'=.*$',$key+'='+$value)}
        else {$text+="`r`n$key=$value`r`n"}
    }
    [IO.File]::WriteAllText($config,$text,(New-Object Text.UTF8Encoding($false)))
    Write-Output 'Installed. Game graphics preserved. Start SteamVR, then Play.cmd for spatial belt. Repair-SteamVR.cmd is optional.'
    exit 0
} catch {Write-Error $_;exit 1}
