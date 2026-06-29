# Starts TrustTunnel elevated and writes a unique diagnostic log.
# Windows PowerShell 5.1 / Windows 10 and 11

$BaseDir = $PSScriptRoot
$ExePath = Join-Path $BaseDir "trusttunnel_client.exe"
$ConfigPath = Join-Path $BaseDir "lwtt_client.toml"
$LogDir = Join-Path $BaseDir "log\client"
$PidPath = Join-Path $LogDir "trusttunnel_client.pid"
$LatestPointerPath = Join-Path $LogDir "latest_client_log.txt"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

if (-not (Test-Administrator)) {
    $arguments = (
        '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f
        $PSCommandPath
    )
    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $arguments
    exit
}

if (-not (Test-Path -LiteralPath $ExePath -PathType Leaf)) {
    exit 2
}

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    exit 3
}

if (-not (Test-Path -LiteralPath $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# Do not start a second client when the PID file still points to a live process.
if (Test-Path -LiteralPath $PidPath -PathType Leaf) {
    try {
        $existingPidText = ([System.IO.File]::ReadAllText($PidPath)).Trim()
        $existingPid = 0
        if ([int]::TryParse($existingPidText, [ref]$existingPid)) {
            $existingProcess = Get-Process -Id $existingPid -ErrorAction SilentlyContinue
            if (
                $null -ne $existingProcess -and
                $existingProcess.ProcessName -eq "trusttunnel_client"
            ) {
                exit 0
            }
        }
    }
    catch {
    }

    Remove-Item -LiteralPath $PidPath -Force -ErrorAction SilentlyContinue
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$randomPart = Get-Random -Minimum 1000 -Maximum 9999
$baseLogPath = Join-Path $LogDir ("trusttunnel_{0}_{1}" -f $stamp, $randomPart)
$outputPath = $baseLogPath + ".out.log"
$errorPath = $baseLogPath + ".err.log"
$metaPath = $baseLogPath + ".meta.txt"

[System.IO.File]::WriteAllText(
    $LatestPointerPath,
    $baseLogPath,
    $Utf8NoBom
)

$meta = New-Object System.Collections.Generic.List[string]
$meta.Add("LW TrustTunnel Client / TrustTunnel session")
$meta.Add(("Started: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff zzz")))
$meta.Add(("Executable: {0}" -f $ExePath))
$meta.Add(("Configuration: {0}" -f $ConfigPath))
$meta.Add(("Computer: {0}" -f $env:COMPUTERNAME))
$meta.Add(("User: {0}" -f [Security.Principal.WindowsIdentity]::GetCurrent().Name))
$meta.Add("")

[System.IO.File]::WriteAllLines($metaPath, $meta, $Utf8NoBom)

$process = $null
try {
    $process = Start-Process `
        -FilePath $ExePath `
        -ArgumentList @("-c", ('"{0}"' -f $ConfigPath)) `
        -WorkingDirectory $BaseDir `
        -WindowStyle Hidden `
        -RedirectStandardOutput $outputPath `
        -RedirectStandardError $errorPath `
        -PassThru

    [System.IO.File]::WriteAllText(
        $PidPath,
        [string]$process.Id,
        $Utf8NoBom
    )

    Add-Content -LiteralPath $metaPath -Value (
        "PID: {0}`r`n" -f $process.Id
    ) -Encoding UTF8

    $process.WaitForExit()

    Add-Content -LiteralPath $metaPath -Value (
        "Finished: {0}`r`nExit code: {1}`r`n" -f
        (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff zzz"),
        $process.ExitCode
    ) -Encoding UTF8
}
catch {
    Add-Content -LiteralPath $metaPath -Value (
        "Runner error: {0}`r`n" -f $_.Exception.ToString()
    ) -Encoding UTF8
}
finally {
    try {
        if (Test-Path -LiteralPath $PidPath -PathType Leaf) {
            $pidText = ([System.IO.File]::ReadAllText($PidPath)).Trim()
            if ($null -eq $process -or $pidText -eq [string]$process.Id) {
                Remove-Item -LiteralPath $PidPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
    }
}
