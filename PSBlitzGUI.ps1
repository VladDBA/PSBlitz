#Requires -Version 5.0
<#
.SYNOPSIS
 Graphical user interface for PSBlitz.ps1.

.DESCRIPTION
 Provides a Windows Forms GUI for configuring and launching PSBlitz.ps1.
 Must reside in the same directory as PSBlitz.ps1.

.NOTES
 Author: Vlad Drumea (VladDBA)
 Website: https://vladdba.com/

 Copyright (c) 2026 Vlad Drumea, licensed under MIT
 License: MIT https://opensource.org/licenses/MIT

.LINK
 https://github.com/VladDBA/PSBlitz
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ([System.Management.Automation.PSTypeName]'User32Msg').Type) {
    Add-Type -Namespace '' -Name 'User32Msg' -MemberDefinition @'
        [DllImport("user32.dll")]
        public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
'@
}

###Locate PSBlitz.ps1
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$PSBlitzScript = Join-Path -Path $ScriptPath -ChildPath "PSBlitz.ps1"

if (-not (Test-Path -Path $PSBlitzScript)) {
    [System.Windows.Forms.MessageBox]::Show(
        "PSBlitz.ps1 was not found at:`n$PSBlitzScript`n`nEnsure PSBlitzGUI.ps1 is in the same directory as PSBlitz.ps1.",
        "PSBlitz GUI - Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}

###Read PSBlitz version
$PSBlitzVersion = ""
$versionLine = Select-String -Path $PSBlitzScript -Pattern '^\$Vers\s*=\s*"([^"]+)"' |
Select-Object -First 1
if ($versionLine -and $versionLine.Matches[0].Groups[1].Success) {
    $PSBlitzVersion = $versionLine.Matches[0].Groups[1].Value
}

###Use the same PowerShell executable that launched this GUI
$PSExe = if ($PSVersionTable.PSVersion.Major -ge 7) { "pwsh" } else { "powershell" }

###Helper: escape single quotes for embedding in PS single-quoted strings
function EscSQ {
    param([string]$s)
    return $s.Replace("'", "''")
}

###Shared fonts and colours
$MainFont = New-Object System.Drawing.Font("Segoe UI", 9)
$SmallFont = New-Object System.Drawing.Font("Segoe UI", 8)
$BoldFont = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$GrayColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
$BlueColor = [System.Drawing.Color]::FromArgb(0, 120, 215)

###Control factory helpers
function New-Lbl {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 150, [int]$H = 22)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Location = [System.Drawing.Point]::new($X, $Y)
    $l.Size = [System.Drawing.Size]::new($W, $H)
    $l.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    return $l
}

function New-Txt {
    param([int]$X, [int]$Y, [int]$W = 340, [string]$Default = "", [bool]$Pw = $false)
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = [System.Drawing.Point]::new($X, $Y)
    $t.Size = [System.Drawing.Size]::new($W, 24)
    $t.Add_HandleCreated({
            # EM_SETMARGINS = 0xD3, EC_LEFTMARGIN = 0x0001, 4px left margin
            [User32Msg]::SendMessage($this.Handle, 0x00D3, [IntPtr]1, [IntPtr]4) | Out-Null
        })
    $t.Text = $Default
    if ($Pw) { $t.UseSystemPasswordChar = $true }
    return $t
}

function New-Chk {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 360, [bool]$Chk = $false)
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $Text
    $c.Location = [System.Drawing.Point]::new($X, $Y)
    $c.Size = [System.Drawing.Size]::new($W, 22)
    $c.Checked = $Chk
    return $c
}

function New-Num {
    param([int]$X, [int]$Y, [int]$W = 90, [int]$Lo = 0, [int]$Hi = 99999, [int]$Val = 0)
    $n = New-Object System.Windows.Forms.NumericUpDown
    $n.Location = [System.Drawing.Point]::new($X, $Y)
    $n.Size = [System.Drawing.Size]::new($W, 24)
    $n.Minimum = $Lo
    $n.Maximum = $Hi
    $n.Value = $Val
    return $n
}

###Main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "PSBlitz $PSBlitzVersion"
$form.Size = [System.Drawing.Size]::new(560, 660)
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false
$form.Font = $MainFont

###Tab control
$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = [System.Drawing.Point]::new(10, 10)
$tabs.Size = [System.Drawing.Size]::new(524, 555)

$tabConn = New-Object System.Windows.Forms.TabPage; $tabConn.Text = "Connection"
$tabOpts = New-Object System.Windows.Forms.TabPage; $tabOpts.Text = "Options"
$tabAdv = New-Object System.Windows.Forms.TabPage; $tabAdv.Text = "Advanced"

$tabs.TabPages.AddRange(@($tabConn, $tabOpts, $tabAdv))
$form.Controls.Add($tabs)

# ---------------------------------------------------------------------------
# Tab: Connection
# ---------------------------------------------------------------------------
$y = 15
$tServer = New-Txt 155 $y 340
$tabConn.Controls.AddRange(@((New-Lbl "Server *" 10 $y), $tServer))

$y += 35
$tLogin = New-Txt 155 $y 340
$tabConn.Controls.AddRange(@((New-Lbl "SQL Login" 10 $y), $tLogin))

$noteLogin = New-Lbl "Leave blank to use Windows authentication" 155 ($y + 26) 340 16
$noteLogin.Font = $SmallFont
$noteLogin.ForeColor = $GrayColor
$tabConn.Controls.Add($noteLogin)

$y += 35
$tPass = New-Txt 155 $y 340 "" $true
$tabConn.Controls.AddRange(@((New-Lbl "Password" 10 $y), $tPass))

$y += 35
$tDB = New-Txt 155 $y 340
$tabConn.Controls.AddRange(@((New-Lbl "Database" 10 $y), $tDB))

$noteDB = New-Lbl "Leave blank to check the whole instance" 155 ($y + 26) 340 16
$noteDB.Font = $SmallFont
$noteDB.ForeColor = $GrayColor
$tabConn.Controls.Add($noteDB)

$y += 58
$sep1 = New-Object System.Windows.Forms.Label
$sep1.Location = [System.Drawing.Point]::new(10, $y)
$sep1.Size = [System.Drawing.Size]::new(490, 1)
$sep1.BorderStyle = [System.Windows.Forms.BorderStyle]::Fixed3D
$tabConn.Controls.Add($sep1)

$y += 8
$hdr = New-Lbl "Connection string examples:" 10 $y 490 18
$hdr.Font = $BoldFont
$tabConn.Controls.Add($hdr)

$y += 22
foreach ($note in @(
        "Named instance       Server01\InstanceName",
        "Port-based           Server01,1433",
        "Default instance     Server01",
        "Azure SQL DB         server.database.windows.net,1433:DatabaseName",
        "Azure SQL MI         server.database.windows.net")) {
    $n = New-Lbl $note 10 $y 490 17
    $n.Font = $SmallFont
    $n.ForeColor = $GrayColor
    $tabConn.Controls.Add($n)
    $y += 18
}

# ---------------------------------------------------------------------------
# Tab: Options
# ---------------------------------------------------------------------------
$y = 15
$cInDepth = New-Chk "In-depth check" 10 $y
$tabOpts.Controls.Add($cInDepth)

$y += 28
$cToHTML = New-Chk "Output report as HTML (instead of Excel)" 10 $y
$tabOpts.Controls.Add($cToHTML)

$y += 28
$cZip = New-Chk "Create a zip archive of the output files" 10 $y
$tabOpts.Controls.Add($cZip)

$y += 35
$nDelay = New-Num 180 $y 80 1 300 10
$tabOpts.Controls.AddRange(@((New-Lbl "BlitzWho delay (sec)" 10 $y 165), $nDelay))

$y += 35
$tOutDir = New-Txt 180 $y 240
$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "Browse..."
$btnBrowse.Location = [System.Drawing.Point]::new(426, $y)
$btnBrowse.Size = [System.Drawing.Size]::new(80, 24)
$btnBrowse.Add_Click({
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = "Select output directory for PSBlitz results"
        if (-not [string]::IsNullOrWhiteSpace($tOutDir.Text) -and (Test-Path -Path $tOutDir.Text)) {
            $dlg.SelectedPath = $tOutDir.Text
        }
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $tOutDir.Text = $dlg.SelectedPath
        }
    })
$tabOpts.Controls.AddRange(@((New-Lbl "Output directory" 10 $y 165), $tOutDir, $btnBrowse))

$y += 40
$grpSkip = New-Object System.Windows.Forms.GroupBox
$grpSkip.Text = "Skip Checks"
$grpSkip.Location = [System.Drawing.Point]::new(10, $y)
$grpSkip.Size = [System.Drawing.Size]::new(490, 115)

$cSkipFrag = New-Chk "Index Fragmentation" 10 22 215
$cSkipStats = New-Chk "Statistics Info" 240 22 215
$cSkipDead = New-Chk "Deadlocks" 10 52 215
$cSkipCache = New-Chk "Plan Cache" 240 52 215
$cSkipQS = New-Chk "Query Store" 10 82 215
$grpSkip.Controls.AddRange(@($cSkipFrag, $cSkipStats, $cSkipDead, $cSkipCache, $cSkipQS))
$tabOpts.Controls.Add($grpSkip)

# ---------------------------------------------------------------------------
# Tab: Advanced
# ---------------------------------------------------------------------------
$y = 15
$nCacheTop = New-Num 200 $y 90 0 9999 10
$hCacheTop = New-Lbl "(0 = skip plan cache)" 295 $y 200 22
$hCacheTop.Font = $SmallFont
$hCacheTop.ForeColor = $GrayColor
$tabAdv.Controls.AddRange(@((New-Lbl "Cache top N queries" 10 $y 185), $nCacheTop, $hCacheTop))

$y += 35
$nCacheMins = New-Num 200 $y 90 0 99999 0
$hCacheMins = New-Lbl "(0 = entire plan cache)" 295 $y 200 22
$hCacheMins.Font = $SmallFont
$hCacheMins.ForeColor = $GrayColor
$tabAdv.Controls.AddRange(@((New-Lbl "Cache minutes back" 10 $y 185), $nCacheMins, $hCacheMins))

$y += 35
$nQSTop = New-Num 200 $y 90 0 9999 20
$hQSTop = New-Lbl "(0 = skip Query Store)" 295 $y 200 22
$hQSTop.Font = $SmallFont
$hQSTop.ForeColor = $GrayColor
$tabAdv.Controls.AddRange(@((New-Lbl "Query Store top N" 10 $y 185), $nQSTop, $hQSTop))

$y += 35
$tQSStart = New-Txt 200 $y 285
$tabAdv.Controls.AddRange(@((New-Lbl "QS interval start" 10 $y 185), $tQSStart))

$y += 24
$hQSStart = New-Lbl "Format: yyyy-MM-dd HH:mm:ss  (empty = 7 days ago)" 200 $y 285 16
$hQSStart.Font = $SmallFont
$hQSStart.ForeColor = $GrayColor
$tabAdv.Controls.Add($hQSStart)

$y += 22
$tQSEnd = New-Txt 200 $y 285
$tabAdv.Controls.AddRange(@((New-Lbl "QS interval end" 10 $y 185), $tQSEnd))

$y += 24
$hQSEnd = New-Lbl "Format: yyyy-MM-dd HH:mm:ss  (empty = now)" 200 $y 285 16
$hQSEnd.Font = $SmallFont
$hQSEnd.ForeColor = $GrayColor
$tabAdv.Controls.Add($hQSEnd)

$y += 27
$nMaxTO = New-Num 200 $y 90 0 99999 1000
$tabAdv.Controls.AddRange(@((New-Lbl "Max timeout (sec)" 10 $y 185), $nMaxTO))

$y += 35
$nConnTO = New-Num 200 $y 90 0 9999 45
$tabAdv.Controls.AddRange(@((New-Lbl "Conn timeout (sec)" 10 $y 185), $nConnTO))

$y += 35
$nMaxDBs = New-Num 200 $y 90 1 9999 50
$hMaxDBs = New-Lbl "(HTML output only - raise for large instances)" 295 $y 210 22
$hMaxDBs.Font = $SmallFont
$hMaxDBs.ForeColor = $GrayColor
$tabAdv.Controls.AddRange(@((New-Lbl "Max user databases" 10 $y 185), $nMaxDBs, $hMaxDBs))

# ---------------------------------------------------------------------------
# Bottom bar: Help | [status] | Run PSBlitz | Close
# ---------------------------------------------------------------------------
$btnHelp = New-Object System.Windows.Forms.Button
$btnHelp.Text = "Help"
$btnHelp.Location = [System.Drawing.Point]::new(10, 578)
$btnHelp.Size = [System.Drawing.Size]::new(70, 32)
$btnHelp.Add_Click({
        [System.Windows.Forms.MessageBox]::Show(@"
PSBlitz $PSBlitzVersion  |  https://github.com/VladDBA/PSBlitz

CONNECTION TAB
  Server      Required. Accepts: HostName\Instance, HostName,Port,
              HostName, or an Azure endpoint.
  SQL Login   Leave blank for Windows integrated security.
  Password    Required only when SQL Login is specified.
  Database    Leave blank to run against the whole instance.
              Specify a name to focus index, cache, and lock
              checks on one database.

OPTIONS TAB
  In-depth check    Runs more thorough diagnostics (takes longer).
  HTML output       Use when MS Office is not installed on this machine.
  Zip archive       Packs all output files into a .zip.
  BlitzWho delay    Seconds between session activity snapshots (default 10).
  Output directory  Where to save the output folder (default: PSBlitz dir).
  Skip Checks       Exclude specific diagnostic steps from the run.

ADVANCED TAB
  Cache top N        Queries returned from plan cache (default 10).
  Cache minutes back Look-back window for plan cache (default: all cache).
  QS top N           Queries returned from Query Store (default 20).
  QS interval        Date/time range for Query Store queries.
  Max timeout        Timeout in seconds for long steps (default 1000).
  Conn timeout       SQL connection timeout in seconds (default 45).
  Max user databases Index data limit threshold (default 50, HTML only).
"@,
            "PSBlitz GUI - Help",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    })
$form.Controls.Add($btnHelp)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = [System.Drawing.Point]::new(88, 585)
$lblStatus.Size = [System.Drawing.Size]::new(247, 18)
$lblStatus.Font = $SmallFont
$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(0, 128, 0)
$form.Controls.Add($lblStatus)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "Close"
$btnClose.Location = [System.Drawing.Point]::new(461, 578)
$btnClose.Size = [System.Drawing.Size]::new(80, 32)
$btnClose.Add_Click({ $form.Close() })
$form.CancelButton = $btnClose
$form.Controls.Add($btnClose)

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "Run PSBlitz"
$btnRun.Location = [System.Drawing.Point]::new(343, 578)
$btnRun.Size = [System.Drawing.Size]::new(112, 32)
$btnRun.BackColor = $BlueColor
$btnRun.ForeColor = [System.Drawing.Color]::White
$btnRun.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRun.Font = $BoldFont
$form.AcceptButton = $btnRun
$form.Controls.Add($btnRun)

# ---------------------------------------------------------------------------
# Run button: build encoded command and launch PSBlitz in a new console
# ---------------------------------------------------------------------------
$btnRun.Add_Click({
        $lblStatus.Text = ""

        $serverVal = $tServer.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($serverVal)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Server name is required.",
                "PSBlitz GUI",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            $tabs.SelectedTab = $tabConn
            $tServer.Focus()
            return
        }

        ###Build the PSBlitz call as a PowerShell expression (single-quoted values)
        ###Using -EncodedCommand avoids all shell-escaping issues for paths and passwords
        $cmd = [System.Text.StringBuilder]::new()
        [void]$cmd.Append("& '$(EscSQ $PSBlitzScript)'")
        [void]$cmd.Append(" -ServerName '$(EscSQ $serverVal)'")

        $loginVal = $tLogin.Text.Trim()
        $passVal = $tPass.Text
        if (-not [string]::IsNullOrWhiteSpace($loginVal)) {
            [void]$cmd.Append(" -SQLLogin '$(EscSQ $loginVal)'")
            [void]$cmd.Append(" -SQLPass '$(EscSQ $passVal)'")
        }

        $dbVal = $tDB.Text.Trim()
        if (-not [string]::IsNullOrWhiteSpace($dbVal)) {
            [void]$cmd.Append(" -CheckDB '$(EscSQ $dbVal)'")
        }

        if ($cInDepth.Checked) { [void]$cmd.Append(" -InDepth") }
        if ($cToHTML.Checked) { [void]$cmd.Append(" -ToHTML") }
        if ($cZip.Checked) { [void]$cmd.Append(" -ZipOutput") }

        if ($nDelay.Value -ne 10) {
            [void]$cmd.Append(" -BlitzWhoDelay $([int]$nDelay.Value)")
        }

        $outDirVal = $tOutDir.Text.Trim()
        if (-not [string]::IsNullOrWhiteSpace($outDirVal)) {
            [void]$cmd.Append(" -OutputDir '$(EscSQ $outDirVal)'")
        }

        ###Skip checks: pass as array literal  e.g. -SkipChecks 'IndexFrag','Deadlock'
        $skipItems = [System.Collections.Generic.List[string]]::new()
        if ($cSkipFrag.Checked) { $skipItems.Add("IndexFrag") }
        if ($cSkipStats.Checked) { $skipItems.Add("StatsInfo") }
        if ($cSkipDead.Checked) { $skipItems.Add("Deadlock") }
        if ($cSkipCache.Checked) { $skipItems.Add("PlanCache") }
        if ($cSkipQS.Checked) { $skipItems.Add("QueryStore") }
        if ($skipItems.Count -gt 0) {
            $quotedItems = $skipItems | ForEach-Object { "'$_'" }
            [void]$cmd.Append(" -SkipChecks $($quotedItems -join ',')")
        }

        ###Advanced parameters - only include when they differ from PSBlitz defaults
        if ($nCacheTop.Value -ne 10) {
            [void]$cmd.Append(" -CacheTop $([int]$nCacheTop.Value)")
        }
        if ($nCacheMins.Value -ne 0) {
            [void]$cmd.Append(" -CacheMinutesBack $([int]$nCacheMins.Value)")
        }
        if ($nQSTop.Value -ne 20) {
            [void]$cmd.Append(" -QueryStoreTop $([int]$nQSTop.Value)")
        }

        $qsStartVal = $tQSStart.Text.Trim()
        if (-not [string]::IsNullOrWhiteSpace($qsStartVal)) {
            [void]$cmd.Append(" -QueryStoreIntervalStart '$(EscSQ $qsStartVal)'")
        }
        $qsEndVal = $tQSEnd.Text.Trim()
        if (-not [string]::IsNullOrWhiteSpace($qsEndVal)) {
            [void]$cmd.Append(" -QueryStoreIntervalEnd '$(EscSQ $qsEndVal)'")
        }

        if ($nMaxTO.Value -ne 1000) {
            [void]$cmd.Append(" -MaxTimeout $([int]$nMaxTO.Value)")
        }
        if ($nConnTO.Value -ne 45) {
            [void]$cmd.Append(" -ConnTimeout $([int]$nConnTO.Value)")
        }
        if ($nMaxDBs.Value -ne 50) {
            [void]$cmd.Append(" -MaxUsrDBs $([int]$nMaxDBs.Value)")
        }

        ###Encode and launch in a new console window
        $encoded = [Convert]::ToBase64String(
            [System.Text.Encoding]::Unicode.GetBytes($cmd.ToString())
        )

        Start-Process -FilePath $PSExe -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-EncodedCommand", $encoded
        )

        $lblStatus.Text = "PSBlitz launched - check the new console window."
    })

[void]$form.ShowDialog()
