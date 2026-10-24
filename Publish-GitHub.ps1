param([ValidatePattern('^[A-Za-z0-9_.-]+$')][string]$RepositoryName='RE2-Immersive-VR')
$ErrorActionPreference='Stop'
function Run([string]$Program,[string[]]$Arguments) {
    & $Program @Arguments
    if($LASTEXITCODE -ne 0) {throw "$Program failed with exit code $LASTEXITCODE. No force push was attempted."}
}
try {
    if(-not(Get-Command git -ErrorAction SilentlyContinue)) {throw 'Git is required: https://git-scm.com/'}
    if(-not(Get-Command gh -ErrorAction SilentlyContinue)) {throw 'GitHub CLI is required: https://cli.github.com/ . Install it, then rerun this script.'}
    Push-Location $PSScriptRoot
    try {
        & gh auth status --hostname github.com
        if($LASTEXITCODE -ne 0) {Run 'gh' @('auth','login','--hostname','github.com','--git-protocol','https','--web')}
        $login=(& gh api user --jq '.login').Trim()
        if($LASTEXITCODE -ne 0 -or -not $login) {throw 'GitHub account could not be determined.'}
        $id=(& gh api user --jq '.id').Trim()
        if($LASTEXITCODE -ne 0 -or -not $id) {throw 'GitHub user ID could not be determined.'}
        $fullName=$login+'/'+$RepositoryName
        & gh repo view $fullName --json name 2>$null | Out-Null
        if($LASTEXITCODE -eq 0) {throw "$fullName already exists. This script will not overwrite an existing repository."}
        if(-not(Test-Path -LiteralPath '.git')) {Run 'git' @('init','-b','main')}
        & git remote get-url origin 2>$null | Out-Null
        if($LASTEXITCODE -eq 0) {throw 'An origin remote is already configured; refusing to replace it.'}
        Run 'git' @('config','user.name',$login)
        Run 'git' @('config','user.email',($id+'+'+$login+'@users.noreply.github.com'))
        Run 'git' @('add','README.md','LICENSE','THIRD_PARTY_NOTICES.md','CHANGELOG.md','CONTRIBUTING.md','SECURITY.md','VERSION','.gitignore','.gitattributes','.github','runtime','support','installer','tools','docs','third_party','Publish-GitHub.ps1','Publish-GitHub.cmd')
        & git diff --cached --quiet
        if($LASTEXITCODE -eq 1) {Run 'git' @('commit','-m','Publish RE2 Immersive VR source snapshot and Russian documentation')}
        elseif($LASTEXITCODE -ne 0) {throw 'Could not inspect staged changes.'}
        Run 'gh' @('repo','create',$fullName,'--public','--source','.','--remote','origin','--push','--description','Experimental open-source RE2 Remake PCVR mod for Quest 3 / SteamVR: weapon handling, spatial belt, installer and diagnostics')
        Write-Output ('Published https://github.com/'+$fullName)
    } finally {Pop-Location}
} catch {Write-Error $_;exit 1}
