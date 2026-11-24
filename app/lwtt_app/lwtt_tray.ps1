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
. (Join-Path $PSScriptRoot 'lwtt_bypass_ui.ps1')
$script:TrayJob = $null
$script:ExitReplyId = ''
$script:ExitAfterDisconnect = $false
$script:ExitWhenIdle = $false


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

if ($null -eq (Get-LikewebPendingJob) -and -not (Test-LikewebRecoveryRequired)) {
    $initialLock = $null
    try { $initialLock = Enter-LikewebOperationLock; Remove-LikewebStaleJobs; Initialize-LikewebExistingProfile }
    catch { Write-LikewebRuntimeError 'Initialize profiles' $_ }
    finally { if ($null -ne $initialLock) { $initialLock.Dispose() } }
}

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

}

function Update-TrayStatus {
    # A connection continues safely if its manager closes. The tray adopts its result.
    if ($null -eq $script:TrayJob) {
        $descriptorPath = Join-Path $script:LikewebLogDir 'pending_job.json'
        if ([IO.File]::Exists($descriptorPath)) {
            try {
                $orphan = [IO.File]::ReadAllText($descriptorPath) | ConvertFrom-Json
                if ($orphan.OwnerPid -and $orphan.OwnerPid -ne $PID -and $null -eq (Get-Process -Id ([int]$orphan.OwnerPid) -ErrorAction SilentlyContinue) -and [IO.File]::Exists($orphan.ResultPath)) { $script:TrayJob = $orphan }
            } catch { Write-LikewebRuntimeError 'Read detached operation' $_ }
        }
    }
    if ($script:ExitWhenIdle -and $null -eq (Get-LikewebPendingJob)) { $script:ExitWhenIdle = $false; Close-LikewebApplication }
    if ($script:ExitReplyId) {
        $reply = Join-Path $script:LikewebLogDir ('manager_reply_' + $script:ExitReplyId + '.json')
        if ([IO.File]::Exists($reply)) {
            $answer = [IO.File]::ReadAllText($reply) | ConvertFrom-Json
            [IO.File]::Delete($reply); $script:ExitReplyId = ''
            if ($answer.Closed) { Close-LikewebApplication }
        } elseif ($null -eq (Get-LikewebManagerProcess)) { $script:ExitReplyId = ''; Close-LikewebApplication }
    }
    if ($null -ne $script:TrayJob) {
        try {
            $result = Receive-LikewebJob $script:TrayJob
            if ($null -ne $result) {
                $script:TrayJob = $null
                $script:CertificateHelpProfileId = if ($result.CanAddCertificate) { [string]$result.ProfileId } else { '' }
                $certificateHelpItem.Visible = -not [string]::IsNullOrWhiteSpace($script:CertificateHelpProfileId)
                if (-not $result.Success) { $script:ExitAfterDisconnect = $false; Show-TrayMessage $result.ErrorMessage ([Windows.Forms.ToolTipIcon]::Error) }
                elseif ($script:ExitAfterDisconnect) { $script:ExitAfterDisconnect = $false; $script:ExitWhenIdle = $true }
                else { Show-TrayMessage 'Операция завершена.' ([Windows.Forms.ToolTipIcon]::Info) }
            }
        } catch { Write-LikewebRuntimeError 'Read tray job' $_ }
    }
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
            "Restoring" {
                Set-TrayState "Connecting"
                $statusItem.Text = 'Статус: восстановление подключения…'
                return
            }
        }
    }

    if (Get-LikewebTunnelReady) {
        Set-TrayState "Connected"
    }
    elseif (Get-LikewebProcess) {
        Set-TrayState 'Connecting'
        $statusItem.Text = 'Статус: туннель пока не подтвердил подключение'
        $disconnectItem.Enabled = $true
    }
    else {
        Set-TrayState "Disconnected"
    }
}

function Start-CurrentVpn {
    try {
        $active = Get-LikewebActiveProfileInfo
        if ($null -eq $active) { throw 'Сначала выберите сервер.' }
        $script:TrayJob = Start-LikewebAction -Action Connect -ProfilePath $active.Path
        Update-TrayStatus
    } catch { Show-TrayMessage $_.Exception.Message ([Windows.Forms.ToolTipIcon]::Error) }
}

function Stop-CurrentVpn {
    try {
        $script:TrayJob = Start-LikewebAction -Action Disconnect
        Update-TrayStatus
    } catch { Show-TrayMessage $_.Exception.Message ([Windows.Forms.ToolTipIcon]::Error) }
}

function Switch-ToServerAndConnect {
    param([string]$ProfileId)
    try {
        $path = Join-Path $script:LikewebProfilesDir ((ConvertTo-LikewebSafeId $ProfileId) + '.toml')
        $script:TrayJob = Start-LikewebAction -Action Connect -ProfilePath $path
        Rebuild-ServersMenu
        Update-TrayStatus
    } catch { Show-TrayMessage $_.Exception.Message ([Windows.Forms.ToolTipIcon]::Error) }
}

function Start-ServerManager {
    param([ValidateSet('Servers','Add','Certificate')][string]$Mode = 'Servers', [string]$ProfileId = '')
    try {
        if ($null -ne (Get-LikewebManagerProcess)) { $null = Send-LikewebManagerRequest $Mode $ProfileId; return }
        $arguments = '-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Mode {1}' -f $ManagerScript, $Mode
        if ($ProfileId) { $arguments += ' -ProfileId "' + (ConvertTo-LikewebSafeId $ProfileId) + '"' }
        Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -WorkingDirectory $script:LikewebBaseDir -WindowStyle Hidden
    } catch { Show-TrayMessage ('Не удалось открыть управление серверами. ' + $_.Exception.Message) ([Windows.Forms.ToolTipIcon]::Error) }
}

function Rebuild-ServersMenu {
    foreach ($oldItem in @($serversMenu.DropDownItems)) { $oldItem.Dispose() }
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
            $item.Enabled = -not $profile.Invalid -and $null -eq (Get-LikewebPendingJob)

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
    if ($null -ne (Get-LikewebPendingJob)) {
        Show-TrayMessage 'Дождитесь завершения операции. При проверке сервера закройте её окно для безопасной отмены.' ([Windows.Forms.ToolTipIcon]::Warning)
        return
    }
    if ($null -ne (Get-LikewebManagerProcess)) {
        if (-not $script:ExitReplyId) { $script:ExitReplyId = Send-LikewebManagerRequest 'Close' }
        return
    }
    if (Get-LikewebProcess) {
        try {
            $script:TrayJob = Start-LikewebAction -Action Disconnect
            $script:ExitAfterDisconnect = $true
        } catch { Show-TrayMessage $_.Exception.Message ([Windows.Forms.ToolTipIcon]::Error) }
        return
    }
    $timer.Stop()
    $notifyIcon.Visible = $false
    [Windows.Forms.Application]::Exit()
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

$bypassItem = New-Object System.Windows.Forms.ToolStripMenuItem
$bypassItem.Text = 'Обход VPN…'
$bypassItem.Add_Click({
    try { Show-LikewebBypassDialog }
    catch { Show-TrayMessage $_.Exception.Message ([Windows.Forms.ToolTipIcon]::Error) }
})
$certificateHelpItem = New-Object Windows.Forms.ToolStripMenuItem
$certificateHelpItem.Text = 'Добавить сертификат для сервера…'
$certificateHelpItem.Visible = $false
$certificateHelpItem.Add_Click({
    if ($script:CertificateHelpProfileId) { Start-ServerManager 'Certificate' $script:CertificateHelpProfileId }
})

$recoverItem = New-Object System.Windows.Forms.ToolStripMenuItem
$recoverItem.Text = 'Восстановить подключение'
$recoverItem.Add_Click({
    try { $script:TrayJob = Start-LikewebAction -Action Recover }
    catch { Show-TrayMessage $_.Exception.Message ([Windows.Forms.ToolTipIcon]::Error) }
})

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
[void]$menu.Items.Add($bypassItem)
[void]$menu.Items.Add($recoverItem)
[void]$menu.Items.Add($certificateHelpItem)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($checkIpItem)
[void]$menu.Items.Add($exportLogItem)
[void]$menu.Items.Add($openFolderItem)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($exitItem)

$notifyIcon.ContextMenuStrip = $menu

$menu.Add_Opening({
    $script:TrayMenuVisible = $true
    $recoverItem.Visible = Test-LikewebRecoveryRequired
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
if (Test-LikewebRecoveryRequired) { Show-TrayMessage 'Обнаружена незавершённая операция. Выберите «Восстановить подключение» в меню.' ([Windows.Forms.ToolTipIcon]::Warning) }

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
