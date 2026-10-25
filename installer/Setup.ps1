param([ValidateSet('Install','Rollback','Uninstall')][string]$Action='Install',[string]$GamePath,
    [ValidateSet('Auto','RT','NonRT')][string]$Branch='Auto',[string]$FrameworkArchive,[switch]$Plan)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Hash([string]$p) {
    $s=[IO.File]::OpenRead($p);$a=[Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($a.ComputeHash($s)).Replace('-','') } finally {$s.Dispose();$a.Dispose()}
}
function WriteJson($o,[string]$p) { $o|ConvertTo-Json -Depth 40|Set-Content -LiteralPath $p -Encoding UTF8 }
function Child([string]$root,[string]$relative) {
    if([IO.Path]::IsPathRooted($relative) -or $relative.Contains(':')) {throw 'Unsafe package path.'}
    $p=[IO.Path]::GetFullPath((Join-Path $root $relative))
    if(-not $p.StartsWith($root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) {throw 'Path escapes installation folder.'}
    $parent=Split-Path $p
    while($parent.Length -ge $root.Length) {
        if(Test-Path -LiteralPath $parent) {
            if((Get-Item -LiteralPath $parent -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {throw 'Linked installation folders are not supported.'}
        }
        $parent=Split-Path $parent
    }
    if((Test-Path -LiteralPath $p) -and ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'Linked target file is not supported.'}
    return $p
}
try {
    $acf=$null
    if(-not $GamePath) {
        $key=Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue
        $roots=@()
        if($key -and $key.PSObject.Properties['InstallPath']) {
            $roots+= $key.InstallPath
            $vdf=Join-Path $key.InstallPath 'steamapps\libraryfolders.vdf'
            if(Test-Path -LiteralPath $vdf) {
                foreach($m in [regex]::Matches((Get-Content -Raw -LiteralPath $vdf),'"path"\s+"([^"]+)"')) {$roots+=$m.Groups[1].Value.Replace('\\','\')}
            }
        }
        $found=@()
        foreach($root in ($roots|Select-Object -Unique)) {
            $a=Join-Path $root 'steamapps\appmanifest_883710.acf'
            if(Test-Path -LiteralPath $a) {
                $text=Get-Content -Raw -LiteralPath $a
                $name=[regex]::Match($text,'"installdir"\s+"([^"]+)"').Groups[1].Value
                $dir=Join-Path (Join-Path $root 'steamapps\common') $name
                if(Test-Path -LiteralPath (Join-Path $dir 're2.exe')) {$found+=@{path=$dir;acf=$a}}
            }
        }
        if($found.Count -eq 1) {$GamePath=$found[0].path;$acf=$found[0].acf}
        else {$GamePath=Read-Host 'RE2 folder containing re2.exe'}
    }
    $GamePath=(Resolve-Path -LiteralPath $GamePath).Path
    if(-not (Test-Path -LiteralPath (Join-Path $GamePath 're2.exe'))) {throw 're2.exe missing.'}
    if(Get-Process -Name re2 -ErrorAction SilentlyContinue) {throw 'Close RE2 first.'}
    if(-not $acf) {
        $candidate=Join-Path (Split-Path (Split-Path $GamePath)) 'appmanifest_883710.acf'
        if(Test-Path -LiteralPath $candidate) {$acf=$candidate}
    }
    $stateDir=Child $GamePath '.re2ivr'
    $stateFile=Child $GamePath '.re2ivr\setup.json'
    $state=$null
    if(Test-Path -LiteralPath $stateFile) {$state=Get-Content -Raw -LiteralPath $stateFile|ConvertFrom-Json}
    if($state -and $state.schema -ne 2) {throw 'Unsupported setup state.'}
    if($state) {
        foreach($f in $state.files) {
            $dest=Child $GamePath $f.path
            if(-not (Test-Path -LiteralPath $dest) -or (Hash $dest) -ne $f.hash) {throw "Managed file missing or edited: $($f.path). Resolve before update/removal."}
        }
    }
    if($Action -ne 'Install') {
        if(-not $state) {throw 'No unified installation found.'}
        if($Plan) {Write-Output "$Action plan: restore previous managed files; no changes.";exit 0}
        do {
            # Verify the complete generation before changing any file.
            foreach($f in $state.files) {
                $dest=Child $GamePath $f.path
                if(-not (Test-Path -LiteralPath $dest) -or (Hash $dest) -ne $f.hash) {throw "Modified file: $($f.path)"}
                if($f.backup) {if((Hash (Child $stateDir $f.backup)) -ne $f.originalHash) {throw 'Backup corrupted.'}}
            }
            foreach($f in $state.files) {
                $dest=Child $GamePath $f.path
                if($f.backup) {Copy-Item -LiteralPath (Child $stateDir $f.backup) -Destination $dest -Force}
                else {Remove-Item -LiteralPath $dest}
            }
            $state=$state.previous
            if($state) {WriteJson $state ($stateFile+'.tmp');Move-Item -LiteralPath ($stateFile+'.tmp') -Destination $stateFile -Force}
            else {Remove-Item -LiteralPath $stateFile}
        } while($Action -eq 'Uninstall' -and $state)
        Write-Output 'Restored. User settings, saved games and backup history retained.';exit 0
    }
    if($Branch -eq 'Auto') {
        if(-not $acf) {throw 'Steam branch cannot be detected. Supply -Branch RT or NonRT.'}
        $text=Get-Content -Raw -LiteralPath $acf
        $beta=[regex]::Match($text,'"BetaKey"\s+"([^"]+)"').Groups[1].Value
        if($beta -eq 'dx11_non-rt') {$Branch='NonRT'}
        elseif($beta -eq '' -or $beta -eq 'public') {$Branch='RT'}
        else {throw "Unknown Steam branch $beta. Select RT or NonRT explicitly."}
    }
    $manifest=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'manifest.json')|ConvertFrom-Json
    foreach($f in $manifest.files) {
        $source=Child (Join-Path $PSScriptRoot 'payload') $f.path
        if((Hash $source) -ne $f.sha256) {throw 'Mod package integrity failure.'}
    }
    if($Plan) {Write-Output "Install $($manifest.version) + official REFramework v1.5.9.1 ($Branch) into $GamePath. No changes/downloads.";exit 0}
    $stage=Join-Path ([IO.Path]::GetTempPath()) ('RE2IVR-'+[Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage|Out-Null
    $releaseTag='v1.5.9.1';$archiveHash='';$assetName='offline archive'
    $bundled=Join-Path $PSScriptRoot 'framework\RE2.zip'
    if(-not $FrameworkArchive -and $Branch -eq 'RT' -and (Test-Path -LiteralPath $bundled)) {
        if((Hash $bundled) -ne '787C0203DC89087C808A69EC92424EF91EE8F9790FD541A331531050F2BC0BDB') {throw 'Bundled official framework hash mismatch.'}
        $FrameworkArchive=$bundled
    }
    if(-not $FrameworkArchive) {
        [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
        $api='https://api.github.com/repos/praydog/REFramework/releases/tags/'+$releaseTag
        $release=Invoke-RestMethod -Uri $api -Headers @{'User-Agent'='RE2IVR-Setup/0.8.7'}
        $assets=@($release.assets|Where-Object {if($Branch -eq 'RT') {$_.name -eq 'RE2.zip'} else {$_.name -match '^RE2_TDB[^/]*\.zip$'}})
        if($assets.Count -ne 1) {throw 'Could not select an unambiguous official RE2 asset.'}
        $asset=$assets[0];$assetName=$asset.name
        $expectedPrefix='https://github.com/praydog/REFramework/releases/download/'+$releaseTag+'/'
        if(-not $asset.browser_download_url.StartsWith($expectedPrefix,[StringComparison]::Ordinal)) {throw 'Unexpected asset host/path.'}
        $FrameworkArchive=Join-Path $stage 'framework.zip'
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $FrameworkArchive -UseBasicParsing
        if((Get-Item -LiteralPath $FrameworkArchive).Length -ne $asset.size) {throw 'Incomplete framework download.'}
        $archiveHash=Hash $FrameworkArchive
        if($asset.PSObject.Properties['digest'] -and $asset.digest) {
            if($asset.digest -notmatch '^sha256:([a-fA-F0-9]{64})$' -or $Matches[1] -ne $archiveHash) {throw 'Official framework digest mismatch.'}
        }
    } else {$FrameworkArchive=(Resolve-Path -LiteralPath $FrameworkArchive).Path;$archiveHash=Hash $FrameworkArchive}
    $zip=[IO.Compression.ZipFile]::OpenRead($FrameworkArchive)
    $incoming=@{};$unpack=Join-Path $stage 'files';New-Item -ItemType Directory -Path $unpack|Out-Null
    try {
        foreach($entry in $zip.Entries) {
            if($entry.FullName.EndsWith('/')) {continue}
            $rel=$entry.FullName.Replace('/','\')
            if($rel -match '(?i)\.(exe|ps1|cmd|bat)$' -or $rel.StartsWith('.re2ivr',[StringComparison]::OrdinalIgnoreCase)) {throw 'Unexpected executable or private path in framework archive.'}
            $dest=Child $unpack $rel
            if($incoming.ContainsKey($rel)) {throw 'Duplicate archive path.'}
            New-Item -ItemType Directory -Path (Split-Path $dest) -Force|Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$dest,$false)
            $incoming[$rel]=$dest
        }
    } finally {$zip.Dispose()}
    if(-not $incoming.ContainsKey('dinput8.dll') -or (-not $incoming.ContainsKey('openvr_api.dll') -and -not $incoming.ContainsKey('openxr_loader.dll'))) {throw 'Archive is not a complete RE2 VR package.'}
    foreach($f in $manifest.files) {
        $rel=$f.path.Replace('/','\')
        if($incoming.ContainsKey($rel)) {
            # Only reviewed upstream scripts may be replaced; all other collisions stay fatal.
            $reviewed=@{
                'reframework\autorun\re2_vr_grenade.lua'='9AA606200361013305CCAA6A5E4B94A37D448E2820FC13D09556EF4BADC672EA'
                'reframework\autorun\re2_vr_crosshair.lua'='634D85D182886A572904E0A5D097303B1B7DA34F97EB9A1C9E2E828DC8FB7D47'
            }
            if(-not $reviewed.ContainsKey($rel) -or (Hash $incoming[$rel]) -ne $reviewed[$rel]) {throw 'Framework/mod file collision.'}
        }
        $incoming[$rel]=Child (Join-Path $PSScriptRoot 'payload') $rel
    }
    if($state) {foreach($f in $state.files) {if(-not $incoming.ContainsKey($f.path)) {throw 'Update drops a managed file. Roll back/remove first.'}}}
    $probe=$null
    $probeFile=Child $GamePath 're2ivr-probe-state.json'
    $probeAllowed=@('dinput8.dll','reframework\autorun\RE2_TypeSchema.lua','reframework\autorun\RE2_AutoDiscovery.lua','reframework\autorun\RE2_NativeAdapter.lua')
    if(-not $state -and (Test-Path -LiteralPath $probeFile)) {
        $probe=Get-Content -Raw -LiteralPath $probeFile|ConvertFrom-Json
        foreach($f in $probe.files) {
            if($probeAllowed -notcontains $f.path -or (Hash (Child $GamePath $f.path)) -ne $f.hash) {throw 'Probe modified; refusing migration.'}
        }
    }
    $generation=[Guid]::NewGuid().ToString('N');$rows=@()
    foreach($rel in ($incoming.Keys|Sort-Object)) {
        $dest=Child $GamePath $rel;$backup=$null;$oldHash=$null
        if(Test-Path -LiteralPath $dest) {
            $owned=$state -and @($state.files|Where-Object {$_.path -eq $rel}).Count -eq 1
            $legacy=$false
            if($rel -eq 'reframework\autorun\re2ivr_bootstrap.lua') {
                $legacyPath=Join-Path $stateDir 'state.json'
                if(Test-Path -LiteralPath $legacyPath) {
                    $legacyState=Get-Content -Raw -LiteralPath $legacyPath|ConvertFrom-Json
                    $legacy=(Hash $dest) -eq $legacyState.hash
                }
            }
            $probeOwned=$probe -and @($probe.files|Where-Object {$_.path -eq $rel}).Count -eq 1
            if(-not $owned -and -not $legacy -and -not $probeOwned) {throw "Existing unmanaged file: $rel. No files changed; refusing to overwrite."}
            $backup='history\'+$generation+'\'+$rel;$oldHash=Hash $dest
        }
        $rows+=@{path=$rel;hash=(Hash $incoming[$rel]);backup=$backup;originalHash=$oldHash}
    }
    foreach($f in $rows) {if($f.backup) {$b=Child $stateDir $f.backup;New-Item -ItemType Directory -Force -Path (Split-Path $b)|Out-Null;Copy-Item -LiteralPath (Child $GamePath $f.path) -Destination $b}}
    $changed=@()
    try {
        foreach($f in $rows) {
            $dest=Child $GamePath $f.path;New-Item -ItemType Directory -Force -Path (Split-Path $dest)|Out-Null
            $changed+=,$f
            Copy-Item -LiteralPath $incoming[$f.path] -Destination $dest -Force
            if((Hash $dest) -ne $f.hash) {throw 'Installed hash mismatch.'}
        }
        New-Item -ItemType Directory -Force -Path $stateDir|Out-Null
        WriteJson @{schema=2;version=$manifest.version;framework=$releaseTag;asset=$assetName;archiveSHA256=$archiveHash;branch=$Branch;files=$rows;previous=$state} ($stateFile+'.tmp')
        Move-Item -LiteralPath ($stateFile+'.tmp') -Destination $stateFile -Force
    } catch {
        $failure=$_
        foreach($f in $changed) {
            $dest=Child $GamePath $f.path
            if($f.backup) {Copy-Item -LiteralPath (Child $stateDir $f.backup) -Destination $dest -Force}
            elseif(Test-Path -LiteralPath $dest) {Remove-Item -LiteralPath $dest}
        }
        throw $failure
    }
    WriteJson @{gamePath=$GamePath} (Join-Path $PSScriptRoot 'installed-location.json')
    Write-Output 'REFramework + RE2IVR installed. Use Play.cmd here. Steam starts the game normally.'
    Write-Output "Temporary package cache retained: $stage"
    exit 0
} catch {Write-Error $_;exit 1}
