# Single coordinator shared by the tray, manager and background worker.
function Get-LikewebJobProcess {
    param([object]$Job)
    try {
        $process = Get-Process -Id ([int]$Job.Pid) -ErrorAction SilentlyContinue
        if ($null -ne $process -and $process.ProcessName -eq 'powershell' -and [Math]::Abs(($process.StartTime.ToUniversalTime() - [datetime]::Parse($Job.StartedAt).ToUniversalTime()).TotalSeconds) -lt 2) { return $process }
    } catch { Write-LikewebRuntimeError 'Inspect job process' $_ }
    return $null
}

function Get-LikewebPendingJob {
    $path = Join-Path $script:LikewebLogDir 'pending_job.json'
    if (-not [IO.File]::Exists($path)) { return $null }
    try {
        $job = [IO.File]::ReadAllText($path) | ConvertFrom-Json -ErrorAction Stop
        if ($null -ne (Get-LikewebJobProcess $job)) { return $job }
    } catch { Write-LikewebRuntimeError 'Read pending job' $_ }
    return $null
}

function Get-LikewebProcess {
    # Never use the first unrelated process with the same name as a fallback.
    foreach ($process in @(Get-Process -Name 'trusttunnel_client' -ErrorAction SilentlyContinue)) {
        try {
            if ([IO.Path]::GetFullPath($process.Path) -ieq [IO.Path]::GetFullPath($script:LikewebExePath)) { return $process }
        } catch { Write-LikewebRuntimeError 'Inspect client process' $_ }
    }
    return $null
}

function Get-LikewebTunnelReady {
    $process = Get-LikewebProcess
    if ($null -eq $process) { $script:TunnelStatusCache = $null; return $false }
    $key = [string]$process.Id + ':' + $process.StartTime.ToUniversalTime().Ticks
    if ($null -eq $script:TunnelStatusCache -or $script:TunnelStatusCache.Key -ne $key) {
        $script:TunnelStatusCache = @{ Key = $key; Ready = $false; Files = @{} }
    }
    $set = Get-LikewebLatestVpnLogSet
    if (-not $set.MetaPath -or -not [IO.File]::Exists($set.MetaPath)) { return $false }
    try {
        $meta = Read-LikewebSharedText $set.MetaPath
        if ($meta -notmatch ('(?m)^PID:[ \t]*' + [regex]::Escape([string]$process.Id) + '[ \t]*\r?$')) { return $false }
    } catch { Write-LikewebRuntimeError 'Inspect session metadata' $_; return $false }
    foreach ($path in @($set.OutputPath,$set.ErrorPath)) {
        if (-not $path -or -not [IO.File]::Exists($path)) { continue }
        if (-not $script:TunnelStatusCache.Files.ContainsKey($path)) {
            $script:TunnelStatusCache.Files[$path] = @{ Offset = [long]0; Partial = '' }
        }
        $cursor = $script:TunnelStatusCache.Files[$path]
        $stream = $null; $reader = $null
        try {
            $stream = [IO.File]::Open($path,'Open','Read','ReadWrite')
            if ($stream.Length -lt $cursor.Offset) { $cursor.Offset = [long]0; $cursor.Partial = ''; $script:TunnelStatusCache.Ready = $false }
            [void]$stream.Seek($cursor.Offset, [IO.SeekOrigin]::Begin)
            $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $true)
            $buffer = New-Object char[] 4096
            while (($count = $reader.Read($buffer,0,$buffer.Length)) -gt 0) {
                $cursor.Partial += [string]::new($buffer,0,$count)
                while (($newline = $cursor.Partial.IndexOf("`n")) -ge 0) {
                    $line = $cursor.Partial.Substring(0,$newline)
                    $cursor.Partial = $cursor.Partial.Substring($newline + 1)
                    if ($line -match 'Successfully connected to endpoint') { $script:TunnelStatusCache.Ready = $true }
                    elseif ($line -match 'Waiting recovery:|TRUSTTUNNEL_CLIENT_APP.*Error:') { $script:TunnelStatusCache.Ready = $false }
                }
            }
            $cursor.Offset = $stream.Position
        } catch { Write-LikewebRuntimeError 'Read tunnel status' $_; $script:TunnelStatusCache.Ready = $false }
        finally { if ($null -ne $reader) { $reader.Dispose() } elseif ($null -ne $stream) { $stream.Dispose() } }
    }
    return [bool]$script:TunnelStatusCache.Ready
}

function Stop-LikewebVpnAndWait {
    $process = Get-LikewebProcess
    if ($null -eq $process) { return $true }
    try {
        Stop-Process -Id $process.Id -Force -ErrorAction Stop
        return $process.WaitForExit(15000)
    } catch { Write-LikewebRuntimeError 'Stop client' $_; return $false }
}

function Start-LikewebVpnAndWait {
    param([string]$CancelPath = '')
    if (Get-LikewebProcess) { return Get-LikewebTunnelReady }
    $previousLog = (Get-LikewebLatestVpnLogSet).BasePath
    $arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $script:LikewebVpnRunnerPath
    $runner = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -WorkingDirectory $script:LikewebBaseDir -WindowStyle Hidden -PassThru
    try {
        $deadline = (Get-Date).AddSeconds(40)
        while ((Get-Date) -lt $deadline) {
            if ($CancelPath -and [IO.File]::Exists($CancelPath)) { throw 'Проверка отменена. Восстанавливаем прежнее подключение.' }
            if ($runner.HasExited -and -not (Get-LikewebProcess)) { return $false }
            if ((Get-LikewebLatestVpnLogSet).BasePath -ne $previousLog -and (Get-LikewebTunnelReady)) { return $true }
            Start-Sleep -Milliseconds 250
        }
        return $false
    } finally { $runner.Dispose() }
}

function Set-LikewebActiveProfile {
    param([string]$ProfilePath)
    $content = Add-LikewebBypassToToml ([IO.File]::ReadAllText($ProfilePath))
    $id = [IO.Path]::GetFileNameWithoutExtension($ProfilePath)
    $changes = [ordered]@{}
    $changes[$script:LikewebActiveConfigPath] = $content
    $changes[$script:LikewebActiveProfilePath] = $id
    Invoke-LikewebFileTransaction $changes
}

function Set-LikewebOperationState {
    param([string]$State, [string]$ProfileId = '', [string]$DisplayName = '')
    if ($State -eq 'Idle') {
        if ([IO.File]::Exists($script:LikewebOperationStatePath)) { [IO.File]::Delete($script:LikewebOperationStatePath) }
        return
    }
    Write-LikewebAtomicText $script:LikewebOperationStatePath (@{ State = $State; ProfileId = $ProfileId; DisplayName = $DisplayName; Pid = $PID; UpdatedAt = (Get-Date).ToString('o') } | ConvertTo-Json)
}

function Get-LikewebOperationState {
    $job = Get-LikewebPendingJob
    if ($null -eq $job) { return $null }
    try {
        $state = [IO.File]::ReadAllText($script:LikewebOperationStatePath) | ConvertFrom-Json -ErrorAction Stop
        if ([int]$state.Pid -eq [int]$job.Pid) { return $state }
    } catch { Write-LikewebRuntimeError 'Read operation state' $_ }
    return [pscustomobject]@{ State = 'Connecting'; ProfileId = ''; DisplayName = '' }
}

function Test-LikewebRecoveryRequired {
    return ([IO.File]::Exists((Join-Path $script:LikewebLogDir 'connection_recovery.json')) -or [IO.File]::Exists((Join-Path $script:LikewebLogDir 'files_recovery.json')))
}

function Restore-LikewebConnectionJournal {
    $fileJournal = Join-Path $script:LikewebLogDir 'files_recovery.json'
    if ([IO.File]::Exists($fileJournal)) {
        Restore-LikewebFileSnapshot @([IO.File]::ReadAllText($fileJournal) | ConvertFrom-Json)
        [IO.File]::Delete($fileJournal)
    }
    $journal = Join-Path $script:LikewebLogDir 'connection_recovery.json'
    if (-not [IO.File]::Exists($journal)) { return }
    $snapshot = [IO.File]::ReadAllText($journal) | ConvertFrom-Json -ErrorAction Stop
    Set-LikewebOperationState 'Restoring'
    if (-not (Stop-LikewebVpnAndWait)) { throw 'Не удалось остановить процесс для восстановления. Исходные настройки сохранены.' }
    Restore-LikewebFileSnapshot @($snapshot.Files)
    if ($snapshot.WasRunning -and -not (Start-LikewebVpnAndWait)) { throw 'Настройки восстановлены, но прежний сервер пока недоступен. Повторите восстановление.' }
    [IO.File]::Delete($journal)
}

function Get-LikewebCertificateFailure {
    param([string]$LogText, [bool]$HasCertificate)
    $lines = @($LogText -split '\r?\n' | Where-Object {
        $_ -match '(?i)Failed to verify certificate:|certificate[ _]verify[ _]failed|WCRYPT_E_(?!OK)|hostname mismatch|certificate (?:has )?expired|certificate (?:is )?not yet valid|certificate.*does not match|self[- ]signed certificate|unable to (?:get (?:local )?issuer certificate|verify the first certificate)|CERT_E_(?:EXPIRED|CN_NO_MATCH|UNTRUSTEDROOT|CHAINING)'
    })
    if (-not $lines.Count) { return $null }
    $evidence = $lines -join "`n"
    $kind = 'CertificateTrust'; $canAdd = -not $HasCertificate
    if ($evidence -match '(?i)certificate (?:has )?expired|CERT_E_EXPIRED') {
        $kind = 'CertificateExpired'; $canAdd = $false
        $message = 'Срок действия сертификата истёк. Проверьте дату на компьютере и попросите администратора обновить сертификат сервера.'
    } elseif ($evidence -match '(?i)not yet valid') {
        $kind = 'CertificateNotYetValid'; $canAdd = $false
        $message = 'Срок действия сертификата ещё не начался. Проверьте дату на компьютере и сертификат сервера.'
    } elseif ($evidence -match '(?i)hostname mismatch|certificate.*does not match|CERT_E_CN_NO_MATCH') {
        $kind = 'CertificateHostname'; $canAdd = $false
        $message = 'Домен сервера не совпадает с сертификатом. Проверьте поле домена и настройки сертификата на сервере.'
    } elseif ($evidence -match 'WCRYPT_E_(?:CERT_OPEN_STORE|I2D_X509|CERT_ADD_ENCODED_CERTIFICATE_TO_STORE)') {
        $kind = 'CertificateValidation'; $canAdd = $false
        $message = 'Не удалось выполнить проверку сертификата. Проверьте системное хранилище сертификатов Windows и журнал диагностики.'
    } elseif ($HasCertificate) {
        $message = 'Не удалось подтвердить сертификат сервера. Проверьте выбранный PEM, домен и цепочку сертификатов на сервере.'
    } else {
        $message = 'Не удалось подтвердить сертификат сервера. Если он самоподписанный, добавьте PEM-файл, полученный от администратора.'
    }
    return [pscustomobject]@{ ErrorKind = $kind; ErrorMessage = $message; CanAddCertificate = $canAdd }
}

function Invoke-LikewebConnectionOperation {
    param([ValidateSet('Connect','Disconnect','Test','Recover')][string]$Action, [string]$ProfilePath = '', [string]$ConfigPath = '', [string]$CancelPath = '')
    $lock = Enter-LikewebOperationLock -Worker
    $journal = Join-Path $script:LikewebLogDir 'connection_recovery.json'
    $success = $false; $restored = $true; $errorText = ''; $logText = ''
    $attemptStarted = $false; $attemptLogBefore = ''; $hasCertificate = $false
    $restoreInProgress = $false
    $errorKind = 'Connection'; $canAddCertificate = $false
    $profileId = if ($Action -eq 'Connect') { [IO.Path]::GetFileNameWithoutExtension($ProfilePath) } else { '' }
    try {
        if ($Action -eq 'Recover') { Restore-LikewebConnectionJournal; $success = $true }
        else {
            if (Test-LikewebRecoveryRequired) { throw 'Есть незавершённая операция. Выберите «Восстановить подключение» в трее.' }
            $content = ''
            if ($Action -eq 'Connect') { $content = Add-LikewebBypassToToml ([IO.File]::ReadAllText($ProfilePath)) }
            if ($Action -eq 'Test') { $content = Add-LikewebBypassToToml ([IO.File]::ReadAllText($ConfigPath)) }
            if ($Action -ne 'Disconnect') { Backup-LikewebActiveConfig }
            $snapshot = @{ Files = @(Get-LikewebFileSnapshot @($script:LikewebActiveConfigPath, $script:LikewebActiveProfilePath)); WasRunning = ($null -ne (Get-LikewebProcess)) }
            Write-LikewebAtomicText $journal ($snapshot | ConvertTo-Json -Depth 6)
            Set-LikewebOperationState 'Disconnecting'
            # No configuration may change until the previous process has exited.
            if (-not (Stop-LikewebVpnAndWait)) { [IO.File]::Delete($journal); throw 'Прежний процесс не остановлен. Настройки не изменены.' }
            if ($Action -eq 'Disconnect') { $success = $true }
            else {
                if ($CancelPath -and [IO.File]::Exists($CancelPath)) { throw 'Проверка отменена.' }
                Write-LikewebAtomicText $script:LikewebActiveConfigPath $content
                if ($Action -eq 'Connect') { Write-LikewebAtomicText $script:LikewebActiveProfilePath ([IO.Path]::GetFileNameWithoutExtension($ProfilePath)) }
                Set-LikewebOperationState 'Connecting'
                $hasCertificate = -not [string]::IsNullOrWhiteSpace((Get-LikewebEmbeddedCertificate $content))
                $attemptLogBefore = (Get-LikewebLatestVpnLogSet).BasePath
                $attemptStarted = $true
                if (-not (Start-LikewebVpnAndWait -CancelPath $CancelPath)) { throw 'Туннель не подтвердил подключение. Откройте журнал диагностики.' }
                $success = $true
                if ($Action -eq 'Test') {
                    try { $logText = Protect-LikewebDiagnosticText (Get-LikewebLatestVpnLogText) }
                    catch { Write-LikewebRuntimeError 'Read successful test log' $_ }
                    $attemptStarted = $false
                    $restoreInProgress = $true
                    Restore-LikewebConnectionJournal
                    $restoreInProgress = $false
                }
            }
            if ([IO.File]::Exists($journal)) { [IO.File]::Delete($journal) }
        }
    } catch {
        $errorText = $_.Exception.Message
        Write-LikewebRuntimeError 'Connection operation' $_
        if ($restoreInProgress) {
            $restored = $false
            $errorKind = 'Restoration'
            $errorText = 'Проверка сервера завершена, но прежнее подключение не восстановлено. ' + $errorText
        }
        else {
            # Diagnostic failures must never prevent restoring the previous session.
            try {
                $rawLog = Get-LikewebLatestVpnLogText
                if ($attemptStarted -and (Get-LikewebLatestVpnLogSet).BasePath -ne $attemptLogBefore -and -not ($CancelPath -and [IO.File]::Exists($CancelPath))) {
                    $failure = Get-LikewebCertificateFailure $rawLog $hasCertificate
                    if ($null -ne $failure) {
                        $errorKind = $failure.ErrorKind
                        $errorText = $failure.ErrorMessage
                        $canAddCertificate = $failure.CanAddCertificate
                    }
                }
                $logText = Protect-LikewebDiagnosticText $rawLog
            } catch { Write-LikewebRuntimeError 'Read failed operation log' $_ }
            if ([IO.File]::Exists($journal) -and $Action -ne 'Recover') {
                try { Restore-LikewebConnectionJournal }
                catch { $restored = $false; $errorText += ' ' + $_.Exception.Message }
            } elseif ($Action -eq 'Recover') { $restored = $false }
        }
        $success = $false
    } finally {
        try { Clear-LikewebOperationState }
        catch { Write-LikewebRuntimeError 'Clear operation marker' $_ }
        finally { $lock.Dispose() }
    }
    return [pscustomobject]@{ Success = $success; PreviousConnectionRestored = $restored; ErrorMessage = $errorText; LogTail = $logText; ErrorKind = $errorKind; CanAddCertificate = $canAddCertificate; ProfileId = $profileId }
}

function Start-LikewebAction {
    param([ValidateSet('Connect','Disconnect','Test','Recover')][string]$Action, [string]$ProfilePath = '', [string]$TomlContent = '')
    $lock = Enter-LikewebOperationLock
    $paths = @(); $process = $null
    try {
        if ($Action -ne 'Recover' -and (Test-LikewebRecoveryRequired)) { throw 'Есть незавершённая операция. Выберите восстановление в трее.' }
        $directory = Join-Path $script:LikewebLogDir 'jobs'
        [void][IO.Directory]::CreateDirectory($directory)
        $token = [guid]::NewGuid().ToString('N')
        $resultPath = Join-Path $directory ($token + '.json')
        $cancelPath = Join-Path $directory ($token + '.cancel')
        $configPath = Join-Path $directory ($token + '.toml')
        $paths = @($configPath, $resultPath, $cancelPath)
        if ($Action -eq 'Test') { Write-LikewebAtomicText $configPath $TomlContent }
        $worker = Join-Path $script:LikewebBaseDir 'lwtt_test_worker.ps1'
        $arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Action {1} -ProfilePath "{2}" -ConfigPath "{3}" -ResultPath "{4}" -CancelPath "{5}"' -f $worker, $Action, $ProfilePath, $configPath, $resultPath, $cancelPath
        $process = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -WorkingDirectory $script:LikewebBaseDir -WindowStyle Hidden -PassThru
        $job = [pscustomobject]@{ Pid = $process.Id; StartedAt = $process.StartTime.ToUniversalTime().ToString('o'); ResultPath = $resultPath; CancelPath = $cancelPath; ConfigPath = $configPath; Action = $Action; OwnerPid = $PID }
        Write-LikewebAtomicText (Join-Path $script:LikewebLogDir 'pending_job.json') ($job | ConvertTo-Json)
        return $job
    } catch {
        foreach ($path in $paths) { if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) } }
        throw
    } finally { if ($null -ne $process) { $process.Dispose() }; $lock.Dispose() }
}

function Receive-LikewebJob {
    param([object]$Job)
    if ([IO.File]::Exists($Job.ResultPath)) {
        $result = [IO.File]::ReadAllText($Job.ResultPath) | ConvertFrom-Json -ErrorAction Stop
        foreach ($path in @($Job.ResultPath,$Job.ConfigPath,$Job.CancelPath)) { if ($path -and [IO.File]::Exists($path)) { [IO.File]::Delete($path) } }
        return $result
    }
    $process = Get-LikewebJobProcess $Job
    if ($null -eq $process) {
        foreach ($path in @($Job.ConfigPath,$Job.CancelPath)) { if ($path -and [IO.File]::Exists($path)) { [IO.File]::Delete($path) } }
        return [pscustomobject]@{ Success = $false; PreviousConnectionRestored = $false; ErrorMessage = 'Операция завершилась без результата. Используйте восстановление в трее.'; LogTail = '' }
    }
    return $null
}

function Remove-LikewebStaleJobs {
    if ($null -ne (Get-LikewebPendingJob)) { return }
    $directory = Join-Path $script:LikewebLogDir 'jobs'
    if ([IO.Directory]::Exists($directory)) {
        foreach ($file in @(Get-ChildItem -LiteralPath $directory -File)) {
            if ($file.Extension -in @('.toml','.cancel') -or $file.LastWriteTime -lt (Get-Date).AddDays(-1)) {
                Remove-Item -LiteralPath $file.FullName -Force
            }
        }
    }
    $oldTestDirectory = Join-Path $script:LikewebProfilesDir 'test'
    if ([IO.Directory]::Exists($oldTestDirectory)) {
        Get-ChildItem -LiteralPath $oldTestDirectory -File | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1) } | Remove-Item -Force
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $script:LikewebLogDir -Filter 'manager_reply_*.json' -File)) {
        if ($file.LastWriteTime -lt (Get-Date).AddDays(-1)) { Remove-Item -LiteralPath $file.FullName -Force }
    }
}
