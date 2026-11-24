$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lwtt_common.ps1')
$lock = Enter-LikewebOperationLock
try {
    if (-not (Stop-LikewebVpnAndWait)) { throw 'Не удалось остановить процесс TrustTunnel.' }
} finally { $lock.Dispose() }
