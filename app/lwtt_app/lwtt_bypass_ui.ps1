# A shared bypass list, independent of server profiles.
function Show-LikewebBypassDialog {
    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = 'Обход VPN'
    $dialog.Size = [Drawing.Size]::new(650,570)
    $dialog.MinimumSize = [Drawing.Size]::new(540,480)
    $dialog.StartPosition = 'CenterScreen'
    $dialog.Font = [Drawing.Font]::new('Segoe UI',10)
    $enabled = New-Object Windows.Forms.CheckBox
    $enabled.Text = 'Включить обход VPN для всех серверов'
    $enabled.SetBounds(20,16,590,30)
    $hint = New-Object Windows.Forms.Label
    $hint.Text = "Один домен, IP или подсеть на строку. Для всех поддоменов: *.example.org.`r`nПравила из профиля сервера сохраняются и действуют дополнительно."
    $hint.SetBounds(20,52,590,54)
    $hint.Anchor = 'Top,Left,Right'
    $text = New-Object Windows.Forms.TextBox
    $text.Multiline = $true; $text.AcceptsReturn = $true; $text.ScrollBars = 'Both'; $text.WordWrap = $false
    $text.SetBounds(20,112,590,275)
    $text.Anchor = 'Top,Bottom,Left,Right'
    $normalize = New-Object Windows.Forms.Button
    $normalize.Text = 'Извлечь домены из ссылок'
    $normalize.SetBounds(20,399,260,32); $normalize.Anchor = 'Bottom,Left'
    $status = New-Object Windows.Forms.Label
    $status.SetBounds(20,438,590,35); $status.Anchor = 'Bottom,Left,Right'
    $status.ForeColor = [Drawing.Color]::Firebrick
    $save = New-Object Windows.Forms.Button
    $save.Text = 'Сохранить и применить'
    $save.SetBounds(20,481,270,34); $save.Anchor = 'Bottom,Left'
    $close = New-Object Windows.Forms.Button
    $close.Text = 'Закрыть'; $close.SetBounds(470,481,140,34); $close.Anchor = 'Bottom,Right'
    $dialog.Controls.AddRange(@($enabled,$hint,$text,$normalize,$status,$save,$close))
    $settings = Get-LikewebBypassSettings
    $enabled.Checked = $settings.Enabled
    $text.Text = $settings.Rules -join "`r`n"
    $state = @{ Dirty = $false }
    $text.Add_TextChanged({ $state.Dirty = $true })
    $enabled.Add_CheckedChanged({ $state.Dirty = $true })
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
            $status.Text = 'Ссылки преобразованы в домены. Проверьте список перед сохранением.'
        } catch { $status.Text = $_.Exception.Message }
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
            $lock.Dispose(); $lock = $null
            if (Get-LikewebProcess) {
                $active = Get-LikewebActiveProfileInfo
                if ($null -eq $active) { throw 'Выберите сервер для применения правил.' }
                $script:TrayJob = Start-LikewebAction -Action Connect -ProfilePath $active.Path
                $status.Text = 'Список сохранён. Выполняется переподключение; результат появится в трее.'
            } else { $status.Text = 'Список сохранён и будет применён при следующем подключении.' }
        } catch {
            $status.Text = $(if ($saved) { 'Список сохранён, но пока не применён. ' } else { '' }) + $_.Exception.Message
        } finally { if ($null -ne $lock) { $lock.Dispose() } }
    })
    $close.Add_Click({ $dialog.Close() })
    $dialog.Add_FormClosing({
        param($sender,$eventArgs)
        if ($state.Dirty -and [Windows.Forms.MessageBox]::Show('Закрыть без сохранения списка?', 'Обход VPN', 'YesNo', 'Warning') -ne 'Yes') { $eventArgs.Cancel = $true }
    })
    try { [void]$dialog.ShowDialog() }
    finally { $dialog.Dispose() }
}
