# Section-aware editing: unrelated TOML values remain unchanged.
function Get-LikewebTomlEntries {
    param([string]$Content)
    $section = ''
    $lines = [regex]::Matches($Content, '[^\r\n]*(?:\r\n|\n|\r|$)')
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        $line = $lines[$lineIndex]
        if ($line.Value -match '^\s*\[\[(.+)\]\]') { $section = 'array:' + $Matches[1]; continue }
        if ($line.Value -match '^\s*\[([^\[\]]+)\]\s*(?:#.*)?(?:\r?\n)?$') { $section = $Matches[1].Trim(); continue }
        if ($line.Value -notmatch '^\s*([A-Za-z0-9_-]+)\s*=\s*') { continue }
        $key = $Matches[1]; $valueStart = $line.Index + $Matches[0].Length
        $quote = ''; $depth = 0; $escaped = $false; $end = $valueStart
        for ($i = $valueStart; $i -lt $Content.Length; $i++) {
            $c = $Content[$i]; $end = $i + 1
            if ($quote) {
                if ($escaped) { $escaped = $false; continue }
                if ($quote.Contains('"') -and $c -eq '\') { $escaped = $true; continue }
                if (($i + $quote.Length -le $Content.Length -and [string]::CompareOrdinal($Content,$i,$quote,0,$quote.Length) -eq 0)) { $i += $quote.Length - 1; $end = $i + 1; $quote = '' }
                continue
            }
            if ($c -eq '#') {
                $commentStart = $i
                while ($i -lt $Content.Length -and $Content[$i] -ne "`n") { $i++ }
                if ($depth -eq 0) { $end = $commentStart; break }; continue
            }
            if ($c -eq '"' -or $c -eq "'") {
                $quote = [string]$c
                if ($i + 2 -lt $Content.Length -and $Content.Substring($i,3) -eq ($quote * 3)) { $quote *= 3; $i += 2 }
            } elseif ($c -eq '[' -or $c -eq '{') { $depth++ }
            elseif ($c -eq ']' -or $c -eq '}') { $depth--; if ($depth -lt 0) { throw 'Повреждённый TOML.' } }
            elseif (($c -eq "`n" -or $c -eq "`r") -and $depth -eq 0) { $end = $i; break }
        }
        if ($quote -or $depth -ne 0) { throw ('Повреждённый TOML: поле ' + $key) }
        [pscustomobject]@{ Section = $section; Key = $key; Start = $line.Index; Length = $end - $line.Index; Value = $Content.Substring($valueStart, $end - $valueStart).Trim() }
        while ($lineIndex + 1 -lt $lines.Count -and $lines[$lineIndex + 1].Index -lt $end) { $lineIndex++ }
    }
}

function Get-LikewebTomlValue {
    param([string]$Content, [string]$Section, [string]$Key)
    $entries = @(Get-LikewebTomlEntries $Content | Where-Object { $_.Section -eq $Section -and $_.Key -eq $Key })
    if ($entries.Count -gt 1) { throw ('Повторяющееся поле TOML: ' + $Key) }
    if ($entries.Count) { return $entries[0].Value }
    return ''
}

function Set-LikewebTomlValue {
    param([string]$Content, [string]$Section, [string]$Key, [string]$Value)
    $entries = @(Get-LikewebTomlEntries $Content | Where-Object { $_.Section -eq $Section -and $_.Key -eq $Key })
    if ($entries.Count -gt 1) { throw ('Повторяющееся поле TOML: ' + $Key) }
    $assignment = $Key + ' = ' + $Value
    if ($entries.Count) { $entry = $entries[0]; return $Content.Remove($entry.Start, $entry.Length).Insert($entry.Start, $assignment + ' ') }
    if (-not $Section) { return $assignment + "`r`n" + $Content }
    $header = [regex]::Match($Content, '(?m)^\s*\[' + [regex]::Escape($Section) + '\][ \t]*(?:#[^\r\n]*)?\r?$')
    if ($header.Success) { return $Content.Insert($header.Index + $header.Length, "`r`n" + $assignment) }
    return $Content.TrimEnd() + "`r`n`r`n[" + $Section + "]`r`n" + $assignment + "`r`n"
}

function ConvertFrom-LikewebTomlString {
    param([string]$Value, [switch]$Multiline)
    $builder = New-Object Text.StringBuilder
    for ($i = 0; $i -lt $Value.Length; $i++) {
        if ($Value[$i] -ne '\') { [void]$builder.Append($Value[$i]); continue }
        if ($Multiline) {
            $scan = $i + 1
            while ($scan -lt $Value.Length -and $Value[$scan] -in @(' ',"`t")) { $scan++ }
            if ($scan -lt $Value.Length -and $Value[$scan] -in @("`r","`n")) {
                if ($Value[$scan] -eq "`r") { $scan++; if ($scan -ge $Value.Length -or $Value[$scan] -ne "`n") { throw 'Некорректный перенос строки TOML.' } }
                $scan++
                while ($scan -lt $Value.Length -and $Value[$scan] -in @(' ',"`t","`r","`n")) { $scan++ }
                $i = $scan - 1
                continue
            }
        }
        $i++; if ($i -ge $Value.Length) { throw 'Незавершённое экранирование TOML.' }
        switch -CaseSensitive ($Value[$i]) {
            'n' { [void]$builder.Append("`n") }; 'r' { [void]$builder.Append("`r") }; 't' { [void]$builder.Append("`t") }
            'b' { [void]$builder.Append([char]8) }; 'f' { [void]$builder.Append([char]12) }
            '"' { [void]$builder.Append('"') }; '\' { [void]$builder.Append('\') }
            { $_ -eq 'u' -or $_ -eq 'U' } {
                $count = if ($_ -ceq 'u') { 4 } else { 8 }
                if ($i + $count -ge $Value.Length) { throw 'Неверная Unicode-последовательность TOML.' }
                $hex = $Value.Substring($i + 1, $count)
                if ($hex -notmatch '^[0-9a-fA-F]+$') { throw 'Неверная Unicode-последовательность TOML.' }
                [void]$builder.Append([char]::ConvertFromUtf32([Convert]::ToInt32($hex,16))); $i += $count
            }
            default { throw 'Неизвестная escape-последовательность TOML.' }
        }
    }
    return $builder.ToString()
}

function ConvertFrom-LikewebTomlScalar {
    param([string]$Value)
    if ($Value.Length -ge 6 -and ($Value.StartsWith('"""') -or $Value.StartsWith("'''"))) {
        $delimiter = $Value.Substring(0,3)
        if (-not $Value.EndsWith($delimiter)) { throw 'Незавершённая многострочная строка TOML.' }
        $body = $Value.Substring(3,$Value.Length - 6) -replace '^\r?\n',''
        if ($delimiter -eq "'''") { return $body }
        return ConvertFrom-LikewebTomlString $body -Multiline
    }
    if ($Value -match '^"((?:\\.|[^"\\])*)"$') { return ConvertFrom-LikewebTomlString $Matches[1] }
    if ($Value -match "^'([^']*)'$") { return $Matches[1] }
    throw 'Этот формат значения нельзя изменить в редакторе. Исходный профиль сохранён.'
}

function Get-LikewebTomlStringValue {
    param([string]$Content, [string]$Key)
    $value = Get-LikewebTomlValue $Content 'endpoint' $Key
    if ($value) { return ConvertFrom-LikewebTomlScalar $value }
    return ''
}

function Get-LikewebTomlBooleanValue {
    param([string]$Content, [string]$Key, [bool]$Default = $false)
    $value = Get-LikewebTomlValue $Content 'endpoint' $Key
    if ($value -eq 'true') { return $true }; if ($value -eq 'false') { return $false }
    return $Default
}

function Normalize-LikewebHostname {
    param([string]$Hostname)
    $value = $Hostname.Trim().TrimEnd('.')
    $numericIp = $null
    if ($value -match '^\d+\.\d+\.\d+\.\d+$' -and -not [Net.IPAddress]::TryParse($value,[ref]$numericIp)) { throw 'Некорректный IPv4-адрес.' }
    if (-not $value -or $value -match '[/\\:@\s*]' -or [Uri]::CheckHostName($value) -eq [UriHostNameType]::Unknown) { throw 'Укажите домен без протокола, порта и пути.' }
    return ([Globalization.IdnMapping]::new()).GetAscii($value).ToLowerInvariant()
}

function Normalize-LikewebAddress {
    param([string]$Address)
    $value = $Address.Trim(); $port = 443
    if ($value -match '^\[([^\]]+)\](?::([0-9]+))?$') {
        $hostValue = $Matches[1]; $portValue = $Matches[2]; $ip = $null
        if (-not [Net.IPAddress]::TryParse($hostValue,[ref]$ip) -or $ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetworkV6) { throw 'Некорректный IPv6-адрес.' }
        $hostValue = '[' + $ip.ToString() + ']'
    } elseif ($value -match '^([^:\s]+)(?::([0-9]+))?$') {
        $hostValue = $Matches[1]; $portValue = $Matches[2]
        if ([Uri]::CheckHostName($hostValue) -eq [UriHostNameType]::Unknown -or $hostValue -match '[/\\@]') { throw 'Некорректный адрес сервера.' }
        $numericIp = $null
        if ($hostValue -match '^\d+\.\d+\.\d+\.\d+$' -and -not [Net.IPAddress]::TryParse($hostValue,[ref]$numericIp)) { throw 'Некорректный IPv4-адрес.' }
        $hostValue = ([Globalization.IdnMapping]::new()).GetAscii($hostValue)
    } else { throw 'Адрес должен иметь формат example.org:443 или [IPv6]:443.' }
    if ($portValue -and (-not [int]::TryParse($portValue,[ref]$port) -or $port -lt 1 -or $port -gt 65535)) { throw 'Порт должен быть от 1 до 65535.' }
    return $hostValue + ':' + $port
}

function Update-LikewebProfileToml {
    param([string]$Original, [string]$Generated)
    $result = $Original
    foreach ($key in @('hostname','addresses','has_ipv6','username','password','certificate','upstream_protocol','skip_verification')) {
        if ($key -eq 'addresses' -and (Normalize-LikewebAddress (Get-LikewebAddressFromToml $Original)) -eq (Normalize-LikewebAddress (Get-LikewebAddressFromToml $Generated))) { continue }
        $value = Get-LikewebTomlValue $Generated 'endpoint' $key
        $result = Set-LikewebTomlValue $result 'endpoint' $key $value
    }
    foreach ($key in @('profile_id','display_name','server_name','generated_by')) {
        $value = Get-LikewebCommentValue $Generated $key
        $result = [regex]::Replace($result, '(?m)^[ \t]*#[ \t]*' + [regex]::Escape($key) + '[ \t]*=.*$', '')
        $result = '# ' + $key + ' = ' + $value + "`r`n" + $result
    }
    return $result
}

function ConvertTo-LikewebBypassRules {
    param([string]$Text)
    $seen = @{}; $number = 0
    foreach ($line in ($Text -split '\r?\n')) {
        $number++; $value = $line.Trim()
        if (-not $value -or $value.StartsWith('#')) { continue }
        if ($value -match '^(?i)https?://') { throw ('Строка {0}: укажите домен без https:// и пути.' -f $number) }
        $ip = $null
        if ($value.Contains('/')) {
            $parts = $value.Split('/'); $bits = 0
            if ($parts.Count -ne 2 -or -not [Net.IPAddress]::TryParse($parts[0],[ref]$ip) -or -not [int]::TryParse($parts[1],[ref]$bits) -or $bits -lt 0 -or $bits -gt ($ip.GetAddressBytes().Length * 8)) { throw ('Строка {0}: некорректная подсеть.' -f $number) }
            $value = $ip.ToString() + '/' + $bits
        } elseif ([Net.IPAddress]::TryParse($value.Trim('[',']'),[ref]$ip)) { $value = $ip.ToString() }
        else {
            $wildcard = $value.StartsWith('*.'); $domain = if ($wildcard) { $value.Substring(2) } else { $value }
            try { $domain = Normalize-LikewebHostname $domain } catch { throw ('Строка {0}: некорректный домен.' -f $number) }
            $value = $(if ($wildcard) { '*.' } else { '' }) + $domain
        }
        if (-not $seen.ContainsKey($value)) { $seen[$value] = $true; $value }
    }
}

function Get-LikewebBypassSettings {
    $path = Join-Path $script:LikewebBaseDir 'settings\bypass.json'
    if (-not [IO.File]::Exists($path)) { return [pscustomobject]@{ Enabled = $false; Rules = @() } }
    $settings = [IO.File]::ReadAllText($path) | ConvertFrom-Json -ErrorAction Stop
    if ($settings.Enabled -isnot [bool]) { throw 'Неверный формат настройки Enabled в settings/bypass.json: требуется true или false без кавычек.' }
    return [pscustomobject]@{ Enabled = [bool]$settings.Enabled; Rules = @(ConvertTo-LikewebBypassRules ($settings.Rules -join "`n")) }
}

function Add-LikewebBypassToToml {
    param([string]$Content)
    $settings = Get-LikewebBypassSettings
    if (-not $settings.Enabled -or -not $settings.Rules.Count) { return $Content }
    $mode = Get-LikewebTomlValue $Content '' 'vpn_mode'
    if ((ConvertFrom-LikewebTomlScalar $mode) -ne 'general') { throw 'Общий обход VPN доступен для профилей с vpn_mode = general.' }
    $original = Get-LikewebTomlValue $Content '' 'exclusions'
    if (-not $original) { $original = '[]' }
    if ($original -notmatch '(?s)^\[(.*)\]$') { throw 'Не удалось прочитать исключения профиля.' }
    $manualRules = @(ConvertFrom-LikewebTomlStringArray $original)
    $rules = @(@($manualRules) + @($settings.Rules) | Select-Object -Unique | ForEach-Object { '"' + (ConvertTo-LikewebTomlString $_) + '"' }) -join ",`r`n  "
    return Set-LikewebTomlValue $Content '' 'exclusions' ("[`r`n  " + $rules + "`r`n]")
}

function ConvertFrom-LikewebTomlStringArray {
    param([string]$Value)
    if ($Value -notmatch '(?s)^\[(.*)\]$') { throw 'Ожидался список строк TOML.' }
    $inside = $Matches[1]; $position = 0; $expectValue = $true
    while ($position -lt $inside.Length) {
        $skip = [regex]::Match($inside.Substring($position), '^(?:\s|#[^\r\n]*(?:\r?\n|$))*')
        $position += $skip.Length
        if ($position -ge $inside.Length) { break }
        if (-not $expectValue) {
            if ($inside[$position] -ne ',') { throw 'В списке TOML пропущена запятая.' }
            $position++; $expectValue = $true; continue
        }
        $match = [regex]::Match($inside.Substring($position), '^(?:"(?:\\.|[^"\\])*"|''[^'']*'')')
        if (-not $match.Success) { throw 'Не удалось прочитать строку списка TOML.' }
        ConvertFrom-LikewebTomlScalar $match.Value
        $position += $match.Length; $expectValue = $false
    }
}

function Get-LikewebAddressFromToml {
    param([string]$Content)
    $value = Get-LikewebTomlValue $Content 'endpoint' 'addresses'
    if (-not $value) { return '' }
    $addresses = @(ConvertFrom-LikewebTomlStringArray $value)
    if ($addresses.Count) { return $addresses[0] }
    return ''
}

function Get-LikewebEmbeddedCertificate {
    param([string]$Content)
    $value = Get-LikewebTomlValue $Content 'endpoint' 'certificate'
    if (-not $value) { return '' }
    return (ConvertFrom-LikewebTomlScalar $value).Trim()
}
