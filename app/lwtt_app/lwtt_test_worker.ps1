param(
    [ValidateSet('Connect','Disconnect','Test','Recover')][string]$Action = 'Test',
    [string]$ProfilePath = '',
    [string]$ConfigPath = '',
    [Parameter(Mandatory = $true)][string]$ResultPath,
    [string]$CancelPath = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lwtt_common.ps1')
# The launcher holds the lock until its pending-job descriptor is published.
$registered = $false
$deadline = (Get-Date).AddSeconds(10)
while ((Get-Date) -lt $deadline) {
    $pending = Get-LikewebPendingJob
    if ($null -ne $pending -and [int]$pending.Pid -eq $PID) { $registered = $true; break }
    Start-Sleep -Milliseconds 100
}
try {
    if (-not $registered) { throw 'Запуск операции не был подтверждён. Настройки не изменены.' }
    $result = Invoke-LikewebConnectionOperation -Action $Action -ProfilePath $ProfilePath -ConfigPath $ConfigPath -CancelPath $CancelPath
} catch {
    $result = [pscustomobject]@{ Success = $false; PreviousConnectionRestored = $false; ErrorMessage = $_.Exception.Message; LogTail = '' }
} finally {
    if ($ConfigPath -and [IO.File]::Exists($ConfigPath)) { [IO.File]::Delete($ConfigPath) }
}
Write-LikewebAtomicText $ResultPath ($result | ConvertTo-Json -Depth 5)
