# Safe storage and recovery for Windows PowerShell 5.1.
function Write-LikewebAtomicText {
    param([string]$Path, [string]$Text)
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, $Text, $script:LikewebUtf8NoBom)
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, [System.Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}

function Enter-LikewebOperationLock {
    param([switch]$Worker)
    $deadline = (Get-Date).AddSeconds(5)
    do {
        $lock = $null
        try {
            $lock = [IO.File]::Open((Join-Path $script:LikewebLogDir 'operation.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
            $job = Get-LikewebPendingJob
            if ($null -ne $job -and (-not $Worker -or [int]$job.Pid -ne $PID)) { throw 'Busy' }
            return $lock
        } catch {
            if ($null -ne $lock) { $lock.Dispose() }
            $job = Get-LikewebPendingJob
            if (-not $Worker -or $null -eq $job -or [int]$job.Pid -ne $PID -or (Get-Date) -ge $deadline) {
                throw 'Другая операция ещё выполняется. Дождитесь её завершения.'
            }
            Start-Sleep -Milliseconds 100
        }
    } while ($true)
}

function Get-LikewebFileSnapshot {
    param([string[]]$Paths)
    foreach ($path in $Paths) {
        $full = [IO.Path]::GetFullPath($path)
        $base = [IO.Path]::GetFullPath($script:LikewebBaseDir).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
        if (-not $full.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { throw 'Файл находится вне папки приложения.' }
        [pscustomobject]@{ Path = $full; Data = $(if ([IO.File]::Exists($full)) { [Convert]::ToBase64String([IO.File]::ReadAllBytes($full)) } else { $null }) }
    }
}

function Restore-LikewebFileSnapshot {
    param([object[]]$Snapshot)
    foreach ($item in $Snapshot) {
        $null = @(Get-LikewebFileSnapshot @([string]$item.Path))
        if ($null -eq $item.Data) {
            if ([IO.File]::Exists($item.Path)) { [IO.File]::Delete($item.Path) }
        } else {
            $temporary = $item.Path + '.restore.tmp'
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $item.Path))
            try {
                [IO.File]::WriteAllBytes($temporary, [Convert]::FromBase64String([string]$item.Data))
                if ([IO.File]::Exists($item.Path)) { [IO.File]::Replace($temporary, $item.Path, [System.Management.Automation.Language.NullString]::Value) }
                else { [IO.File]::Move($temporary, $item.Path) }
            } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
        }
    }
}

function Invoke-LikewebFileTransaction {
    param([System.Collections.IDictionary]$Changes)
    $journal = Join-Path $script:LikewebLogDir 'files_recovery.json'
    if ([IO.File]::Exists($journal)) { throw 'Есть незавершённое сохранение. Выберите восстановление в меню трея.' }
    $snapshot = @(Get-LikewebFileSnapshot @($Changes.Keys))
    Write-LikewebAtomicText $journal (ConvertTo-Json -InputObject $snapshot -Depth 5)
    try {
        foreach ($path in $Changes.Keys) {
            if ($null -eq $Changes[$path]) { if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) } }
            else { Write-LikewebAtomicText $path ([string]$Changes[$path]) }
        }
        [IO.File]::Delete($journal)
    } catch {
        Restore-LikewebFileSnapshot $snapshot
        [IO.File]::Delete($journal)
        throw
    }
}

function Write-LikewebRuntimeError {
    param([string]$Context, [object]$ErrorRecord)
    try {
        $path = Join-Path $script:LikewebLogDir 'runtime.log'
        if ([IO.File]::Exists($path) -and (Get-Item -LiteralPath $path).Length -gt 1MB) { Move-Item -LiteralPath $path -Destination ($path + '.old') -Force }
        Add-Content -LiteralPath $path -Encoding UTF8 -Value ('{0:o} {1}: {2}' -f (Get-Date), $Context, $ErrorRecord.Exception.GetType().Name)
    } catch { [Diagnostics.Trace]::WriteLine('Unable to write LWTT runtime log.') }
}

function Protect-LikewebDiagnosticText {
    param([string]$Text)
    $secrets = New-Object 'System.Collections.Generic.List[string]'
    foreach ($profile in @(Get-LikewebProfiles)) {
        if ($profile.Password) { $secrets.Add($profile.Password) }
        if ($profile.Username) { $secrets.Add($profile.Username) }
    }
    if ([IO.File]::Exists($script:LikewebActiveConfigPath)) {
        try {
            $active = [IO.File]::ReadAllText($script:LikewebActiveConfigPath)
            foreach ($key in @('username','password')) {
                $secretValue = Get-LikewebTomlStringValue $active $key
                if ($secretValue) { $secrets.Add($secretValue) }
            }
        } catch { Write-LikewebRuntimeError 'Read active secrets for diagnostic redaction' $_ }
    }
    foreach ($secret in @($secrets | Select-Object -Unique | Sort-Object Length -Descending)) {
        $Text = $Text.Replace($secret, '[скрыто]')
        $Text = $Text.Replace((ConvertTo-LikewebTomlString $secret), '[скрыто]')
    }
    return [regex]::Replace($Text, '(?im)((?:password|authorization|username)\s*[:=]\s*).*$', '$1[скрыто]')
}
