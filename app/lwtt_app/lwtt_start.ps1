$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lwtt_common.ps1')
if (-not (Test-LikewebAdministrator)) {
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath
    $elevated = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    try { exit $elevated.ExitCode } finally { $elevated.Dispose() }
}
$profile = Get-LikewebActiveProfileInfo
if ($null -eq $profile) { throw 'Сначала добавьте и выберите сервер в приложении.' }
$job = Start-LikewebAction -Action Connect -ProfilePath $profile.Path
$result = $null
while ($null -eq $result) { Start-Sleep -Milliseconds 250; $result = Receive-LikewebJob $job }
if (-not $result.Success) { throw $result.ErrorMessage }
Write-Host 'Туннель подтвердил подключение.'
