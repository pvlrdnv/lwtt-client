# Панель управления LW TrustTunnel Client с быстрым переключением серверов
# Windows PowerShell 5.1 / Windows 10 и 11

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$commonPath = Join-Path $PSScriptRoot "lwtt_common.ps1"
if (-not (Test-Path -LiteralPath $commonPath)) {
    [void][System.Windows.Forms.MessageBox]::Show(
        "Не найден lwtt_common.ps1.",
        "LW TrustTunnel Client",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    exit
}

. $commonPath


function New-StatusDotBitmap {
    param([System.Drawing.Color]$Color)

    $bitmap = New-Object System.Drawing.Bitmap 16, 16
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $brush = New-Object System.Drawing.SolidBrush($Color)
    try {
        $graphics.FillEllipse($brush, 3, 3, 10, 10)
    }
    finally {
        $brush.Dispose()
        $graphics.Dispose()
    }
    return $bitmap
}


function New-MenuSymbolBitmap {
    param(
        [ValidateSet("Connect", "Disconnect", "Folder", "Exit")]
        [string]$Kind,
        [System.Drawing.Color]$Color = [System.Drawing.Color]::FromArgb(80, 80, 80)
    )

    $size = 16
    $bitmap = New-Object System.Drawing.Bitmap $size, $size
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::Transparent)

    $pen = New-Object System.Drawing.Pen($Color, [single]1.8)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $brush = New-Object System.Drawing.SolidBrush($Color)

    try {
        switch ($Kind) {
            "Connect" {
                $points = [System.Drawing.Point[]]@(
                    [System.Drawing.Point]::new(5, 3),
                    [System.Drawing.Point]::new(13, 8),
                    [System.Drawing.Point]::new(5, 13)
                )
                $graphics.FillPolygon($brush, $points)
            }
            "Disconnect" {
                $graphics.FillRectangle($brush, 4, 4, 8, 8)
            }
            "Folder" {
                $folderBrush = New-Object System.Drawing.SolidBrush($Color)
                try {
                    $graphics.FillRectangle($folderBrush, 2, 6, 12, 7)
                    $graphics.FillRectangle($folderBrush, 3, 4, 5, 3)
                }
                finally {
                    $folderBrush.Dispose()
                }
            }
            "Exit" {
                $graphics.DrawRectangle($pen, 3, 3, 7, 10)
                $graphics.DrawLine($pen, 8, 8, 14, 8)
                $graphics.DrawLine($pen, 11, 5, 14, 8)
                $graphics.DrawLine($pen, 11, 11, 14, 8)
            }
        }
    }
    finally {
        $pen.Dispose()
        $brush.Dispose()
        $graphics.Dispose()
    }

    return $bitmap
}

$ManagerScript = Join-Path $script:LikewebBaseDir "lwtt_manager.ps1"
$ConnectedIconPath = Join-Path $script:LikewebBaseDir "icons8-start-96.ico"
$DisconnectedIconPath = Join-Path $script:LikewebBaseDir "icons8-stop2-96.ico"
$BusyIconPath = Join-Path $script:LikewebBaseDir "icons8-waiting-96.ico"

# v4.7: the tray is intentionally started elevated once at application start.
# This avoids repeated UAC prompts during connect, disconnect and server tests.
# Drag-and-drop of certificate files is disabled in the manager; certificates
# are selected by the explicit "Выбрать файл" button.

Initialize-LikewebExistingProfile

$createdNew = $false
$mutex = New-Object System.Threading.Mutex(
    $true,
    "Local\LikewebTrustTunnelTray",
    [ref]$createdNew
)

if (-not $createdNew) {
    exit
}

$script:OperationInProgress = $false
$script:ManagerLaunchInProgress = $false
$script:TrayMenuVisible = $false

function Get-TruncatedText {
    param([string]$Text, [int]$MaximumLength = 60)

    if ($null -eq $Text) {
        return ""
    }

    if ($Text.Length -le $MaximumLength) {
        return $Text
    }

    return $Text.Substring(0, $MaximumLength - 1) + "…"
}


function Get-LikewebServerManagerProcessIdsForTray {
    $ids = New-Object System.Collections.Generic.HashSet[int]

    try {
        if (Test-Path -LiteralPath $script:LikewebManagerPidPath -PathType Leaf) {
            $pidText = ([System.IO.File]::ReadAllText($script:LikewebManagerPidPath)).Trim()
            $managerPid = 0
            if ([int]::TryParse($pidText, [ref]$managerPid)) {
                [void]$ids.Add($managerPid)
            }
        }
    }
    catch {
    }

    try {
        $escapedScript = [Regex]::Escape($script:LikewebBaseDir + "\lwtt_manager.ps1")
        $managerProcesses = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue
        foreach ($process in $managerProcesses) {
            $commandLine = [string]$process.CommandLine
            if (-not [string]::IsNullOrWhiteSpace($commandLine) -and $commandLine -match $escapedScript) {
                [void]$ids.Add([int]$process.ProcessId)
            }
        }
    }
    catch {
    }

    return @($ids | Where-Object { $null -ne (Get-Process -Id $_ -ErrorAction SilentlyContinue) })
}

function Wait-LikewebServerManagerClosedForTray {
    param([int]$TimeoutMilliseconds = 3000)

    $deadline = (Get-Date).AddMilliseconds($TimeoutMilliseconds)
    while ((Get-Date) -lt $deadline) {
        if (@(Get-LikewebServerManagerProcessIdsForTray).Count -eq 0) {
            return $true
        }
        Start-Sleep -Milliseconds 100
        try { [System.Windows.Forms.Application]::DoEvents() } catch {}
    }

    return (@(Get-LikewebServerManagerProcessIdsForTray).Count -eq 0)
}

function Show-TrayMessage {
    param(
        [string]$Text,
        [System.Windows.Forms.ToolTipIcon]$Icon = [System.Windows.Forms.ToolTipIcon]::Info
    )

    $notifyIcon.ShowBalloonTip(3000, "LW TrustTunnel Client", $Text, $Icon)
}

function Get-CurrentDisplayName {
    $profile = Get-LikewebActiveProfileInfo

    if ($null -eq $profile) {
        return "сервер не выбран"
    }

    return $profile.DisplayName
}

function Set-TrayState {
    param(
        [ValidateSet("Connected", "Disconnected", "Connecting", "Disconnecting")]
        [string]$State
    )

    $displayName = Get-CurrentDisplayName
    $currentServerItem.Text = "Сервер: " + $displayName

    switch ($State) {
        "Connected" {
            $statusItem.Text = "Статус: подключено"
            $connectItem.Enabled = $false
            $disconnectItem.Enabled = $true
            $notifyIcon.Text = Get-TruncatedText ("LW TrustTunnel Client: " + $displayName)
            $notifyIcon.Icon = $connectedIcon
            $statusItem.Image = $script:StatusDotConnected
        }
        "Disconnected" {
            $statusItem.Text = "Статус: отключено"
            $connectItem.Enabled = $true
            $disconnectItem.Enabled = $false
            $notifyIcon.Text = Get-TruncatedText ("LW TrustTunnel Client: отключено – " + $displayName)
            $notifyIcon.Icon = $disconnectedIcon
            $statusItem.Image = $script:StatusDotDisconnected
        }
        "Connecting" {
            $statusItem.Text = "Статус: подключение..."
            $connectItem.Enabled = $false
            $disconnectItem.Enabled = $false
            $notifyIcon.Text = Get-TruncatedText ("LW TrustTunnel Client: подключение – " + $displayName)
            $notifyIcon.Icon = $busyIcon
            $statusItem.Image = $script:StatusDotBusy
        }
        "Disconnecting" {
            $statusItem.Text = "Статус: отключение..."
            $connectItem.Enabled = $false
            $disconnectItem.Enabled = $false
            $notifyIcon.Text = Get-TruncatedText ("LW TrustTunnel Client: отключение – " + $displayName)
            $notifyIcon.Icon = $busyIcon
            $statusItem.Image = $script:StatusDotBusy
        }
    }

    [System.Windows.Forms.Application]::DoEvents()
}

function Update-TrayStatus {
    if ($script:OperationInProgress) {
        return
    }

    $sharedState = Get-LikewebOperationState
    if ($null -ne $sharedState) {
        switch ([string]$sharedState.State) {
            "Connecting" {
                Set-TrayState "Connecting"
                return
            }
            "Disconnecting" {
                Set-TrayState "Disconnecting"
                return
            }
        }
    }

    if (Get-LikewebProcess) {
        Set-TrayState "Connected"
    }
    else {
        Set-TrayState "Disconnected"
    }
}

function Start-CurrentVpn {
    if (Get-LikewebProcess) {
        Update-TrayStatus
        return
    }

    $activeProfile = Get-LikewebActiveProfileInfo
    if ($null -eq $activeProfile) {
        Show-TrayMessage "Сначала выберите сервер." ([System.Windows.Forms.ToolTipIcon]::Warning)
        return
    }

    $script:OperationInProgress = $true
    Set-LikewebOperationState "Connecting" $activeProfile.Id $activeProfile.DisplayName
    Set-TrayState "Connecting"
    Start-Sleep -Milliseconds 500

    $started = Start-LikewebVpnAndWait
    Clear-LikewebOperationState
    $script:OperationInProgress = $false

    if ($started) {
        Set-TrayState "Connected"
    }
    else {
        Set-TrayState "Disconnected"
        Show-TrayMessage (
            "TrustTunnel не запустился. Запустите lwtt_start.bat вручную, чтобы увидеть техническую ошибку."
        ) ([System.Windows.Forms.ToolTipIcon]::Error)
    }
}

function Stop-CurrentVpn {
    if (-not (Get-LikewebProcess)) {
        Update-TrayStatus
        return
    }

    $activeProfile = Get-LikewebActiveProfileInfo
    $script:OperationInProgress = $true
    Set-LikewebOperationState "Disconnecting" $(if ($null -ne $activeProfile) { $activeProfile.Id } else { "" }) $(if ($null -ne $activeProfile) { $activeProfile.DisplayName } else { "" })
    Set-TrayState "Disconnecting"
    Start-Sleep -Milliseconds 500
    $stopped = Stop-LikewebVpnAndWait
    Clear-LikewebOperationState
    $script:OperationInProgress = $false

    if ($stopped) {
        Set-TrayState "Disconnected"
    }
    else {
        Update-TrayStatus
        Show-TrayMessage "Не удалось остановить TrustTunnel." ([System.Windows.Forms.ToolTipIcon]::Error)
    }
}

function Switch-ToServerAndConnect {
    param([string]$ProfileId)

    $path = Join-Path $script:LikewebProfilesDir ($ProfileId + ".toml")

    if (-not (Test-Path -LiteralPath $path)) {
        Show-TrayMessage "Профиль сервера не найден." ([System.Windows.Forms.ToolTipIcon]::Error)
        return
    }

    try {
        $profile = Get-LikewebProfileInfo $path
        $activeId = Get-LikewebActiveProfileId

        if ($activeId -eq $ProfileId -and (Get-LikewebProcess)) {
            Update-TrayStatus
            return
        }

        $script:OperationInProgress = $true
        Set-LikewebOperationState "Disconnecting" $activeId ""
        Set-TrayState "Disconnecting"
        [void](Stop-LikewebVpnAndWait)

        Set-LikewebActiveProfile $path
        Rebuild-ServersMenu
        Set-LikewebOperationState "Connecting" $profile.Id $profile.DisplayName
        Set-TrayState "Connecting"
        Start-Sleep -Milliseconds 500

        $started = Start-LikewebVpnAndWait
        Clear-LikewebOperationState
        $script:OperationInProgress = $false

        if ($started) {
            Set-TrayState "Connected"
        }
        else {
            Set-TrayState "Disconnected"
            Show-TrayMessage (
                "Не удалось подключиться к серверу «" + $profile.DisplayName + "»."
            ) ([System.Windows.Forms.ToolTipIcon]::Error)
        }
    }
    catch {
        Clear-LikewebOperationState
        $script:OperationInProgress = $false
        Update-TrayStatus
        Show-TrayMessage $_.Exception.Message ([System.Windows.Forms.ToolTipIcon]::Error)
    }
}

function Start-ServerManager {
    param(
        [ValidateSet("Servers", "Add")]
        [string]$Mode = "Servers",
        [string]$ProfileId = ""
    )

    if (-not (Test-Path -LiteralPath $ManagerScript)) {
        Show-TrayMessage "Не найден lwtt_manager.ps1." ([System.Windows.Forms.ToolTipIcon]::Error)
        return
    }

    if ($script:ManagerLaunchInProgress) {
        return
    }

    $script:ManagerLaunchInProgress = $true

    # Keep only one manager window. Before opening a requested view, close any
    # previous manager instance so repeated tray clicks cannot create duplicates.
    try {
        Close-LikewebServerManagerWindows
        [void](Wait-LikewebServerManagerClosedForTray 3000)
        Start-Sleep -Milliseconds 150
    }
    catch {
    }

    $powershellPath = Join-Path $PSHOME "powershell.exe"
    $argumentList = New-Object System.Collections.Generic.List[string]
    $argumentList.Add("-NoProfile")
    $argumentList.Add("-STA")
    $argumentList.Add("-ExecutionPolicy")
    $argumentList.Add("Bypass")
    $argumentList.Add("-WindowStyle")
    $argumentList.Add("Hidden")
    $argumentList.Add("-File")
    $argumentList.Add($ManagerScript)
    $argumentList.Add("-Mode")
    $argumentList.Add($Mode)

    if (-not [string]::IsNullOrWhiteSpace($ProfileId)) {
        $argumentList.Add("-ProfileId")
        $argumentList.Add($ProfileId)
    }

    try {
        Start-Process `
            -FilePath $powershellPath `
            -ArgumentList $argumentList.ToArray() `
            -WorkingDirectory $script:LikewebBaseDir `
            -WindowStyle Hidden
    }
    catch {
        try {
            $shell = New-Object -ComObject Shell.Application
            $shellArgs = ($argumentList | ForEach-Object {
                if ($_ -match '\\|\s') { '"' + ([string]$_).Replace('"', '') + '"' } else { [string]$_ }
            }) -join " "
            $shell.ShellExecute($powershellPath, $shellArgs, $script:LikewebBaseDir, "open", 0)
        }
        catch {
            Show-TrayMessage "Не удалось открыть управление серверами." ([System.Windows.Forms.ToolTipIcon]::Error)
        }
    }
    finally {
        $script:ManagerLaunchInProgress = $false
$script:TrayMenuVisible = $false
    }
}

function Rebuild-ServersMenu {
    $serversMenu.DropDownItems.Clear()
    $activeId = Get-LikewebActiveProfileId
    $profiles = @(Get-LikewebProfiles)

    if ($profiles.Count -eq 0) {
        $emptyItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $emptyItem.Text = "Нет сохраненных серверов"
        $emptyItem.Enabled = $false
        [void]$serversMenu.DropDownItems.Add($emptyItem)
    }
    else {
        foreach ($profile in $profiles) {
            $item = New-Object System.Windows.Forms.ToolStripMenuItem
            $item.Text = $profile.DisplayName
            $item.ToolTipText = $profile.Address
            $item.Tag = $profile.Id
            $item.Checked = ($profile.Id -eq $activeId)

            $item.Add_Click({
                param($sender, $eventArgs)
                Switch-ToServerAndConnect ([string]$sender.Tag)
            })

            [void]$serversMenu.DropDownItems.Add($item)
        }
    }

    [void]$serversMenu.DropDownItems.Add(
        (New-Object System.Windows.Forms.ToolStripSeparator)
    )

    $manageItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $manageItem.Text = "Управление серверами..."
    $manageItem.Add_Click({ Start-ServerManager "Servers" })
    [void]$serversMenu.DropDownItems.Add($manageItem)

    $addItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $addItem.Text = "Добавить новый сервер..."
    $addItem.Add_Click({ Start-ServerManager "Add" })
    [void]$serversMenu.DropDownItems.Add($addItem)
}


function Export-LikewebDiagnosticLog {
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Title = "Сохранить журнал диагностики LW TrustTunnel Client"
    $dialog.Filter = "Текстовый файл (*.txt)|*.txt|Все файлы (*.*)|*.*"
    $dialog.DefaultExt = "txt"
    $dialog.AddExtension = $true
    $dialog.OverwritePrompt = $true
    $dialog.FileName = (
        "LW_TrustTunnel_Client_diagnostic_{0}.txt" -f
        (Get-Date -Format "yyyyMMdd_HHmmss")
    )
    $dialog.InitialDirectory = [Environment]::GetFolderPath(
        [Environment+SpecialFolder]::Desktop
    )

    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }

    try {
        $content = New-LikewebDiagnosticLogContent
        [System.IO.File]::WriteAllText(
            $dialog.FileName,
            $content,
            $script:LikewebUtf8NoBom
        )
        Show-TrayMessage "Журнал диагностики сохранен."
    }
    catch {
        Show-TrayMessage (
            "Не удалось сохранить журнал: " + $_.Exception.Message
        ) ([System.Windows.Forms.ToolTipIcon]::Error)
    }
}

function Close-LikewebApplication {
    $exitItem.Enabled = $false
    $connectItem.Enabled = $false
    $disconnectItem.Enabled = $false

    if (Get-LikewebProcess) {
        $activeProfile = Get-LikewebActiveProfileInfo
        $script:OperationInProgress = $true
        Set-LikewebOperationState "Disconnecting" $(if ($null -ne $activeProfile) { $activeProfile.Id } else { "" }) $(if ($null -ne $activeProfile) { $activeProfile.DisplayName } else { "" })
        Set-TrayState "Disconnecting"
        $stopped = Stop-LikewebVpnAndWait
        Clear-LikewebOperationState
        $script:OperationInProgress = $false

        if (-not $stopped) {
            Update-TrayStatus
            $exitItem.Enabled = $true
            Show-TrayMessage (
                "Не удалось отключить TrustTunnel. Приложение останется открытым."
            ) ([System.Windows.Forms.ToolTipIcon]::Error)
            return
        }
    }

    Close-LikewebServerManagerWindows
    $timer.Stop()
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
    [System.Windows.Forms.Application]::Exit()
}

if (Test-Path -LiteralPath $ConnectedIconPath) {
    $connectedIcon = New-Object System.Drawing.Icon($ConnectedIconPath)
}
else {
    $connectedIcon = [System.Drawing.SystemIcons]::Information
}

if (Test-Path -LiteralPath $DisconnectedIconPath) {
    $disconnectedIcon = New-Object System.Drawing.Icon($DisconnectedIconPath)
}
else {
    $disconnectedIcon = [System.Drawing.SystemIcons]::Error
}

if (Test-Path -LiteralPath $BusyIconPath) {
    $busyIcon = New-Object System.Drawing.Icon($BusyIconPath)
}
else {
    $busyIcon = [System.Drawing.SystemIcons]::Warning
}

$script:StatusImageConnected = $connectedIcon.ToBitmap()
$script:StatusImageDisconnected = $disconnectedIcon.ToBitmap()
$script:StatusImageBusy = $busyIcon.ToBitmap()
$script:StatusDotConnected = New-StatusDotBitmap ([System.Drawing.Color]::FromArgb(16, 124, 16))
$script:StatusDotDisconnected = New-StatusDotBitmap ([System.Drawing.Color]::FromArgb(196, 43, 28))
$script:StatusDotBusy = New-StatusDotBitmap ([System.Drawing.Color]::FromArgb(255, 185, 0))

$script:MenuIconConnect = New-MenuSymbolBitmap "Connect" ([System.Drawing.Color]::FromArgb(16, 124, 16))
$script:MenuIconDisconnect = New-MenuSymbolBitmap "Disconnect" ([System.Drawing.Color]::FromArgb(196, 43, 28))
$script:MenuIconFolder = New-MenuSymbolBitmap "Folder" ([System.Drawing.Color]::FromArgb(80, 80, 80))
$script:MenuIconExit = New-MenuSymbolBitmap "Exit" ([System.Drawing.Color]::FromArgb(80, 80, 80))

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Visible = $true
$notifyIcon.Text = "LW TrustTunnel Client"

$menu = New-Object System.Windows.Forms.ContextMenuStrip

$statusItem = New-Object System.Windows.Forms.ToolStripMenuItem
$statusItem.Enabled = $true
$statusItem.Font = New-Object System.Drawing.Font(
    $statusItem.Font,
    [System.Drawing.FontStyle]::Bold
)

$currentServerItem = New-Object System.Windows.Forms.ToolStripMenuItem
$currentServerItem.Enabled = $false

$connectItem = New-Object System.Windows.Forms.ToolStripMenuItem
$connectItem.Text = "Подключить"
$connectItem.Image = $script:MenuIconConnect

$disconnectItem = New-Object System.Windows.Forms.ToolStripMenuItem
$disconnectItem.Text = "Отключить"
$disconnectItem.Image = $script:MenuIconDisconnect

$serversMenu = New-Object System.Windows.Forms.ToolStripMenuItem
$serversMenu.Text = "Серверы"

$checkIpItem = New-Object System.Windows.Forms.ToolStripMenuItem
$checkIpItem.Text = "Проверить внешний IP"

$exportLogItem = New-Object System.Windows.Forms.ToolStripMenuItem
$exportLogItem.Text = "Сохранить журнал диагностики..."

$openFolderItem = New-Object System.Windows.Forms.ToolStripMenuItem
$openFolderItem.Text = "Открыть папку программы"
$openFolderItem.Image = $script:MenuIconFolder

$exitItem = New-Object System.Windows.Forms.ToolStripMenuItem
$exitItem.Text = "Закрыть приложение"
$exitItem.Image = $script:MenuIconExit

[void]$menu.Items.Add($statusItem)
[void]$menu.Items.Add($currentServerItem)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($connectItem)
[void]$menu.Items.Add($disconnectItem)
[void]$menu.Items.Add($serversMenu)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($checkIpItem)
[void]$menu.Items.Add($exportLogItem)
[void]$menu.Items.Add($openFolderItem)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($exitItem)

$notifyIcon.ContextMenuStrip = $menu

$menu.Add_Opening({
    $script:TrayMenuVisible = $true
    Rebuild-ServersMenu
    Update-TrayStatus
})

$menu.Add_Closed({
    $script:TrayMenuVisible = $false
})

$connectItem.Add_Click({ Start-CurrentVpn })
$disconnectItem.Add_Click({ Stop-CurrentVpn })
$checkIpItem.Add_Click({ Start-Process "https://2ip.io/" })
$exportLogItem.Add_Click({ Export-LikewebDiagnosticLog })
$openFolderItem.Add_Click({
    Start-Process "explorer.exe" -ArgumentList ('"{0}"' -f $script:LikewebInstallRoot)
})

$exitItem.Add_Click({
    Close-LikewebApplication
})

# Left-click opens the menu. It does not toggle the connection.
$notifyIcon.Add_MouseUp({
    param($sender, $eventArgs)
    if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        if ($script:TrayMenuVisible -or $menu.Visible) {
            $menu.Close()
            $script:TrayMenuVisible = $false
        }
        else {
            Rebuild-ServersMenu
            Update-TrayStatus
            $menu.Show([System.Windows.Forms.Cursor]::Position)
            $script:TrayMenuVisible = $true
        }
    }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000
$timer.Add_Tick({ Update-TrayStatus })
$timer.Start()

Rebuild-ServersMenu
Update-TrayStatus

try {
    [System.Windows.Forms.Application]::Run()
}
finally {
    $timer.Stop()
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()

    if ($createdNew) {
        $mutex.ReleaseMutex()
    }

    $mutex.Dispose()
}
