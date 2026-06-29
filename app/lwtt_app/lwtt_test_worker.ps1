param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,
    [Parameter(Mandatory = $true)]
    [string]$ResultPath,
    [Parameter(Mandatory = $true)]
    [string]$LogPath
)

$ErrorActionPreference = "Stop"

$commonPath = Join-Path $PSScriptRoot "lwtt_common.ps1"
. $commonPath

function Write-TestResult {
    param(
        [bool]$Success,
        [bool]$PreviousConnectionRestored,
        [string]$ErrorMessage,
        [string]$LogTail
    )

    $result = [ordered]@{
        Success = $Success
        PreviousConnectionRestored = $PreviousConnectionRestored
        ErrorMessage = $ErrorMessage
        LogTail = $LogTail
    }

    $json = $result | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($ResultPath, $json, $script:LikewebUtf8NoBom)
}

$hadActiveConfig = Test-Path -LiteralPath $script:LikewebActiveConfigPath
$activeConfigBytes = $null
$hadActiveProfile = Test-Path -LiteralPath $script:LikewebActiveProfilePath
$activeProfileText = ""
$wasRunning = $null -ne (Get-LikewebProcess)
$restoreSucceeded = $true
$testSucceeded = $false
$errorMessage = ""

try {
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Временный файл конфигурации не найден."
    }

    if (-not (Test-Path -LiteralPath $script:LikewebExePath)) {
        throw "Не найден trusttunnel_client.exe."
    }

    if ($hadActiveConfig) {
        $activeConfigBytes = [System.IO.File]::ReadAllBytes($script:LikewebActiveConfigPath)
    }

    if ($hadActiveProfile) {
        $activeProfileText = [System.IO.File]::ReadAllText($script:LikewebActiveProfilePath)
    }

    [void](Stop-LikewebVpnAndWait)
    [System.IO.File]::Copy($ConfigPath, $script:LikewebActiveConfigPath, $true)

    if (Test-Path -LiteralPath $LogPath) {
        Remove-Item -LiteralPath $LogPath -Force
    }

    $testSucceeded = Start-LikewebVpnAndWait

    if (-not $testSucceeded) {
        $errorMessage = "TrustTunnel не создал устойчивое подключение."
    }

    [void](Stop-LikewebVpnAndWait)

    $latestLogText = Get-LikewebLatestVpnLogText
    if (-not [string]::IsNullOrWhiteSpace($latestLogText)) {
        [System.IO.File]::WriteAllText(
            $LogPath,
            $latestLogText,
            $script:LikewebUtf8NoBom
        )
    }
}
catch {
    $testSucceeded = $false
    $errorMessage = $_.Exception.Message
}
finally {
    try {
        [void](Stop-LikewebVpnAndWait)

        if ($hadActiveConfig) {
            [System.IO.File]::WriteAllBytes(
                $script:LikewebActiveConfigPath,
                $activeConfigBytes
            )
        }
        elseif (Test-Path -LiteralPath $script:LikewebActiveConfigPath) {
            Remove-Item -LiteralPath $script:LikewebActiveConfigPath -Force
        }

        if ($hadActiveProfile) {
            [System.IO.File]::WriteAllText(
                $script:LikewebActiveProfilePath,
                $activeProfileText,
                $script:LikewebUtf8NoBom
            )
        }
        elseif (Test-Path -LiteralPath $script:LikewebActiveProfilePath) {
            Remove-Item -LiteralPath $script:LikewebActiveProfilePath -Force
        }

        if ($wasRunning -and $hadActiveConfig) {
            $restoreSucceeded = Start-LikewebVpnAndWait
        }
    }
    catch {
        $restoreSucceeded = $false
        if ([string]::IsNullOrWhiteSpace($errorMessage)) {
            $errorMessage = "Не удалось восстановить предыдущее подключение."
        }
    }

    $logTail = ""
    if (Test-Path -LiteralPath $LogPath) {
        try {
            $lines = @(Get-Content -LiteralPath $LogPath -ErrorAction Stop)
            $logTail = ($lines | Select-Object -Last 40) -join "`r`n"
        }
        catch {}
    }

    if ([string]::IsNullOrWhiteSpace($logTail) -and -not [string]::IsNullOrWhiteSpace($errorMessage)) {
        $logTail = $errorMessage
    }

    Write-TestResult $testSucceeded $restoreSucceeded $errorMessage $logTail
}
