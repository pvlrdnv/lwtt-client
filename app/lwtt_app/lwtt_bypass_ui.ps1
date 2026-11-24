# A shared bypass list, independent of server profiles.
function Show-LikewebBypassDialog {
    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = 'Обход VPN'
    $dialog.ClientSize = [Drawing.Size]::new(650,610)
    $dialog.MinimumSize = [Drawing.Size]::new(540,530)
    $dialog.StartPosition = 'CenterScreen'
    $dialogFont = [Drawing.Font]::new('Segoe UI',10)
    $headingFont = [Drawing.Font]::new('Segoe UI',11,[Drawing.FontStyle]::Bold)
    $actionFont = [Drawing.Font]::new('Segoe UI',10,[Drawing.FontStyle]::Bold)
    $dialog.Font = $dialogFont
    $enablePanel = New-Object Windows.Forms.Panel
    $enablePanel.SetBounds(20,16,610,94)
    $enablePanel.Anchor = 'Top,Left,Right'
    $enableAccent = New-Object Windows.Forms.Panel
    $enableAccent.Dock = 'Left'
    $enableAccent.Width = 6
    $enablePanel.Controls.Add($enableAccent)
    $enabled = New-Object Windows.Forms.CheckBox
    $enabled.Text = 'Включить обход VPN для всех серверов'
    $enabled.SetBounds(16,10,578,32)
    $enabled.Anchor = 'Top,Left,Right'
    $enabled.Font = $headingFont
    $enabled.AccessibleName = 'Включить обход VPN для всех серверов'
    $enabled.TabIndex = 0
    $enablePanel.Controls.Add($enabled)
    $enableNote = New-Object Windows.Forms.Label
    $enableNote.SetBounds(16,48,578,36)
    $enableNote.Anchor = 'Top,Left,Right'
    $enablePanel.Controls.Add($enableNote)
    $hint = New-Object Windows.Forms.Label
    $hint.Text = "Один домен, IP или подсеть на строку. Для всех поддоменов: *.example.org.`r`nПравила из профиля сервера сохраняются и действуют дополнительно."
    $hint.SetBounds(20,122,610,50)
    $hint.Anchor = 'Top,Left,Right'
    $text = New-Object Windows.Forms.TextBox
    $text.Multiline = $true; $text.AcceptsReturn = $true; $text.ScrollBars = 'Both'; $text.WordWrap = $false
    $text.SetBounds(20,180,610,275)
    $text.Anchor = 'Top,Bottom,Left,Right'
    $text.TabIndex = 1
    $normalize = New-Object Windows.Forms.Button
    $normalize.Text = 'Извлечь домены из ссылок'
    $normalize.SetBounds(20,467,260,32); $normalize.Anchor = 'Bottom,Left'
    $normalize.TabIndex = 2
    $status = New-Object Windows.Forms.Label
    $status.SetBounds(20,508,610,35); $status.Anchor = 'Bottom,Left,Right'
    $status.ForeColor = [Drawing.Color]::Firebrick
    $save = New-Object Windows.Forms.Button
    $save.Text = 'Сохранить и применить'
    $save.SetBounds(360,552,270,40); $save.Anchor = 'Bottom,Right'
    $save.Font = $actionFont
    $save.FlatStyle = 'Flat'
    $save.FlatAppearance.BorderSize = 0
    $save.UseVisualStyleBackColor = $false
    $save.BackColor = [Drawing.Color]::FromArgb(0,120,212)
    $save.ForeColor = [Drawing.Color]::White
    $save.FlatAppearance.MouseOverBackColor = [Drawing.Color]::FromArgb(0,102,184)
    $save.FlatAppearance.MouseDownBackColor = [Drawing.Color]::FromArgb(0,84,153)
    $save.TabIndex = 4
    $close = New-Object Windows.Forms.Button
    $close.Text = 'Закрыть'; $close.SetBounds(20,552,140,40); $close.Anchor = 'Bottom,Left'
    $close.TabIndex = 3
    $dialog.Controls.AddRange(@($enablePanel,$hint,$text,$normalize,$status,$save,$close))
    $settings = Get-LikewebBypassSettings
    $enabled.Checked = $settings.Enabled
    $text.Text = $settings.Rules -join "`r`n"
    $state = @{ Dirty = $false }
    $text.Add_TextChanged({ $state.Dirty = $true })
    $refreshEnablePanel = {
        if ($enabled.Checked) {
            $enablePanel.BackColor = [Drawing.Color]::FromArgb(232,243,255)
            $enableAccent.BackColor = [Drawing.Color]::FromArgb(0,120,212)
            $enabled.ForeColor = [Drawing.Color]::FromArgb(0,69,120)
            $enableNote.ForeColor = [Drawing.Color]::FromArgb(39,74,105)
            $enableNote.Text = 'Адреса из списка пойдут напрямую. Сохраните изменения кнопкой внизу.'
        } else {
            $enablePanel.BackColor = [Drawing.Color]::FromArgb(255,243,205)
            $enableAccent.BackColor = [Drawing.Color]::FromArgb(224,151,0)
            $enabled.ForeColor = [Drawing.Color]::FromArgb(107,67,0)
            $enableNote.ForeColor = [Drawing.Color]::FromArgb(107,76,20)
            $enableNote.Text = 'Чтобы список работал, включите обход и сохраните изменения.'
        }
        $enabled.BackColor = $enablePanel.BackColor
        $enableNote.BackColor = $enablePanel.BackColor
    }
    & $refreshEnablePanel
    $enabled.Add_CheckedChanged({ $state.Dirty = $true; & $refreshEnablePanel })
    $normalize.Add_Click({
        try {
            $lines = foreach ($line in ($text.Text -split '\r?\n')) {
                $value = $line.Trim()
                if ($value -match '^(?i)https?://') {
                    $uri = [Uri]$value
                    if (-not $uri.IsAbsoluteUri -or -not $uri.DnsSafeHost) { throw 'Не удалось прочитать ссылку.' }
                    $uri.DnsSafeHost
                } else { $value }
            }
            $text.Text = $lines -join "`r`n"
            $status.ForeColor = [Drawing.Color]::FromArgb(0,69,120)
            $status.Text = 'Ссылки преобразованы в домены. Проверьте список перед сохранением.'
        } catch { $status.ForeColor = [Drawing.Color]::Firebrick; $status.Text = $_.Exception.Message }
    })
    $save.Add_Click({
        $lock = $null; $saved = $false
        try {
            $rules = @(ConvertTo-LikewebBypassRules $text.Text)
            $lock = Enter-LikewebOperationLock
            if (Test-LikewebRecoveryRequired) { throw 'Сначала восстановите незавершённую операцию в трее.' }
            $changes = [ordered]@{}
            $changes[(Join-Path $script:LikewebBaseDir 'settings\bypass.json')] = (@{ Enabled = $enabled.Checked; Rules = $rules } | ConvertTo-Json -Depth 4)
            Invoke-LikewebFileTransaction $changes
            $state.Dirty = $false; $saved = $true
            $status.ForeColor = [Drawing.Color]::FromArgb(16,124,16)
            $lock.Dispose(); $lock = $null
            if (Get-LikewebProcess) {
                $active = Get-LikewebActiveProfileInfo
                if ($null -eq $active) { throw 'Выберите сервер для применения правил.' }
                $script:TrayJob = Start-LikewebAction -Action Connect -ProfilePath $active.Path
                $status.Text = 'Список сохранён. Выполняется переподключение; результат появится в трее.'
            } else { $status.Text = 'Список сохранён и будет применён при следующем подключении.' }
        } catch {
            $status.ForeColor = [Drawing.Color]::Firebrick
            $status.Text = $(if ($saved) { 'Список сохранён, но пока не применён. ' } else { '' }) + $_.Exception.Message
        } finally { if ($null -ne $lock) { $lock.Dispose() } }
    })
    $close.Add_Click({ $dialog.Close() })
    $dialog.Add_FormClosing({
        param($sender,$eventArgs)
        if ($state.Dirty -and [Windows.Forms.MessageBox]::Show('Закрыть без сохранения списка?', 'Обход VPN', 'YesNo', 'Warning') -ne 'Yes') { $eventArgs.Cancel = $true }
    })
    try { [void]$dialog.ShowDialog() }
    finally { $dialog.Dispose(); $headingFont.Dispose(); $actionFont.Dispose(); $dialogFont.Dispose() }
}
