# Общие функции LW TrustTunnel Client для Windows PowerShell 5.1

$script:LikewebBaseDir = $PSScriptRoot
$script:LikewebInstallRoot = Split-Path -Parent $script:LikewebBaseDir
if ([string]::IsNullOrWhiteSpace($script:LikewebInstallRoot)) {
    $script:LikewebInstallRoot = $script:LikewebBaseDir
}
$versionPath = Join-Path $script:LikewebBaseDir 'VERSION'
if (-not (Test-Path -LiteralPath $versionPath)) { $versionPath = Join-Path (Split-Path -Parent $script:LikewebInstallRoot) 'VERSION' }
$script:LikewebAppVersion = if (Test-Path -LiteralPath $versionPath) { ([IO.File]::ReadAllText($versionPath)).Trim() } else { 'unknown' }
$script:LikewebProfilesDir = Join-Path $script:LikewebBaseDir "profiles"
$script:LikewebCertificatesDir = Join-Path $script:LikewebProfilesDir "certificates"
$script:LikewebBackupsDir = Join-Path $script:LikewebProfilesDir "backups"
$script:LikewebActiveConfigPath = Join-Path $script:LikewebBaseDir "lwtt_client.toml"
$script:LikewebActiveProfilePath = Join-Path $script:LikewebProfilesDir "active_profile.txt"
$script:LikewebExePath = Join-Path $script:LikewebBaseDir "trusttunnel_client.exe"
$script:LikewebStartBatPath = Join-Path $script:LikewebBaseDir "lwtt_start.bat"
$script:LikewebStopBatPath = Join-Path $script:LikewebBaseDir "lwtt_stop.bat"
$script:LikewebLogDir = Join-Path $script:LikewebBaseDir "log"
$script:LikewebVpnLogDir = Join-Path $script:LikewebLogDir "client"
$script:LikewebLatestVpnLogPointer = Join-Path $script:LikewebVpnLogDir "latest_client_log.txt"
$script:LikewebVpnPidPath = Join-Path $script:LikewebVpnLogDir "trusttunnel_client.pid"
$script:LikewebVpnRunnerPath = Join-Path $script:LikewebBaseDir "lwtt_runner.ps1"
$script:LikewebManagerPidPath = Join-Path $script:LikewebLogDir "lwtt_manager.pid"
$script:LikewebOperationStatePath = Join-Path $script:LikewebLogDir "operation_state.json"
$script:LikewebUtf8NoBom = New-Object System.Text.UTF8Encoding($false)

foreach ($directory in @(
    $script:LikewebProfilesDir,
    $script:LikewebCertificatesDir,
    $script:LikewebBackupsDir,
    $script:LikewebLogDir,
    $script:LikewebVpnLogDir
)) {
    if (-not (Test-Path -LiteralPath $directory)) {
        [void](New-Item -ItemType Directory -Path $directory -Force)
    }
}

function Test-LikewebAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}


function Initialize-LikewebNativeLauncher {
    if ("Likeweb.NativeLauncher" -as [type]) {
        return
    }

    $source = @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace Likeweb {
    public static class NativeLauncher {
        private const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
        private const uint TOKEN_ASSIGN_PRIMARY = 0x0001;
        private const uint TOKEN_DUPLICATE = 0x0002;
        private const uint TOKEN_QUERY = 0x0008;
        private const uint MAXIMUM_ALLOWED = 0x02000000;
        private const int SecurityImpersonation = 2;
        private const int TokenPrimary = 1;
        private const uint LOGON_WITH_PROFILE = 0x00000001;
        private const uint CREATE_UNICODE_ENVIRONMENT = 0x00000400;
        private const uint CREATE_NO_WINDOW = 0x08000000;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct STARTUPINFO {
            public int cb;
            public string lpReserved;
            public string lpDesktop;
            public string lpTitle;
            public int dwX;
            public int dwY;
            public int dwXSize;
            public int dwYSize;
            public int dwXCountChars;
            public int dwYCountChars;
            public int dwFillAttribute;
            public int dwFlags;
            public short wShowWindow;
            public short cbReserved2;
            public IntPtr lpReserved2;
            public IntPtr hStdInput;
            public IntPtr hStdOutput;
            public IntPtr hStdError;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct PROCESS_INFORMATION {
            public IntPtr hProcess;
            public IntPtr hThread;
            public int dwProcessId;
            public int dwThreadId;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr OpenProcess(
            uint processAccess,
            bool bInheritHandle,
            int processId
        );

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool OpenProcessToken(
            IntPtr processHandle,
            uint desiredAccess,
            out IntPtr tokenHandle
        );

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool DuplicateTokenEx(
            IntPtr existingToken,
            uint desiredAccess,
            IntPtr tokenAttributes,
            int impersonationLevel,
            int tokenType,
            out IntPtr newToken
        );

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CreateProcessWithTokenW(
            IntPtr token,
            uint logonFlags,
            string applicationName,
            StringBuilder commandLine,
            uint creationFlags,
            IntPtr environment,
            string currentDirectory,
            ref STARTUPINFO startupInfo,
            out PROCESS_INFORMATION processInformation
        );

        [DllImport("kernel32.dll")]
        private static extern bool CloseHandle(IntPtr handle);

        public static int StartUnelevated(string commandLine, string workingDirectory) {
            Process shell = null;
            foreach (Process candidate in Process.GetProcessesByName("explorer")) {
                if (candidate.SessionId == Process.GetCurrentProcess().SessionId) {
                    shell = candidate;
                    break;
                }
            }

            if (shell == null) {
                throw new InvalidOperationException("Explorer process was not found.");
            }

            IntPtr processHandle = IntPtr.Zero;
            IntPtr shellToken = IntPtr.Zero;
            IntPtr primaryToken = IntPtr.Zero;
            PROCESS_INFORMATION processInfo = new PROCESS_INFORMATION();

            try {
                processHandle = OpenProcess(
                    PROCESS_QUERY_LIMITED_INFORMATION,
                    false,
                    shell.Id
                );

                if (processHandle == IntPtr.Zero) {
                    throw new System.ComponentModel.Win32Exception(
                        Marshal.GetLastWin32Error()
                    );
                }

                if (!OpenProcessToken(
                    processHandle,
                    TOKEN_DUPLICATE | TOKEN_QUERY,
                    out shellToken
                )) {
                    throw new System.ComponentModel.Win32Exception(
                        Marshal.GetLastWin32Error()
                    );
                }

                if (!DuplicateTokenEx(
                    shellToken,
                    MAXIMUM_ALLOWED,
                    IntPtr.Zero,
                    SecurityImpersonation,
                    TokenPrimary,
                    out primaryToken
                )) {
                    throw new System.ComponentModel.Win32Exception(
                        Marshal.GetLastWin32Error()
                    );
                }

                STARTUPINFO startupInfo = new STARTUPINFO();
                startupInfo.cb = Marshal.SizeOf(typeof(STARTUPINFO));
                startupInfo.lpDesktop = "winsta0\\default";

                StringBuilder mutableCommandLine = new StringBuilder(commandLine);

                if (!CreateProcessWithTokenW(
                    primaryToken,
                    LOGON_WITH_PROFILE,
                    null,
                    mutableCommandLine,
                    CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW,
                    IntPtr.Zero,
                    workingDirectory,
                    ref startupInfo,
                    out processInfo
                )) {
                    throw new System.ComponentModel.Win32Exception(
                        Marshal.GetLastWin32Error()
                    );
                }

                return processInfo.dwProcessId;
            }
            finally {
                if (processInfo.hThread != IntPtr.Zero) {
                    CloseHandle(processInfo.hThread);
                }
                if (processInfo.hProcess != IntPtr.Zero) {
                    CloseHandle(processInfo.hProcess);
                }
                if (primaryToken != IntPtr.Zero) {
                    CloseHandle(primaryToken);
                }
                if (shellToken != IntPtr.Zero) {
                    CloseHandle(shellToken);
                }
                if (processHandle != IntPtr.Zero) {
                    CloseHandle(processHandle);
                }
            }
        }
    }
}
"@

    Add-Type -TypeDefinition $source -Language CSharp
}

function Start-LikewebPowerShellUnelevated {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        [string[]]$ScriptArguments = @()
    )

    Initialize-LikewebNativeLauncher

    $powershellPath = Join-Path $PSHOME "powershell.exe"
    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add(('"{0}"' -f $powershellPath))
    $parts.Add("-NoProfile")
    $parts.Add("-ExecutionPolicy")
    $parts.Add("Bypass")
    $parts.Add("-WindowStyle")
    $parts.Add("Hidden")
    $parts.Add("-File")
    $parts.Add(('"{0}"' -f $ScriptPath.Replace('"', '')))

    foreach ($argument in $ScriptArguments) {
        $argumentText = [string]$argument
        if ($argumentText -match '^-[A-Za-z]') {
            $parts.Add($argumentText)
        }
        else {
            $parts.Add(('"{0}"' -f $argumentText.Replace('"', '')))
        }
    }

    $commandLine = $parts -join " "

    try {
        return [Likeweb.NativeLauncher]::StartUnelevated(
            $commandLine,
            $script:LikewebBaseDir
        )
    }
    catch {
        # Explorer COM is a useful fallback on systems where token duplication
        # is restricted by local security policy.
        $shell = New-Object -ComObject Shell.Application
        $shellArguments = $parts.GetRange(1, $parts.Count - 1) -join " "
        $shell.ShellExecute(
            $powershellPath,
            $shellArguments,
            $script:LikewebBaseDir,
            "open",
            0
        )
        return 0
    }
}

function ConvertTo-LikewebSafeId {
    param([string]$Name)

    $safe = $Name.Trim()
    $safe = $safe -replace '[^A-Za-z0-9._-]', '_'
    $safe = $safe -replace '_+', '_'
    $safe = $safe.Trim([char[]]'_.-')

    if ([string]::IsNullOrWhiteSpace($safe)) {
        throw "Не удалось сформировать служебный идентификатор сервера."
    }

    if ($safe.Length -gt 128) { throw 'Служебное имя сервера не должно быть длиннее 128 символов.' }
    if ($safe -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { throw 'Это служебное имя зарезервировано Windows. Выберите другое имя.' }
    return $safe
}

function ConvertTo-LikewebTomlString {
    param([string]$Value)

    if ($null -eq $Value) {
        return ""
    }

    $result = $Value.Replace('\', '\\')
    $result = $result.Replace('"', '\"')
    $result = $result.Replace("`r", '\r')
    $result = $result.Replace("`n", '\n')
    $result = $result.Replace("`t", '\t')
    $result = $result.Replace([string][char]8, '\b').Replace([string][char]12, '\f')
    if ($result -match '[\x00-\x07\x0B\x0E-\x1F\x7F]') { throw 'Недопустимый управляющий символ.' }
    return $result
}

function ConvertTo-LikewebCommentValue {
    param([string]$Value)

    if ($null -eq $Value) {
        return ""
    }

    return (($Value -replace '[\r\n]+', ' ').Trim())
}

function Get-LikewebFieldAfterLabel {
    param(
        [string[]]$Lines,
        [string[]]$Patterns
    )

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i].Trim()

        foreach ($pattern in $Patterns) {
            if ($line -match ("^(?i:" + $pattern + ")\s*(?:[:\-–\u2014]\s*)?(.*)$")) {
                $sameLineValue = $Matches[1].Trim()

                if (-not [string]::IsNullOrWhiteSpace($sameLineValue)) {
                    return $sameLineValue
                }

                for ($j = $i + 1; $j -lt $Lines.Count; $j++) {
                    $next = $Lines[$j].Trim()
                    if ($next -match '^(?i:Server\s+name|Имя\s+сервера|Address|Адрес|Domain\s+name(?:\s+from\s+server\s+certificate)?|Доменное\s+имя.*|Username|User\s+name|Логин|Имя\s+пользователя|Password|Пароль|Protocol|Протокол|Allow\s+IPv6.*|Разрешить\s+IPv6.*|Self-signed\s+certificate|Сертификат)\s*:?[ \t]*$') { return "" }
                    if (-not [string]::IsNullOrWhiteSpace($next)) {
                        return $next
                    }
                }
            }
        }
    }

    return ""
}

function Get-LikewebDisplayNameFromHeader {
    param([string[]]$Lines)

    $fieldLabelPattern = '^(?i)(Server\s+name|Address|Domain\s+name|Username|User\s+name|Password|Protocol|Allow\s+IPv6|Self-signed\s+certificate|Имя\s+сервера|Адрес|Домен|Логин|Имя\s+пользователя|Пароль|Протокол|Разрешить\s+IPv6|Сертификат)\b'

    foreach ($rawLine in $Lines) {
        $line = $rawLine.Trim()

        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($line -match $fieldLabelPattern) {
            continue
        }

        $candidate = $line
        $candidate = $candidate -replace '^[^\p{L}\p{N}]+', ''
        $candidate = $candidate -replace '\s*[\u2014–-]\s*(?i:ручной\s+ввод|manual\s+input).*$',''
        $candidate = $candidate.Trim()

        if (
            $candidate -match '\([^)]+\)' -and
            $candidate.Length -ge 3 -and
            $candidate.Length -le 120
        ) {
            return $candidate
        }
    }

    return ""
}

function Parse-LikewebSettingsMessage {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Вставьте сообщение с настройками сервера."
    }

    $normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    $lines = $normalized.Split("`n")

    $serverName = Get-LikewebFieldAfterLabel $lines @(
        'Server\s+name',
        'Имя\s+сервера'
    )

    $displayName = Get-LikewebDisplayNameFromHeader $lines
    if ([string]::IsNullOrWhiteSpace($displayName)) {
        $displayName = $serverName
    }

    return [pscustomobject][ordered]@{
        DisplayName = $displayName
        ServerName = $serverName
        Address = Get-LikewebFieldAfterLabel $lines @(
            'Address',
            'Адрес'
        )
        Hostname = Get-LikewebFieldAfterLabel $lines @(
            'Domain\s+name\s+from\s+server\s+certificate',
            'Domain\s+name',
            'Доменное\s+имя\s+из\s+сертификата\s+сервера',
            'Доменное\s+имя'
        )
        Username = Get-LikewebFieldAfterLabel $lines @(
            'Username',
            'User\s+name',
            'Логин',
            'Имя\s+пользователя'
        )
        Password = Get-LikewebFieldAfterLabel $lines @(
            'Password',
            'Пароль'
        )
        Protocol = Get-LikewebFieldAfterLabel $lines @(
            'Protocol',
            'Протокол'
        )
        IPv6 = Get-LikewebFieldAfterLabel $lines @(
            'Allow\s+IPv6\s+connections\s+via\s+the\s+server',
            'Allow\s+IPv6',
            'Разрешить\s+IPv6'
        )
        CertificateMode = Get-LikewebFieldAfterLabel $lines @(
            'Self-signed\s+certificate',
            'Certificate',
            'Самоподписанный\s+сертификат',
            'Сертификат'
        )
    }
}

function Normalize-LikewebProtocol {
    param([string]$Protocol)
    $value = $Protocol.Trim().ToLowerInvariant()
    if (-not $value) { return 'http2' }
    if ($value -match '^(?:http[ /]?)?([23])(?:\.0)?$' -or $value -match '^h([23])$') { return 'http' + $Matches[1] }
    throw 'Поддерживаются только протоколы HTTP/2 и HTTP/3.'
}

function ConvertTo-LikewebBoolean {
    param([string]$Value)

    $normalized = $Value.Trim().ToLowerInvariant()
    return $normalized -match '^(yes|true|1|да|включено|enabled)$'
}

function ConvertFrom-LikewebCertificateBytes {
    param([byte[]]$Bytes)

    if ($null -eq $Bytes -or $Bytes.Length -eq 0) {
        throw "Файл сертификата пуст."
    }

    # PEM is normally ASCII/UTF-8, but files received through messengers are
    # sometimes saved as UTF-8 with BOM or UTF-16. Detect the common variants.
    if ($Bytes.Length -ge 3 -and
        $Bytes[0] -eq 0xEF -and
        $Bytes[1] -eq 0xBB -and
        $Bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($Bytes, 3, $Bytes.Length - 3)
    }

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2)
    }

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) {
        return [System.Text.Encoding]::BigEndianUnicode.GetString($Bytes, 2, $Bytes.Length - 2)
    }

    try {
        $strictUtf8 = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false, $true)
        return $strictUtf8.GetString($Bytes)
    }
    catch {
        return [System.Text.Encoding]::Default.GetString($Bytes)
    }
}

function New-LikewebX509Certificate {
    param([byte[]]$Bytes)

    $errors = New-Object System.Collections.Generic.List[string]

    # Import() is the most compatible path for Windows PowerShell 5.1 and
    # older .NET Framework builds, including ECDSA certificates.
    try {
        $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
        $certificate.Import($Bytes)
        return $certificate
    }
    catch {
        $errors.Add($_.Exception.Message)
    }

    try {
        return New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList (,$Bytes)
    }
    catch {
        $errors.Add($_.Exception.Message)
    }

    try {
        return [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($Bytes)
    }
    catch {
        $errors.Add($_.Exception.Message)
    }

    throw ("Windows не смог прочитать метаданные X.509: " + (($errors | Select-Object -Unique) -join "; "))
}

function Read-LikewebDerLength {
    param([byte[]]$Bytes, [ref]$Offset, [int]$Limit)
    if ($Offset.Value -ge $Limit) { throw 'Неполное расширение SAN сертификата.' }
    $length = [int]$Bytes[$Offset.Value]; $Offset.Value++
    if ($length -ge 128) {
        $count = $length -band 127
        if ($count -lt 1 -or $count -gt 4 -or $Offset.Value + $count -gt $Limit) { throw 'Некорректная длина SAN сертификата.' }
        $length = [long]0
        for ($i=0; $i -lt $count; $i++) { $length = $length * 256 + $Bytes[$Offset.Value]; $Offset.Value++ }
    }
    if ($length -gt $Limit - $Offset.Value) { throw 'Расширение SAN обрывается до конца значения.' }
    return [int]$length
}

function Get-LikewebCertificateSanNames {
    param([byte[]]$Bytes)
    if ($Bytes.Length -lt 2 -or $Bytes[0] -ne 48) { throw 'Некорректное расширение SAN сертификата.' }
    $offset = 1
    $length = Read-LikewebDerLength $Bytes ([ref]$offset) $Bytes.Length
    $end = $offset + $length
    if ($end -ne $Bytes.Length) { throw 'Некорректная длина последовательности SAN.' }
    while ($offset -lt $end) {
        $tag = [int]$Bytes[$offset]; $offset++
        $length = Read-LikewebDerLength $Bytes ([ref]$offset) $end
        if ($tag -eq 130) {
            if ($length -lt 1) { throw 'Пустое DNS-имя в SAN.' }
            for ($i=$offset; $i -lt $offset+$length; $i++) { if ($Bytes[$i] -gt 127) { throw 'DNS-имя SAN должно использовать ASCII.' } }
            [Text.Encoding]::ASCII.GetString($Bytes,$offset,$length).TrimEnd('.').ToLowerInvariant()
        } elseif ($tag -eq 135) {
            if ($length -notin @(4,16)) { throw 'Некорректный IP-адрес в SAN.' }
            $address = New-Object byte[] $length
            [Array]::Copy($Bytes,$offset,$address,0,$length)
            ([Net.IPAddress]::new($address)).ToString()
        }
        $offset += $length
    }
}

function Get-LikewebCertificateInformationFromPem {
    param([string]$Pem)

    if ([string]::IsNullOrWhiteSpace($Pem)) {
        throw "Файл сертификата пуст."
    }

    $normalizedPem = ($Pem -replace "`0", "").Trim()
    $matches = [regex]::Matches(
        $normalizedPem,
        '-----BEGIN\s+(?:X509\s+)?CERTIFICATE-----(.*?)-----END\s+(?:X509\s+)?CERTIFICATE-----',
        [System.Text.RegularExpressions.RegexOptions]::Singleline -bor
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if ($matches.Count -eq 0) {
        throw "В файле не найден блок BEGIN CERTIFICATE / END CERTIFICATE."
    }

    $firstBase64 = $matches[0].Groups[1].Value -replace '\s', ''
    try {
        [byte[]]$bytes = [Convert]::FromBase64String($firstBase64)
    }
    catch {
        throw "Содержимое PEM не является корректным Base64."
    }

    $certificate = $null
    $metadataError = ""
    try {
        $certificate = New-LikewebX509Certificate $bytes
    }
    catch {
        # A valid PEM must still be usable by TrustTunnel even when an older
        # Windows/.NET build cannot decode its ECDSA metadata. Do not reject it.
        $metadataError = $_.Exception.Message
    }

    if ($null -eq $certificate) {
        return [pscustomobject]@{
            Pem = $normalizedPem
            Count = $matches.Count
            Subject = ""
            Issuer = ""
            NotBefore = [DateTime]::MinValue
            NotAfter = [DateTime]::MaxValue
            IsSelfSigned = $false
            IsCertificateAuthority = $false
            DnsName = ""
            DnsNames = @()
            MetadataRead = $false
            ParseWarning = $metadataError
        }
    }

    try {
        $san = @($certificate.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.17' })
        if ($san.Count) {
            # Decode DER directly: extension.Format() depends on the Windows UI language.
            $dnsNames = @(Get-LikewebCertificateSanNames $san[0].RawData)
        } else {
            # Compatibility fallback for older self-signed leaf certificates without SAN.
            $commonName = $certificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::DnsName,$false)
            $dnsNames = @($commonName | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('.').ToLowerInvariant() })
        }
        $isCa = $false
        foreach ($extension in $certificate.Extensions) {
            if ($extension.Oid.Value -eq '2.5.29.19') {
                $constraints = [Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new()
                $constraints.CopyFrom($extension)
                $isCa = $constraints.CertificateAuthority
            }
        }
        return [pscustomobject]@{
            Pem = $normalizedPem
            Count = $matches.Count
            Subject = $certificate.Subject
            Issuer = $certificate.Issuer
            NotBefore = $certificate.NotBefore
            NotAfter = $certificate.NotAfter
            IsSelfSigned = ($certificate.Subject -eq $certificate.Issuer)
            IsCertificateAuthority = $isCa
            DnsName = $(if ($dnsNames.Count) { $dnsNames[0] } else { '' })
            DnsNames = @($dnsNames | Select-Object -Unique)
            MetadataRead = $true
            ParseWarning = ''
        }
    } finally { $certificate.Dispose() }
}

function Get-LikewebCertificateInformation {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Файл сертификата не найден."
    }

    [byte[]]$fileBytes = [System.IO.File]::ReadAllBytes($Path)
    $pem = ConvertFrom-LikewebCertificateBytes $fileBytes
    return Get-LikewebCertificateInformationFromPem $pem
}

function New-LikewebProfileToml {
    param(
        [string]$DisplayName,
        [string]$ServerName,
        [string]$Address,
        [string]$Hostname,
        [string]$Username,
        [string]$Password,
        [string]$Protocol,
        [bool]$HasIPv6,
        [string]$CertificatePem,
        [bool]$EmbedCertificate
    )

    $profileId = ConvertTo-LikewebSafeId $ServerName
    $escapedAddress = ConvertTo-LikewebTomlString $Address
    $escapedHostname = ConvertTo-LikewebTomlString $Hostname
    $escapedUsername = ConvertTo-LikewebTomlString $Username
    $escapedPassword = ConvertTo-LikewebTomlString $Password
    $displayComment = ConvertTo-LikewebCommentValue $DisplayName
    $serverComment = ConvertTo-LikewebCommentValue $ServerName
    $ipv6Text = if ($HasIPv6) { "true" } else { "false" }

    if ($EmbedCertificate -and -not [string]::IsNullOrWhiteSpace($CertificatePem)) {
        if ($CertificatePem.Contains("'''")) {
            throw "Сертификат содержит недопустимую для TOML последовательность символов."
        }

        $certificateBlock = "certificate = '''`r`n" + $CertificatePem.Trim() + "`r`n'''"
    }
    else {
        $certificateBlock = 'certificate = ""'
    }

    $template = @"
# Likeweb TrustTunnel profile
# profile_id = $profileId
# display_name = $displayComment
# server_name = $serverComment
# generated_by = lwtt_manager_v4

loglevel = "info"
vpn_mode = "general"
killswitch_enabled = true
killswitch_allow_ports = []
post_quantum_group_enabled = true
exclusions = []

dns_upstreams = [
  "https://cloudflare-dns.com/dns-query",
  "tls://1dot1dot1dot1.cloudflare-dns.com",
  "quic://dns.cloudflare.com",
  "https://dns.google/dns-query",
  "tls://dns.google"
]

[endpoint]
hostname = "$escapedHostname"
addresses = ["$escapedAddress"]
custom_sni = ""
has_ipv6 = $ipv6Text
username = "$escapedUsername"
password = "$escapedPassword"
client_random = ""
skip_verification = false
$certificateBlock
upstream_protocol = "$Protocol"
anti_dpi = false

[listener]

[listener.tun]
bound_if = ""
included_routes = ["0.0.0.0/0", "2000::/3"]
excluded_routes = [
  "0.0.0.0/8",
  "10.0.0.0/8",
  "169.254.0.0/16",
  "172.16.0.0/12",
  "192.168.0.0/16",
  "224.0.0.0/3"
]
mtu_size = 1280
change_system_dns = true
"@

    return $template.Trim() + "`r`n"
}

function Get-LikewebCommentValue {
    param(
        [string]$Content,
        [string]$Key
    )

    $escapedKey = [regex]::Escape($Key)
    $match = [regex]::Match(
        $Content,
        '(?m)^\s*#\s*' + $escapedKey + '\s*=\s*(.*?)\s*$'
    )

    if ($match.Success) {
        return $match.Groups[1].Value.Trim()
    }

    return ""
}

function Get-LikewebProfileInfo {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Не передан путь к файлу профиля."
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Файл профиля не найден."
    }

    $content = [System.IO.File]::ReadAllText($Path)
    $id = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $displayName = Get-LikewebCommentValue $content "display_name"
    $serverName = Get-LikewebCommentValue $content "server_name"

    if ([string]::IsNullOrWhiteSpace($serverName)) {
        $serverName = Get-LikewebCommentValue $content "profile_name"
    }

    if ([string]::IsNullOrWhiteSpace($serverName)) {
        $serverName = $id
    }

    if ([string]::IsNullOrWhiteSpace($displayName)) {
        $displayName = $serverName
    }

    if ([string]::IsNullOrWhiteSpace($displayName)) {
        $displayName = $id
    }

    foreach ($key in @('hostname','username')) {
        if (-not (Get-LikewebTomlStringValue $content $key)) { throw ('В профиле отсутствует поле ' + $key) }
    }
    if (-not (Get-LikewebAddressFromToml $content)) { throw 'В профиле отсутствует адрес сервера.' }
    $certificatePem = Get-LikewebEmbeddedCertificate $content

    return [pscustomobject][ordered]@{
        Id = $id
        DisplayName = $displayName
        ServerName = $serverName
        Address = Get-LikewebAddressFromToml $content
        Hostname = Get-LikewebTomlStringValue $content "hostname"
        Username = Get-LikewebTomlStringValue $content "username"
        Password = Get-LikewebTomlStringValue $content "password"
        Protocol = Get-LikewebTomlStringValue $content "upstream_protocol"
        HasIPv6 = Get-LikewebTomlBooleanValue $content "has_ipv6" $true
        CertificatePem = $certificatePem
        EmbedCertificate = -not [string]::IsNullOrWhiteSpace($certificatePem)
        Invalid = $false
        Path = $Path
    }
}

function Get-LikewebProfiles {
    $profiles = @()

    foreach ($file in @(
        Get-ChildItem -LiteralPath $script:LikewebProfilesDir -Filter "*.toml" -File -ErrorAction SilentlyContinue
    )) {
        try {
            $profiles += Get-LikewebProfileInfo $file.FullName
        }
        catch {
            Write-LikewebRuntimeError 'Read profile' $_
            $profiles += [pscustomobject]@{ Id = $file.BaseName; DisplayName = $file.BaseName + ' (ошибка файла)'; Address = 'Не удалось прочитать профиль'; Path = $file.FullName; Invalid = $true }
        }
    }

    return @($profiles | Sort-Object DisplayName)
}

function Get-LikewebActiveProfileId {
    if (Test-Path -LiteralPath $script:LikewebActiveProfilePath) {
        try {
            $id = ([IO.File]::ReadAllText($script:LikewebActiveProfilePath)).Trim()
            if ($id -and $id -cne (ConvertTo-LikewebSafeId $id)) { throw 'Некорректный идентификатор активного профиля.' }
            return $id
        } catch { Write-LikewebRuntimeError 'Read active profile pointer' $_ }
    }
    return ''
}

function Get-LikewebActiveProfileInfo {
    $id = Get-LikewebActiveProfileId
    if (-not $id) { return $null }
    $path = Join-Path $script:LikewebProfilesDir ($id + '.toml')
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { return Get-LikewebProfileInfo $path }
    catch { Write-LikewebRuntimeError 'Read active profile' $_; return $null }
}

function Backup-LikewebActiveConfig {
    if (-not (Test-Path -LiteralPath $script:LikewebActiveConfigPath)) {
        return
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
    $backupPath = Join-Path $script:LikewebBackupsDir (
        "lwtt_client." + $timestamp + ".toml"
    )

    Copy-Item -LiteralPath $script:LikewebActiveConfigPath -Destination $backupPath -Force

    $backups = @(
        Get-ChildItem -LiteralPath $script:LikewebBackupsDir -Filter "*.toml" -File |
        Sort-Object LastWriteTime -Descending
    )

    if ($backups.Count -gt 10) {
        $backups | Select-Object -Skip 10 | Remove-Item -Force
    }
}

function Initialize-LikewebExistingProfile {
    if (-not (Test-Path -LiteralPath $script:LikewebActiveConfigPath)) {
        try {
            $activeIdForConfig = Get-LikewebActiveProfileId
            if (-not [string]::IsNullOrWhiteSpace($activeIdForConfig)) {
                $activeProfileForConfig = Join-Path $script:LikewebProfilesDir ($activeIdForConfig + ".toml")
                if (Test-Path -LiteralPath $activeProfileForConfig -PathType Leaf) {
                    Copy-Item -LiteralPath $activeProfileForConfig -Destination $script:LikewebActiveConfigPath -Force
                }
            }
        }
        catch {}
    }

    if (-not (Test-Path -LiteralPath $script:LikewebActiveConfigPath)) {
        return
    }

    try {
        $activeId = Get-LikewebActiveProfileId

        if (-not [string]::IsNullOrWhiteSpace($activeId)) {
            $knownPath = Join-Path $script:LikewebProfilesDir ($activeId + ".toml")
            if (Test-Path -LiteralPath $knownPath) {
                return
            }
        }

        $content = [System.IO.File]::ReadAllText($script:LikewebActiveConfigPath)
        $serverName = Get-LikewebCommentValue $content "server_name"

        if ([string]::IsNullOrWhiteSpace($serverName)) {
            $serverName = Get-LikewebCommentValue $content "profile_name"
        }

        if ([string]::IsNullOrWhiteSpace($serverName)) {
            $serverName = Get-LikewebTomlStringValue $content "hostname"
        }

        if ([string]::IsNullOrWhiteSpace($serverName)) {
            $serverName = "current"
        }

        $profileId = ConvertTo-LikewebSafeId $serverName
        $profilePath = Join-Path $script:LikewebProfilesDir ($profileId + ".toml")

        if (-not (Test-Path -LiteralPath $profilePath)) {
            Copy-Item -LiteralPath $script:LikewebActiveConfigPath -Destination $profilePath -Force
        }

        [System.IO.File]::WriteAllText(
            $script:LikewebActiveProfilePath,
            $profileId,
            $script:LikewebUtf8NoBom
        )
    }
    catch {
        # Рабочая конфигурация не изменяется, если импорт не удался.
    }
}

function Read-LikewebSharedText {
    param([string]$Path)

    $stream = $null
    $reader = $null

    try {
        $stream = New-Object System.IO.FileStream(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )
        $reader = New-Object System.IO.StreamReader(
            $stream,
            [System.Text.Encoding]::UTF8,
            $true
        )
        return $reader.ReadToEnd()
    }
    finally {
        if ($null -ne $reader) {
            $reader.Dispose()
        }
        elseif ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

function Get-LikewebLatestVpnLogSet {
    $basePath = ""

    if (Test-Path -LiteralPath $script:LikewebLatestVpnLogPointer -PathType Leaf) {
        try {
            $basePath = (Read-LikewebSharedText $script:LikewebLatestVpnLogPointer).Trim()
        }
        catch {
            $basePath = ""
        }
    }

    if ([string]::IsNullOrWhiteSpace($basePath)) {
        $latest = Get-ChildItem `
            -LiteralPath $script:LikewebVpnLogDir `
            -Filter "trusttunnel_*.out.log" `
            -File `
            -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        if ($null -ne $latest) {
            $basePath = $latest.FullName.Substring(
                0,
                $latest.FullName.Length - ".out.log".Length
            )
        }
    }

    return [pscustomobject]@{
        BasePath = $basePath
        OutputPath = if ([string]::IsNullOrWhiteSpace($basePath)) { "" } else { $basePath + ".out.log" }
        ErrorPath = if ([string]::IsNullOrWhiteSpace($basePath)) { "" } else { $basePath + ".err.log" }
        MetaPath = if ([string]::IsNullOrWhiteSpace($basePath)) { "" } else { $basePath + ".meta.txt" }
    }
}

function Get-LikewebLatestVpnLogText {
    $set = Get-LikewebLatestVpnLogSet
    $parts = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($set.MetaPath) -and
        (Test-Path -LiteralPath $set.MetaPath -PathType Leaf)) {
        try {
            $parts.Add("===== META =====")
            $parts.Add((Read-LikewebSharedText $set.MetaPath))
        }
        catch {
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($set.OutputPath) -and
        (Test-Path -LiteralPath $set.OutputPath -PathType Leaf)) {
        try {
            $parts.Add("===== TRUSTTUNNEL OUTPUT =====")
            $parts.Add((Read-LikewebSharedText $set.OutputPath))
        }
        catch {
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($set.ErrorPath) -and
        (Test-Path -LiteralPath $set.ErrorPath -PathType Leaf)) {
        try {
            $parts.Add("===== TRUSTTUNNEL ERRORS =====")
            $parts.Add((Read-LikewebSharedText $set.ErrorPath))
        }
        catch {
        }
    }

    return ($parts -join "`r`n")
}



function Clear-LikewebOperationState {
    Set-LikewebOperationState "Idle"
}

function New-LikewebDiagnosticLogContent {
    $profile = Get-LikewebActiveProfileInfo
    $runningProcess = Get-LikewebProcess
    $lines = New-Object System.Collections.Generic.List[string]

    $lines.Add("LW TRUSTTUNNEL CLIENT DIAGNOSTIC LOG")
    $lines.Add(("Created: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz")))
    $lines.Add(("Application version: {0}" -f $script:LikewebAppVersion))
    $lines.Add(("Computer: {0}" -f $env:COMPUTERNAME))
    $lines.Add(("Windows: {0}" -f [Environment]::OSVersion.VersionString))
    $lines.Add(("PowerShell: {0}" -f $PSVersionTable.PSVersion))
    $lines.Add(("Application folder: {0}" -f $script:LikewebBaseDir))
    $lines.Add(("Install folder: {0}" -f $script:LikewebInstallRoot))
    $lines.Add(("TrustTunnel process: {0}" -f $(if ($null -ne $runningProcess) {
        "running (PID " + $runningProcess.Id + ")"
    } else {
        "not running"
    })))

    $operationState = Get-LikewebOperationState
    if ($null -ne $operationState) {
        $lines.Add(("Operation state: {0}" -f $operationState.State))
    }

    if ($null -ne $profile) {
        $lines.Add(("Active server: {0}" -f $profile.DisplayName))
        $lines.Add(("Address: {0}" -f $profile.Address))
        $lines.Add(("Profile ID: {0}" -f $profile.Id))
    }
    else {
        $lines.Add("Active server: not selected")
    }

    $lines.Add("")
    $vpnText = Get-LikewebLatestVpnLogText
    if ([string]::IsNullOrWhiteSpace($vpnText)) {
        $lines.Add("===== TRUSTTUNNEL LOG =====")
        $lines.Add("No TrustTunnel log has been created yet.")
    }
    else {
        $lines.Add($vpnText)
    }

    $managerLog = Join-Path $script:LikewebLogDir "lwtt_manager.log"
    $lines.Add("")
    $lines.Add("===== SERVER MANAGER LOG =====")

    if (Test-Path -LiteralPath $managerLog -PathType Leaf) {
        try {
            $managerLines = @(
                Get-Content -LiteralPath $managerLog -Tail 500 -ErrorAction Stop
            )
            if ($managerLines.Count -gt 0) {
                foreach ($line in $managerLines) {
                    $lines.Add([string]$line)
                }
            }
            else {
                $lines.Add("The manager log is empty.")
            }
        }
        catch {
            $lines.Add("Unable to read the manager log: " + $_.Exception.Message)
        }
    }
    else {
        $lines.Add("The manager log does not exist.")
    }

    return Protect-LikewebDiagnosticText ($lines -join "`r`n")
}

function Invoke-LikewebHiddenBatch {
    param([string]$BatchPath)

    if (-not (Test-Path -LiteralPath $BatchPath)) {
        throw ("Не найден файл " + [System.IO.Path]::GetFileName($BatchPath))
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $env:ComSpec
    $startInfo.Arguments = ('/d /c ""{0}""' -f $BatchPath)
    $startInfo.WorkingDirectory = $script:LikewebBaseDir
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    [System.Diagnostics.Process]::Start($startInfo) | Out-Null
}


# Keep the public helper names while separating persistence, configuration and process control.
. (Join-Path $PSScriptRoot 'lwtt_storage.ps1')
. (Join-Path $PSScriptRoot 'lwtt_configuration.ps1')
. (Join-Path $PSScriptRoot 'lwtt_connection.ps1')
. (Join-Path $PSScriptRoot 'lwtt_manager_ipc.ps1')
