param([switch]$HelperOnly)
$ErrorActionPreference='Stop'
try {
    $location=Join-Path $PSScriptRoot 'installed-location.json'
    if(-not(Test-Path -LiteralPath $location)) {throw 'Run Install.cmd first.'}
    $helper=Join-Path $PSScriptRoot 'RE2IVR-DialogInput.exe'
    $target=([IO.Path]::GetFullPath((Get-Content -Raw -LiteralPath $location|ConvertFrom-Json).gamePath)).TrimEnd('\')
    # Replace only a previous instance of our helper configured for this exact game.
    # Otherwise the older per-game mutex can keep the new belt helper from starting.
    foreach($process in @(Get-CimInstance Win32_Process -Filter "Name='RE2IVR-DialogInput.exe'" -ErrorAction SilentlyContinue)) {
        try {
            $match=[regex]::Match([string]$process.CommandLine,'--location\s+"([^"]+)"')
            if(-not $match.Success) {continue}
            $oldLocation=Get-Content -Raw -LiteralPath $match.Groups[1].Value|ConvertFrom-Json
            $oldTarget=([IO.Path]::GetFullPath($oldLocation.gamePath)).TrimEnd('\')
            if($oldTarget -ieq $target -and [IO.Path]::GetFileName($process.ExecutablePath) -ieq 'RE2IVR-DialogInput.exe') {
                Stop-Process -Id $process.ProcessId -ErrorAction Stop
            }
        } catch {Write-Output 'Previous input helper could not be replaced. Close that helper before restarting Play.cmd.'}
    }
    Start-Process -FilePath $helper -ArgumentList @('--location',('"'+$location+'"')) -WindowStyle Hidden
    if(-not $HelperOnly) {Start-Process 'steam://rungameid/883710'}
} catch {Write-Error $_;exit 1}
