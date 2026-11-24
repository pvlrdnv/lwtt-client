# Build the actual manager and tray UI without showing a window or starting VPN.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path ([IO.Path]::GetTempPath()) ('lwtt-ui-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($runtime)
Get-ChildItem -LiteralPath (Join-Path $root 'app\lwtt_app') -File | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $runtime }
Copy-Item -LiteralPath (Join-Path $root 'VERSION') -Destination $runtime
try {
    $path = Join-Path $runtime 'lwtt_manager.ps1'
    $source = [IO.File]::ReadAllText($path)
    $probe = @'
[void]$form.Handle
$settings = @{ DisplayName='Test'; ServerName='test'; Address='example.org:443'; Hostname='example.org'; Username='test'; Password='a\n"b'; Protocol='http2'; HasIPv6=$true; CertificatePem=''; EmbedCertificate=$false }
$profilePath = Join-Path $script:LikewebProfilesDir 'test.toml'
$original = (New-LikewebProfileToml @settings).Replace('mtu_size = 1280','mtu_size = 1420')
Write-LikewebAtomicText $profilePath $original
Load-ProfileForEditing 'test'
if ($passwordTextBox.Text -cne $settings.Password) { throw 'Editor changed password during loading.' }
$hostnameTextBox.Text = 'https://invalid.example/path'
$validation = Get-EditorValidationResult
if ($validation.IsValid -or -not $errorProvider.GetError($hostnameTextBox)) { throw 'Hostname field error was cleared immediately.' }
$hostnameTextBox.Text = 'example.org'
$serverNameTextBox.Text = 'CON'
$validation = Get-EditorValidationResult
if ($validation.IsValid -or -not $errorProvider.GetError($serverNameTextBox)) { throw 'Reserved Windows name was not highlighted.' }
$serverNameTextBox.Text = 'test'

foreach ($i in 1..100) { $usernameTextBox.AppendText('x'); Update-EditorValidation }
if ($usernameTextBox.Text.Length -ne 104) { throw 'Continuous editor input failed.' }
$result = Get-EditorToml
if (-not $result.Toml.Contains('mtu_size = 1420')) { throw 'Actual editor lost extra settings.' }
$originalConfirm = ${function:Confirm-DiscardChanges}
function Confirm-DiscardChanges { return $false }
$null = Send-LikewebManagerRequest 'Add'
Poll-ManagerRequests
if ($script:EditingProfileId -ne 'test' -or $usernameTextBox.Text.Length -ne 104) { throw 'Tray request discarded unsaved input.' }
Set-Item Function:Confirm-DiscardChanges $originalConfirm
$script:EditorDirty = $false
$script:TestWorkerProcess = $null
Save-EditorProfile $false
if (-not ([IO.File]::ReadAllText($profilePath)).Contains('mtu_size = 1420')) { throw 'Actual save lost extra settings.' }
if ((Get-LikewebProfileInfo $profilePath).Username.Length -ne 104) { throw 'Actual save did not persist editor input.' }

# Optional certificates must not be required even when a bot's message mentions PEM/self-signed.
$settings['CertificateMode'] = 'Self-signed certificate; PEM required'
$script:EditorDirty = $false
Show-NewServerPage
Fill-EditorFromParsedSettings ([pscustomobject]$settings)
if (-not (Get-EditorValidationResult).IsValid) { throw 'Import still requires a PEM file.' }
if ($script:CertificateExpanded -or $certificateSurface.Height -ne 96) { throw 'Certificate section is not collapsed by default.' }
function New-TestCertificatePem {
    param([string]$Organization)
    $rsa = [Security.Cryptography.RSACng]::new(2048)
    $cert = $null
    try {
        $subjectName = if ($Organization -eq 'Authority') { 'CN=LWTT Root CA' } else { 'CN=example.org, O=' + $Organization }
        $request = [Security.Cryptography.X509Certificates.CertificateRequest]::new($subjectName, $rsa, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
        if ($Organization -eq 'Authority') { $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($true,$false,0,$true)) }
        if ($Organization -eq 'SAN') {
            $names = [Text.Encoding]::ASCII.GetBytes('san.example.org')
            $rawSan = [byte[]](@(48,($names.Length+2),130,$names.Length) + $names)
            $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509Extension]::new('2.5.29.17',$rawSan,$false))
        }
        if ($Organization -eq 'Second') {
            $issuerRequest = [Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=LWTT Test CA', $rsa, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
            $issuerRequest.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($true,$false,0,$true))
            $issuer = $issuerRequest.CreateSelfSigned([DateTimeOffset]::Now.AddDays(-2),[DateTimeOffset]::Now.AddYears(2))
            try { $cert = $request.Create($issuer,[DateTimeOffset]::Now.AddDays(-1),[DateTimeOffset]::Now.AddMonths(6),[byte[]](1,2,3,4)) }
            finally { $issuer.Dispose() }
        } else { $cert = $request.CreateSelfSigned([DateTimeOffset]::Now.AddDays(-1), [DateTimeOffset]::Now.AddYears(1)) }
        $body = [Convert]::ToBase64String($cert.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert), [Base64FormattingOptions]::InsertLineBreaks)
        return "-----BEGIN CERTIFICATE-----`r`n" + $body + "`r`n-----END CERTIFICATE-----"
    } finally { if ($null -ne $cert) { $cert.Dispose() }; $rsa.Dispose() }
}
$authorityPem = New-TestCertificatePem 'Authority'
$sanPem = New-TestCertificatePem 'SAN'
$authorityFile = Join-Path $PSScriptRoot 'authority.pem'; Write-LikewebAtomicText $authorityFile $authorityPem
$sanFile = Join-Path $PSScriptRoot 'san.pem'; Write-LikewebAtomicText $sanFile $sanPem
Load-CertificateIntoEditor $authorityFile
if (-not $script:SelectedCertificateInfo.IsCertificateAuthority -or -not (Get-EditorValidationResult).IsValid) { throw 'CA file was incorrectly matched against the server hostname.' }
Load-CertificateIntoEditor $sanFile
if ((Get-EditorValidationResult).IsValid) { throw 'CN incorrectly overrode the certificate SAN.' }
$hostnameTextBox.Text = 'san.example.org'
if (-not (Get-EditorValidationResult).IsValid) { throw 'SAN DNS name was not recognized.' }
$hostnameTextBox.Text = 'example.org'
Clear-CertificateSelection
$script:EditorDirty = $false
$firstPem = New-TestCertificatePem 'First'
$secondPem = New-TestCertificatePem 'Second'
$firstFile = Join-Path $PSScriptRoot 'first.pem'; Write-LikewebAtomicText $firstFile $firstPem
$secondFile = Join-Path $PSScriptRoot 'second.pem'; Write-LikewebAtomicText $secondFile $secondPem
$badFile = Join-Path $PSScriptRoot 'bad.pem'; Write-LikewebAtomicText $badFile 'not a certificate'
Load-ProfileForEditing 'test'
if ($script:CertificateExpanded) { throw 'Editing without PEM unexpectedly expanded the section.' }
Open-CertificateSection
Load-CertificateIntoEditor $firstFile
if ($null -eq $script:SelectedCertificateInfo -or -not $script:CertificateExpanded) { throw 'PEM did not load in editor.' }
if (-not (Get-EditorValidationResult).IsValid) { throw 'Valid PEM was rejected.' }
Save-EditorProfile $false
$firstStored = (Get-LikewebProfileInfo $profilePath).CertificatePem
if (-not $firstStored -or $firstStored -ne $firstPem.Trim()) { throw 'Selected PEM was not used in the TOML profile.' }
Load-ProfileForEditing 'test'
if ($script:CertificateExpanded -or $null -eq $script:SelectedCertificateInfo) { throw 'Saved PEM did not load into collapsed editing section.' }
Open-CertificateSection
Load-CertificateIntoEditor $secondFile
if ($script:SelectedCertificateInfo.IsSelfSigned) { throw 'Test fixture should cover a CA-issued certificate.' }
Save-EditorProfile $false
if ((Get-LikewebProfileInfo $profilePath).CertificatePem -ne $secondPem.Trim()) { throw 'Replacing PEM did not update TOML.' }
$storedCertificate = Join-Path $script:LikewebCertificatesDir 'test.pem'
if (([IO.File]::ReadAllText($storedCertificate)).Trim() -ne $secondPem.Trim()) { throw 'Replacing PEM did not update local copy.' }
Load-ProfileForEditing 'test'
Load-CertificateIntoEditor $badFile
if ($script:SelectedCertificateInfo.Pem.Trim() -ne $secondPem.Trim()) { throw 'Invalid replacement discarded the previous PEM.' }
Clear-CertificateSelection
if (-not [IO.File]::Exists($storedCertificate)) { throw 'PEM removal was applied before saving.' }
Save-EditorProfile $false
if ((Get-LikewebProfileInfo $profilePath).CertificatePem -or [IO.File]::Exists($storedCertificate)) { throw 'Removing PEM did not update profile and local copy.' }
if ((Get-LikewebTomlValue ([IO.File]::ReadAllText($profilePath)) 'endpoint' 'skip_verification') -ne 'false') { throw 'System trust disabled TLS verification.' }
Load-ProfileForEditing 'test'
# A certificate trust error during a test expands the optional section without altering the profile.
Complete-ServerTest ([pscustomobject]@{ Success=$false; PreviousConnectionRestored=$true; ErrorMessage='Certificate trust failed; optional PEM'; LogTail='test log'; CanAddCertificate=$true })
if (-not $script:CertificateExpanded) { throw 'Certificate error did not reveal the optional upload action.' }

$originalReceive = ${function:Receive-LikewebJob}
function Receive-LikewebJob { param($Job) return [pscustomobject]@{ Success=$false; PreviousConnectionRestored=$true; ErrorMessage='Certificate trust error'; CanAddCertificate=$true; ProfileId='test'; LogTail='test' } }
$script:ConnectionJob = [pscustomobject]@{ Action='Connect' }
[void][Windows.Forms.Timer].GetMethod('OnTick',[Reflection.BindingFlags]'Instance,NonPublic').Invoke($serverRefreshTimer,@([EventArgs]::Empty))
if ($serversMessagePanel.Height -ne 86 -or $serversCertificateButton.Tag -ne 'test') { throw 'Connection failure did not provide the certificate action for the correct profile.' }
Set-Item Function:Receive-LikewebJob $originalReceive
Set-CertificateExpanded $false
[void][Windows.Forms.Button].GetMethod('OnClick',[Reflection.BindingFlags]'Instance,NonPublic').Invoke($serversCertificateButton,@([EventArgs]::Empty))
if (-not $script:CertificateExpanded -or $script:EditingProfileId -ne 'test') { throw 'Certificate error action did not open the correct profile section.' }

Write-Output 'PASS: optional/collapsed certificate UI, real PEM load, replace, invalid replacement, removal on save, retained TLS verification and certificate-error action.'

$originalDeleteConfirmation = ${function:Show-DeleteConfirmation}
$brokenProfile = Join-Path $script:LikewebProfilesDir 'broken.toml'
Write-LikewebAtomicText $brokenProfile 'not valid profile'
function Show-DeleteConfirmation { param($DisplayName) return $true }
Delete-ProfileById 'broken'
if ([IO.File]::Exists($brokenProfile)) { throw 'Corrupted inactive profile could not be deleted.' }
Write-LikewebAtomicText $brokenProfile 'not valid profile'
function Show-DeleteConfirmation { param($DisplayName) Write-LikewebAtomicText $script:LikewebActiveProfilePath 'broken'; return $true }
Delete-ProfileById 'broken'
if (-not [IO.File]::Exists($brokenProfile)) { throw 'Profile that became active during confirmation was deleted.' }
Write-LikewebAtomicText $script:LikewebActiveProfilePath 'test'
Set-Item Function:Show-DeleteConfirmation $originalDeleteConfirmation
Write-Output 'PASS: broken profile removal and active-profile recheck after confirmation.'
$validationTimer.Stop(); $autoRecognitionTimer.Stop(); $testPollTimer.Stop(); $serverRefreshTimer.Stop()
$form.Dispose()
Write-Output 'PASS: real manager initialization, profile loading, continuous input and preserved settings after save.'
'@
    $source = $source.Replace('[void]$form.ShowDialog()', $probe)
    # Runtime exceptions must fail the test instead of opening the production error dialog.
    $source = $source.Replace('Write-LikewebManagerLog "Критическая ошибка окна менеджера" $_', 'throw')
    [IO.File]::WriteAllText($path,$source,[Text.UTF8Encoding]::new($true))
    & $path
    $path = Join-Path $runtime 'lwtt_tray.ps1'
    $source = [IO.File]::ReadAllText($path)
    $source = $source.Replace('Local\LikewebTrustTunnelTray', ('Local\LWTT_Test_' + [guid]::NewGuid().ToString('N')))
    $source = $source.Replace('[System.Windows.Forms.Application]::Run()', @'
if ($bypassItem.Text -notmatch 'Обход' -or $null -eq $recoverItem) { throw 'Tray routing actions missing.' }
$activeProfile = Get-LikewebActiveProfileInfo
Rebuild-ServersMenu
Update-TrayStatus

$originalReceive = ${function:Receive-LikewebJob}
$originalShowMessage = ${function:Show-TrayMessage}
$originalStartManager = ${function:Start-ServerManager}
function Show-TrayMessage { param($Text,$Icon) }
function Receive-LikewebJob { param($Job) return [pscustomobject]@{ Success=$false; ErrorMessage='Certificate trust error'; CanAddCertificate=$true; ProfileId='test' } }
function Start-ServerManager { param($Mode,$ProfileId) $script:ProbeMode=$Mode; $script:ProbeProfileId=$ProfileId }
$script:TrayJob = [pscustomobject]@{ Action='Connect' }
Update-TrayStatus
if (-not $certificateHelpItem.Available -or $script:CertificateHelpProfileId -ne 'test') { throw 'Tray did not expose the certificate action.' }
[void][Windows.Forms.ToolStripItem].GetMethod('OnClick',[Reflection.BindingFlags]'Instance,NonPublic').Invoke($certificateHelpItem,@([EventArgs]::Empty))
if ($script:ProbeMode -ne 'Certificate' -or $script:ProbeProfileId -ne 'test') { throw 'Tray certificate action targeted the wrong profile or mode.' }
Set-Item Function:Receive-LikewebJob $originalReceive
Set-Item Function:Show-TrayMessage $originalShowMessage
Set-Item Function:Start-ServerManager $originalStartManager
Write-Output 'PASS: certificate failure actions in manager and tray target the correct profile.'

Write-Output 'PASS: real tray initialization, menus and status refresh without VPN.'
'@)
    [IO.File]::WriteAllText($path,$source,[Text.UTF8Encoding]::new($true))
    & $path
    . (Join-Path $runtime 'lwtt_common.ps1')
    $path = Join-Path $runtime 'lwtt_bypass_ui.ps1'
    $source = [IO.File]::ReadAllText($path).Replace('[void]$dialog.ShowDialog()', @'
$text.Text = "https://example.org/path`r`n*.example.org"
[void][Windows.Forms.Button].GetMethod('OnClick', [Reflection.BindingFlags]'Instance,NonPublic').Invoke($normalize, @([EventArgs]::Empty))
if ($text.Text -match 'https://') { throw 'Bypass URL conversion failed.' }
[void][Windows.Forms.Button].GetMethod('OnClick', [Reflection.BindingFlags]'Instance,NonPublic').Invoke($save, @([EventArgs]::Empty))
$saved = Get-LikewebBypassSettings
if ($saved.Rules.Count -ne 2) { throw 'Bypass dialog did not save the list.' }
Write-Output 'PASS: real bypass dialog construction, URL conversion and persistence without reconnect.'
'@)
    [IO.File]::WriteAllText($path,$source,[Text.UTF8Encoding]::new($true))
    . $path
    Show-LikewebBypassDialog
} finally {
    for ($retry=0; $retry -lt 5 -and [IO.Directory]::Exists($runtime); $retry++) {
        try { [IO.Directory]::Delete($runtime,$true) }
        catch { if ($retry -eq 4) { throw }; Start-Sleep -Milliseconds 300 }
    }
}
