$ErrorActionPreference='Stop'
try {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $location=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'installed-location.json')|ConvertFrom-Json
    $data=Join-Path $location.gamePath 'reframework\data'
    $out=Join-Path $PSScriptRoot ('RE2IVR-report-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'.zip')
    if(Test-Path -LiteralPath $out) {throw 'Report archive already exists. Try again in a moment.'}
    $zip=[IO.Compression.ZipFile]::Open($out,[IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach($name in @('re2ivr_mvp_status.json','re2ivr_mvp_transaction.json','re2ivr_mvp_error.json','re2ivr_mvp_settings.json','re2ivr_presentation_status.json','re2ivr_comfort_status.json','re2ivr_stereo_check.json','re2ivr_fire_contract.json','re2ivr_ammo_fault.json','re2ivr_model_status.json','re2ivr_dialog_status.json','re2ivr_input_bridge.json','re2ivr_belt_status.json','re2ivr_belt.json','re2ivr_title_layers.json','re2ivr_shortcut_bindings.json','re2ivr_shortcut_status.json')) {
            $p=Join-Path $data $name
            if(Test-Path -LiteralPath $p) {[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$p,$name)|Out-Null}
        }
        $snapshot=[ordered]@{}
        foreach($name in @('re2_fw_config.txt','re2_config.ini')) {
            $p=Join-Path $location.gamePath $name
            $values=[ordered]@{}
            if(Test-Path -LiteralPath $p) {
                foreach($line in (Get-Content -LiteralPath $p)) {
                    if($line -match '^((?:FirstPerson_(?:Enabled|HideJointMesh|ForceRotateMesh|ShowInCutscenes|FOVMultiplier|FOVOffset))|(?:VR_(?:AlternateFrameRendering|AsyncRendering_V3|ForceFPS|ForceLensDistortion|2DUIScale|2DUIDistance|OpenXRResolutionScale))|(?:NormalWindowResolution|WindowMode|FullScreenMode|PCWindowMode|PCResolution|PCDXver|PCLensDistortion|HDRmode|PCImage_Quality|PCFidelityFXResolution|PCRenderingMethod|PCAntiAliasing))=(.*)$') {
                        $values[$Matches[1]]=$Matches[2]
                    }
                }
            }
            $snapshot[$name]=$values
        }
        $entry=$zip.CreateEntry('display-settings.json')
        $writer=New-Object IO.StreamWriter($entry.Open())
        try {$writer.Write(($snapshot|ConvertTo-Json -Depth 5))} finally {$writer.Dispose()}
    } finally {$zip.Dispose()}
    Write-Output "Saved: $out"
    exit 0
} catch {Write-Error $_;exit 1}
