# Isolated WinForms regression checks. No application startup or VPN processes.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$sourcePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'app\lwtt_app\lwtt_manager.ps1'
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
foreach ($name in @('Update-AdvancedGridLayout','Update-EditorValidation','Request-EditorLayout')) {
    $definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    if ($null -eq $definition) { throw ('Missing function: ' + $name) }
    Invoke-Expression $definition.Extent.Text
}
function Assert-Editor { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
function Get-LikewebPendingJob { return $null }
function Get-EditorValidationResult { return [pscustomobject]@{ IsValid = $true; Errors = @() } }
function Update-RecognitionSummary { $summarySurface.Visible = $false }
$form = New-Object Windows.Forms.Form
$advancedFieldsPanel = New-Object Windows.Forms.Panel
$advancedGrid = New-Object Windows.Forms.TableLayoutPanel
$advancedFieldsPanel.Controls.Add($advancedGrid)
$form.Controls.Add($advancedFieldsPanel)
$saveButton = New-Object Windows.Forms.Button
$saveConnectButton = New-Object Windows.Forms.Button
$testButton = New-Object Windows.Forms.Button
$summarySurface = New-Object Windows.Forms.Panel
$summarySurface.Visible = $false
$script:UiToolTip = New-Object Windows.Forms.ToolTip
$script:AdvancedFieldContainers = New-Object 'System.Collections.Generic.List[object]'
$script:ParentChanges = 0
try {
    foreach ($i in 0..8) {
        $container = New-Object Windows.Forms.Panel
        $input = New-Object Windows.Forms.TextBox
        $container.Controls.Add($input)
        $script:AdvancedFieldContainers.Add([pscustomobject]@{ Container = $container; Input = $input })
    }
    $advancedFieldsPanel.Width = 900
    Update-AdvancedGridLayout
    Assert-Editor ($advancedGrid.ColumnCount -eq 2 -and $advancedGrid.Controls.Count -eq 9) 'Initial grid structure is invalid.'
    foreach ($item in $script:AdvancedFieldContainers) { $item.Container.Add_ParentChanged({ $script:ParentChanges++ }) }
    $input = $script:AdvancedFieldContainers[0].Input
    $input.Text = 'abc'; $input.SelectionStart = 1; $input.SelectionLength = 1
    foreach ($i in 1..100) { Update-EditorValidation; Update-AdvancedGridLayout }
    Assert-Editor ($script:ParentChanges -eq 0) 'Validation or repeated layout detached a field.'
    Assert-Editor ($input.SelectionStart -eq 1 -and $input.SelectionLength -eq 1) 'Layout reset text selection.'
    foreach ($width in @(600,900,800,500,1000)) {
        $advancedFieldsPanel.Width = $width
        Update-AdvancedGridLayout
        Assert-Editor ($advancedGrid.Controls.Count -eq 9) 'Column transition lost a field.'
        $positions = @{}
        foreach ($item in $script:AdvancedFieldContainers) {
            $position = $advancedGrid.GetPositionFromControl($item.Container)
            $key = '{0}:{1}' -f $position.Column, $position.Row
            Assert-Editor (-not $positions.ContainsKey($key)) 'Two fields occupy the same cell.'
            $positions[$key] = $true
        }
    }
    Assert-Editor ($script:ParentChanges -eq 0) 'Column transition detached a field.'
    $script:LoadingEditor = $true
    $saveButton.Enabled = $false
    Update-EditorValidation
    Assert-Editor (-not $saveButton.Enabled) 'Loading guard did not suppress validation.'
    Write-Output 'PASS: PowerShell syntax, repeated validation, stable parents and selection, column transitions, loading guard.'
} finally {
    $script:UiToolTip.Dispose()
    $saveButton.Dispose(); $saveConnectButton.Dispose(); $testButton.Dispose(); $summarySurface.Dispose(); $form.Dispose()
}
