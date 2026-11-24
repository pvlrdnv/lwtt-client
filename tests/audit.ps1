# Regressions found during the full-project audit. No real network operations.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path ([IO.Path]::GetTempPath()) ('lwtt-audit-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($runtime)
Get-ChildItem -LiteralPath (Join-Path $root 'app\lwtt_app') -Filter '*.ps1' | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $runtime }
Copy-Item -LiteralPath (Join-Path $root 'VERSION') -Destination $runtime
function Assert-Audit { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw $Message } }
function Assert-AuditThrows { param([scriptblock]$Code,[string]$Message) $failed=$false; try { & $Code } catch { $failed=$true }; Assert-Audit $failed $Message }
try {
    . (Join-Path $runtime 'lwtt_common.ps1')
    $settings = @{ DisplayName='Audit'; ServerName='first'; Address='example.org:443'; Hostname='example.org'; Username='alphauser'; Password='firstsecret'; Protocol='http2'; HasIPv6=$true; CertificatePem=''; EmbedCertificate=$false }
    $first = New-LikewebProfileToml @settings
    Write-LikewebAtomicText (Join-Path $script:LikewebProfilesDir 'first.toml') $first
    $settings.ServerName='second'; $settings.Username='betausers'; $settings.Password='othersecret'
    $second = New-LikewebProfileToml @settings
    $profile = Join-Path $script:LikewebProfilesDir 'second.toml'
    Write-LikewebAtomicText $profile $second
    $redacted = Protect-LikewebDiagnosticText 'firstsecret othersecret alphauser betausers'
    foreach ($secret in @('firstsecret','othersecret','alphauser','betausers')) { Assert-Audit (-not $redacted.Contains($secret)) 'Equal-length secrets leaked into diagnostics.' }
    $path = Join-Path $runtime 'atomic.txt'
    Write-LikewebAtomicText $path 'before'; Write-LikewebAtomicText $path 'after'
    Assert-Audit (([IO.File]::ReadAllText($path)) -eq 'after' -and @(Get-ChildItem -LiteralPath $runtime -Filter '*.bak').Count -eq 0) 'Atomic replace left an unnecessary backup.'
    foreach ($id in @('CON','con.toml','NUL','COM1','LPT9','AUX',$('a' * 129))) { Assert-AuditThrows { ConvertTo-LikewebSafeId $id } ('Reserved/long ID accepted: ' + $id) }
    Assert-Audit ((ConvertTo-LikewebSafeId 'normal.server-1') -eq 'normal.server-1') 'Valid ID rejected.'
    Write-LikewebAtomicText $script:LikewebActiveProfilePath '../outside'
    Assert-Audit (-not (Get-LikewebActiveProfileId) -and $null -eq (Get-LikewebActiveProfileInfo)) 'Invalid active pointer was accepted or prevented startup.'
    Write-LikewebAtomicText $script:LikewebActiveProfilePath 'broken'
    Write-LikewebAtomicText (Join-Path $script:LikewebProfilesDir 'broken.toml') 'hostname = bad'
    Assert-Audit ($null -eq (Get-LikewebActiveProfileInfo)) 'Corrupted active profile prevented startup.'
    [IO.File]::Delete((Join-Path $script:LikewebProfilesDir 'broken.toml'))
    Write-LikewebAtomicText $script:LikewebActiveProfilePath 'first'
    Assert-AuditThrows { Normalize-LikewebAddress '999.999.999.999:443' } 'Invalid numeric IPv4 accepted.'
    Assert-AuditThrows { ConvertTo-LikewebBypassRules '999.999.999.999' } 'Invalid numeric IPv4 accepted as bypass domain.'
    foreach ($protocol in @('nonsense3','HTTP/1.3','HTTP/2xxx')) { Assert-AuditThrows { Normalize-LikewebProtocol $protocol } 'Invalid protocol accepted.' }
    Assert-Audit ((Normalize-LikewebProtocol 'HTTP/3') -eq 'http3' -and (Normalize-LikewebProtocol 'h2') -eq 'http2') 'Valid protocol rejected.'
    $bypassPath = Join-Path $runtime 'settings\bypass.json'
    Write-LikewebAtomicText $bypassPath (@{ Enabled='false'; Rules=@() } | ConvertTo-Json)
    Assert-AuditThrows { Get-LikewebBypassSettings } 'String false silently enabled bypass.'
    Write-LikewebAtomicText $bypassPath (@{ Enabled=$false; Rules=@() } | ConvertTo-Json)
    $multiline = '[endpoint]' + "`n" + 'certificate = """' + "`n" + '-----BEGIN CERTIFICATE-----\nYWJj\n-----END CERTIFICATE-----' + "`n" + '"""'
    Assert-Audit ((Get-LikewebEmbeddedCertificate $multiline) -eq "-----BEGIN CERTIFICATE-----`nYWJj`n-----END CERTIFICATE-----") 'Basic multiline TOML certificate was not decoded.'
    Assert-Audit ((ConvertFrom-LikewebTomlString ('one\' + "`n  two") -Multiline) -eq 'onetwo') 'Multiline continuation failed.'
    Assert-Audit ((ConvertFrom-LikewebTomlString ('one\\' + "`n  two") -Multiline) -eq ('one\' + "`n  two")) 'An escaped backslash was mistaken for a line continuation.'
    $dns = [Text.Encoding]::ASCII.GetBytes('san.example.org')
    $san = [byte[]](@(48,($dns.Length+2),130,$dns.Length) + $dns)
    $names = @(Get-LikewebCertificateSanNames $san)
    Assert-Audit ($names.Count -eq 1 -and $names[0] -eq 'san.example.org') 'DER SAN DNS decoding failed.'
    $ipNames = @(Get-LikewebCertificateSanNames ([byte[]](48,6,135,4,192,0,2,1)))
    Assert-Audit ($ipNames[0] -eq '192.0.2.1') 'DER SAN IP decoding failed.'
    Assert-AuditThrows { Get-LikewebCertificateSanNames ([byte[]](48,5,130,9,1)) } 'Truncated SAN was accepted.'
    # Receiving a completed/dead job must not wait on an unrelated process reusing its PID.
    $job = [pscustomobject]@{ Pid=$PID; StartedAt='2001-01-01T00:00:00Z'; ResultPath=(Join-Path $runtime 'missing.json'); ConfigPath=''; CancelPath='' }
    $received = Receive-LikewebJob $job
    Assert-Audit ($null -ne $received -and -not $received.Success) 'A reused PID kept an old job alive.'
    Write-Output 'PASS: equal-length secret redaction, atomic replacement, safe IDs, active-path validation, IPv4, multiline TOML, DER SAN and reused PIDs.'
    # Inject an unreadable log while a connection fails; rollback must still happen.
    $script:FakeRunning=$true; $script:Starts=0; $script:FailFirst=$true; $script:FailRestore=$false
    function Get-LikewebProcess { if ($script:FakeRunning) { return [pscustomobject]@{ Id=123 } }; return $null }
    function Stop-LikewebVpnAndWait { $script:FakeRunning=$false; return $true }
    function Start-LikewebVpnAndWait {
        param($CancelPath)
        $script:Starts++
        if (($script:FailFirst -and $script:Starts -eq 1) -or ($script:FailRestore -and $script:Starts -gt 1)) { return $false }
        $script:FakeRunning=$true; return $true
    }
    function Get-LikewebLatestVpnLogText { throw 'Injected unreadable log' }
    Write-LikewebAtomicText $script:LikewebActiveConfigPath $first
    $result = Invoke-LikewebConnectionOperation Connect $profile
    Assert-Audit (-not $result.Success -and $result.PreviousConnectionRestored -and $script:FakeRunning -and ([IO.File]::ReadAllText($script:LikewebActiveConfigPath)) -ceq $first) 'A diagnostic failure prevented rollback.'
    # A successful test followed by failed restoration must not retry silently.
    $script:Starts=0; $script:FailFirst=$false; $script:FailRestore=$true; $script:FakeRunning=$true
    $result = Invoke-LikewebConnectionOperation -Action Test -ConfigPath $profile
    Assert-Audit (-not $result.Success -and -not $result.PreviousConnectionRestored -and $result.ErrorKind -eq 'Restoration' -and $script:Starts -eq 2 -and (Test-LikewebRecoveryRequired)) 'Failed restoration was retried or misreported.'
    Write-Output 'PASS: unreadable logs cannot prevent rollback; failed restoration retains its journal without a silent second attempt.'
} finally {
    for ($retry=0; $retry -lt 5 -and [IO.Directory]::Exists($runtime); $retry++) {
        try { [IO.Directory]::Delete($runtime,$true) }
        catch { if ($retry -eq 4) { throw }; Start-Sleep -Milliseconds 300 }
    }
}
