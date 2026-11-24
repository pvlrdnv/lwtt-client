# Isolated regressions; no real VPN process or system network changes.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$failures = @()
foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $root 'app') -Filter '*.ps1' -Recurse) + @(Get-ChildItem -LiteralPath (Join-Path $root 'tools') -Filter '*.ps1') + @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1')) {
    $tokens = $null; $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if ($errors.Count) { $failures += ($file.Name + ': ' + ($errors | Out-String)) }
}
if ($failures.Count) { throw ($failures -join "`n") }
Write-Output 'PASS: all PowerShell files parse.'
$testError = $null
$backgroundProcess = $null
$runtime = Join-Path ([IO.Path]::GetTempPath()) ('lwtt-test-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($runtime)
Get-ChildItem -LiteralPath (Join-Path $root 'app\lwtt_app') -Filter '*.ps1' | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $runtime }
Copy-Item -LiteralPath (Join-Path $root 'VERSION') -Destination $runtime
function Assert-Test { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw $Message } }
function Assert-Throws { param([scriptblock]$Code,[string]$Message) $thrown=$false; try { & $Code } catch { $thrown=$true }; Assert-Test $thrown $Message }
try {
    . (Join-Path $runtime 'lwtt_common.ps1')
    foreach ($value in @('normal','literal\n','literal\t','quote"slash\','двойной\\слеш'," tabs`tlines`r`n",' leading and trailing ')) {
        Assert-Test ((ConvertFrom-LikewebTomlString (ConvertTo-LikewebTomlString $value)) -ceq $value) 'TOML string roundtrip failed.'
    }
    Assert-Test ((ConvertFrom-LikewebTomlString '\u0410\U0001F600') -eq ([string][char]0x410 + [char]::ConvertFromUtf32(0x1F600))) 'Unicode escapes failed.'
    Assert-Throws { ConvertFrom-LikewebTomlString '\q' } 'Unknown escape accepted.'
    foreach ($address in @('example.org:0','example.org:65536','example.org:99999','[not-ip]:443','https://example.org','domain/path:443')) { Assert-Throws { Normalize-LikewebAddress $address } ('Invalid address accepted: ' + $address) }
    Assert-Test ((Normalize-LikewebAddress '[2001:db8::1]:8443') -eq '[2001:db8::1]:8443') 'IPv6 address failed.'
    Assert-Test ((Normalize-LikewebAddress 'example.org') -eq 'example.org:443') 'Default port failed.'
    $settings = @{ DisplayName='Name'; ServerName='server'; Address='example.org:443'; Hostname='example.org'; Username='user'; Password='test\n"value'; Protocol='http2'; HasIPv6=$true; CertificatePem=''; EmbedCertificate=$false }
    $generated = New-LikewebProfileToml @settings
    $original = $generated.Replace('exclusions = []', "exclusions = [`n 'manual.example', # keep manual`n '203.0.113.0/24',`n]").Replace('mtu_size = 1280','mtu_size = 1400').Replace('addresses = ["example.org:443"]','addresses = ["example.org:443", "backup.example:443"]') + "`n[custom]`nvalue = '''line1`n[endpoint]`nusername = fake`n'''`n"
    $updated = Update-LikewebProfileToml $original ($generated.Replace('username = "user"','username = "changed"'))
    Assert-Test ((Get-LikewebTomlStringValue $updated 'username') -eq 'changed') 'Managed key update failed.'
    Assert-Test ($updated.Contains('mtu_size = 1400') -and $updated.Contains('"backup.example:443"') -and $updated.Contains('username = fake')) 'Unrelated TOML data lost.'
    Assert-Test ((Get-LikewebTomlStringValue $updated 'password') -ceq $settings.Password) 'Password changed after profile edit.'
    $cert = "-----BEGIN CERTIFICATE-----`nYWJj`n-----END CERTIFICATE-----"
    $withCert = Set-LikewebTomlValue $updated 'endpoint' 'certificate' ("'''`n"+$cert+"`n'''")
    Assert-Test ((Get-LikewebEmbeddedCertificate $withCert) -eq $cert) 'Multiline certificate parse failed.'
    $rules = @(ConvertTo-LikewebBypassRules "EXAMPLE.org`nexample.org`n*.example.org`n2001:db8::1`n10.0.0.0/8")
    Assert-Test ($rules.Count -eq 4) 'Bypass normalization/deduplication failed.'
    foreach ($invalid in @('https://example.org/path','10.0.0.0/33','bad/domain','*.*.org')) { Assert-Throws { ConvertTo-LikewebBypassRules $invalid } 'Invalid bypass entry accepted.' }
    Write-LikewebAtomicText (Join-Path $runtime 'settings\bypass.json') (@{ Enabled=$true; Rules=$rules } | ConvertTo-Json)
    $applied = Add-LikewebBypassToToml $original
    $merged = @(ConvertFrom-LikewebTomlStringArray (Get-LikewebTomlValue $applied '' 'exclusions'))
    Assert-Test ($merged -contains 'manual.example' -and $merged -contains 'example.org' -and $merged.Count -eq 6) 'Manual exclusions were not merged.'
    Assert-Test ((Get-LikewebTomlValue $applied 'listener.tun' 'excluded_routes') -eq (Get-LikewebTomlValue $original 'listener.tun' 'excluded_routes')) 'Local routes changed.'
    Write-LikewebAtomicText (Join-Path $runtime 'settings\bypass.json') (@{ Enabled=$false; Rules=$rules } | ConvertTo-Json)
    Assert-Test ((Add-LikewebBypassToToml $original) -ceq $original) 'Disabled bypass modified configuration.'
    $parsed = Parse-LikewebSettingsMessage "Server name`nserver`nAddress`nUsername`nuser`nPassword`npass"
    Assert-Test (-not $parsed.Address -and $parsed.Username -eq 'user') 'Import consumed the next field label.'
    Write-Output 'PASS: TOML roundtrip, Unicode, managed edits, preserved unknown keys, certificates, address validation, bypass merge and import boundaries.'

    foreach ($case in @(
        @{ Log='Failed to verify certificate: WCRYPT_E_TRUST_STATUS'; Has=$false; Kind='CertificateTrust'; Add=$true },
        @{ Log='Failed to verify certificate: WCRYPT_E_TRUST_STATUS'; Has=$true; Kind='CertificateTrust'; Add=$false },
        @{ Log='Failed to verify certificate: self-signed certificate'; Has=$false; Kind='CertificateTrust'; Add=$true },
        @{ Log='Failed to verify certificate: certificate has expired'; Has=$false; Kind='CertificateExpired'; Add=$false },
        @{ Log='certificate hostname mismatch'; Has=$false; Kind='CertificateHostname'; Add=$false },
        @{ Log='certificate is not yet valid'; Has=$false; Kind='CertificateNotYetValid'; Add=$false },
        @{ Log='Failed to verify certificate: WCRYPT_E_CERT_OPEN_STORE'; Has=$false; Kind='CertificateValidation'; Add=$false }
    )) {
        $failure = Get-LikewebCertificateFailure $case.Log $case.Has
        Assert-Test ($failure.ErrorKind -eq $case.Kind -and $failure.CanAddCertificate -eq $case.Add) ('Incorrect certificate diagnosis: ' + $case.Log)
    }
    foreach ($log in @('connection timed out', 'failed to resolve hostname', 'authentication failed', 'certificate = ""', 'server certificate is installed', 'connection refused', 'certificate = expired.pem', 'configuration certificate = unexpired-file')) {
        Assert-Test ($null -eq (Get-LikewebCertificateFailure $log $false)) ('Unrelated error attributed to certificate: ' + $log)
    }
    Write-Output 'PASS: certificate failure classification; timeout, DNS and authorization errors are not reported as missing PEM.'

    # Readiness must survive long logs and detect a recovery event written in two pieces.
    $realGetProcess = ${function:Get-LikewebProcess}
    function Get-LikewebProcess { return [pscustomobject]@{ Id = 321; StartTime = [datetime]'2026-01-01' } }
    $logBase = Join-Path $script:LikewebVpnLogDir 'trusttunnel_ready_test'
    Write-LikewebAtomicText $script:LikewebLatestVpnLogPointer $logBase
    Write-LikewebAtomicText ($logBase + '.meta.txt') "PID: 321`r`n"
    Write-LikewebAtomicText ($logBase + '.out.log') ("Successfully connected to endpoint`n" + ('ordinary log line' + "`n") * 200)
    Assert-Test (Get-LikewebTunnelReady) 'Readiness disappeared from a long log.'
    Write-LikewebAtomicText ($logBase + '.meta.txt') "PID: 999`r`n"
    Assert-Test (-not (Get-LikewebTunnelReady)) 'A previous process log was accepted as current tunnel state.'
    Write-LikewebAtomicText ($logBase + '.meta.txt') "PID: 321`r`n"
    [IO.File]::AppendAllText(($logBase + '.out.log'), 'Waiting recov')
    Assert-Test (Get-LikewebTunnelReady) 'Partial log event changed readiness prematurely.'
    [IO.File]::AppendAllText(($logBase + '.out.log'), "ery: error`n")
    Assert-Test (-not (Get-LikewebTunnelReady)) 'Recovery event did not clear readiness.'
    Set-Item Function:Get-LikewebProcess $realGetProcess
    Write-Output 'PASS: incremental tunnel readiness, long logs and split state events.'
    # Test atomic rollback by injecting one write failure after the first update.
    $a = Join-Path $runtime 'a.txt'; $b = Join-Path $runtime 'b.txt'
    Write-LikewebAtomicText $a 'before-a'; Write-LikewebAtomicText $b 'before-b'
    $realWrite = ${function:Write-LikewebAtomicText}
    function Write-LikewebAtomicText { param($Path,$Text) if ($Path -eq $b) { throw 'Injected write failure' }; & $realWrite $Path $Text }
    $changes = [ordered]@{}; $changes[$a]='after-a'; $changes[$b]='after-b'
    Assert-Throws { Invoke-LikewebFileTransaction $changes } 'Write failure was ignored.'
    Set-Item Function:Write-LikewebAtomicText $realWrite
    Assert-Test (([IO.File]::ReadAllText($a)) -eq 'before-a' -and ([IO.File]::ReadAllText($b)) -eq 'before-b') 'Transaction rollback failed.'
    $lock = Enter-LikewebOperationLock
    try { Assert-Throws { Enter-LikewebOperationLock } 'Concurrent operation was allowed.' } finally { $lock.Dispose() }
    # Replace process control at its boundary. Never launch TrustTunnel during tests.
    $script:FakeRunning = $true; $script:StopFails=$false; $script:Starts=0; $script:FirstStartFails=$false
    function Get-LikewebProcess { if ($script:FakeRunning) { return [pscustomobject]@{ Id=123 } }; return $null }
    function Stop-LikewebVpnAndWait { if ($script:StopFails) { return $false }; $script:FakeRunning=$false; return $true }
    function Start-LikewebVpnAndWait { param($CancelPath) $script:Starts++; if ($CancelPath -and [IO.File]::Exists($CancelPath)) { throw 'Cancelled' }; if ($script:FirstStartFails -and $script:Starts -eq 1) { return $false }; $script:FakeRunning=$true; return $true }
    function Get-LikewebLatestVpnLogText { return 'test log' }
    Write-LikewebAtomicText $script:LikewebActiveConfigPath $original
    Write-LikewebAtomicText $script:LikewebActiveProfilePath 'previous'
    $profile = Join-Path $script:LikewebProfilesDir 'new.toml'
    Write-LikewebAtomicText $profile $generated
    $testConfig = Join-Path $runtime 'test.toml'; Write-LikewebAtomicText $testConfig $generated
    $script:StopFails=$true
    $result = Invoke-LikewebConnectionOperation Connect $profile
    Assert-Test (-not $result.Success -and ([IO.File]::ReadAllText($script:LikewebActiveConfigPath)) -ceq $original) 'Failed stop replaced active config.'
    $script:StopFails=$false; $script:FirstStartFails=$true; $script:Starts=0
    $result = Invoke-LikewebConnectionOperation Connect $profile
    Assert-Test (-not $result.Success -and $result.PreviousConnectionRestored -and $script:FakeRunning -and ([IO.File]::ReadAllText($script:LikewebActiveProfilePath)) -eq 'previous') 'Connect rollback failed.'
    $script:FirstStartFails=$false; $script:Starts=0
    $result = Invoke-LikewebConnectionOperation -Action Test -ConfigPath $testConfig
    Assert-Test ($result.Success -and $result.PreviousConnectionRestored -and $script:FakeRunning -and ([IO.File]::ReadAllText($script:LikewebActiveConfigPath)) -ceq $original) 'Test did not restore previous session.'
    $cancel = Join-Path $runtime 'cancel'; Write-LikewebAtomicText $cancel 'cancel'
    $result = Invoke-LikewebConnectionOperation -Action Test -ConfigPath $testConfig -CancelPath $cancel
    Assert-Test (-not $result.Success -and $result.PreviousConnectionRestored -and $script:FakeRunning) 'Cancellation did not restore previous session.'
    $snapshot = @{ Files = @(Get-LikewebFileSnapshot @($script:LikewebActiveConfigPath,$script:LikewebActiveProfilePath)); WasRunning = $false }
    Write-LikewebAtomicText (Join-Path $script:LikewebLogDir 'connection_recovery.json') ($snapshot | ConvertTo-Json -Depth 6)
    Write-LikewebAtomicText $script:LikewebActiveConfigPath $generated
    $result = Invoke-LikewebConnectionOperation -Action Recover
    Assert-Test ($result.Success -and -not (Test-LikewebRecoveryRequired) -and ([IO.File]::ReadAllText($script:LikewebActiveConfigPath)) -ceq $original) 'Recovery after an interrupted operation failed.'
    Write-Output 'PASS: transaction rollback, operation lock, failed stop, failed start rollback, test restoration and cancellation.'

    # Classification uses the failed attempt's log, never the subsequent restored session.
    $oldLogSet = ${function:Get-LikewebLatestVpnLogSet}
    $oldLogText = ${function:Get-LikewebLatestVpnLogText}
    $oldStart = ${function:Start-LikewebVpnAndWait}
    function Get-LikewebLatestVpnLogSet { return [pscustomobject]@{ BasePath=$script:FakeLogPath } }
    function Get-LikewebLatestVpnLogText { return $script:FakeCertificateLog }
    function Start-LikewebVpnAndWait {
        param($CancelPath)
        $script:Starts++
        if ($script:Starts -eq 1) {
            if ($script:AdvanceLog) { $script:FakeLogPath='failed-session' }
            $script:FakeRunning=$false
            return $false
        }
        $script:FakeLogPath='restored-session'; $script:FakeCertificateLog='Successfully connected to endpoint'
        $script:FakeRunning=$true; return $true
    }
    foreach ($advance in @($true,$false)) {
        $script:FakeRunning=$true; $script:Starts=0; $script:AdvanceLog=$advance
        $script:FakeLogPath='old-session'; $script:FakeCertificateLog='Failed to verify certificate: WCRYPT_E_TRUST_STATUS'
        $result = Invoke-LikewebConnectionOperation -Action Connect -ProfilePath $profile
        if ($advance) {
            Assert-Test ($result.ErrorKind -eq 'CertificateTrust' -and $result.CanAddCertificate -and $result.ProfileId -eq 'new' -and $result.LogTail -match 'WCRYPT_E_TRUST_STATUS') 'Certificate diagnosis was lost during rollback.'
        } else {
            Assert-Test ($result.ErrorKind -eq 'Connection' -and -not $result.CanAddCertificate) 'A stale certificate log was attributed to a new attempt.'
        }
    }
    Set-Item Function:Get-LikewebLatestVpnLogSet $oldLogSet
    Set-Item Function:Get-LikewebLatestVpnLogText $oldLogText
    Set-Item Function:Start-LikewebVpnAndWait $oldStart
    Write-Output 'PASS: failed-session certificate diagnosis survives rollback; stale logs are ignored.'

    # Exercise the real worker launch and result protocol, with only network/process primitives stubbed.
    $connectionModule = Join-Path $runtime 'lwtt_connection.ps1'
    $stubs = @'
function Get-LikewebProcess { return $null }
function Stop-LikewebVpnAndWait { return $true }
function Start-LikewebVpnAndWait { param($CancelPath) Start-Sleep -Milliseconds 500; return $true }
'@
    Add-Content -LiteralPath $connectionModule -Value $stubs -Encoding UTF8
    $job = Start-LikewebAction -Action Connect -ProfilePath $profile
    $backgroundProcess = Get-LikewebJobProcess $job
    Assert-Throws { Enter-LikewebOperationLock } 'Pending worker did not reserve the coordinator.'
    $deadline = (Get-Date).AddSeconds(60)
    $result = $null
    do { Start-Sleep -Milliseconds 100; $result = Receive-LikewebJob $job } while ($null -eq $result -and (Get-Date) -lt $deadline)
    Assert-Test ($null -ne $result -and $result.Success) ('Background job failed: ' + $result.ErrorMessage)
    Assert-Test (-not [IO.File]::Exists($job.ResultPath) -and -not [IO.File]::Exists($job.ConfigPath)) 'Background job input/output was not cleaned.'
    Write-Output 'PASS: actual PowerShell worker launch, pending-job reservation, result delivery and cleanup with mocked VPN primitives.'

} catch { $testError = $_ }
finally {
    if ($null -ne $backgroundProcess) {
        try { if (-not $backgroundProcess.HasExited) { [void]$backgroundProcess.WaitForExit(10000) } }
        finally { $backgroundProcess.Dispose() }
    }
    if ($runtime -and [IO.Directory]::Exists($runtime)) {
        for ($retry = 0; $retry -lt 5; $retry++) {
            try { [IO.Directory]::Delete($runtime,$true); break }
            catch {
                if ($retry -eq 4) {
                    if ($null -eq $testError) { throw }
                    Write-Warning ('Test cleanup failed: ' + $_.Exception.GetType().Name)
                }
                Start-Sleep -Milliseconds 300
            }
        }
    }
}
if ($null -ne $testError) { throw $testError }
& (Join-Path $PSScriptRoot 'editor.ps1')
