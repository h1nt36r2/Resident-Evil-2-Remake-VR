param([string]$GamePath,[ValidateSet('Apply','Restore')][string]$Action='Apply')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function Set-Entry([string]$Text,[string]$Section,[string]$Key,[string]$Value) {
    $lines=New-Object 'System.Collections.Generic.List[string]'
    foreach($line in ($Text -split "`r?`n")) {$lines.Add($line)}
    $begin=0;$end=$lines.Count
    if($Section) {
        $begin=-1
        for($i=0;$i -lt $lines.Count;$i++) {if($lines[$i].Trim() -ieq "[$Section]") {$begin=$i+1;break}}
        if($begin -lt 0) {$lines.Add("[$Section]");$begin=$lines.Count;$end=$lines.Count}
        else {for($i=$begin;$i -lt $lines.Count;$i++) {if($lines[$i] -match '^\s*\[') {$end=$i;break}}}
    }
    $found=$false
    for($i=$begin;$i -lt $end;$i++) {
        if($lines[$i] -match ('^\s*'+[regex]::Escape($Key)+'\s*=')) {$lines[$i]="$Key=$Value";$found=$true}
    }
    if(-not $found) {$lines.Insert($end,"$Key=$Value")}
    return [string]::Join("`r`n",$lines)
}
try {
    if(-not $GamePath) {$GamePath=(Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'installed-location.json')|ConvertFrom-Json).gamePath}
    $GamePath=(Resolve-Path -LiteralPath $GamePath).Path
    if(-not(Test-Path -LiteralPath (Join-Path $GamePath 're2.exe'))) {throw 're2.exe missing.'}
    if(Get-Process -Name re2 -ErrorAction SilentlyContinue) {throw 'Close RE2 before changing VR configuration.'}
    $stateDir=Join-Path $GamePath '.re2ivr'
    New-Item -ItemType Directory -Path $stateDir -Force|Out-Null
    $stateFile=Join-Path $stateDir 'presentation-profile.json'
    if($Action -eq 'Restore') {
        $state=Get-Content -Raw -LiteralPath $stateFile|ConvertFrom-Json
        foreach($row in $state.files) {
            if(@('re2_fw_config.txt','re2_config.ini') -notcontains $row.name) {throw 'Unexpected config path.'}
            $source=[IO.Path]::GetFullPath((Join-Path $stateDir $row.backup))
            if(-not $source.StartsWith($stateDir+'\',[StringComparison]::OrdinalIgnoreCase)) {throw 'Unsafe backup path.'}
            if($row.existed) {Copy-Item -LiteralPath $source -Destination (Join-Path $GamePath $row.name) -Force}
        }
        Write-Output 'Previous game/VR configuration restored. Restart RE2.';exit 0
    }
    $generation='presentation-'+[Guid]::NewGuid().ToString('N')
    $backupDir=Join-Path $stateDir $generation
    New-Item -ItemType Directory -Path $backupDir|Out-Null
    $files=@();$originals=@{};$updates=@{}
    foreach($name in @('re2_fw_config.txt','re2_config.ini')) {
        $p=Join-Path $GamePath $name;$exists=Test-Path -LiteralPath $p
        $originals[$name]=$(if($exists){[IO.File]::ReadAllBytes($p)}else{$null})
        $text=$(if($exists){[IO.File]::ReadAllText($p)}else{''})
        if($exists) {Copy-Item -LiteralPath $p -Destination (Join-Path $backupDir $name)}
        $files+=@{name=$name;existed=$exists;backup=$generation+'\'+$name}
        $updates[$name]=$text
    }
    $framework=[ordered]@{
        FirstPerson_Enabled='true';FirstPerson_HideJointMesh='true';FirstPerson_ForceRotateMesh='true'
        FirstPerson_DisableVignette='true';FirstPerson_ShowInCutscenes='false'
        VR_DecoupledPitch='true';VR_ForceLensDistortion='true';VR_ForceMotionBlur='true'
        VR_ForceVSync='true';VR_ForceAntiAliasing='true';VR_ForceFPS='false'
        VR_2DUIScale='16.000000';VR_2DUIDistance='1.250000'
    }
    foreach($key in $framework.Keys) {$updates['re2_fw_config.txt']=Set-Entry $updates['re2_fw_config.txt'] '' $key $framework[$key]}
    # Recover only the two renderer switches that our 0.4.1+ profile overwrote.
    # Do not replace the full user's config or guess a branch-specific renderer mode.
    $recoveryFile=Join-Path $stateDir 'renderer-recovery-055.json'
    $rendererRecovered=@{}
    if(-not(Test-Path -LiteralPath $recoveryFile)) {
        $oldConfig=Join-Path $stateDir 'config-before-mvp.txt'
        if(Test-Path -LiteralPath $oldConfig) {
            $oldText=[IO.File]::ReadAllText($oldConfig)
            foreach($key in @('VR_AsyncRendering_V3','VR_AlternateFrameRendering')) {
                $match=[regex]::Match($oldText,'(?m)^'+[regex]::Escape($key)+'=(true|false)\s*$')
                if($match.Success) {
                    $updates['re2_fw_config.txt']=Set-Entry $updates['re2_fw_config.txt'] '' $key $match.Groups[1].Value
                    $rendererRecovered[$key]=$match.Groups[1].Value
                }
            }
        }
    }
    $game=[ordered]@{
        NormalWindowResolution='(1280.000000,720.000000)';WindowMode='Normal';FullScreenMode='false'
        PCMotionBlurEnable='0';PCLensDistortion='0';PCLensFlareEnable='0';PCVSync='0'
    }
    foreach($key in $game.Keys) {$updates['re2_config.ini']=Set-Entry $updates['re2_config.ini'] 'RenderConfig' $key $game[$key]}
    $updates['re2_config.ini']=Set-Entry $updates['re2_config.ini'] 'Display' 'HDRmode' '0'
    # This is only the desktop mirror size. Eye projections/IPD remain runtime-owned.
    try {
        foreach($name in $updates.Keys) {[IO.File]::WriteAllText((Join-Path $GamePath $name),$updates[$name],(New-Object Text.UTF8Encoding($false)))}
        @{schema=1;profile='SteamVR-0.5.5';files=$files}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $stateFile -Encoding UTF8
        if(-not(Test-Path -LiteralPath $recoveryFile)) {@{schema=1;recovered=$rendererRecovered}|ConvertTo-Json|Set-Content -LiteralPath $recoveryFile -Encoding UTF8}
    } catch {
        foreach($name in $originals.Keys) {
            $target=Join-Path $GamePath $name
            if($null -ne $originals[$name]) {[IO.File]::WriteAllBytes($target,$originals[$name])}
            elseif(Test-Path -LiteralPath $target) {Remove-Item -LiteralPath $target}
        }
        throw
    }
    Write-Output 'SteamVR profile applied: renderer switches recovered from original backup when available; force-600-FPS disabled. Restart RE2. No IPD/eye offsets changed.'
} catch {Write-Error $_;exit 1}
