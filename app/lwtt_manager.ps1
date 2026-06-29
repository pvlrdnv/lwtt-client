param(
    [ValidateSet("Servers", "Add")]
    [string]$Mode = "Servers",
    [string]$ProfileId = ""
)

# LW TrustTunnel Client Server Manager v4.13
# Windows PowerShell 5.1 / Windows 10 and Windows 11

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Security

[System.Windows.Forms.Application]::EnableVisualStyles()

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

# v4.7: the manager remains in the same elevated application session as the tray.
# This minimizes UAC prompts: the user confirms elevation once at application start.
# Drag-and-drop is disabled; PEM files are added through the "Выбрать файл" button.

Initialize-LikewebExistingProfile

try {
    [System.IO.File]::WriteAllText(
        $script:LikewebManagerPidPath,
        [string]$PID,
        $script:LikewebUtf8NoBom
    )
}
catch {
}

$script:ManagerLogDir = Join-Path $PSScriptRoot "log"
$script:ManagerLogPath = Join-Path $script:ManagerLogDir "lwtt_manager.log"
try {
    if (-not (Test-Path -LiteralPath $script:ManagerLogDir)) {
        New-Item -ItemType Directory -Path $script:ManagerLogDir -Force | Out-Null
    }
}
catch {
}

function Write-LikewebManagerLog {
    param(
        [string]$Message,
        [System.Management.Automation.ErrorRecord]$ErrorRecord = $null
    )

    try {
        $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"), $Message
        if ($null -ne $ErrorRecord) {
            $line += "`r`n" + $ErrorRecord.ToString()
            if ($null -ne $ErrorRecord.ScriptStackTrace) {
                $line += "`r`n" + $ErrorRecord.ScriptStackTrace
            }
        }
        Add-Content -LiteralPath $script:ManagerLogPath -Value $line -Encoding UTF8
    }
    catch {
    }
}

# v4.1 stability fix:
# Use standard WinForms controls instead of runtime-compiled custom C# controls.
# Some Windows PowerShell 5.1 installations failed to compile those controls,
# which left the server list blank while the page header remained visible.

# -------------------- Theme --------------------

$script:ColorWindow = [System.Drawing.Color]::FromArgb(243, 243, 243)
$script:ColorSurface = [System.Drawing.Color]::White
$script:ColorSurfaceHover = [System.Drawing.Color]::FromArgb(248, 250, 252)
$script:ColorBorder = [System.Drawing.Color]::FromArgb(224, 224, 224)
$script:ColorText = [System.Drawing.Color]::FromArgb(31, 31, 31)
$script:ColorSecondaryText = [System.Drawing.Color]::FromArgb(96, 96, 96)
$script:ColorAccent = [System.Drawing.Color]::FromArgb(0, 120, 212)
$script:ColorAccentHover = [System.Drawing.Color]::FromArgb(0, 103, 192)
$script:ColorAccentPressed = [System.Drawing.Color]::FromArgb(0, 90, 158)
$script:ColorSuccess = [System.Drawing.Color]::FromArgb(16, 124, 16)
$script:ColorSuccessSurface = [System.Drawing.Color]::FromArgb(242, 250, 242)
$script:ColorError = [System.Drawing.Color]::FromArgb(196, 43, 28)
$script:ColorErrorSurface = [System.Drawing.Color]::FromArgb(253, 244, 243)
$script:ColorWarning = [System.Drawing.Color]::FromArgb(157, 93, 0)
$script:ColorWarningSurface = [System.Drawing.Color]::FromArgb(255, 249, 230)
$script:ColorInfoSurface = [System.Drawing.Color]::FromArgb(243, 248, 253)

$installedFonts = New-Object System.Drawing.Text.InstalledFontCollection
$fontNames = @($installedFonts.Families | ForEach-Object { $_.Name })
$script:FontFamilyName = if ($fontNames -contains "Segoe UI Variable Text") {
    "Segoe UI Variable Text"
}
elseif ($fontNames -contains "Segoe UI Variable") {
    "Segoe UI Variable"
}
else {
    "Segoe UI"
}

$script:FontBody = [System.Drawing.Font]::new($script:FontFamilyName, 10.5)
$script:FontSecondary = [System.Drawing.Font]::new($script:FontFamilyName, 9.25)
$script:FontTitle = [System.Drawing.Font]::new(
    $script:FontFamilyName,
    15.0,
    [System.Drawing.FontStyle]::Bold
)
$script:FontSection = [System.Drawing.Font]::new(
    $script:FontFamilyName,
    12.0,
    [System.Drawing.FontStyle]::Bold
)
$script:FontSemibold = [System.Drawing.Font]::new(
    $script:FontFamilyName,
    10.5,
    [System.Drawing.FontStyle]::Bold
)

$script:UiToolTip = New-Object System.Windows.Forms.ToolTip
$script:UiToolTip.AutoPopDelay = 7000
$script:UiToolTip.InitialDelay = 450
$script:UiToolTip.ReshowDelay = 100

function New-LikewebUiIcon {
    param(
        [ValidateSet(
            "Play", "Stop", "Edit", "Delete", "Add", "Refresh", "Search",
            "Save", "Cancel", "Certificate", "Success", "Error", "Warning",
            "Info", "Loading", "Copy", "More", "Back", "Paste", "Clear", "Eye",
            "EyeOff", "File", "Server", "ChevronDown", "ChevronUp", "Folder"
        )]
        [string]$Kind,
        [int]$Size = 16,
        [System.Drawing.Color]$Color = [System.Drawing.Color]::Empty
    )

    $bitmap = [System.Drawing.Bitmap]::new($Size, $Size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::Transparent)

    if ($Color.IsEmpty) {
        $Color = $script:ColorSecondaryText
    }

    $pen = [System.Drawing.Pen]::new($Color, [single]1.8)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $brush = [System.Drawing.SolidBrush]::new($Color)

    switch ($Kind) {
        "Success" {
            $graphics.FillEllipse($brush, 2, 2, $Size - 4, $Size - 4)
            $whitePen = [System.Drawing.Pen]::new([System.Drawing.Color]::White, [single]1.8)
            $graphics.DrawLines($whitePen, [System.Drawing.Point[]]@(
                [System.Drawing.Point]::new(4, [int]($Size / 2)),
                [System.Drawing.Point]::new(7, $Size - 5),
                [System.Drawing.Point]::new($Size - 4, 4)
            ))
            $whitePen.Dispose()
        }
        "Error" {
            $graphics.FillEllipse($brush, 2, 2, $Size - 4, $Size - 4)
            $whitePen = [System.Drawing.Pen]::new([System.Drawing.Color]::White, [single]1.8)
            $graphics.DrawLine($whitePen, 5, 5, $Size - 5, $Size - 5)
            $graphics.DrawLine($whitePen, $Size - 5, 5, 5, $Size - 5)
            $whitePen.Dispose()
        }
        "Warning" {
            $points = [System.Drawing.Point[]]@(
                [System.Drawing.Point]::new([int]($Size / 2), 2),
                [System.Drawing.Point]::new($Size - 2, $Size - 3),
                [System.Drawing.Point]::new(2, $Size - 3)
            )
            $graphics.FillPolygon($brush, $points)
            $whitePen = [System.Drawing.Pen]::new([System.Drawing.Color]::White, [single]1.6)
            $graphics.DrawLine($whitePen, [int]($Size / 2), 6, [int]($Size / 2), 10)
            $graphics.DrawEllipse($whitePen, [int]($Size / 2), 12, 1, 1)
            $whitePen.Dispose()
        }
        "Info" {
            $graphics.FillEllipse($brush, 2, 2, $Size - 4, $Size - 4)
            $whitePen = [System.Drawing.Pen]::new([System.Drawing.Color]::White, [single]1.6)
            $graphics.DrawLine($whitePen, [int]($Size / 2), 7, [int]($Size / 2), 12)
            $graphics.DrawEllipse($whitePen, [int]($Size / 2), 4, 1, 1)
            $whitePen.Dispose()
        }
        "Loading" {
            $graphics.DrawArc($pen, 2, 2, $Size - 5, $Size - 5, 25, 285)
            $graphics.DrawLine($pen, $Size - 5, 2, $Size - 2, 5)
        }
        "Play" {
            $points = [System.Drawing.Point[]]@(
                [System.Drawing.Point]::new(5, 3),
                [System.Drawing.Point]::new($Size - 3, [int]($Size / 2)),
                [System.Drawing.Point]::new(5, $Size - 3)
            )
            $graphics.FillPolygon($brush, $points)
        }
        "Stop" {
            $graphics.FillRectangle($brush, 4, 4, $Size - 8, $Size - 8)
        }
        "Add" {
            $graphics.DrawLine($pen, [int]($Size / 2), 3, [int]($Size / 2), $Size - 3)
            $graphics.DrawLine($pen, 3, [int]($Size / 2), $Size - 3, [int]($Size / 2))
        }
        "Edit" {
            $graphics.DrawLine($pen, 3, $Size - 4, $Size - 4, 3)
            $graphics.DrawLine($pen, 3, $Size - 4, 7, $Size - 3)
        }
        "Delete" {
            $graphics.DrawRectangle($pen, 4, 6, $Size - 8, $Size - 9)
            $graphics.DrawLine($pen, 3, 5, $Size - 3, 5)
            $graphics.DrawLine($pen, 6, 3, $Size - 6, 3)
        }
        "Refresh" {
            $graphics.DrawArc($pen, 2, 2, $Size - 5, $Size - 5, 35, 285)
            $graphics.DrawLine($pen, $Size - 5, 2, $Size - 2, 5)
            $graphics.DrawLine($pen, $Size - 5, 2, $Size - 7, 6)
        }
        "Search" {
            $graphics.DrawEllipse($pen, 2, 2, $Size - 7, $Size - 7)
            $graphics.DrawLine($pen, $Size - 6, $Size - 6, $Size - 2, $Size - 2)
        }
        "Save" {
            $graphics.DrawRectangle($pen, 2, 2, $Size - 5, $Size - 5)
            $graphics.DrawRectangle($pen, 5, 3, $Size - 10, 4)
            $graphics.DrawRectangle($pen, 5, 9, $Size - 10, $Size - 12)
        }
        "Cancel" {
            $graphics.DrawLine($pen, 3, 3, $Size - 3, $Size - 3)
            $graphics.DrawLine($pen, $Size - 3, 3, 3, $Size - 3)
        }
        "Certificate" {
            $graphics.DrawRectangle($pen, 3, 2, $Size - 7, $Size - 6)
            $graphics.DrawLine($pen, 5, 6, $Size - 5, 6)
            $graphics.DrawLine($pen, 5, 9, $Size - 7, 9)
            $graphics.DrawEllipse($pen, $Size - 7, $Size - 7, 5, 5)
        }
        "Copy" {
            $graphics.DrawRectangle($pen, 5, 3, $Size - 8, $Size - 8)
            $graphics.DrawRectangle($pen, 3, 6, $Size - 8, $Size - 8)
        }
        "More" {
            $graphics.FillEllipse($brush, 2, [int]($Size / 2) - 1, 2, 2)
            $graphics.FillEllipse($brush, [int]($Size / 2) - 1, [int]($Size / 2) - 1, 2, 2)
            $graphics.FillEllipse($brush, $Size - 4, [int]($Size / 2) - 1, 2, 2)
        }
        "Back" {
            $graphics.DrawLine($pen, 4, [int]($Size / 2), $Size - 3, [int]($Size / 2))
            $graphics.DrawLine($pen, 4, [int]($Size / 2), 8, 4)
            $graphics.DrawLine($pen, 4, [int]($Size / 2), 8, $Size - 4)
        }
        "Paste" {
            $graphics.DrawRectangle($pen, 4, 4, $Size - 7, $Size - 6)
            $graphics.DrawRectangle($pen, 6, 2, $Size - 11, 4)
        }
        "Clear" {
            $graphics.DrawLine($pen, 4, 4, $Size - 4, $Size - 4)
            $graphics.DrawLine($pen, $Size - 4, 4, 4, $Size - 4)
        }
        "Eye" {
            $graphics.DrawArc($pen, 2, 5, $Size - 4, $Size - 8, 180, 180)
            $graphics.DrawArc($pen, 2, 3, $Size - 4, $Size - 8, 0, 180)
            $graphics.DrawEllipse($pen, [int]($Size / 2) - 2, [int]($Size / 2) - 2, 4, 4)
        }
        "EyeOff" {
            $graphics.DrawArc($pen, 2, 5, $Size - 4, $Size - 8, 180, 180)
            $graphics.DrawArc($pen, 2, 3, $Size - 4, $Size - 8, 0, 180)
            $graphics.DrawLine($pen, 3, 3, $Size - 3, $Size - 3)
        }
        "File" {
            $graphics.DrawRectangle($pen, 4, 2, $Size - 8, $Size - 4)
            $graphics.DrawLine($pen, 6, 7, $Size - 6, 7)
            $graphics.DrawLine($pen, 6, 10, $Size - 7, 10)
        }
        "Server" {
            $graphics.DrawRectangle($pen, 2, 3, $Size - 4, 5)
            $graphics.DrawRectangle($pen, 2, 10, $Size - 4, 5)
            $graphics.FillEllipse($brush, 4, 5, 2, 2)
            $graphics.FillEllipse($brush, 4, 12, 2, 2)
        }
        "ChevronDown" {
            $graphics.DrawLine($pen, 3, 6, [int]($Size / 2), $Size - 4)
            $graphics.DrawLine($pen, [int]($Size / 2), $Size - 4, $Size - 3, 6)
        }
        "ChevronUp" {
            $graphics.DrawLine($pen, 3, $Size - 5, [int]($Size / 2), 4)
            $graphics.DrawLine($pen, [int]($Size / 2), 4, $Size - 3, $Size - 5)
        }
        "Folder" {
            $graphics.DrawRectangle($pen, 2, 5, $Size - 4, $Size - 7)
            $graphics.DrawLine($pen, 3, 5, 7, 5)
            $graphics.DrawLine($pen, 7, 5, 9, 3)
            $graphics.DrawLine($pen, 9, 3, $Size - 5, 3)
        }
    }

    $brush.Dispose()
    $pen.Dispose()
    $graphics.Dispose()
    return $bitmap
}

$script:IconInfo = New-LikewebUiIcon "Info" 18 $script:ColorAccent
$script:IconSuccess = New-LikewebUiIcon "Success" 18 $script:ColorSuccess
$script:IconError = New-LikewebUiIcon "Error" 18 $script:ColorError
$script:IconWarning = New-LikewebUiIcon "Warning" 18 $script:ColorWarning
$script:IconLoading = New-LikewebUiIcon "Loading" 18 $script:ColorAccent
$script:IconCopy = New-LikewebUiIcon "Copy" 16 $script:ColorSecondaryText
$script:IconConnected = New-LikewebUiIcon "Success" 18 $script:ColorSuccess
$script:IconDisconnected = New-LikewebUiIcon "Error" 18 $script:ColorError
$script:IconPlay = New-LikewebUiIcon "Play" 16 $script:ColorAccent
$script:IconStop = New-LikewebUiIcon "Stop" 16 $script:ColorSecondaryText
$script:IconAddWhite = New-LikewebUiIcon "Add" 16 [System.Drawing.Color]::White
$script:IconAdd = New-LikewebUiIcon "Add" 16 $script:ColorAccent
$script:IconMore = New-LikewebUiIcon "More" 18 $script:ColorSecondaryText
$script:IconEdit = New-LikewebUiIcon "Edit" 16 $script:ColorSecondaryText
$script:IconDelete = New-LikewebUiIcon "Delete" 16 $script:ColorError
$script:IconFolder = New-LikewebUiIcon "Folder" 16 $script:ColorSecondaryText
$script:IconBack = New-LikewebUiIcon "Back" 16 $script:ColorText
$script:IconPaste = New-LikewebUiIcon "Paste" 16 $script:ColorSecondaryText
$script:IconClear = New-LikewebUiIcon "Clear" 16 $script:ColorSecondaryText
$script:IconSearch = New-LikewebUiIcon "Search" 16 $script:ColorAccent
$script:IconCertificate = New-LikewebUiIcon "Certificate" 28 $script:ColorAccent
$script:IconFile = New-LikewebUiIcon "File" 28 $script:ColorAccent
$script:IconSave = New-LikewebUiIcon "Save" 16 $script:ColorSecondaryText
$script:IconSaveWhite = New-LikewebUiIcon "Save" 16 [System.Drawing.Color]::White
$script:IconCancel = New-LikewebUiIcon "Cancel" 16 $script:ColorSecondaryText
$script:IconEye = New-LikewebUiIcon "Eye" 16 $script:ColorSecondaryText
$script:IconEyeOff = New-LikewebUiIcon "EyeOff" 16 $script:ColorSecondaryText
$script:IconChevronDown = New-LikewebUiIcon "ChevronDown" 14 $script:ColorSecondaryText
$script:IconChevronUp = New-LikewebUiIcon "ChevronUp" 14 $script:ColorSecondaryText
$script:IconServer = New-LikewebUiIcon "Server" 48 $script:ColorSecondaryText

function Set-Accessible {
    param(
        [System.Windows.Forms.Control]$Control,
        [string]$Name,
        [string]$Description = ""
    )

    $Control.AccessibleName = $Name
    if (-not [string]::IsNullOrWhiteSpace($Description)) {
        $Control.AccessibleDescription = $Description
    }
}

function New-FluentButton {
    param(
        [string]$Text,
        [ValidateSet("Primary", "Secondary", "Subtle", "Danger", "Icon")]
        [string]$Style = "Secondary",
        [System.Drawing.Image]$Image = $null,
        [int]$Width = 120,
        [int]$Height = 36,
        [string]$AccessibleName = "",
        [string]$ToolTip = ""
    )

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Size = [System.Drawing.Size]::new($Width, $Height)
    $button.Font = $script:FontBody
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.UseVisualStyleBackColor = $false
    $button.UseCompatibleTextRendering = $false
    $button.AutoEllipsis = $true
    $button.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $button.FlatAppearance.BorderSize = 1
    $button.Padding = [System.Windows.Forms.Padding]::new(8, 0, 8, 0)

    if ($null -ne $Image) {
        $button.Image = $Image
        $button.ImageAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $button.TextImageRelation = [System.Windows.Forms.TextImageRelation]::ImageBeforeText
    }

    # Fixed pixel widths were too small for Russian labels on some DPI/font
    # combinations. Measure the actual caption and grow the button when needed.
    if ($Style -ne "Icon" -and -not [string]::IsNullOrWhiteSpace($Text)) {
        $measureFlags = (
            [System.Windows.Forms.TextFormatFlags]::SingleLine -bor
            [System.Windows.Forms.TextFormatFlags]::NoPadding
        )
        $measured = [System.Windows.Forms.TextRenderer]::MeasureText(
            $Text,
            $button.Font,
            [System.Drawing.Size]::new(2000, $Height),
            $measureFlags
        )
        $imageAllowance = if ($null -ne $Image) { $Image.Width + 10 } else { 0 }
        $minimumWidth = $measured.Width + $imageAllowance + 30
        if ($button.Width -lt $minimumWidth) {
            $button.Width = $minimumWidth
        }
        $button.MinimumSize = [System.Drawing.Size]::new($minimumWidth, $Height)
    }

    switch ($Style) {
        "Primary" {
            $button.BackColor = $script:ColorAccent
            $button.ForeColor = [System.Drawing.Color]::White
            $button.FlatAppearance.BorderColor = $script:ColorAccent
            $button.FlatAppearance.MouseOverBackColor = $script:ColorAccentHover
            $button.FlatAppearance.MouseDownBackColor = $script:ColorAccentPressed
        }
        "Subtle" {
            $button.BackColor = [System.Drawing.Color]::Transparent
            $button.ForeColor = $script:ColorText
            $button.FlatAppearance.BorderSize = 0
            $button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(235, 235, 235)
            $button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(225, 225, 225)
        }
        "Danger" {
            $button.BackColor = $script:ColorSurface
            $button.ForeColor = $script:ColorError
            $button.FlatAppearance.BorderColor = $script:ColorBorder
            $button.FlatAppearance.MouseOverBackColor = $script:ColorErrorSurface
            $button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(248, 229, 227)
        }
        "Icon" {
            $button.BackColor = [System.Drawing.Color]::Transparent
            $button.ForeColor = $script:ColorText
            $button.FlatAppearance.BorderSize = 0
            $button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(235, 235, 235)
            $button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(225, 225, 225)
            $button.Padding = [System.Windows.Forms.Padding]::new(0)
            $button.ImageAlign = [System.Drawing.ContentAlignment]::MiddleCenter
            $button.Text = ""
        }
        default {
            $button.BackColor = $script:ColorSurface
            $button.ForeColor = $script:ColorText
            $button.FlatAppearance.BorderColor = $script:ColorBorder
            $button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(247, 247, 247)
            $button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(237, 237, 237)
        }
    }

    if ([string]::IsNullOrWhiteSpace($AccessibleName)) {
        $AccessibleName = $Text
    }
    Set-Accessible $button $AccessibleName $ToolTip

    if (-not [string]::IsNullOrWhiteSpace($ToolTip)) {
        $script:UiToolTip.SetToolTip($button, $ToolTip)
    }

    $button | Add-Member -MemberType NoteProperty -Name LikewebEnabledBackColor -Value $button.BackColor
    $button | Add-Member -MemberType NoteProperty -Name LikewebEnabledForeColor -Value $button.ForeColor
    $button | Add-Member -MemberType NoteProperty -Name LikewebEnabledBorderColor -Value $button.FlatAppearance.BorderColor
    $button.Add_EnabledChanged({
        param($sender, $eventArgs)
        if ($sender.Enabled) {
            $sender.BackColor = $sender.LikewebEnabledBackColor
            $sender.ForeColor = $sender.LikewebEnabledForeColor
            $sender.FlatAppearance.BorderColor = $sender.LikewebEnabledBorderColor
        }
        else {
            $sender.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
            $sender.ForeColor = [System.Drawing.Color]::FromArgb(125, 125, 125)
            $sender.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(218, 218, 218)
        }
        $sender.Invalidate()
    })

    return $button
}

function New-FluentSurface {
    param(
        [int]$Height = 100,
        [int]$CornerRadius = 8,
        [bool]$TabStop = $false
    )

    # A standard Panel is intentionally used here for maximum compatibility
    # with Windows PowerShell 5.1 and different .NET Framework builds.
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Height = $Height
    $panel.BackColor = $script:ColorSurface
    $panel.TabStop = $TabStop

    # Add lightweight state properties used by the rest of the UI.
    $panel | Add-Member -MemberType NoteProperty -Name CornerRadius -Value $CornerRadius
    $panel | Add-Member -MemberType NoteProperty -Name BorderColor -Value $script:ColorBorder
    $panel | Add-Member -MemberType NoteProperty -Name FocusBorderColor -Value $script:ColorAccent
    $panel | Add-Member -MemberType NoteProperty -Name BorderThickness -Value 1
    $panel | Add-Member -MemberType NoteProperty -Name AccentColor -Value ([System.Drawing.Color]::Transparent)
    $panel | Add-Member -MemberType NoteProperty -Name AccentWidth -Value 0
    $panel | Add-Member -MemberType NoteProperty -Name NormalBackColor -Value $script:ColorSurface
    $panel | Add-Member -MemberType NoteProperty -Name HoverBackColor -Value $script:ColorSurfaceHover

    $panel.Add_Paint({
        param($sender, $eventArgs)

        $graphics = $eventArgs.Graphics
        $borderColor = if ($sender.Focused) {
            $sender.FocusBorderColor
        }
        else {
            $sender.BorderColor
        }

        if ($sender.Width -gt 1 -and $sender.Height -gt 1) {
            $pen = New-Object System.Drawing.Pen($borderColor, [single]$sender.BorderThickness)
            try {
                $graphics.DrawRectangle($pen, 0, 0, $sender.Width - 1, $sender.Height - 1)
            }
            finally {
                $pen.Dispose()
            }
        }

        if (
            $sender.AccentWidth -gt 0 -and
            $sender.AccentColor -ne [System.Drawing.Color]::Transparent
        ) {
            $brush = New-Object System.Drawing.SolidBrush($sender.AccentColor)
            try {
                $graphics.FillRectangle($brush, 0, 0, $sender.AccentWidth, $sender.Height)
            }
            finally {
                $brush.Dispose()
            }
        }
    })

    $panel.Add_Enter({ param($sender, $eventArgs) $sender.Invalidate() })
    $panel.Add_Leave({ param($sender, $eventArgs) $sender.Invalidate() })
    $panel.Add_Resize({ param($sender, $eventArgs) $sender.Invalidate() })

    return $panel
}

function New-PageLabel {
    param(
        [string]$Text,
        [ValidateSet("Title", "Section", "Body", "Secondary", "Semibold")]
        [string]$Style = "Body"
    )

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.AutoSize = $true
    $label.ForeColor = $script:ColorText
    $label.BackColor = [System.Drawing.Color]::Transparent

    switch ($Style) {
        "Title" { $label.Font = $script:FontTitle }
        "Section" { $label.Font = $script:FontSection }
        "Secondary" {
            $label.Font = $script:FontSecondary
            $label.ForeColor = $script:ColorSecondaryText
        }
        "Semibold" { $label.Font = $script:FontSemibold }
        default { $label.Font = $script:FontBody }
    }

    return $label
}

function Set-StatusPair {
    param(
        [System.Windows.Forms.PictureBox]$Picture,
        [System.Windows.Forms.Label]$Label,
        [ValidateSet("Neutral", "Success", "Warning", "Error", "Loading")]
        [string]$State,
        [string]$Text
    )

    $Label.Text = $Text

    switch ($State) {
        "Success" {
            $Picture.Image = $script:IconSuccess
            $Label.ForeColor = $script:ColorSuccess
        }
        "Warning" {
            $Picture.Image = $script:IconWarning
            $Label.ForeColor = $script:ColorWarning
        }
        "Error" {
            $Picture.Image = $script:IconError
            $Label.ForeColor = $script:ColorError
        }
        "Loading" {
            $Picture.Image = $script:IconLoading
            $Label.ForeColor = $script:ColorAccent
        }
        default {
            $Picture.Image = $script:IconInfo
            $Label.ForeColor = $script:ColorSecondaryText
        }
    }

    $Label.AccessibleName = $Text
}

# -------------------- Application state --------------------

$script:EditingProfileId = ""
$script:SettingsRecognized = $false
$script:RecognitionAttempted = $false
$script:CertificateExpected = $false
$script:SelectedCertificateInfo = $null
$script:SelectedCertificatePath = ""
$script:EditorDirty = $false
$script:LoadingEditor = $false
$script:AdvancedVisible = $false
$script:OperationProfileId = ""
$script:OperationKind = ""
$script:ServerRows = @{}
$script:LastProfileSignature = ""
$script:TestWorkerProcess = $null
$script:TestStartedAt = $null
$script:TestResultPath = ""
$script:TestConfigPath = ""
$script:TestLogPath = ""
$script:LastTestLog = ""

# UI references are initialized later.
$script:CurrentView = "Servers"

function Show-CriticalError {
    param([string]$Message)

    [void][System.Windows.Forms.MessageBox]::Show(
        $Message,
        "LW TrustTunnel Client",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
}

function Confirm-DiscardChanges {
    if (-not $script:EditorDirty) {
        return $true
    }

    $result = [System.Windows.Forms.MessageBox]::Show(
        "Есть несохраненные изменения. Отменить их и вернуться к списку серверов?",
        "LW TrustTunnel Client",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    return $result -eq [System.Windows.Forms.DialogResult]::Yes
}

function Show-DeleteConfirmation {
    param([string]$DisplayName)

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "Удаление сервера"
    $dialog.StartPosition = "CenterParent"
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.ClientSize = [System.Drawing.Size]::new(460, 190)
    $dialog.Font = $script:FontBody
    $dialog.BackColor = $script:ColorWindow
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi

    $icon = New-Object System.Windows.Forms.PictureBox
    $icon.Image = $script:IconWarning
    $icon.SizeMode = "CenterImage"
    $icon.Location = [System.Drawing.Point]::new(24, 28)
    $icon.Size = [System.Drawing.Size]::new(32, 32)
    $dialog.Controls.Add($icon)

    $title = New-PageLabel "Удалить сервер «$DisplayName»?" "Section"
    $title.Location = [System.Drawing.Point]::new(72, 24)
    $title.MaximumSize = [System.Drawing.Size]::new(350, 0)
    $dialog.Controls.Add($title)

    $text = New-PageLabel "Профиль и сохраненный сертификат будут удалены. Это действие нельзя отменить." "Secondary"
    $text.Location = [System.Drawing.Point]::new(72, 62)
    $text.MaximumSize = [System.Drawing.Size]::new(350, 0)
    $dialog.Controls.Add($text)

    $cancel = New-FluentButton "Отмена" "Secondary" $null 104 36 "Отмена"
    $cancel.Location = [System.Drawing.Point]::new(228, 132)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dialog.Controls.Add($cancel)

    $delete = New-FluentButton "Удалить" "Danger" $script:IconDelete 104 36 "Удалить сервер"
    $delete.Location = [System.Drawing.Point]::new(340, 132)
    $delete.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dialog.Controls.Add($delete)

    $dialog.AcceptButton = $delete
    $dialog.CancelButton = $cancel

    return $dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK
}


function Copy-LikewebTextToClipboard {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return
    }

    try {
        [System.Windows.Forms.Clipboard]::SetText($Text)
    }
    catch {
        Show-CriticalError ("Не удалось скопировать текст ошибки. " + $_.Exception.Message)
    }
}

function New-MessageCopyButton {
    $button = New-FluentButton "" "Icon" $script:IconCopy 32 32 "Скопировать ошибку" "Скопировать подробный текст ошибки в буфер обмена"
    $button.Anchor = "Top,Right"
    $button.Visible = $false
    $button.Add_Click({
        param($sender, $eventArgs)
        Copy-LikewebTextToClipboard ([string]$sender.Tag)
    })
    return $button
}

# -------------------- Inline message bars --------------------

function Set-MessageBar {
    param(
        [System.Windows.Forms.Panel]$Panel,
        [System.Windows.Forms.PictureBox]$Icon,
        [System.Windows.Forms.Label]$Label,
        [ValidateSet("Hidden", "Info", "Success", "Warning", "Error", "Loading")]
        [string]$State,
        [string]$Text = "",
        [System.Windows.Forms.Button]$CopyButton = $null
    )

    if ($State -eq "Hidden") {
        $Panel.Visible = $false
        if ($null -ne $CopyButton) { $CopyButton.Visible = $false }
        return
    }

    $Panel.Visible = $true
    $Label.Text = $Text
    $Label.AccessibleName = $Text

    if ($null -ne $CopyButton) {
        $CopyButton.Tag = $Text
        $CopyButton.Visible = ($State -eq "Error" -and -not [string]::IsNullOrWhiteSpace($Text))
        $CopyButton.BringToFront()
    }

    switch ($State) {
        "Success" {
            $Panel.BackColor = $script:ColorSuccessSurface
            $Icon.Image = $script:IconSuccess
            $Label.ForeColor = $script:ColorSuccess
        }
        "Warning" {
            $Panel.BackColor = $script:ColorWarningSurface
            $Icon.Image = $script:IconWarning
            $Label.ForeColor = $script:ColorWarning
        }
        "Error" {
            $Panel.BackColor = $script:ColorErrorSurface
            $Icon.Image = $script:IconError
            $Label.ForeColor = $script:ColorError
        }
        "Loading" {
            $Panel.BackColor = $script:ColorInfoSurface
            $Icon.Image = $script:IconLoading
            $Label.ForeColor = $script:ColorAccent
        }
        default {
            $Panel.BackColor = $script:ColorInfoSurface
            $Icon.Image = $script:IconInfo
            $Label.ForeColor = $script:ColorText
        }
    }
}

function Set-ServersMessage {
    param(
        [ValidateSet("Hidden", "Info", "Success", "Warning", "Error", "Loading")]
        [string]$State,
        [string]$Text = ""
    )

    Set-MessageBar $serversMessagePanel $serversMessageIcon $serversMessageLabel $State $Text $serversMessageCopyButton
}

function Set-EditorMessage {
    param(
        [ValidateSet("Hidden", "Info", "Success", "Warning", "Error", "Loading")]
        [string]$State,
        [string]$Text = ""
    )

    Set-MessageBar $editorMessagePanel $editorMessageIcon $editorMessageLabel $State $Text $editorMessageCopyButton
}

# -------------------- Editor state and validation --------------------

function Test-CertificateMatchesHostname {
    param(
        [object]$CertificateDnsNames,
        [string]$Hostname
    )

    if ([string]::IsNullOrWhiteSpace($Hostname)) {
        return $true
    }

    $hostnameValue = $Hostname.Trim().ToLowerInvariant()
    $hostnameValue = $hostnameValue -replace '^https?://', ''
    $hostnameValue = $hostnameValue.Split('/')[0]
    if ($hostnameValue.StartsWith('[')) {
        $closingBracket = $hostnameValue.IndexOf(']')
        if ($closingBracket -gt 0) {
            $hostnameValue = $hostnameValue.Substring(1, $closingBracket - 1)
        }
    }
    elseif ($hostnameValue.Contains(':')) {
        $hostnameValue = $hostnameValue.Split(':')[0]
    }
    $hostnameValue = $hostnameValue.Trim().TrimEnd('.')

    $names = @()
    if ($null -ne $CertificateDnsNames) {
        if ($CertificateDnsNames -is [string]) {
            $names = @([string]$CertificateDnsNames)
        }
        else {
            $names = @($CertificateDnsNames)
        }
    }

    # If Windows cannot expose certificate metadata, do not reject a valid PEM
    # only because the local .NET build is too old to inspect it.
    if ($names.Count -eq 0) {
        return $true
    }

    foreach ($name in $names) {
        if ([string]::IsNullOrWhiteSpace([string]$name)) {
            continue
        }

        $dnsNameValue = ([string]$name).Trim().ToLowerInvariant().TrimEnd('.')
        if ($dnsNameValue -eq $hostnameValue) {
            return $true
        }

        if ($dnsNameValue.StartsWith('*.')) {
            $baseDomain = $dnsNameValue.Substring(2)
            if ($hostnameValue.EndsWith('.' + $baseDomain)) {
                $prefix = $hostnameValue.Substring(
                    0,
                    $hostnameValue.Length - $baseDomain.Length - 1
                )
                # RFC-style wildcard: exactly one label before the base domain.
                if (-not $prefix.Contains('.') -and $prefix.Length -gt 0) {
                    return $true
                }
            }
        }
    }

    return $false
}

function Mark-EditorDirty {
    if (-not $script:LoadingEditor) {
        $script:EditorDirty = $true
    }
}

function Set-RecognitionStatus {
    param(
        [string]$Text,
        [ValidateSet("Neutral", "Success", "Warning", "Error", "Loading")]
        [string]$State = "Neutral"
    )

    Set-StatusPair $recognitionStatusIcon $recognitionStatusLabel $State $Text
}

function Set-CertificateStatus {
    param(
        [string]$Text,
        [ValidateSet("Neutral", "Success", "Warning", "Error", "Loading")]
        [string]$State = "Neutral"
    )

    Set-StatusPair $certificateStatusIcon $certificateStatusLabel $State $Text
}

function Set-TestStatus {
    param(
        [string]$Text,
        [ValidateSet("Neutral", "Success", "Warning", "Error", "Loading")]
        [string]$State = "Neutral"
    )

    Set-StatusPair $testStatusIcon $testStatusLabel $State $Text
}

function Update-CertificateCard {
    if ($null -eq $script:SelectedCertificateInfo) {
        $certificateEmptyPanel.Visible = $true
        $certificateFilePanel.Visible = $false
        return
    }

    $certificateEmptyPanel.Visible = $false
    $certificateFilePanel.Visible = $true

    $fileName = if (-not [string]::IsNullOrWhiteSpace($script:SelectedCertificatePath)) {
        [System.IO.Path]::GetFileName($script:SelectedCertificatePath)
    }
    else {
        "Сертификат из профиля"
    }

    $certificateFileNameLabel.Text = $fileName

    if ($script:SelectedCertificateInfo.MetadataRead -eq $false) {
        $certificateFileDetailsLabel.Text = "PEM-сертификат · метаданные X.509 недоступны"
        return
    }

    $kindText = if ($script:SelectedCertificateInfo.IsSelfSigned) {
        "Самоподписанный сертификат"
    }
    else {
        "Сертификат удостоверяющего центра"
    }

    $validityText = "Действует до " + $script:SelectedCertificateInfo.NotAfter.ToString("dd.MM.yyyy")
    $certificateFileDetailsLabel.Text = $kindText + " · " + $validityText
}

function Clear-CertificateSelection {
    $script:SelectedCertificateInfo = $null
    $script:SelectedCertificatePath = ""
    $embedCertificateCheckBox.Checked = $false
    Update-CertificateCard

    if ($script:CertificateExpected) {
        Set-CertificateStatus "Требуется сертификат. Добавьте файл .pem." "Warning"
    }
    else {
        Set-CertificateStatus "Сертификат не требуется. При необходимости его можно добавить." "Neutral"
    }

    Mark-EditorDirty
    Update-EditorValidation
}

function Load-CertificateIntoEditor {
    param([string]$Path)

    try {
        Set-CertificateStatus "Проверяем сертификат…" "Loading"
        [System.Windows.Forms.Application]::DoEvents()

        $info = Get-LikewebCertificateInformation $Path
        $script:SelectedCertificateInfo = $info
        $script:SelectedCertificatePath = $Path

        # Self-signed certificates must be embedded. If an old Windows build
        # cannot read the metadata, embedding is the safest behavior because
        # the administrator explicitly supplied this PEM.
        $embedCertificateCheckBox.Checked = (
            $info.IsSelfSigned -or
            $info.MetadataRead -eq $false
        )
        Update-CertificateCard

        if ($info.MetadataRead -eq $false) {
            Set-CertificateStatus "PEM загружен и будет встроен. Windows не смог проверить его метаданные." "Warning"
        }
        elseif ($info.NotAfter -lt (Get-Date)) {
            Set-CertificateStatus "Истек срок действия сертификата. Выберите актуальный PEM." "Error"
        }
        elseif (-not (Test-CertificateMatchesHostname $(if ($info.PSObject.Properties.Name -contains "DnsNames") { $info.DnsNames } else { $info.DnsName }) $hostnameTextBox.Text)) {
            Set-CertificateStatus "Сертификат не соответствует домену. Проверьте PEM или домен сервера." "Error"
        }
        elseif ($info.IsSelfSigned) {
            Set-CertificateStatus "Сертификат проверен и будет встроен в конфигурацию." "Success"
        }
        else {
            Set-CertificateStatus "Сертификат проверен. Для публичного сертификата будет использовано хранилище Windows." "Success"
        }

        Mark-EditorDirty
        Update-EditorValidation
    }
    catch {
        Write-LikewebManagerLog ("Ошибка чтения PEM: " + $Path) $_
        $script:SelectedCertificateInfo = $null
        $script:SelectedCertificatePath = ""
        Update-CertificateCard
        Set-CertificateStatus "Не удалось прочитать PEM. Проверьте файл или выберите другой сертификат." "Error"
        Set-EditorMessage "Error" ("Не удалось прочитать сертификат. Подробности записаны в " + $script:ManagerLogPath)
        Update-EditorValidation
    }
}

function Open-CertificateDialog {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Выберите сертификат сервера"
    $dialog.Filter = "Сертификаты PEM (*.pem;*.crt;*.cer)|*.pem;*.crt;*.cer|Все файлы (*.*)|*.*"
    $dialog.Multiselect = $false

    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        Load-CertificateIntoEditor $dialog.FileName
    }
}

function Update-RecognitionSummary {
    if (-not [string]::IsNullOrWhiteSpace($script:EditingProfileId)) {
        $summarySurface.Visible = $false
        return
    }

    if (-not $script:RecognitionAttempted -or -not $script:SettingsRecognized) {
        $summarySurface.Visible = $false
        return
    }

    $summarySurface.Visible = $true
    $summaryNameValue.Text = $displayNameTextBox.Text.Trim()
    $summaryAddressValue.Text = $addressTextBox.Text.Trim()
    $summaryProtocolValue.Text = $protocolComboBox.Text
    $summaryIpv6Value.Text = if ($ipv6CheckBox.Checked) { "Разрешен" } else { "Запрещен" }
    $summaryCertificateValue.Text = if ($null -ne $script:SelectedCertificateInfo) {
        "Добавлен"
    }
    elseif ($script:CertificateExpected) {
        "Требуется"
    }
    else {
        "Не требуется"
    }
}

function Set-FieldError {
    param(
        [string]$Field,
        [System.Windows.Forms.Control]$Control,
        [string]$Message
    )

    $label = $script:FieldErrorLabels[$Field]
    if ($null -eq $label) {
        return
    }

    $label.Text = $Message
    $label.Visible = -not [string]::IsNullOrWhiteSpace($Message)
    $errorProvider.SetError($Control, $Message)
}

function Get-EditorValidationResult {
    $errors = New-Object System.Collections.Generic.List[string]

    $displayName = $displayNameTextBox.Text.Trim()
    $serverName = $serverNameTextBox.Text.Trim()
    $address = $addressTextBox.Text.Trim()
    $hostname = $hostnameTextBox.Text.Trim()
    $username = $usernameTextBox.Text.Trim()
    $password = $passwordTextBox.Text

    Set-FieldError "DisplayName" $displayNameTextBox ""
    Set-FieldError "ServerName" $serverNameTextBox ""
    Set-FieldError "Address" $addressTextBox ""
    Set-FieldError "Hostname" $hostnameTextBox ""
    Set-FieldError "Username" $usernameTextBox ""
    Set-FieldError "Password" $passwordTextBox ""

    if ([string]::IsNullOrWhiteSpace($displayName)) {
        $message = "Укажите название, которое увидит пользователь."
        $errors.Add($message)
        Set-FieldError "DisplayName" $displayNameTextBox $message
    }

    if ([string]::IsNullOrWhiteSpace($serverName)) {
        $message = "Укажите служебное имя сервера."
        $errors.Add($message)
        Set-FieldError "ServerName" $serverNameTextBox $message
    }

    if ([string]::IsNullOrWhiteSpace($address)) {
        $message = "Укажите адрес сервера."
        $errors.Add($message)
        Set-FieldError "Address" $addressTextBox $message
    }
    else {
        try { [void](Normalize-LikewebAddress $address) }
        catch {
            $errors.Add($_.Exception.Message)
            Set-FieldError "Address" $addressTextBox $_.Exception.Message
        }
    }

    if ([string]::IsNullOrWhiteSpace($hostname)) {
        $message = "Укажите домен из сертификата сервера."
        $errors.Add($message)
        Set-FieldError "Hostname" $hostnameTextBox $message
    }

    if ([string]::IsNullOrWhiteSpace($username)) {
        $message = "Укажите имя пользователя."
        $errors.Add($message)
        Set-FieldError "Username" $usernameTextBox $message
    }

    if ([string]::IsNullOrWhiteSpace($password)) {
        $message = "Укажите пароль."
        $errors.Add($message)
        Set-FieldError "Password" $passwordTextBox $message
    }

    if ($script:CertificateExpected -and $null -eq $script:SelectedCertificateInfo) {
        $errors.Add("Добавьте сертификат, указанный администратором.")
    }

    if (
        $null -ne $script:SelectedCertificateInfo -and
        $script:SelectedCertificateInfo.MetadataRead -ne $false
    ) {
        if ($script:SelectedCertificateInfo.NotAfter -lt (Get-Date)) {
            $errors.Add("Выбранный сертификат просрочен.")
        }
        elseif (-not (Test-CertificateMatchesHostname $(if ($script:SelectedCertificateInfo.PSObject.Properties.Name -contains "DnsNames") { $script:SelectedCertificateInfo.DnsNames } else { $script:SelectedCertificateInfo.DnsName }) $hostname)) {
            $errors.Add("Сертификат не соответствует домену сервера.")
        }
    }

    if ($embedCertificateCheckBox.Checked -and $null -eq $script:SelectedCertificateInfo) {
        $errors.Add("Для встраивания сертификата сначала выберите PEM-файл.")
    }

    return [pscustomobject]@{
        IsValid = ($errors.Count -eq 0)
        Errors = @($errors)
    }
}

function Update-EditorValidation {
    if ($null -eq $saveButton) {
        return
    }

    $result = Get-EditorValidationResult
    $enabled = $result.IsValid -and -not $script:TestWorkerProcess

    $saveButton.Enabled = $enabled
    $saveConnectButton.Enabled = $enabled
    $testButton.Enabled = $enabled

    $reason = if ($enabled) {
        ""
    }
    elseif ($script:TestWorkerProcess) {
        "Дождитесь окончания проверки сервера."
    }
    elseif ($result.Errors.Count -gt 0) {
        $result.Errors[0]
    }
    else {
        "Заполните обязательные параметры."
    }

    $script:UiToolTip.SetToolTip($saveButton, $reason)
    $script:UiToolTip.SetToolTip($saveConnectButton, $reason)
    $script:UiToolTip.SetToolTip($testButton, $reason)

    Update-RecognitionSummary
    Update-EditorContentLayout
}

function Set-AdvancedVisibility {
    param([bool]$Visible)

    $script:AdvancedVisible = $Visible
    $advancedFieldsPanel.Visible = $Visible
    $advancedToggleButton.Image = if ($Visible) {
        $script:IconChevronUp
    }
    else {
        $script:IconChevronDown
    }
    $advancedToggleButton.Text = "Расширенные настройки"
    Update-EditorContentLayout
}

function Reset-Editor {
    $script:LoadingEditor = $true
    try {
        $script:EditingProfileId = ""
        $script:SettingsRecognized = $false
        $script:RecognitionAttempted = $false
        $script:CertificateExpected = $false
        $script:SelectedCertificateInfo = $null
        $script:SelectedCertificatePath = ""
        $script:LastTestLog = ""

        # New-server mode shows the simple import workflow. Technical fields
        # remain available through the always-visible advanced-settings row.
        $settingsSurface.Visible = $true
        $certificateSurface.Visible = $true
        $advancedToggleButton.Visible = $true

        $messageTextBox.Clear()
        $displayNameTextBox.Clear()
        $serverNameTextBox.Clear()
        $addressTextBox.Clear()
        $hostnameTextBox.Clear()
        $usernameTextBox.Clear()
        $passwordTextBox.Clear()
        $protocolComboBox.SelectedItem = "HTTP/2"
        $ipv6CheckBox.Checked = $true
        $embedCertificateCheckBox.Checked = $false
        $passwordTextBox.UseSystemPasswordChar = $true
        $passwordToggleButton.Image = $script:IconEye
        $passwordToggleButton.AccessibleName = "Показать пароль"
        $script:UiToolTip.SetToolTip($passwordToggleButton, "Показать пароль")

        $summarySurface.Visible = $false
        $testDetailsSurface.Visible = $false
        $testDetailsTextBox.Clear()
        Set-RecognitionStatus "Вставьте сообщение с параметрами сервера." "Neutral"
        Set-CertificateStatus "Выберите файл .pem вручную кнопкой выше." "Neutral"
        Update-CertificateCard
        Set-AdvancedVisibility $false
        Set-EditorMessage "Hidden"
        Set-TestStatus "Сервер еще не проверен." "Neutral"
    }
    finally {
        $script:LoadingEditor = $false
        $script:EditorDirty = $false
        Update-EditorValidation
    }
}

function Fill-EditorFromParsedSettings {
    param([pscustomobject]$Settings)

    $script:LoadingEditor = $true
    try {
        $displayNameTextBox.Text = $Settings.DisplayName
        $serverNameTextBox.Text = $Settings.ServerName
        $addressTextBox.Text = $Settings.Address
        $hostnameTextBox.Text = $Settings.Hostname
        $usernameTextBox.Text = $Settings.Username
        $passwordTextBox.Text = $Settings.Password

        $normalizedProtocol = Normalize-LikewebProtocol $Settings.Protocol
        $protocolComboBox.SelectedItem = if ($normalizedProtocol -eq "http3") {
            "HTTP/3"
        }
        else {
            "HTTP/2"
        }

        $ipv6CheckBox.Checked = ConvertTo-LikewebBoolean $Settings.IPv6
        $script:CertificateExpected = (
            $Settings.CertificateMode -match
            '(?i)(custom|included|self|pem|пользователь|самоподпис|включ|импорт)'
        )

        $missing = New-Object System.Collections.Generic.List[string]
        if ([string]::IsNullOrWhiteSpace($Settings.DisplayName)) { $missing.Add("название сервера") }
        if ([string]::IsNullOrWhiteSpace($Settings.ServerName)) { $missing.Add("служебное имя") }
        if ([string]::IsNullOrWhiteSpace($Settings.Address)) { $missing.Add("адрес") }
        if ([string]::IsNullOrWhiteSpace($Settings.Hostname)) { $missing.Add("домен сертификата") }
        if ([string]::IsNullOrWhiteSpace($Settings.Username)) { $missing.Add("имя пользователя") }
        if ([string]::IsNullOrWhiteSpace($Settings.Password)) { $missing.Add("пароль") }

        $script:RecognitionAttempted = $true
        if ($missing.Count -eq 0) {
            $script:SettingsRecognized = $true
            Set-RecognitionStatus (
                "Настройки распознаны: " + $Settings.DisplayName
            ) "Success"
        }
        else {
            $script:SettingsRecognized = $false
            Set-RecognitionStatus (
                "Распознано не всё. Проверьте: " + ($missing -join ", ") + "."
            ) "Warning"
            Set-AdvancedVisibility $true
        }

        if ($script:CertificateExpected -and $null -eq $script:SelectedCertificateInfo) {
            Set-CertificateStatus "Требуется сертификат из сообщения администратора." "Warning"
        }
        elseif (-not $script:CertificateExpected -and $null -eq $script:SelectedCertificateInfo) {
            Set-CertificateStatus "Сертификат не требуется. При необходимости его можно добавить." "Neutral"
        }
    }
    finally {
        $script:LoadingEditor = $false
        $script:EditorDirty = $true
        Update-EditorValidation
    }
}

function Invoke-Recognition {
    if ([string]::IsNullOrWhiteSpace($messageTextBox.Text)) {
        $script:RecognitionAttempted = $true
        $script:SettingsRecognized = $false
        Set-RecognitionStatus "Вставьте сообщение с параметрами сервера." "Warning"
        Update-RecognitionSummary
        Update-EditorValidation
        return
    }

    try {
        Set-RecognitionStatus "Распознаем настройки…" "Loading"
        [System.Windows.Forms.Application]::DoEvents()
        $settings = Parse-LikewebSettingsMessage $messageTextBox.Text
        Fill-EditorFromParsedSettings $settings
    }
    catch {
        $script:RecognitionAttempted = $true
        $script:SettingsRecognized = $false
        Set-RecognitionStatus (
            "Не удалось распознать настройки. " + $_.Exception.Message
        ) "Error"
        $summarySurface.Visible = $false
        Update-EditorValidation
    }
}

function Get-EditorSettings {
    $validation = Get-EditorValidationResult
    if (-not $validation.IsValid) {
        throw ($validation.Errors[0])
    }

    $certificatePem = ""
    if ($null -ne $script:SelectedCertificateInfo) {
        $certificatePem = $script:SelectedCertificateInfo.Pem
    }

    $serverName = $serverNameTextBox.Text.Trim()

    return [pscustomobject][ordered]@{
        DisplayName = $displayNameTextBox.Text.Trim()
        ServerName = $serverName
        ProfileId = ConvertTo-LikewebSafeId $serverName
        Address = Normalize-LikewebAddress $addressTextBox.Text
        Hostname = $hostnameTextBox.Text.Trim()
        Username = $usernameTextBox.Text.Trim()
        Password = $passwordTextBox.Text
        Protocol = Normalize-LikewebProtocol $protocolComboBox.Text
        HasIPv6 = $ipv6CheckBox.Checked
        CertificatePem = $certificatePem
        EmbedCertificate = $embedCertificateCheckBox.Checked
    }
}

function Get-EditorToml {
    $settings = Get-EditorSettings
    $toml = New-LikewebProfileToml `
        -DisplayName $settings.DisplayName `
        -ServerName $settings.ServerName `
        -Address $settings.Address `
        -Hostname $settings.Hostname `
        -Username $settings.Username `
        -Password $settings.Password `
        -Protocol $settings.Protocol `
        -HasIPv6 $settings.HasIPv6 `
        -CertificatePem $settings.CertificatePem `
        -EmbedCertificate $settings.EmbedCertificate

    return [pscustomobject]@{
        Settings = $settings
        Toml = $toml
    }
}

# -------------------- Server list --------------------

function Register-RowHover {
    param(
        [System.Windows.Forms.Panel]$Row,
        [System.Windows.Forms.Control]$Control
    )

    # Event handlers run after this function has returned. Capture the concrete
    # Panel instance so $Row cannot be resolved to an unrelated object later.
    $capturedRow = $Row

    $mouseEnterHandler = {
        if ($null -eq $capturedRow -or $capturedRow.IsDisposed) {
            return
        }
        $capturedRow.BackColor = $capturedRow.HoverBackColor
        $capturedRow.Invalidate()
    }.GetNewClosure()

    $mouseLeaveHandler = {
        if ($null -eq $capturedRow -or $capturedRow.IsDisposed) {
            return
        }
        $cursor = $capturedRow.PointToClient(
            [System.Windows.Forms.Cursor]::Position
        )
        if (-not $capturedRow.ClientRectangle.Contains($cursor)) {
            $capturedRow.BackColor = $capturedRow.NormalBackColor
            $capturedRow.Invalidate()
        }
    }.GetNewClosure()

    $Control.Add_MouseEnter($mouseEnterHandler)
    $Control.Add_MouseLeave($mouseLeaveHandler)

    foreach ($child in $Control.Controls) {
        Register-RowHover $capturedRow $child
    }
}

function Resize-ServerRows {
    if ($null -eq $serversFlow) {
        return
    }

    $available = [Math]::Max(620, $serversFlow.ClientSize.Width - 24)
    foreach ($rowState in $script:ServerRows.Values) {
        $row = $rowState.Row
        $row.Width = $available

        $right = $available - 16
        $rowState.MoreButton.Left = $right - $rowState.MoreButton.Width
        $right = $rowState.MoreButton.Left - 8
        $rowState.ActionButton.Left = $right - $rowState.ActionButton.Width
        $rowState.BusyProgress.Left = $rowState.ActionButton.Left
        $rowState.BusyLabel.Left = $rowState.ActionButton.Left

        $textRight = $rowState.ActionButton.Left - 24
        $rowState.NameLabel.Width = [Math]::Max(180, $textRight - $rowState.NameLabel.Left)
        $rowState.AddressLabel.Width = $rowState.NameLabel.Width
        $rowState.StateLabel.Width = $rowState.NameLabel.Width
    }

    if ($emptyStatePanel.Visible) {
        $emptyStatePanel.Width = $available
    }
}

function Update-ServerRowState {
    param(
        [pscustomobject]$Profile,
        [string]$ActiveId,
        [bool]$IsRunning
    )

    if (-not $script:ServerRows.ContainsKey($Profile.Id)) {
        return
    }

    $rowState = $script:ServerRows[$Profile.Id]
    $isConnected = ($Profile.Id -eq $ActiveId -and $IsRunning)
    $isActive = ($Profile.Id -eq $ActiveId)
    $isBusy = ($script:OperationProfileId -eq $Profile.Id)

    $rowState.NameLabel.Text = $Profile.DisplayName
    $rowState.AddressLabel.Text = $Profile.Address
    $rowState.MenuDelete.Enabled = -not $isActive
    $rowState.MenuDelete.ToolTipText = if ($isActive) {
        "Сначала выберите другой сервер"
    }
    else {
        "Удалить сервер"
    }

    if ($isBusy) {
        $rowState.StatusIcon.Image = $script:IconLoading
        $rowState.StateLabel.Text = if ($script:OperationKind -eq "Connect") {
            "Подключение…"
        }
        else {
            "Отключение…"
        }
        $rowState.StateLabel.ForeColor = $script:ColorAccent
        $rowState.ActionButton.Visible = $false
        $rowState.BusyLabel.Visible = $true
        $rowState.BusyProgress.Visible = $true
        $rowState.MoreButton.Enabled = $false
        $rowState.Row.AccentWidth = 4
        $rowState.Row.AccentColor = $script:ColorAccent
        $rowState.Row.NormalBackColor = $script:ColorInfoSurface
        $rowState.Row.HoverBackColor = $script:ColorInfoSurface
    }
    else {
        $rowState.BusyLabel.Visible = $false
        $rowState.BusyProgress.Visible = $false
        $rowState.ActionButton.Visible = $true
        $rowState.MoreButton.Enabled = $true

        if ($isConnected) {
            $rowState.StatusIcon.Image = $script:IconConnected
            $rowState.StateLabel.Text = "Подключено"
            $rowState.StateLabel.ForeColor = $script:ColorSuccess
            $rowState.ActionButton.Text = "Отключить"
            $rowState.ActionButton.Image = $script:IconStop
            $rowState.ActionButton.Tag = "Disconnect|" + $Profile.Id
            $rowState.Row.AccentWidth = 4
            $rowState.Row.AccentColor = $script:ColorSuccess
            $rowState.Row.NormalBackColor = $script:ColorSuccessSurface
            $rowState.Row.HoverBackColor = [System.Drawing.Color]::FromArgb(236, 247, 236)
        }
        else {
            $rowState.StatusIcon.Image = $script:IconDisconnected
            $rowState.StateLabel.Text = if ($isActive) {
                "Отключено · выбранный сервер"
            }
            else {
                "Отключено"
            }
            $rowState.StateLabel.ForeColor = $script:ColorError
            $rowState.ActionButton.Text = "Подключить"
            $rowState.ActionButton.Image = $script:IconPlay
            $rowState.ActionButton.Tag = "Connect|" + $Profile.Id
            $rowState.Row.AccentWidth = if ($isActive) { 4 } else { 0 }
            $rowState.Row.AccentColor = $script:ColorAccent
            $rowState.Row.NormalBackColor = if ($isActive) {
                $script:ColorInfoSurface
            }
            else {
                $script:ColorSurface
            }
            $rowState.Row.HoverBackColor = $script:ColorSurfaceHover
        }
    }

    $rowState.Row.BackColor = $rowState.Row.NormalBackColor
    $rowState.Row.Invalidate()
}

function New-ServerRow {
    param([pscustomobject]$Profile)

    $row = New-FluentSurface 84 8 $true
    $row.Width = [Math]::Max(620, $serversFlow.ClientSize.Width - 24)
    $row.Margin = [System.Windows.Forms.Padding]::new(0, 0, 0, 8)
    $row.Tag = $Profile.Id
    Set-Accessible $row ("Сервер " + $Profile.DisplayName) ("Адрес " + $Profile.Address)

    $statusIcon = New-Object System.Windows.Forms.PictureBox
    $statusIcon.Location = [System.Drawing.Point]::new(18, 17)
    $statusIcon.Size = [System.Drawing.Size]::new(22, 22)
    $statusIcon.SizeMode = "CenterImage"
    $statusIcon.AccessibleName = "Состояние подключения"
    $row.Controls.Add($statusIcon)

    $nameLabel = New-PageLabel $Profile.DisplayName "Semibold"
    $nameLabel.Location = [System.Drawing.Point]::new(52, 10)
    $nameLabel.Size = [System.Drawing.Size]::new(430, 23)
    $nameLabel.AutoSize = $false
    $nameLabel.AutoEllipsis = $true
    $row.Controls.Add($nameLabel)

    $addressLabel = New-PageLabel $Profile.Address "Secondary"
    $addressLabel.Location = [System.Drawing.Point]::new(52, 34)
    $addressLabel.Size = [System.Drawing.Size]::new(430, 20)
    $addressLabel.AutoSize = $false
    $addressLabel.AutoEllipsis = $true
    $row.Controls.Add($addressLabel)

    $stateLabel = New-PageLabel "Отключено" "Secondary"
    $stateLabel.Location = [System.Drawing.Point]::new(52, 57)
    $stateLabel.Size = [System.Drawing.Size]::new(430, 20)
    $stateLabel.AutoSize = $false
    $row.Controls.Add($stateLabel)

    $action = New-FluentButton "Подключить" "Secondary" $script:IconPlay 124 36 "Подключить сервер"
    $action.Top = 24
    $action.Add_Click({
        param($sender, $eventArgs)
        $parts = ([string]$sender.Tag).Split('|')
        if ($parts.Count -ne 2) { return }
        if ($parts[0] -eq "Connect") {
            Connect-ProfileById $parts[1]
        }
        else {
            Disconnect-ProfileById $parts[1]
        }
    })
    $row.Controls.Add($action)

    $busyLabel = New-PageLabel "Подключение…" "Secondary"
    $busyLabel.Size = [System.Drawing.Size]::new(124, 20)
    $busyLabel.Top = 20
    $busyLabel.TextAlign = "MiddleCenter"
    $busyLabel.Visible = $false
    $row.Controls.Add($busyLabel)

    $busyProgress = New-Object System.Windows.Forms.ProgressBar
    $busyProgress.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $busyProgress.MarqueeAnimationSpeed = 25
    $busyProgress.Size = [System.Drawing.Size]::new(124, 8)
    $busyProgress.Top = 47
    $busyProgress.Visible = $false
    $busyProgress.AccessibleName = "Выполняется операция"
    $row.Controls.Add($busyProgress)

    $more = New-FluentButton "" "Icon" $script:IconMore 36 36 "Дополнительные действия" "Изменить, открыть или удалить сервер"
    $more.Top = 24
    $row.Controls.Add($more)

    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $menu.Font = $script:FontBody
    $menu.ShowImageMargin = $true

    $editItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $editItem.Text = "Изменить"
    $editItem.Image = $script:IconEdit
    $capturedProfileIdForEdit = [string]$Profile.Id
    $capturedProfilePathForEdit = [string]$Profile.Path
    $editItem.Tag = $capturedProfileIdForEdit
    $editItem.Add_Click({
        try {
            $resolvedPath = Resolve-LikewebProfilePathForManager $capturedProfileIdForEdit $capturedProfilePathForEdit
            $resolvedProfile = Get-LikewebProfileInfo $resolvedPath
            Load-ProfileForEditing ([string]$resolvedProfile.Id)
        }
        catch {
            Write-LikewebManagerLog ("Не удалось открыть профиль из меню: " + $capturedProfileIdForEdit) $_
            Set-ServersMessage "Error" ("Не удалось открыть профиль. " + $_.Exception.Message + " Подробности записаны в " + $script:ManagerLogPath)
        }
    }.GetNewClosure())
    [void]$menu.Items.Add($editItem)

    $openItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $openItem.Text = "Открыть файл профиля"
    $openItem.Image = $script:IconFolder
    $capturedProfileIdForOpen = [string]$Profile.Id
    $capturedProfilePathForOpen = [string]$Profile.Path
    $openItem.Tag = $capturedProfileIdForOpen
    $openItem.Add_Click({
        try {
            $path = Resolve-LikewebProfilePathForManager $capturedProfileIdForOpen $capturedProfilePathForOpen
            Start-Process -FilePath "notepad.exe" -ArgumentList ('"{0}"' -f $path)
        }
        catch {
            Write-LikewebManagerLog ("Не удалось открыть файл профиля: " + $capturedProfileIdForOpen) $_
            Set-ServersMessage "Error" ("Не удалось открыть файл профиля. " + $_.Exception.Message + " Подробности записаны в " + $script:ManagerLogPath)
        }
    }.GetNewClosure())
    [void]$menu.Items.Add($openItem)

    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $deleteItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $deleteItem.Text = "Удалить"
    $deleteItem.ForeColor = $script:ColorError
    $deleteItem.Image = $script:IconDelete
    $capturedProfileIdForDelete = [string]$Profile.Id
    $deleteItem.Tag = $capturedProfileIdForDelete
    $deleteItem.Add_Click({
        try {
            Delete-ProfileById $capturedProfileIdForDelete
        }
        catch {
            Write-LikewebManagerLog ("Не удалось удалить профиль из меню: " + $capturedProfileIdForDelete) $_
            Set-ServersMessage "Error" ("Не удалось удалить профиль. " + $_.Exception.Message + " Подробности записаны в " + $script:ManagerLogPath)
        }
    }.GetNewClosure())
    [void]$menu.Items.Add($deleteItem)

    $capturedMenu = $menu
    $capturedMoreButton = $more
    $more.Add_Click({
        $capturedMenu.Show(
            $capturedMoreButton,
            [System.Drawing.Point]::new(0, $capturedMoreButton.Height)
        )
    }.GetNewClosure())

    $capturedRow = $row
    $capturedAction = $action
    $row.Add_Click({ $capturedRow.Focus() }.GetNewClosure())
    $row.Add_KeyDown({
        param($sender, $eventArgs)
        if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            $capturedAction.PerformClick()
            $eventArgs.Handled = $true
        }
        elseif (
            $eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Up -or
            $eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Down
        ) {
            $rows = @($serversFlow.Controls | Where-Object { $_ -is [System.Windows.Forms.Panel] -and $_.Tag })
            $index = [Array]::IndexOf($rows, $sender)
            if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Up) { $index-- } else { $index++ }
            if ($index -ge 0 -and $index -lt $rows.Count) {
                $rows[$index].Focus()
            }
            $eventArgs.Handled = $true
        }
    }.GetNewClosure())

    Register-RowHover $row $row

    $rowState = [pscustomobject]@{
        Row = $row
        StatusIcon = $statusIcon
        NameLabel = $nameLabel
        AddressLabel = $addressLabel
        StateLabel = $stateLabel
        ActionButton = $action
        MoreButton = $more
        BusyLabel = $busyLabel
        BusyProgress = $busyProgress
        Menu = $menu
        MenuDelete = $deleteItem
    }

    $script:ServerRows[$Profile.Id] = $rowState
    [void]$serversFlow.Controls.Add($row)
}

function Rebuild-ServerList {
    param([object[]]$Profiles)

    $serversFlow.SuspendLayout()
    try {
        foreach ($state in $script:ServerRows.Values) {
            if ($null -ne $state.Menu) { $state.Menu.Dispose() }
            if ($null -ne $state.Row) { $state.Row.Dispose() }
        }
        $script:ServerRows = @{}
        $serversFlow.Controls.Clear()

        $emptyStatePanel.Visible = ($Profiles.Count -eq 0)

        if ($Profiles.Count -eq 0) {
            [void]$serversFlow.Controls.Add($emptyStatePanel)
        }
        else {
            foreach ($profile in $Profiles) {
                New-ServerRow $profile
            }
        }
    }
    finally {
        $serversFlow.ResumeLayout()
        Resize-ServerRows
    }
}

function Refresh-ServerList {
    param([switch]$Force)

    try {
        $profiles = @(Get-LikewebProfiles)
        $activeId = Get-LikewebActiveProfileId
        $isRunning = $null -ne (Get-LikewebProcess)

        $signature = ($profiles | ForEach-Object {
            $_.Id + "|" + $_.DisplayName + "|" + $_.Address
        }) -join "||"

        if ($Force -or $signature -ne $script:LastProfileSignature) {
            $script:LastProfileSignature = $signature
            Rebuild-ServerList $profiles
        }

        foreach ($profile in $profiles) {
            Update-ServerRowState $profile $activeId $isRunning
        }
    }
    catch {
        Write-LikewebManagerLog "Ошибка обновления списка серверов" $_

        try {
            $script:LastProfileSignature = ""
            $script:ServerRows = @{}
            $serversFlow.Controls.Clear()
            $emptyStatePanel.Visible = $true
            [void]$serversFlow.Controls.Add($emptyStatePanel)
            Resize-ServerRows
        }
        catch {
            Write-LikewebManagerLog "Не удалось показать резервное пустое состояние" $_
        }

        Set-ServersMessage "Error" (
            "Не удалось загрузить список серверов. Откройте журнал: " +
            $script:ManagerLogPath
        )
    }
}

function Connect-ProfileById {
    param([string]$Id)

    $path = Join-Path $script:LikewebProfilesDir ($Id + ".toml")
    if (-not (Test-Path -LiteralPath $path)) {
        Set-ServersMessage "Error" "Профиль сервера не найден. Обновите список или добавьте сервер заново."
        return
    }

    try {
        Set-ServersMessage "Hidden"
        $profile = Get-LikewebProfileInfo $path
        $activeId = Get-LikewebActiveProfileId
        $script:OperationProfileId = $Id
        $script:OperationKind = "Connect"
        Refresh-ServerList
        [System.Windows.Forms.Application]::DoEvents()

        if (Get-LikewebProcess) {
            Set-LikewebOperationState "Disconnecting" $activeId ""
            [void](Stop-LikewebVpnAndWait)
        }

        Set-LikewebActiveProfile $path
        Set-LikewebOperationState "Connecting" $profile.Id $profile.DisplayName

        if (-not (Start-LikewebVpnAndWait)) {
            throw "TrustTunnel не запустился. Откройте lwtt_start.bat вручную, чтобы увидеть техническую ошибку."
        }
    }
    catch {
        Set-ServersMessage "Error" (
            "Не удалось подключиться. Проверьте адрес, учетные данные и сертификат. " +
            $_.Exception.Message
        )
    }
    finally {
        Clear-LikewebOperationState
        $script:OperationProfileId = ""
        $script:OperationKind = ""
        Refresh-ServerList -Force
    }
}

function Disconnect-ProfileById {
    param([string]$Id)

    $activeId = Get-LikewebActiveProfileId
    if ($Id -ne $activeId -or -not (Get-LikewebProcess)) {
        Refresh-ServerList
        return
    }

    try {
        Set-ServersMessage "Hidden"
        $script:OperationProfileId = $Id
        $script:OperationKind = "Disconnect"
        Refresh-ServerList
        [System.Windows.Forms.Application]::DoEvents()

        Set-LikewebOperationState "Disconnecting" $Id ""
        if (-not (Stop-LikewebVpnAndWait)) {
            throw "Процесс TrustTunnel не завершился. Повторите отключение."
        }
    }
    catch {
        Set-ServersMessage "Error" ("Не удалось отключить TrustTunnel. " + $_.Exception.Message)
    }
    finally {
        Clear-LikewebOperationState
        $script:OperationProfileId = ""
        $script:OperationKind = ""
        Refresh-ServerList -Force
    }
}

function Delete-ProfileById {
    param([string]$Id)

    $path = Join-Path $script:LikewebProfilesDir ($Id + ".toml")

    try {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Профиль сервера не найден."
        }

        $profile = Get-LikewebProfileInfo $path
        $activeId = Get-LikewebActiveProfileId

        if ($Id -eq $activeId) {
            Set-ServersMessage "Warning" "Сначала выберите другой сервер, затем удалите этот профиль."
            return
        }

        if (-not (Show-DeleteConfirmation $profile.DisplayName)) {
            return
        }

        Remove-Item -LiteralPath $path -Force
        $certificatePath = Join-Path $script:LikewebCertificatesDir ($Id + ".pem")
        if (Test-Path -LiteralPath $certificatePath) {
            Remove-Item -LiteralPath $certificatePath -Force
        }

        $script:LastProfileSignature = ""
        Refresh-ServerList -Force
        Set-ServersMessage "Success" ("Сервер удален: " + $profile.DisplayName)
    }
    catch {
        Set-ServersMessage "Error" ("Не удалось удалить сервер. " + $_.Exception.Message)
    }
}

# -------------------- Page navigation and profile editing --------------------

function Update-EditorHeader {
    if ([string]::IsNullOrWhiteSpace($script:EditingProfileId)) {
        $editorTitleLabel.Text = "Новый сервер"
        $editorSubtitleLabel.Text = "Вставьте сообщение администратора и добавьте сертификат, если он требуется"
    }
    else {
        $display = $displayNameTextBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($display)) {
            $display = $script:EditingProfileId
        }
        $editorTitleLabel.Text = "Редактирование: " + $display
        $editorSubtitleLabel.Text = "Измените параметры сервера и сохраните профиль"
    }
}

function Show-ServersPage {
    param([switch]$SkipDiscardCheck)

    if (-not $SkipDiscardCheck -and $script:CurrentView -eq "Editor") {
        if (-not (Confirm-DiscardChanges)) {
            return
        }
    }

    $editorPage.Visible = $false
    $serversPage.Visible = $true
    $serversPage.BringToFront()
    $script:CurrentView = "Servers"
    $form.AcceptButton = $addServerButton
    Refresh-ServerList -Force
    $serversTitleLabel.Focus()
}

function Show-NewServerPage {
    Reset-Editor
    Update-EditorHeader
    $serversPage.Visible = $false
    $editorPage.Visible = $true
    $editorPage.BringToFront()
    $script:CurrentView = "Editor"
    $form.AcceptButton = $saveConnectButton
    $editorPage.PerformLayout()
    $editorFooter.BringToFront()
    Update-EditorResponsiveLayout
    $footerActions.PerformLayout()
    $editorFooter.Refresh()
    $messageTextBox.Focus()

    # Docked controls have their final dimensions only after the page is shown.
    # Run one additional layout pass on the UI thread so the footer is visible
    # even before any settings have been recognized.
    [void]$form.BeginInvoke([System.Windows.Forms.MethodInvoker]{
        $editorPage.PerformLayout()
        $editorFooter.BringToFront()
        Update-EditorResponsiveLayout
        $footerActions.PerformLayout()
        $editorFooter.Refresh()
    })
}

function Resolve-LikewebProfilePathForManager {
    param(
        [string]$Id,
        [string]$FallbackPath = ""
    )

    if (-not [string]::IsNullOrWhiteSpace($FallbackPath)) {
        try {
            if (Test-Path -LiteralPath $FallbackPath -PathType Leaf) {
                return $FallbackPath
            }
        }
        catch {
        }
    }

    if ([string]::IsNullOrWhiteSpace($Id)) {
        throw "Не передан идентификатор сервера. Обновите список серверов и повторите действие."
    }

    if (-not [string]::IsNullOrWhiteSpace($script:LikewebProfilesDir)) {
        try {
            $candidate = Join-Path $script:LikewebProfilesDir ($Id + ".toml")
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return $candidate
            }
        }
        catch {
        }
    }

    $profiles = @(Get-LikewebProfiles)
    foreach ($profile in $profiles) {
        if ([string]$profile.Id -eq $Id -and -not [string]::IsNullOrWhiteSpace([string]$profile.Path)) {
            try {
                if (Test-Path -LiteralPath ([string]$profile.Path) -PathType Leaf) {
                    return [string]$profile.Path
                }
            }
            catch {
            }
        }
    }

    throw "Файл профиля сервера не найден. Обновите список или добавьте сервер заново."
}

function Load-ProfileForEditing {
    param([string]$Id)

    try {
        $profilePath = Resolve-LikewebProfilePathForManager $Id

        # Show a stable loading screen before rebuilding the technical form.
        $serversPage.Visible = $false
        $editorPage.Visible = $true
        $editorPage.BringToFront()
        $script:CurrentView = "Editor"
        $form.AcceptButton = $saveConnectButton
        Set-EditorLoadingOverlay $true
        [System.Windows.Forms.Application]::DoEvents()

        Reset-Editor
        $profile = Get-LikewebProfileInfo $profilePath
        if ($null -eq $profile) {
            throw "Профиль не удалось прочитать."
        }

        $script:LoadingEditor = $true
        try {
            $script:EditingProfileId = [string]$profile.Id
            $script:SettingsRecognized = $true
            $script:RecognitionAttempted = $true
            $displayNameTextBox.Text = [string]$profile.DisplayName
            $serverNameTextBox.Text = [string]$profile.ServerName
            $addressTextBox.Text = [string]$profile.Address
            $hostnameTextBox.Text = [string]$profile.Hostname
            $usernameTextBox.Text = [string]$profile.Username
            $passwordTextBox.Text = [string]$profile.Password
            $ipv6CheckBox.Checked = [bool]$profile.HasIPv6
            $protocolComboBox.SelectedItem = if ($profile.Protocol -eq "http3") { "HTTP/3" } else { "HTTP/2" }

            $certificateFile = Join-Path $script:LikewebCertificatesDir ([string]$profile.Id + ".pem")
            if (Test-Path -LiteralPath $certificateFile -PathType Leaf) {
                Load-CertificateIntoEditor $certificateFile
                $embedCertificateCheckBox.Checked = [bool]$profile.EmbedCertificate
            }
            elseif (-not [string]::IsNullOrWhiteSpace([string]$profile.CertificatePem)) {
                $script:SelectedCertificateInfo = Get-LikewebCertificateInformationFromPem $profile.CertificatePem
                $script:SelectedCertificatePath = ""
                $embedCertificateCheckBox.Checked = $true
                Update-CertificateCard
                Set-CertificateStatus "Сертификат загружен из сохраненного профиля." "Success"
            }
            else {
                $script:SelectedCertificateInfo = $null
                $script:SelectedCertificatePath = ""
                Update-CertificateCard
                Set-CertificateStatus "Для этого профиля сертификат не сохранен." "Neutral"
            }

            Set-RecognitionStatus "Параметры сохраненного сервера загружены." "Success"

            # Editing is a focused technical form: hide the import and large
            # certificate cards, show every editable field immediately.
            $settingsSurface.Visible = $false
            $certificateSurface.Visible = $false
            $summarySurface.Visible = $false
            $advancedToggleButton.Visible = $false
            Set-AdvancedVisibility $true
            Update-EditorHeader
        }
        finally {
            $script:LoadingEditor = $false
            $script:EditorDirty = $false
        }

        Update-EditorValidation
        $editorPage.PerformLayout()
        $editorFooter.BringToFront()
        Update-EditorResponsiveLayout
        $footerActions.PerformLayout()
        $editorFooter.Refresh()
        $editorScrollPanel.AutoScrollPosition = [System.Drawing.Point]::new(0, 0)
        Set-EditorLoadingOverlay $false
        $displayNameTextBox.Focus()
    }
    catch {
        Write-LikewebManagerLog ("Не удалось открыть профиль для редактирования: " + $Id) $_
        try { Set-EditorLoadingOverlay $false } catch {}
        Show-ServersPage -SkipDiscardCheck
        Set-ServersMessage "Error" ("Не удалось открыть профиль. " + $_.Exception.Message + " Подробности записаны в " + $script:ManagerLogPath)
    }
}

function Save-EditorProfile {
    param([bool]$ConnectAfterSave)

    try {
        Set-EditorMessage "Hidden"
        $result = Get-EditorToml
        $settings = $result.Settings
        $newId = $settings.ProfileId
        $newPath = Join-Path $script:LikewebProfilesDir ($newId + ".toml")
        $certificatePath = Join-Path $script:LikewebCertificatesDir ($newId + ".pem")
        $oldId = $script:EditingProfileId
        $activeIdBefore = Get-LikewebActiveProfileId
        $wasEditing = -not [string]::IsNullOrWhiteSpace($oldId)

        if (
            (Test-Path -LiteralPath $newPath) -and
            ((-not $wasEditing) -or ($oldId -ne $newId))
        ) {
            $overwrite = [System.Windows.Forms.MessageBox]::Show(
                "Сервер с таким служебным именем уже существует. Перезаписать его?",
                "LW TrustTunnel Client",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            if ($overwrite -ne [System.Windows.Forms.DialogResult]::Yes) {
                return
            }
        }

        [System.IO.File]::WriteAllText($newPath, $result.Toml, $script:LikewebUtf8NoBom)

        if ($null -ne $script:SelectedCertificateInfo) {
            [System.IO.File]::WriteAllText(
                $certificatePath,
                $script:SelectedCertificateInfo.Pem + "`r`n",
                $script:LikewebUtf8NoBom
            )
        }
        elseif (Test-Path -LiteralPath $certificatePath) {
            Remove-Item -LiteralPath $certificatePath -Force
        }

        if ($wasEditing -and $oldId -ne $newId) {
            $oldPath = Join-Path $script:LikewebProfilesDir ($oldId + ".toml")
            $oldCertificatePath = Join-Path $script:LikewebCertificatesDir ($oldId + ".pem")
            if (Test-Path -LiteralPath $oldPath) {
                Remove-Item -LiteralPath $oldPath -Force
            }
            if (Test-Path -LiteralPath $oldCertificatePath) {
                Remove-Item -LiteralPath $oldCertificatePath -Force
            }
        }

        if ($ConnectAfterSave) {
            if (Get-LikewebProcess) {
                Set-LikewebOperationState "Disconnecting" $activeIdBefore ""
                [void](Stop-LikewebVpnAndWait)
            }
            Set-LikewebActiveProfile $newPath
            Set-LikewebOperationState "Connecting" $newId $settings.DisplayName
            if (-not (Start-LikewebVpnAndWait)) {
                throw "Сервер сохранен, но подключение не установлено. Проверьте адрес, учетные данные и сертификат."
            }
        }
        elseif ($wasEditing -and $activeIdBefore -eq $oldId) {
            Set-LikewebActiveProfile $newPath
        }

        Clear-LikewebOperationState
        $script:EditingProfileId = $newId
        $script:EditorDirty = $false
        $script:LastProfileSignature = ""
        Show-ServersPage -SkipDiscardCheck
        $successMessage = if ($ConnectAfterSave) {
            "Сервер сохранен и подключен: " + $settings.DisplayName
        }
        else {
            "Сервер сохранен: " + $settings.DisplayName
        }
        Set-ServersMessage "Success" $successMessage
    }
    catch {
        Clear-LikewebOperationState
        Set-EditorMessage "Error" (
            "Не удалось сохранить сервер. Проверьте выделенные поля и повторите. " +
            $_.Exception.Message
        )
        Update-EditorValidation
    }
}

# -------------------- Asynchronous test worker --------------------

function Stop-TestWorker {
    if ($null -ne $script:TestWorkerProcess) {
        try {
            if (-not $script:TestWorkerProcess.HasExited) {
                $script:TestWorkerProcess.Kill()
            }
        }
        catch {}
        $script:TestWorkerProcess.Dispose()
        $script:TestWorkerProcess = $null
    }
}

function Complete-ServerTest {
    param([pscustomobject]$Result)

    $testPollTimer.Stop()
    Stop-TestWorker
    foreach ($temporaryPath in @(
        $script:TestConfigPath,
        $script:TestResultPath,
        $script:TestLogPath
    )) {
        if (-not [string]::IsNullOrWhiteSpace($temporaryPath) -and (Test-Path -LiteralPath $temporaryPath)) {
            try { Remove-Item -LiteralPath $temporaryPath -Force } catch {}
        }
    }
    $testProgress.Visible = $false
    $testDetailsLink.Visible = $false

    if ($null -ne $Result -and $Result.Success) {
        Set-TestStatus "Подключение проверено." "Success"
        $testDetailsSurface.Visible = $false
        $script:LastTestLog = [string]$Result.LogTail
    }
    else {
        $message = "Не удалось подключиться. Проверьте адрес, учетные данные и сертификат."
        if ($null -ne $Result -and -not [string]::IsNullOrWhiteSpace([string]$Result.ErrorMessage)) {
            $message += " " + [string]$Result.ErrorMessage
        }
        Set-TestStatus $message "Error"
        $script:LastTestLog = if ($null -ne $Result) { [string]$Result.LogTail } else { "" }
        $testDetailsLink.Visible = -not [string]::IsNullOrWhiteSpace($script:LastTestLog)
    }

    if ($null -ne $Result -and -not $Result.PreviousConnectionRestored) {
        Set-EditorMessage "Warning" "Проверка завершена, но предыдущее соединение TrustTunnel не восстановлено. Подключите нужный сервер снова."
    }

    Update-EditorValidation
    Update-EditorResponsiveLayout
}

function Start-EditorServerTest {
    try {
        $result = Get-EditorToml
        $workerPath = Join-Path $PSScriptRoot "lwtt_test_worker.ps1"
        if (-not (Test-Path -LiteralPath $workerPath)) {
            throw "Не найден lwtt_test_worker.ps1."
        }

        Stop-TestWorker
        $testRoot = Join-Path $script:LikewebProfilesDir "test"
        if (-not (Test-Path -LiteralPath $testRoot)) {
            [void](New-Item -ItemType Directory -Path $testRoot -Force)
        }

        $token = [Guid]::NewGuid().ToString("N")
        $script:TestConfigPath = Join-Path $testRoot ($token + ".toml")
        $script:TestResultPath = Join-Path $testRoot ($token + ".json")
        $script:TestLogPath = Join-Path $testRoot ($token + ".log")
        [System.IO.File]::WriteAllText(
            $script:TestConfigPath,
            $result.Toml,
            $script:LikewebUtf8NoBom
        )

        $arguments = (
            '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -ConfigPath "{1}" -ResultPath "{2}" -LogPath "{3}"' -f
            $workerPath,
            $script:TestConfigPath,
            $script:TestResultPath,
            $script:TestLogPath
        )

        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = "powershell.exe"
        $startInfo.Arguments = $arguments
        $startInfo.WorkingDirectory = $PSScriptRoot
        $startInfo.UseShellExecute = $true
        $startInfo.Verb = "runas"
        $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

        $script:TestWorkerProcess = [System.Diagnostics.Process]::Start($startInfo)
        $script:TestStartedAt = Get-Date
        $script:LastTestLog = ""
        $testDetailsSurface.Visible = $false
        $testDetailsLink.Visible = $false
        $testProgress.Visible = $true
        Set-TestStatus "Проверяем подключение…" "Loading"
        Update-EditorValidation
        Update-EditorResponsiveLayout
        $testPollTimer.Start()
    }
    catch {
        Stop-TestWorker
        $testProgress.Visible = $false
        Set-TestStatus (
            "Не удалось начать проверку. " + $_.Exception.Message
        ) "Error"
        Update-EditorValidation
        Update-EditorResponsiveLayout
    }
}

function Poll-ServerTest {
    if ($null -eq $script:TestWorkerProcess) {
        $testPollTimer.Stop()
        return
    }

    if (Test-Path -LiteralPath $script:TestResultPath) {
        try {
            $json = [System.IO.File]::ReadAllText($script:TestResultPath)
            $result = $json | ConvertFrom-Json
            Complete-ServerTest $result
        }
        catch {
            Complete-ServerTest ([pscustomobject]@{
                Success = $false
                PreviousConnectionRestored = $true
                ErrorMessage = "Не удалось прочитать результат проверки."
                LogTail = $_.Exception.Message
            })
        }
        return
    }

    if ($script:TestWorkerProcess.HasExited) {
        Complete-ServerTest ([pscustomobject]@{
            Success = $false
            PreviousConnectionRestored = $true
            ErrorMessage = "Процесс проверки завершился без результата."
            LogTail = if (Test-Path -LiteralPath $script:TestLogPath) {
                [System.IO.File]::ReadAllText($script:TestLogPath)
            }
            else { "" }
        })
        return
    }

    if (((Get-Date) - $script:TestStartedAt).TotalSeconds -gt 50) {
        Complete-ServerTest ([pscustomobject]@{
            Success = $false
            PreviousConnectionRestored = $false
            ErrorMessage = "Превышено время ожидания проверки."
            LogTail = if (Test-Path -LiteralPath $script:TestLogPath) {
                [System.IO.File]::ReadAllText($script:TestLogPath)
            }
            else { "" }
        })
    }
}

# -------------------- Form and pages --------------------

$form = New-Object System.Windows.Forms.Form
$form.Text = "LW TrustTunnel Client"
$form.StartPosition = "CenterScreen"
$form.ClientSize = [System.Drawing.Size]::new(1040, 760)
$form.MinimumSize = [System.Drawing.Size]::new(820, 650)
$form.BackColor = $script:ColorWindow
$form.Font = $script:FontBody
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.KeyPreview = $true
$form.ShowIcon = $false

$pagesHost = New-Object System.Windows.Forms.Panel
$pagesHost.Dock = "Fill"
$pagesHost.BackColor = $script:ColorWindow
$form.Controls.Add($pagesHost)

# -------------------- Servers page --------------------

$serversPage = New-Object System.Windows.Forms.Panel
$serversPage.Dock = "Fill"
$serversPage.BackColor = $script:ColorWindow
$pagesHost.Controls.Add($serversPage)

$serversHeader = New-Object System.Windows.Forms.Panel
$serversHeader.Dock = "Top"
$serversHeader.Height = 104
$serversHeader.Padding = [System.Windows.Forms.Padding]::new(24, 20, 24, 12)
$serversHeader.BackColor = $script:ColorWindow

$serversTitleLabel = New-PageLabel "Серверы" "Title"
$serversTitleLabel.Location = [System.Drawing.Point]::new(24, 20)
$serversTitleLabel.TabStop = $true
Set-Accessible $serversTitleLabel "Серверы"
$serversHeader.Controls.Add($serversTitleLabel)

$serversSubtitleLabel = New-PageLabel "Управление подключениями LW TrustTunnel Client" "Secondary"
$serversSubtitleLabel.Location = [System.Drawing.Point]::new(24, 55)
$serversHeader.Controls.Add($serversSubtitleLabel)

$addServerButton = New-FluentButton "Добавить сервер" "Primary" $script:IconAddWhite 166 40 "Добавить сервер" "Открыть добавление нового сервера"
$addServerButton.Anchor = "Top,Right"
$addServerButton.Location = [System.Drawing.Point]::new(850, 24)
$serversHeader.Controls.Add($addServerButton)

$serversHeader.Add_Resize({
    $addServerButton.Left = [Math]::Max(
        24,
        $serversHeader.ClientSize.Width - $addServerButton.Width - 24
    )
})

$serversMessagePanel = New-Object System.Windows.Forms.Panel
$serversMessagePanel.Dock = "Top"
$serversMessagePanel.Height = 48
$serversMessagePanel.Padding = [System.Windows.Forms.Padding]::new(24, 10, 24, 10)
$serversMessagePanel.Visible = $false

$serversMessageIcon = New-Object System.Windows.Forms.PictureBox
$serversMessageIcon.Location = [System.Drawing.Point]::new(26, 14)
$serversMessageIcon.Size = [System.Drawing.Size]::new(20, 20)
$serversMessageIcon.SizeMode = "CenterImage"
$serversMessagePanel.Controls.Add($serversMessageIcon)

$serversMessageLabel = New-PageLabel "" "Body"
$serversMessageLabel.Location = [System.Drawing.Point]::new(56, 12)
$serversMessageLabel.AutoSize = $false
$serversMessageLabel.Size = [System.Drawing.Size]::new(900, 25)
$serversMessageLabel.Anchor = "Top,Left,Right"
$serversMessageLabel.AutoEllipsis = $true
$serversMessagePanel.Controls.Add($serversMessageLabel)

$serversMessageCopyButton = New-MessageCopyButton
$serversMessageCopyButton.Location = [System.Drawing.Point]::new(1216, 8)
$serversMessageCopyButton.Anchor = "Top,Right"
$serversMessagePanel.Controls.Add($serversMessageCopyButton)

$serversMessagePanel.Add_Resize({
    $serversMessageCopyButton.Left = [Math]::Max(60, $serversMessagePanel.ClientSize.Width - $serversMessageCopyButton.Width - 24)
    $serversMessageLabel.Width = [Math]::Max(220, $serversMessageCopyButton.Left - $serversMessageLabel.Left - 12)
})

$serversContent = New-Object System.Windows.Forms.Panel
$serversContent.Dock = "Fill"
$serversContent.Padding = [System.Windows.Forms.Padding]::new(24, 12, 24, 24)
$serversContent.BackColor = $script:ColorWindow

$serversFlow = New-Object System.Windows.Forms.FlowLayoutPanel
try {
    $doubleBufferedProperty = [System.Windows.Forms.Control].GetProperty(
        "DoubleBuffered",
        [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic
    )
    if ($null -ne $doubleBufferedProperty) {
        $doubleBufferedProperty.SetValue($serversFlow, $true, $null)
    }
}
catch {
    # Double buffering is an optimization only; the list works without it.
}
$serversFlow.Dock = "Fill"
$serversFlow.AutoScroll = $true
$serversFlow.FlowDirection = [System.Windows.Forms.FlowDirection]::TopDown
$serversFlow.WrapContents = $false
$serversFlow.BackColor = $script:ColorWindow
$serversFlow.Padding = [System.Windows.Forms.Padding]::new(0, 0, 0, 8)
Set-Accessible $serversFlow "Список серверов"
$serversContent.Controls.Add($serversFlow)

$emptyStatePanel = New-FluentSurface 280 8 $false
$emptyStatePanel.Width = 920
$emptyStatePanel.Margin = [System.Windows.Forms.Padding]::new(0, 12, 0, 0)
$emptyStatePanel.HoverBackColor = $script:ColorSurface

$emptyIcon = New-Object System.Windows.Forms.PictureBox
$emptyIcon.Image = $script:IconServer
$emptyIcon.SizeMode = "CenterImage"
$emptyIcon.Size = [System.Drawing.Size]::new(64, 64)
$emptyStatePanel.Controls.Add($emptyIcon)

$emptyTitle = New-PageLabel "Серверы еще не добавлены" "Section"
$emptyTitle.TextAlign = "MiddleCenter"
$emptyTitle.AutoSize = $false
$emptyTitle.Size = [System.Drawing.Size]::new(420, 30)
$emptyStatePanel.Controls.Add($emptyTitle)

$emptyText = New-PageLabel "Добавьте параметры, полученные от администратора" "Secondary"
$emptyText.TextAlign = "MiddleCenter"
$emptyText.AutoSize = $false
$emptyText.Size = [System.Drawing.Size]::new(480, 26)
$emptyStatePanel.Controls.Add($emptyText)

$emptyAddButton = New-FluentButton "Добавить сервер" "Primary" $script:IconAddWhite 166 40 "Добавить сервер"
$emptyStatePanel.Controls.Add($emptyAddButton)

function Update-EmptyStateLayout {
    $emptyIcon.Left = [int](($emptyStatePanel.ClientSize.Width - $emptyIcon.Width) / 2)
    $emptyIcon.Top = 38
    $emptyTitle.Left = [int](($emptyStatePanel.ClientSize.Width - $emptyTitle.Width) / 2)
    $emptyTitle.Top = 112
    $emptyText.Left = [int](($emptyStatePanel.ClientSize.Width - $emptyText.Width) / 2)
    $emptyText.Top = 148
    $emptyAddButton.Left = [int](($emptyStatePanel.ClientSize.Width - $emptyAddButton.Width) / 2)
    $emptyAddButton.Top = 194
}

$emptyStatePanel.Add_Resize({ Update-EmptyStateLayout })
Update-EmptyStateLayout

$serversPage.Controls.Add($serversContent)
$serversPage.Controls.Add($serversMessagePanel)
$serversPage.Controls.Add($serversHeader)

# -------------------- Editor page --------------------

$editorPage = New-Object System.Windows.Forms.Panel
$editorPage.Dock = "Fill"
$editorPage.BackColor = $script:ColorWindow
$editorPage.Visible = $false
$pagesHost.Controls.Add($editorPage)

$editorHeader = New-Object System.Windows.Forms.Panel
$editorHeader.Dock = "Top"
$editorHeader.Height = 112
$editorHeader.BackColor = $script:ColorWindow

$backButton = New-FluentButton "Назад к серверам" "Subtle" $script:IconBack 166 36 "Назад к серверам" "Вернуться к списку серверов"
$backButton.Location = [System.Drawing.Point]::new(16, 12)
$editorHeader.Controls.Add($backButton)

$editorTitleLabel = New-PageLabel "Новый сервер" "Title"
$editorTitleLabel.Location = [System.Drawing.Point]::new(24, 55)
$editorTitleLabel.MaximumSize = [System.Drawing.Size]::new(900, 30)
$editorHeader.Controls.Add($editorTitleLabel)

$editorSubtitleLabel = New-PageLabel "Вставьте сообщение администратора и добавьте сертификат, если он требуется" "Secondary"
$editorSubtitleLabel.Location = [System.Drawing.Point]::new(24, 87)
$editorSubtitleLabel.MaximumSize = [System.Drawing.Size]::new(900, 24)
$editorHeader.Controls.Add($editorSubtitleLabel)

$editorMessagePanel = New-Object System.Windows.Forms.Panel
$editorMessagePanel.Dock = "Top"
$editorMessagePanel.Height = 48
$editorMessagePanel.Visible = $false

$editorMessageIcon = New-Object System.Windows.Forms.PictureBox
$editorMessageIcon.Location = [System.Drawing.Point]::new(26, 14)
$editorMessageIcon.Size = [System.Drawing.Size]::new(20, 20)
$editorMessageIcon.SizeMode = "CenterImage"
$editorMessagePanel.Controls.Add($editorMessageIcon)

$editorMessageLabel = New-PageLabel "" "Body"
$editorMessageLabel.Location = [System.Drawing.Point]::new(56, 12)
$editorMessageLabel.AutoSize = $false
$editorMessageLabel.Size = [System.Drawing.Size]::new(900, 25)
$editorMessageLabel.Anchor = "Top,Left,Right"
$editorMessageLabel.AutoEllipsis = $true
$editorMessagePanel.Controls.Add($editorMessageLabel)

$editorMessageCopyButton = New-MessageCopyButton
$editorMessageCopyButton.Location = [System.Drawing.Point]::new(916, 8)
$editorMessageCopyButton.Anchor = "Top,Right"
$editorMessagePanel.Controls.Add($editorMessageCopyButton)

$editorMessagePanel.Add_Resize({
    $editorMessageCopyButton.Left = [Math]::Max(60, $editorMessagePanel.ClientSize.Width - $editorMessageCopyButton.Width - 24)
    $editorMessageLabel.Width = [Math]::Max(220, $editorMessageCopyButton.Left - $editorMessageLabel.Left - 12)
})

$editorFooter = New-Object System.Windows.Forms.Panel
$editorFooter.Dock = "Bottom"
$editorFooter.Height = 82
$editorFooter.BackColor = $script:ColorSurface
$editorFooter.Padding = [System.Windows.Forms.Padding]::new(24, 18, 24, 18)
$editorFooter.Add_Paint({
    param($sender, $eventArgs)
    $pen = [System.Drawing.Pen]::new($script:ColorBorder, 1)
    $eventArgs.Graphics.DrawLine($pen, 0, 0, $sender.Width, 0)
    $pen.Dispose()
})

$testButton = New-FluentButton "Проверить сервер" "Secondary" $script:IconSearch 154 40 "Проверить сервер" "Проверить подключение без сохранения профиля"
$testButton.Location = [System.Drawing.Point]::new(24, 20)
$editorFooter.Controls.Add($testButton)

$testStatusPanel = New-Object System.Windows.Forms.Panel
$testStatusPanel.BackColor = [System.Drawing.Color]::Transparent
$testStatusPanel.Height = 44
$testStatusPanel.Location = [System.Drawing.Point]::new(194, 18)
$editorFooter.Controls.Add($testStatusPanel)

$testStatusIcon = New-Object System.Windows.Forms.PictureBox
$testStatusIcon.Location = [System.Drawing.Point]::new(0, 12)
$testStatusIcon.Size = [System.Drawing.Size]::new(20, 20)
$testStatusIcon.SizeMode = "CenterImage"
$testStatusPanel.Controls.Add($testStatusIcon)

$testStatusLabel = New-PageLabel "Сервер еще не проверен." "Secondary"
$testStatusLabel.AutoSize = $false
$testStatusLabel.Location = [System.Drawing.Point]::new(28, 0)
$testStatusLabel.Size = [System.Drawing.Size]::new(240, 40)
$testStatusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$testStatusLabel.AutoEllipsis = $true
$testStatusPanel.Controls.Add($testStatusLabel)

$testDetailsLink = New-Object System.Windows.Forms.LinkLabel
$testDetailsLink.Text = "Показать подробности"
$testDetailsLink.Font = $script:FontSecondary
$testDetailsLink.LinkColor = $script:ColorAccent
$testDetailsLink.AutoSize = $true
$testDetailsLink.Visible = $false
$testDetailsLink.Anchor = "Top,Right"
Set-Accessible $testDetailsLink "Показать подробности проверки"
$testStatusPanel.Controls.Add($testDetailsLink)

$testProgress = New-Object System.Windows.Forms.ProgressBar
$testProgress.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
$testProgress.MarqueeAnimationSpeed = 25
$testProgress.Height = 4
$testProgress.Visible = $false
$testProgress.AccessibleName = "Проверяем подключение"
$testStatusPanel.Controls.Add($testProgress)

$footerActions = New-Object System.Windows.Forms.Panel
$footerActions.Size = [System.Drawing.Size]::new(520, 44)
$footerActions.Anchor = "Top,Right"
$footerActions.Location = [System.Drawing.Point]::new($form.ClientSize.Width - 544, 18)
$footerActions.BackColor = $script:ColorSurface

$cancelButton = New-FluentButton "Отмена" "Subtle" $script:IconCancel 92 40 "Отмена" "Вернуться без сохранения"
$cancelButton.Top = 2
$footerActions.Controls.Add($cancelButton)

$saveButton = New-FluentButton "Сохранить" "Secondary" $script:IconSave 110 40 "Сохранить сервер" "Сохранить профиль без подключения"
$saveButton.Top = 2
$footerActions.Controls.Add($saveButton)

$saveConnectButton = New-FluentButton "Сохранить и подключить" "Primary" $script:IconSaveWhite 184 40 "Сохранить и подключить" "Сохранить профиль и сразу подключиться"
$saveConnectButton.Top = 2
$footerActions.Controls.Add($saveConnectButton)

$footerActions.Width = (
    $saveConnectButton.Width +
    $saveButton.Width +
    $cancelButton.Width +
    34
)

$editorFooter.Controls.Add($footerActions)

$editorScrollPanel = New-Object System.Windows.Forms.Panel
$editorScrollPanel.Dock = "Fill"
$editorScrollPanel.AutoScroll = $true
$editorScrollPanel.BackColor = $script:ColorWindow
Set-Accessible $editorScrollPanel "Параметры сервера"

$editorContentHost = New-Object System.Windows.Forms.Panel
$editorContentHost.BackColor = $script:ColorWindow
$editorContentHost.Location = [System.Drawing.Point]::new(24, 16)
$editorContentHost.Width = 980
$editorContentHost.Height = 1100
$editorScrollPanel.Controls.Add($editorContentHost)

$editorPage.Controls.Add($editorScrollPanel)
$editorPage.Controls.Add($editorFooter)
$editorPage.Controls.Add($editorMessagePanel)
$editorPage.Controls.Add($editorHeader)

$editorLoadingOverlay = New-Object System.Windows.Forms.Panel
$editorLoadingOverlay.Dock = "Fill"
$editorLoadingOverlay.BackColor = $script:ColorWindow
$editorLoadingOverlay.Visible = $false
$editorPage.Controls.Add($editorLoadingOverlay)

$editorLoadingCard = New-FluentSurface 132 8 $false
$editorLoadingCard.Width = 360
$editorLoadingCard.Height = 132
$editorLoadingOverlay.Controls.Add($editorLoadingCard)

$editorLoadingLabel = New-PageLabel "Загружаем параметры сервера…" "Section"
$editorLoadingLabel.AutoSize = $false
$editorLoadingLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$editorLoadingLabel.Size = [System.Drawing.Size]::new(320, 32)
$editorLoadingLabel.Location = [System.Drawing.Point]::new(20, 26)
$editorLoadingCard.Controls.Add($editorLoadingLabel)

$editorLoadingProgress = New-Object System.Windows.Forms.ProgressBar
$editorLoadingProgress.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
$editorLoadingProgress.MarqueeAnimationSpeed = 25
$editorLoadingProgress.Size = [System.Drawing.Size]::new(300, 8)
$editorLoadingProgress.Location = [System.Drawing.Point]::new(30, 76)
$editorLoadingCard.Controls.Add($editorLoadingProgress)

$editorLoadingOverlay.Add_Resize({
    $editorLoadingCard.Left = [Math]::Max(0, [int](($editorLoadingOverlay.ClientSize.Width - $editorLoadingCard.Width) / 2))
    $editorLoadingCard.Top = [Math]::Max(0, [int](($editorLoadingOverlay.ClientSize.Height - $editorLoadingCard.Height) / 2))
})

function Set-EditorLoadingOverlay {
    param([bool]$Visible)

    $editorLoadingOverlay.Visible = $Visible
    if ($Visible) {
        $editorLoadingProgress.MarqueeAnimationSpeed = 25
        $editorLoadingOverlay.BringToFront()
        $editorLoadingOverlay.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
    }
    else {
        $editorLoadingProgress.MarqueeAnimationSpeed = 0
        $editorLoadingOverlay.SendToBack()
    }
}

# -------------------- Editor: settings section --------------------

$settingsSurface = New-FluentSurface 296 8 $false
$settingsSurface.Location = [System.Drawing.Point]::new(0, 0)
$settingsSurface.Anchor = "Top,Left,Right"
$editorContentHost.Controls.Add($settingsSurface)

$settingsTitle = New-PageLabel "Настройки сервера" "Section"
$settingsTitle.Location = [System.Drawing.Point]::new(16, 16)
$settingsSurface.Controls.Add($settingsTitle)

$pasteButton = New-FluentButton "Вставить из буфера" "Subtle" $script:IconPaste 158 32 "Вставить из буфера" "Вставить текст настроек из буфера обмена"
$pasteButton.Anchor = "Top,Right"
$settingsSurface.Controls.Add($pasteButton)

$messageTextBox = New-Object System.Windows.Forms.TextBox
$messageTextBox.Multiline = $true
$messageTextBox.ScrollBars = "Vertical"
$messageTextBox.Font = $script:FontBody
$messageTextBox.Location = [System.Drawing.Point]::new(16, 54)
$messageTextBox.Size = [System.Drawing.Size]::new(900, 142)
$messageTextBox.Anchor = "Top,Left,Right"
$messageTextBox.BorderStyle = "FixedSingle"
$messageTextBox.AcceptsReturn = $true
$messageTextBox.AcceptsTab = $false
$messageTextBox.AccessibleName = "Сообщение с настройками сервера"
$settingsSurface.Controls.Add($messageTextBox)

$parseButton = New-FluentButton "Распознать настройки" "Secondary" $script:IconSearch 184 36 "Распознать настройки"
$parseButton.Location = [System.Drawing.Point]::new(16, 212)
$settingsSurface.Controls.Add($parseButton)

$recognitionStatusPanel = New-Object System.Windows.Forms.Panel
$recognitionStatusPanel.BackColor = [System.Drawing.Color]::Transparent
$recognitionStatusPanel.Height = 38
$recognitionStatusPanel.Anchor = "Top,Left,Right"
$settingsSurface.Controls.Add($recognitionStatusPanel)

$recognitionStatusIcon = New-Object System.Windows.Forms.PictureBox
$recognitionStatusIcon.Location = [System.Drawing.Point]::new(0, 9)
$recognitionStatusIcon.Size = [System.Drawing.Size]::new(20, 20)
$recognitionStatusIcon.SizeMode = "CenterImage"
$recognitionStatusPanel.Controls.Add($recognitionStatusIcon)

$recognitionStatusLabel = New-PageLabel "Вставьте сообщение с параметрами сервера." "Secondary"
$recognitionStatusLabel.Location = [System.Drawing.Point]::new(28, 0)
$recognitionStatusLabel.Size = [System.Drawing.Size]::new(620, 38)
$recognitionStatusLabel.AutoSize = $false
$recognitionStatusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$recognitionStatusLabel.Anchor = "Top,Left,Right"
$recognitionStatusLabel.AutoEllipsis = $true
$recognitionStatusPanel.Controls.Add($recognitionStatusLabel)

# -------------------- Editor: certificate section --------------------

$certificateSurface = New-FluentSurface 296 8 $false
$certificateSurface.Anchor = "Top,Left,Right"
$editorContentHost.Controls.Add($certificateSurface)

$certificateTitle = New-PageLabel "Сертификат" "Section"
$certificateTitle.Location = [System.Drawing.Point]::new(16, 16)
$certificateSurface.Controls.Add($certificateTitle)

$certificateDropPanel = New-FluentSurface 106 8 $false
$certificateDropPanel.Location = [System.Drawing.Point]::new(16, 50)
$certificateDropPanel.Anchor = "Top,Left,Right"
$certificateDropPanel.AllowDrop = $false
$certificateDropPanel.BorderColor = [System.Drawing.Color]::FromArgb(150, 180, 210)
$certificateDropPanel.NormalBackColor = $script:ColorInfoSurface
$certificateDropPanel.HoverBackColor = [System.Drawing.Color]::FromArgb(235, 244, 252)
$certificateDropPanel.BackColor = $certificateDropPanel.NormalBackColor
$certificateDropPanel.Cursor = [System.Windows.Forms.Cursors]::Hand
$certificateSurface.Controls.Add($certificateDropPanel)

$certificateEmptyPanel = New-Object System.Windows.Forms.Panel
$certificateEmptyPanel.Dock = "Fill"
$certificateEmptyPanel.BackColor = [System.Drawing.Color]::Transparent
$certificateDropPanel.Controls.Add($certificateEmptyPanel)

$certificateEmptyIcon = New-Object System.Windows.Forms.PictureBox
$certificateEmptyIcon.Image = $script:IconCertificate
$certificateEmptyIcon.SizeMode = "CenterImage"
$certificateEmptyIcon.Size = [System.Drawing.Size]::new(32, 32)
$certificateEmptyPanel.Controls.Add($certificateEmptyIcon)

$certificateEmptyText = New-PageLabel "Выберите файл сертификата .pem" "Semibold"
$certificateEmptyText.AutoSize = $false
$certificateEmptyText.TextAlign = "MiddleCenter"
$certificateEmptyText.Size = [System.Drawing.Size]::new(320, 24)
$certificateEmptyPanel.Controls.Add($certificateEmptyText)

$certificateOrText = New-PageLabel "или" "Secondary"
$certificateOrText.AutoSize = $false
$certificateOrText.TextAlign = "MiddleCenter"
$certificateOrText.Size = [System.Drawing.Size]::new(36, 22)
$certificateEmptyPanel.Controls.Add($certificateOrText)

$chooseCertificateButton = New-FluentButton "Выбрать файл" "Secondary" $null 122 32 "Выбрать сертификат"
$certificateEmptyPanel.Controls.Add($chooseCertificateButton)

$certificateFilePanel = New-Object System.Windows.Forms.Panel
$certificateFilePanel.Dock = "Fill"
$certificateFilePanel.BackColor = [System.Drawing.Color]::Transparent
$certificateFilePanel.Visible = $false
$certificateDropPanel.Controls.Add($certificateFilePanel)

$certificateFileIcon = New-Object System.Windows.Forms.PictureBox
$certificateFileIcon.Image = $script:IconFile
$certificateFileIcon.SizeMode = "CenterImage"
$certificateFileIcon.Location = [System.Drawing.Point]::new(18, 25)
$certificateFileIcon.Size = [System.Drawing.Size]::new(36, 36)
$certificateFilePanel.Controls.Add($certificateFileIcon)

$certificateFileNameLabel = New-PageLabel "certificate.pem" "Semibold"
$certificateFileNameLabel.Location = [System.Drawing.Point]::new(66, 18)
$certificateFileNameLabel.Size = [System.Drawing.Size]::new(520, 24)
$certificateFileNameLabel.AutoSize = $false
$certificateFileNameLabel.AutoEllipsis = $true
$certificateFilePanel.Controls.Add($certificateFileNameLabel)

$certificateFileDetailsLabel = New-PageLabel "Сертификат" "Secondary"
$certificateFileDetailsLabel.Location = [System.Drawing.Point]::new(66, 48)
$certificateFileDetailsLabel.Size = [System.Drawing.Size]::new(520, 22)
$certificateFileDetailsLabel.AutoSize = $false
$certificateFileDetailsLabel.AutoEllipsis = $true
$certificateFilePanel.Controls.Add($certificateFileDetailsLabel)

$replaceCertificateButton = New-FluentButton "Заменить" "Subtle" $null 94 32 "Заменить сертификат"
$replaceCertificateButton.Anchor = "Top,Right"
$certificateFilePanel.Controls.Add($replaceCertificateButton)

$removeCertificateButton = New-FluentButton "Удалить" "Subtle" $null 86 32 "Удалить сертификат"
$removeCertificateButton.ForeColor = $script:ColorError
$removeCertificateButton.Anchor = "Top,Right"
$certificateFilePanel.Controls.Add($removeCertificateButton)

$certificateStatusPanel = New-Object System.Windows.Forms.Panel
$certificateStatusPanel.BackColor = [System.Drawing.Color]::Transparent
$certificateStatusPanel.Height = 38
$certificateStatusPanel.Anchor = "Top,Left,Right"
$certificateSurface.Controls.Add($certificateStatusPanel)

$certificateStatusIcon = New-Object System.Windows.Forms.PictureBox
$certificateStatusIcon.Location = [System.Drawing.Point]::new(0, 9)
$certificateStatusIcon.Size = [System.Drawing.Size]::new(20, 20)
$certificateStatusIcon.SizeMode = "CenterImage"
$certificateStatusPanel.Controls.Add($certificateStatusIcon)

$certificateStatusLabel = New-PageLabel "Выберите файл .pem вручную кнопкой выше." "Secondary"
$certificateStatusLabel.Location = [System.Drawing.Point]::new(28, 0)
$certificateStatusLabel.Size = [System.Drawing.Size]::new(620, 38)
$certificateStatusLabel.AutoSize = $false
$certificateStatusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$certificateStatusLabel.Anchor = "Top,Left,Right"
$certificateStatusLabel.AutoEllipsis = $true
$certificateStatusPanel.Controls.Add($certificateStatusLabel)

# -------------------- Editor: summary --------------------

$summarySurface = New-FluentSurface 192 8 $false
$summarySurface.Anchor = "Top,Left,Right"
$summarySurface.Visible = $false
$editorContentHost.Controls.Add($summarySurface)

$summaryTitle = New-PageLabel "Распознанные параметры" "Section"
$summaryTitle.Location = [System.Drawing.Point]::new(16, 16)
$summarySurface.Controls.Add($summaryTitle)

$summaryTable = New-Object System.Windows.Forms.TableLayoutPanel
$summaryTable.Location = [System.Drawing.Point]::new(16, 52)
$summaryTable.Size = [System.Drawing.Size]::new(900, 122)
$summaryTable.Anchor = "Top,Left,Right"
$summaryTable.ColumnCount = 2
$summaryTable.RowCount = 5
$summaryTable.ColumnStyles.Add(([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Absolute, [single]150)))
$summaryTable.ColumnStyles.Add(([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, [single]100)))
for ($i = 0; $i -lt 5; $i++) {
    $summaryTable.RowStyles.Add(([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Absolute, [single]24)))
}
$summarySurface.Controls.Add($summaryTable)

function Add-SummaryRow {
    param([int]$Row, [string]$Caption)
    $captionLabel = New-PageLabel $Caption "Secondary"
    $captionLabel.Dock = "Fill"
    $captionLabel.TextAlign = "MiddleLeft"
    $valueLabel = New-PageLabel "" "Body"
    $valueLabel.Dock = "Fill"
    $valueLabel.TextAlign = "MiddleLeft"
    $valueLabel.AutoEllipsis = $true
    $summaryTable.Controls.Add($captionLabel, 0, $Row)
    $summaryTable.Controls.Add($valueLabel, 1, $Row)
    return $valueLabel
}

$summaryNameValue = Add-SummaryRow 0 "Название"
$summaryAddressValue = Add-SummaryRow 1 "Адрес"
$summaryProtocolValue = Add-SummaryRow 2 "Протокол"
$summaryIpv6Value = Add-SummaryRow 3 "IPv6"
$summaryCertificateValue = Add-SummaryRow 4 "Сертификат"

# -------------------- Editor: advanced settings --------------------

$advancedToggleButton = New-FluentButton "Расширенные настройки" "Subtle" $script:IconChevronDown 230 44 "Расширенные настройки" "Показать или скрыть технические параметры"
$advancedToggleButton.Anchor = "Top,Left"
$advancedToggleButton.TextAlign = "MiddleLeft"
$editorContentHost.Controls.Add($advancedToggleButton)

$advancedFieldsPanel = New-FluentSurface 420 8 $false
$advancedFieldsPanel.Anchor = "Top,Left,Right"
$advancedFieldsPanel.Visible = $false
$editorContentHost.Controls.Add($advancedFieldsPanel)

$advancedTitle = New-PageLabel "Технические параметры" "Section"
$advancedTitle.Location = [System.Drawing.Point]::new(16, 16)
$advancedFieldsPanel.Controls.Add($advancedTitle)

$advancedGrid = New-Object System.Windows.Forms.TableLayoutPanel
$advancedGrid.Location = [System.Drawing.Point]::new(16, 50)
$advancedGrid.Anchor = "Top,Left,Right"
$advancedGrid.AutoSize = $false
$advancedGrid.GrowStyle = [System.Windows.Forms.TableLayoutPanelGrowStyle]::AddRows
$advancedFieldsPanel.Controls.Add($advancedGrid)

$errorProvider = New-Object System.Windows.Forms.ErrorProvider
$errorProvider.BlinkStyle = [System.Windows.Forms.ErrorBlinkStyle]::NeverBlink
$errorProvider.ContainerControl = $form
$script:FieldErrorLabels = @{}
$script:AdvancedFieldContainers = New-Object System.Collections.Generic.List[object]

function New-AdvancedField {
    param(
        [string]$Key,
        [string]$Caption,
        [System.Windows.Forms.Control]$InputControl,
        [string]$HelperText = ""
    )

    $container = New-Object System.Windows.Forms.Panel
    $container.Height = 86
    $container.Margin = [System.Windows.Forms.Padding]::new(0, 0, 16, 8)
    $container.BackColor = [System.Drawing.Color]::Transparent

    $captionLabel = New-PageLabel $Caption "Body"
    $captionLabel.Location = [System.Drawing.Point]::new(0, 0)
    $container.Controls.Add($captionLabel)

    $InputControl.Location = [System.Drawing.Point]::new(0, 24)
    $InputControl.Anchor = "Top,Left,Right"
    $InputControl.Width = 390
    $container.Controls.Add($InputControl)

    $errorLabel = New-PageLabel "" "Secondary"
    $errorLabel.ForeColor = $script:ColorError
    $errorLabel.Location = [System.Drawing.Point]::new(0, 57)
    $errorLabel.Size = [System.Drawing.Size]::new(390, 22)
    $errorLabel.AutoSize = $false
    $errorLabel.AutoEllipsis = $true
    $errorLabel.Visible = $false
    $errorLabel.Anchor = "Top,Left,Right"
    $container.Controls.Add($errorLabel)

    if (-not [string]::IsNullOrWhiteSpace($HelperText)) {
        $script:UiToolTip.SetToolTip($InputControl, $HelperText)
        $InputControl.AccessibleDescription = $HelperText
    }

    $script:FieldErrorLabels[$Key] = $errorLabel
    $script:AdvancedFieldContainers.Add([pscustomobject]@{
        Key = $Key
        Container = $container
        Input = $InputControl
    })
}

$displayNameTextBox = New-Object System.Windows.Forms.TextBox
$displayNameTextBox.Font = $script:FontBody
$displayNameTextBox.AccessibleName = "Название сервера"
New-AdvancedField "DisplayName" "Название сервера" $displayNameTextBox "Название, которое пользователь увидит в списке"

$serverNameTextBox = New-Object System.Windows.Forms.TextBox
$serverNameTextBox.Font = $script:FontBody
$serverNameTextBox.AccessibleName = "Служебное имя сервера"
New-AdvancedField "ServerName" "Служебное имя" $serverNameTextBox "Используется в имени файла профиля"

$addressTextBox = New-Object System.Windows.Forms.TextBox
$addressTextBox.Font = $script:FontBody
$addressTextBox.AccessibleName = "Адрес сервера"
New-AdvancedField "Address" "Адрес" $addressTextBox "Например, vpn.example.org:443"

$hostnameTextBox = New-Object System.Windows.Forms.TextBox
$hostnameTextBox.Font = $script:FontBody
$hostnameTextBox.AccessibleName = "Домен сертификата"
New-AdvancedField "Hostname" "Домен сертификата" $hostnameTextBox "Имя, указанное в сертификате сервера"

$usernameTextBox = New-Object System.Windows.Forms.TextBox
$usernameTextBox.Font = $script:FontBody
$usernameTextBox.AccessibleName = "Имя пользователя"
New-AdvancedField "Username" "Имя пользователя" $usernameTextBox

$passwordHost = New-Object System.Windows.Forms.Panel
$passwordHost.Height = 28
$passwordHost.BackColor = [System.Drawing.Color]::Transparent

$passwordTextBox = New-Object System.Windows.Forms.TextBox
$passwordTextBox.Font = $script:FontBody
$passwordTextBox.UseSystemPasswordChar = $true
$passwordTextBox.Location = [System.Drawing.Point]::new(0, 0)
$passwordTextBox.Height = 28
$passwordTextBox.Anchor = "Top,Left,Right"
$passwordTextBox.AccessibleName = "Пароль"
$passwordHost.Controls.Add($passwordTextBox)

$passwordToggleButton = New-FluentButton "" "Icon" $script:IconEye 32 28 "Показать пароль" "Показать пароль"
$passwordToggleButton.Anchor = "Top,Right"
$passwordHost.Controls.Add($passwordToggleButton)
$passwordHost.Add_Resize({
    $passwordToggleButton.Left = $passwordHost.ClientSize.Width - $passwordToggleButton.Width
    $passwordTextBox.Width = [Math]::Max(80, $passwordToggleButton.Left - 6)
})
New-AdvancedField "Password" "Пароль" $passwordHost

$protocolComboBox = New-Object System.Windows.Forms.ComboBox
$protocolComboBox.Font = $script:FontBody
$protocolComboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
[void]$protocolComboBox.Items.Add("HTTP/2")
[void]$protocolComboBox.Items.Add("HTTP/3")
$protocolComboBox.SelectedItem = "HTTP/2"
$protocolComboBox.AccessibleName = "Протокол"
New-AdvancedField "Protocol" "Протокол" $protocolComboBox

$optionsHost = New-Object System.Windows.Forms.FlowLayoutPanel
$optionsHost.FlowDirection = [System.Windows.Forms.FlowDirection]::TopDown
$optionsHost.WrapContents = $false
$optionsHost.AutoSize = $false
$optionsHost.Height = 56
$optionsHost.BackColor = [System.Drawing.Color]::Transparent

$ipv6CheckBox = New-Object System.Windows.Forms.CheckBox
$ipv6CheckBox.Text = "Разрешить IPv6 через сервер"
$ipv6CheckBox.Checked = $true
$ipv6CheckBox.AutoSize = $true
$ipv6CheckBox.Font = $script:FontBody
$ipv6CheckBox.AccessibleName = "Разрешить IPv6"
$optionsHost.Controls.Add($ipv6CheckBox)

$embedCertificateCheckBox = New-Object System.Windows.Forms.CheckBox
$embedCertificateCheckBox.Text = "Встроить PEM в конфигурацию"
$embedCertificateCheckBox.AutoSize = $true
$embedCertificateCheckBox.Font = $script:FontBody
$embedCertificateCheckBox.AccessibleName = "Встроить сертификат"
$optionsHost.Controls.Add($embedCertificateCheckBox)
New-AdvancedField "Options" "Дополнительно" $optionsHost

# -------------------- Editor: test details --------------------

$testDetailsSurface = New-FluentSurface 214 8 $false
$testDetailsSurface.Anchor = "Top,Left,Right"
$testDetailsSurface.Visible = $false
$editorContentHost.Controls.Add($testDetailsSurface)

$testDetailsTitle = New-PageLabel "Подробности проверки" "Section"
$testDetailsTitle.Location = [System.Drawing.Point]::new(16, 16)
$testDetailsSurface.Controls.Add($testDetailsTitle)

$hideTestDetailsButton = New-FluentButton "Скрыть" "Subtle" $null 72 32 "Скрыть подробности"
$hideTestDetailsButton.Anchor = "Top,Right"
$testDetailsSurface.Controls.Add($hideTestDetailsButton)

$testDetailsTextBox = New-Object System.Windows.Forms.TextBox
$testDetailsTextBox.Multiline = $true
$testDetailsTextBox.ReadOnly = $true
$testDetailsTextBox.ScrollBars = "Both"
$testDetailsTextBox.WordWrap = $false
$testDetailsTextBox.Font = [System.Drawing.Font]::new("Consolas", 9.0)
$testDetailsTextBox.Location = [System.Drawing.Point]::new(16, 54)
$testDetailsTextBox.Anchor = "Top,Left,Right,Bottom"
$testDetailsTextBox.Size = [System.Drawing.Size]::new(900, 140)
$testDetailsTextBox.AccessibleName = "Технический журнал проверки"
$testDetailsSurface.Controls.Add($testDetailsTextBox)

# -------------------- Responsive layout --------------------

function Update-AdvancedGridLayout {
    if ($null -eq $advancedGrid) {
        return
    }

    $available = [Math]::Max(500, $advancedFieldsPanel.ClientSize.Width - 32)
    $twoColumns = $available -ge 760
    $columns = if ($twoColumns) { 2 } else { 1 }
    $rows = [int][Math]::Ceiling($script:AdvancedFieldContainers.Count / [double]$columns)

    $advancedGrid.SuspendLayout()
    try {
        $advancedGrid.Controls.Clear()
        $advancedGrid.ColumnStyles.Clear()
        $advancedGrid.RowStyles.Clear()
        $advancedGrid.ColumnCount = $columns
        $advancedGrid.RowCount = $rows
        $advancedGrid.Width = $available

        for ($column = 0; $column -lt $columns; $column++) {
            $advancedGrid.ColumnStyles.Add(
                ([System.Windows.Forms.ColumnStyle]::new(
                    [System.Windows.Forms.SizeType]::Percent,
                    [single](100 / $columns)
                ))
            )
        }

        for ($row = 0; $row -lt $rows; $row++) {
            $advancedGrid.RowStyles.Add(
                ([System.Windows.Forms.RowStyle]::new(
                    [System.Windows.Forms.SizeType]::Absolute,
                    [single]94
                ))
            )
        }

        $columnWidth = [int]($available / $columns)
        for ($i = 0; $i -lt $script:AdvancedFieldContainers.Count; $i++) {
            $item = $script:AdvancedFieldContainers[$i]
            $row = [int][Math]::Floor($i / $columns)
            $column = $i % $columns
            $item.Container.Width = $columnWidth - 12
            $item.Container.Dock = "Fill"
            $item.Input.Width = [Math]::Max(180, $item.Container.Width - 8)
            $advancedGrid.Controls.Add($item.Container, $column, $row)
        }

        $advancedGrid.Height = $rows * 94
        $advancedFieldsPanel.Height = 50 + $advancedGrid.Height + 18
    }
    finally {
        $advancedGrid.ResumeLayout()
    }
}

function Update-EditorContentLayout {
    if ($null -eq $editorContentHost) {
        return
    }

    $gap = 24
    $y = 0
    $isEditing = -not [string]::IsNullOrWhiteSpace($script:EditingProfileId)

    if ($isEditing) {
        # The edit page contains only the full technical form. The text-import
        # and certificate cards belong to the add-server workflow and are
        # intentionally hidden here.
        $settingsSurface.Visible = $false
        $certificateSurface.Visible = $false
        $summarySurface.Visible = $false
        $advancedToggleButton.Visible = $false
        $advancedFieldsPanel.Visible = $true
        $script:AdvancedVisible = $true

        Update-AdvancedGridLayout
        $advancedFieldsPanel.Left = 0
        $advancedFieldsPanel.Top = 0
        $y = $advancedFieldsPanel.Height + $gap
    }
    else {
        $settingsSurface.Visible = $true
        $certificateSurface.Visible = $true
        $advancedToggleButton.Visible = $true

        $useTwoColumns = $editorContentHost.Width -ge 880
        if ($useTwoColumns) {
            $settingsSurface.Left = 0
            $settingsSurface.Top = 0
            $certificateSurface.Left = $settingsSurface.Width + $gap
            $certificateSurface.Top = 0
            $y = [Math]::Max(
                $settingsSurface.Bottom,
                $certificateSurface.Bottom
            ) + $gap
        }
        else {
            $settingsSurface.Left = 0
            $settingsSurface.Top = $y
            $y += $settingsSurface.Height + $gap

            $certificateSurface.Left = 0
            $certificateSurface.Top = $y
            $y += $certificateSurface.Height + $gap
        }

        # Keep the entry to all fields directly below the import cards so it
        # remains visible even after the recognition summary appears.
        $advancedToggleButton.Top = $y
        $advancedToggleButton.Left = 0
        $y += $advancedToggleButton.Height + 8

        if ($advancedFieldsPanel.Visible) {
            Update-AdvancedGridLayout
            $advancedFieldsPanel.Left = 0
            $advancedFieldsPanel.Top = $y
            $y += $advancedFieldsPanel.Height + $gap
        }

        if ($summarySurface.Visible) {
            $summarySurface.Left = 0
            $summarySurface.Top = $y
            $y += $summarySurface.Height + $gap
        }
    }

    if ($testDetailsSurface.Visible) {
        $testDetailsSurface.Left = 0
        $testDetailsSurface.Top = $y
        $y += $testDetailsSurface.Height + $gap
    }

    # Reserve a scroll-safe area beneath the last field. Some WinForms/DPI
    # combinations draw the docked footer over the Fill panel; the extra space
    # guarantees that the last controls can be scrolled fully above it.
    $footerSafeArea = [Math]::Max(112, $editorFooter.Height + 40)
    $requiredHeight = $y + $footerSafeArea
    $editorContentHost.Height = [Math]::Max(
        $requiredHeight,
        $editorScrollPanel.ClientSize.Height - 32
    )
    $editorScrollPanel.AutoScrollMinSize = [System.Drawing.Size]::new(
        0,
        $editorContentHost.Height + 16
    )
}

function Update-EditorResponsiveLayout {
    if ($null -eq $editorScrollPanel) {
        return
    }

    $viewportWidth = $editorScrollPanel.ClientSize.Width
    $contentWidth = [Math]::Min(
        1040,
        [Math]::Max(680, $viewportWidth - 48)
    )
    $editorContentHost.Width = $contentWidth
    $editorContentHost.Left = [Math]::Max(
        24,
        [int](($viewportWidth - $contentWidth) / 2)
    )

    $useTwoColumns = $contentWidth -ge 880
    $columnGap = 24

    if ($useTwoColumns) {
        $columnWidth = [int](($contentWidth - $columnGap) / 2)
        $settingsSurface.Width = $columnWidth
        $certificateSurface.Width = $contentWidth - $columnWidth - $columnGap
    }
    else {
        $settingsSurface.Width = $contentWidth
        $certificateSurface.Width = $contentWidth
    }

    foreach ($surface in @(
        $summarySurface,
        $advancedFieldsPanel,
        $testDetailsSurface
    )) {
        $surface.Width = $contentWidth
    }

    $advancedToggleButton.Width = [Math]::Min(280, $contentWidth)

    # Settings section. The paste command shares the title row; the text
    # editor starts below it and keeps a stable layout at higher DPI.
    $settingsSurface.Height = 296
    $pasteButton.Top = 8
    $pasteButton.Left = $settingsSurface.ClientSize.Width - $pasteButton.Width - 16

    $messageTextBox.Left = 16
    $messageTextBox.Top = 54
    $messageTextBox.Width = $settingsSurface.ClientSize.Width - 32
    $messageTextBox.Height = 142

    $parseButton.Left = 16
    $parseButton.Top = 208

    $recognitionStatusPanel.Left = 16
    $recognitionStatusPanel.Top = 246
    $recognitionStatusPanel.Width = [Math]::Max(
        180,
        $settingsSurface.ClientSize.Width - 32
    )
    $recognitionStatusLabel.Width = [Math]::Max(
        140,
        $recognitionStatusPanel.ClientSize.Width - 28
    )

    # Certificate section, equal in height to the settings section.
    $certificateSurface.Height = 296
    $certificateDropPanel.Left = 16
    $certificateDropPanel.Top = 52
    $certificateDropPanel.Width = $certificateSurface.ClientSize.Width - 32
    $certificateDropPanel.Height = 170

    $certificateStatusPanel.Left = 16
    $certificateStatusPanel.Top = 240
    $certificateStatusPanel.Width = [Math]::Max(
        180,
        $certificateSurface.ClientSize.Width - 32
    )
    $certificateStatusLabel.Width = [Math]::Max(
        140,
        $certificateStatusPanel.ClientSize.Width - 28
    )

    $emptyWidth = $certificateDropPanel.ClientSize.Width
    $certificateEmptyIcon.Left = [int](
        ($emptyWidth - $certificateEmptyIcon.Width) / 2
    )
    $certificateEmptyIcon.Top = 16
    $certificateEmptyText.Left = [int](
        ($emptyWidth - $certificateEmptyText.Width) / 2
    )
    $certificateEmptyText.Top = 54
    $certificateOrText.Left = [int](
        ($emptyWidth - $certificateOrText.Width -
         $chooseCertificateButton.Width - 8) / 2
    )
    $certificateOrText.Top = 104
    $chooseCertificateButton.Left = (
        $certificateOrText.Left + $certificateOrText.Width + 8
    )
    $chooseCertificateButton.Top = 98

    # Selected certificate card. On a narrow column the file information stays
    # readable and the secondary actions move to the lower right.
    $certificateFileIcon.Left = 18
    $certificateFileIcon.Top = 30
    $certificateFileNameLabel.Left = 66
    $certificateFileNameLabel.Top = 22
    $certificateFileDetailsLabel.Left = 66
    $certificateFileDetailsLabel.Top = 54

    $removeCertificateButton.Left = (
        $certificateDropPanel.ClientSize.Width -
        $removeCertificateButton.Width - 14
    )
    $removeCertificateButton.Top = 116
    $replaceCertificateButton.Left = (
        $removeCertificateButton.Left -
        $replaceCertificateButton.Width - 8
    )
    $replaceCertificateButton.Top = 116

    $certificateFileNameLabel.Width = [Math]::Max(
        150,
        $certificateDropPanel.ClientSize.Width -
        $certificateFileNameLabel.Left - 18
    )
    $certificateFileDetailsLabel.Width = $certificateFileNameLabel.Width

    $summaryTable.Width = $summarySurface.ClientSize.Width - 32

    $hideTestDetailsButton.Left = (
        $testDetailsSurface.ClientSize.Width -
        $hideTestDetailsButton.Width - 16
    )
    $hideTestDetailsButton.Top = 12
    $testDetailsTextBox.Width = $testDetailsSurface.ClientSize.Width - 32

    # Footer adapts instead of squeezing Russian captions into narrow buttons.
    $footerActions.Width = (
        $saveConnectButton.Width +
        $saveButton.Width +
        $cancelButton.Width + 24
    )

    $cancelButton.Left = 0
    $saveButton.Left = $cancelButton.Right + 8
    $saveConnectButton.Left = $saveButton.Right + 8
    $cancelButton.Top = 2
    $saveButton.Top = 2
    $saveConnectButton.Top = 2

    if ($editorFooter.ClientSize.Width -ge 920) {
        if ($editorFooter.Height -ne 82) {
            $editorFooter.Height = 82
        }
        $testButton.Left = 24
        $testButton.Top = 20
        $footerActions.Top = 18
        $footerActions.Left = (
            $editorFooter.ClientSize.Width -
            $footerActions.Width - 24
        )

        $testStatusPanel.Left = $testButton.Right + 16
        $testStatusPanel.Top = 18
        $testStatusPanel.Width = [Math]::Max(
            180,
            $footerActions.Left - $testStatusPanel.Left - 16
        )
    }
    else {
        if ($editorFooter.Height -ne 132) {
            $editorFooter.Height = 132
        }
        $testButton.Left = 24
        $testButton.Top = 14
        $testStatusPanel.Left = $testButton.Right + 12
        $testStatusPanel.Top = 12
        $testStatusPanel.Width = [Math]::Max(
            180,
            $editorFooter.ClientSize.Width - $testStatusPanel.Left - 24
        )
        $footerActions.Top = 72
        $footerActions.Left = [Math]::Max(
            24,
            $editorFooter.ClientSize.Width -
            $footerActions.Width - 24
        )
    }

    $testStatusIcon.Left = 0
    $testStatusIcon.Top = 12
    $testDetailsLink.Top = 12
    $testDetailsLink.Left = [Math]::Max(
        28,
        $testStatusPanel.ClientSize.Width - $testDetailsLink.Width
    )
    $detailsReserve = if ($testDetailsLink.Visible) {
        $testDetailsLink.Width + 14
    }
    else {
        0
    }
    $testStatusLabel.Left = 28
    $testStatusLabel.Top = 0
    $testStatusLabel.Height = 40
    $testStatusLabel.Width = [Math]::Max(
        100,
        $testStatusPanel.ClientSize.Width - 28 - $detailsReserve
    )
    $testProgress.Left = 28
    $testProgress.Top = 39
    $testProgress.Width = [Math]::Max(
        80,
        [Math]::Min(180, $testStatusLabel.Width)
    )
    $testStatusPanel.BringToFront()

    Update-AdvancedGridLayout
    Update-EditorContentLayout
}

# -------------------- Events --------------------

$addServerButton.Add_Click({ Show-NewServerPage })
$emptyAddButton.Add_Click({ Show-NewServerPage })
$backButton.Add_Click({ Show-ServersPage })
$cancelButton.Add_Click({ Show-ServersPage })

$pasteButton.Add_Click({
    try {
        if ([System.Windows.Forms.Clipboard]::ContainsText()) {
            $messageTextBox.Text = [System.Windows.Forms.Clipboard]::GetText()
            $messageTextBox.Focus()
        }
        else {
            Set-RecognitionStatus "В буфере обмена нет текста." "Warning"
        }
    }
    catch {
        Set-RecognitionStatus "Не удалось прочитать буфер обмена." "Error"
    }
})

$parseButton.Add_Click({ Invoke-Recognition })

$autoRecognitionTimer = New-Object System.Windows.Forms.Timer
$autoRecognitionTimer.Interval = 500
$autoRecognitionTimer.Add_Tick({
    $autoRecognitionTimer.Stop()
    if ($messageTextBox.Text.Trim().Length -ge 20) {
        Invoke-Recognition
    }
})

$messageTextBox.Add_TextChanged({
    Mark-EditorDirty
    if (-not $script:LoadingEditor) {
        $autoRecognitionTimer.Stop()
        $autoRecognitionTimer.Start()
    }
})

$certificateDropPanel.Add_Click({ Open-CertificateDialog })
$certificateEmptyPanel.Add_Click({ Open-CertificateDialog })
$certificateEmptyIcon.Add_Click({ Open-CertificateDialog })
$certificateEmptyText.Add_Click({ Open-CertificateDialog })
$certificateOrText.Add_Click({ Open-CertificateDialog })
$chooseCertificateButton.Add_Click({ Open-CertificateDialog })
$replaceCertificateButton.Add_Click({ Open-CertificateDialog })
$removeCertificateButton.Add_Click({ Clear-CertificateSelection })

# Drag-and-drop is intentionally disabled in v4.7 to keep the application
# elevated after a single UAC prompt. Windows blocks file drops from normal
# Explorer windows into elevated applications, so the supported path is the
# explicit certificate picker button.

$advancedToggleButton.Add_Click({
    Set-AdvancedVisibility (-not $script:AdvancedVisible)
})

$passwordToggleButton.Add_Click({
    $passwordTextBox.UseSystemPasswordChar = -not $passwordTextBox.UseSystemPasswordChar
    if ($passwordTextBox.UseSystemPasswordChar) {
        $passwordToggleButton.Image = $script:IconEye
        $passwordToggleButton.AccessibleName = "Показать пароль"
        $script:UiToolTip.SetToolTip($passwordToggleButton, "Показать пароль")
    }
    else {
        $passwordToggleButton.Image = $script:IconEyeOff
        $passwordToggleButton.AccessibleName = "Скрыть пароль"
        $script:UiToolTip.SetToolTip($passwordToggleButton, "Скрыть пароль")
    }
})

$editorInputs = @(
    $displayNameTextBox,
    $serverNameTextBox,
    $addressTextBox,
    $hostnameTextBox,
    $usernameTextBox,
    $passwordTextBox
)

foreach ($control in $editorInputs) {
    $control.Add_TextChanged({
        Mark-EditorDirty
        Update-EditorHeader
        Update-EditorValidation
    })
}

$hostnameTextBox.Add_Validated({
    if ($null -ne $script:SelectedCertificateInfo) {
        if ($script:SelectedCertificateInfo.MetadataRead -eq $false) {
            Set-CertificateStatus "PEM загружен и будет встроен. Метаданные X.509 не проверены." "Warning"
        }
        elseif (-not (Test-CertificateMatchesHostname $(if ($script:SelectedCertificateInfo.PSObject.Properties.Name -contains "DnsNames") { $script:SelectedCertificateInfo.DnsNames } else { $script:SelectedCertificateInfo.DnsName }) $hostnameTextBox.Text)) {
            Set-CertificateStatus "Сертификат не соответствует домену. Проверьте PEM или домен сервера." "Error"
        }
        elseif ($script:SelectedCertificateInfo.NotAfter -lt (Get-Date)) {
            Set-CertificateStatus "Истек срок действия сертификата." "Error"
        }
        else {
            Set-CertificateStatus "Сертификат проверен." "Success"
        }
    }
})

$protocolComboBox.Add_SelectedIndexChanged({ Mark-EditorDirty; Update-EditorValidation })
$ipv6CheckBox.Add_CheckedChanged({ Mark-EditorDirty; Update-EditorValidation })
$embedCertificateCheckBox.Add_CheckedChanged({ Mark-EditorDirty; Update-EditorValidation })

$testButton.Add_Click({ Start-EditorServerTest })
$saveButton.Add_Click({ Save-EditorProfile $false })
$saveConnectButton.Add_Click({ Save-EditorProfile $true })

$testDetailsLink.Add_LinkClicked({
    $testDetailsTextBox.Text = $script:LastTestLog
    $testDetailsSurface.Visible = $true
    Update-EditorContentLayout
    $editorScrollPanel.ScrollControlIntoView($testDetailsSurface)
})

$hideTestDetailsButton.Add_Click({
    $testDetailsSurface.Visible = $false
    Update-EditorContentLayout
})

$testPollTimer = New-Object System.Windows.Forms.Timer
$testPollTimer.Interval = 300
$testPollTimer.Add_Tick({ Poll-ServerTest })

$serverRefreshTimer = New-Object System.Windows.Forms.Timer
$serverRefreshTimer.Interval = 2000
$serverRefreshTimer.Add_Tick({
    if ($script:CurrentView -eq "Servers") {
        Refresh-ServerList
    }
})
$serverRefreshTimer.Start()

$serversFlow.Add_Resize({ Resize-ServerRows })
$editorScrollPanel.Add_Resize({ Update-EditorResponsiveLayout })
$editorFooter.Add_Resize({ Update-EditorResponsiveLayout })
$form.Add_Resize({
    Resize-ServerRows
    Update-EditorResponsiveLayout
})

$form.Add_KeyDown({
    param($sender, $eventArgs)

    if ($eventArgs.Alt -and $eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::A) {
        Show-NewServerPage
        $eventArgs.SuppressKeyPress = $true
        return
    }

    if ($eventArgs.Control -and $eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::S) {
        if ($script:CurrentView -eq "Editor" -and $saveButton.Enabled) {
            Save-EditorProfile $false
        }
        $eventArgs.SuppressKeyPress = $true
        return
    }

    if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        if ($script:CurrentView -eq "Editor") {
            Show-ServersPage
            $eventArgs.SuppressKeyPress = $true
        }
    }
})

$form.Add_FormClosing({
    param($sender, $eventArgs)
    if ($script:CurrentView -eq "Editor" -and $script:EditorDirty) {
        if (-not (Confirm-DiscardChanges)) {
            $eventArgs.Cancel = $true
            return
        }
    }

    $autoRecognitionTimer.Stop()
    $testPollTimer.Stop()
    $serverRefreshTimer.Stop()
    Stop-TestWorker

    try {
        if (Test-Path -LiteralPath $script:LikewebManagerPidPath -PathType Leaf) {
            $managerPidText = ([System.IO.File]::ReadAllText(
                $script:LikewebManagerPidPath
            )).Trim()
            if ($managerPidText -eq [string]$PID) {
                Remove-Item `
                    -LiteralPath $script:LikewebManagerPidPath `
                    -Force `
                    -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
    }
})

# Logical keyboard order
$addServerButton.TabIndex = 0
$backButton.TabIndex = 0
$pasteButton.TabIndex = 1
$messageTextBox.TabIndex = 2
$parseButton.TabIndex = 3
$certificateDropPanel.TabIndex = 4
$chooseCertificateButton.TabIndex = 5
$advancedToggleButton.TabIndex = 6
$displayNameTextBox.TabIndex = 7
$serverNameTextBox.TabIndex = 8
$addressTextBox.TabIndex = 9
$hostnameTextBox.TabIndex = 10
$usernameTextBox.TabIndex = 11
$passwordTextBox.TabIndex = 12
$passwordToggleButton.TabIndex = 13
$protocolComboBox.TabIndex = 14
$ipv6CheckBox.TabIndex = 15
$embedCertificateCheckBox.TabIndex = 16
$testButton.TabIndex = 17
$cancelButton.TabIndex = 18
$saveButton.TabIndex = 19
$saveConnectButton.TabIndex = 20

# -------------------- Initial state --------------------

Set-ServersMessage "Hidden"
Set-EditorMessage "Hidden"
Reset-Editor
Update-EditorResponsiveLayout

$form.Add_Shown({
    try {
        $addServerButton.Left = [Math]::Max(
            24,
            $serversHeader.ClientSize.Width - $addServerButton.Width - 24
        )
        Resize-ServerRows
        Refresh-ServerList -Force
    }
    catch {
        Write-LikewebManagerLog "Ошибка первичной отрисовки окна" $_
        Set-ServersMessage "Error" (
            "Не удалось отобразить серверы. Журнал: " + $script:ManagerLogPath
        )
    }
})

if (-not [string]::IsNullOrWhiteSpace($ProfileId)) {
    Load-ProfileForEditing $ProfileId
}
elseif ($Mode -eq "Add") {
    Show-NewServerPage
}
else {
    Show-ServersPage -SkipDiscardCheck
}

try {
    [void]$form.ShowDialog()
}
catch {
    Write-LikewebManagerLog "Критическая ошибка окна менеджера" $_
    [void][System.Windows.Forms.MessageBox]::Show(
        "Не удалось открыть управление серверами.`r`n`r`n" +
        $_.Exception.Message +
        "`r`n`r`nЖурнал: " + $script:ManagerLogPath,
        "LW TrustTunnel Client",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
}
