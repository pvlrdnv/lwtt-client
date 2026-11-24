# Verify the real Windows builder, including removal of local runtime state.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('lwtt-build-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
try {
    foreach ($name in @('app','tools','docs','VERSION')) { Copy-Item -LiteralPath (Join-Path $root $name) -Destination $temporary -Recurse }
    $runtime = Join-Path $temporary 'app\lwtt_app'
    foreach ($directory in @('profiles','settings','log')) {
        [void][IO.Directory]::CreateDirectory((Join-Path $runtime $directory))
        [IO.File]::WriteAllText((Join-Path $runtime ($directory + '\private.txt')), 'TEST ONLY - must not enter a public archive')
    }
    $engine = Join-Path $root '.bundle_work\download\trusttunnel_client-v1.0.49-windows-x86_64.zip'
    $output = Join-Path $temporary 'dist'
    & (Join-Path $temporary 'tools\build_bundle.ps1') -TrustTunnelZipPath $engine -OutDir $output
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead((Join-Path $output 'LWTT_Client_Bundle_windows_x86_64.zip'))
    try {
        $names = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\','/') })
        foreach ($name in $names) { if ($name -match '(?i)(^|/)(profiles|settings|log)(/|$)') { throw ('Private state packaged: ' + $name) } }
        foreach ($required in @('lwtt_tray_start.bat','ИНСТРУКЦИЯ БЫСТРОГО СТАРТА.txt','lwtt_app/lwtt_configuration.ps1','lwtt_app/lwtt_connection.ps1','lwtt_app/lwtt_bypass_ui.ps1','lwtt_app/VERSION','lwtt_app/trusttunnel_client.exe','lwtt_app/wintun.dll')) {
            if ($names -notcontains $required) { throw ('Missing file: ' + $required) }
        }
        foreach ($entry in @($archive.Entries | Where-Object { $_.Name -like '*.ps1' -or $_.Name -like '*.bat' })) {
            $reader = New-Object IO.StreamReader($entry.Open())
            try { $actual=$reader.ReadToEnd() } finally { $reader.Dispose() }
            $source = Join-Path (Join-Path $temporary 'app') $entry.FullName
            if ($actual -cne [IO.File]::ReadAllText($source)) { throw ('Stale script: ' + $entry.FullName) }
        }
    } finally { $archive.Dispose() }
    Write-Output 'PASS: real Windows bundle builder, upstream SHA256, current scripts, guide location and excluded runtime data.'
} finally {
    for ($retry=0; $retry -lt 5 -and [IO.Directory]::Exists($temporary); $retry++) {
        try { [IO.Directory]::Delete($temporary,$true) }
        catch { if ($retry -eq 4) { throw }; Start-Sleep -Milliseconds 300 }
    }
}
