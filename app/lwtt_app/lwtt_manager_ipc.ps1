# File mailbox: atomic requests, one manager per installation, no forced closure.
function Get-LikewebManagerProcess {
    if (-not [IO.File]::Exists($script:LikewebManagerPidPath)) { return $null }
    try {
        $managerId = [int]([IO.File]::ReadAllText($script:LikewebManagerPidPath)).Trim()
        $process = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $managerId) -ErrorAction Stop
        $scriptPath = Join-Path $script:LikewebBaseDir 'lwtt_manager.ps1'
        if ($process.Name -eq 'powershell.exe' -and $process.CommandLine.IndexOf($scriptPath, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return Get-Process -Id $managerId -ErrorAction SilentlyContinue }
    } catch { Write-LikewebRuntimeError 'Inspect manager' $_ }
    return $null
}

function Send-LikewebManagerRequest {
    param([string]$Mode = 'Servers', [string]$ProfileId = '')
    $id = [guid]::NewGuid().ToString('N')
    $path = Join-Path $script:LikewebLogDir ('manager_requests\' + $id + '.json')
    Write-LikewebAtomicText $path (@{ Mode = $Mode; ProfileId = $ProfileId; Id = $id; CreatedAt = (Get-Date).ToString('o') } | ConvertTo-Json)
    return $id
}

function Close-LikewebServerManagerWindows {
    # Compatibility entry point. All closure goes through the UI's FormClosing guard.
    if ($null -ne (Get-LikewebManagerProcess)) { $null = Send-LikewebManagerRequest 'Close'; return $false }
    return $true
}
