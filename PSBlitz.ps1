<# PSBlitz.ps1
For updates/info visit https://github.com/VladDBA/PSBlitz

#Usage Examples:
You can run PSBlitz.ps1 by simply right-clicking on the script and then clicking on "Run With PowerShell" which will execute the script in interactive mode, prompting you for the required input.

Otherwise you can navigate to the directory where the script is in PowerShell and execute it by providing parameters and appropriate values.

1. Print the help menu
.\PSBlitz.ps1 ?
or
.\PSBlitz.ps1 Help

2. Run it against the whole instance (named instance SQL01), with default checks via integrated security
.\PSBlitz.ps1 Server01\SQL01

3. Run it against the whole instance listening on port 1433 on host Server01, with default checks via integrated security
.\PSBlitz.ps1 Server01,1433

4. Run it against the whole instance, with in-depth checks via integrated security
.\PSBlitz.ps1 Server01\SQL01 -IsIndepth Y

5. Run it with in-depth checks, limit sp_BlitzIndex, sp_BlitzCache, and sp_BlitzLock to YourDatabase only, via integrated security
.\PSBlitz.ps1 Server01\SQL01 -IsIndepth Y -CheckDB YourDatabase

6. Run it against the whole instance, with default checks via SQL login and password
.\PSBlitz.ps1 Server01\SQL01 -SQLLogin DBA1 -SQLPass SuperSecurePassword

7. Run it against a default instance residing on Server02, with in-depth checks via SQL login and password, while limmiting sp_BlitzIndex, sp_BlitzCache, and sp_BlitzLock to YourDatabase only
.\PSBlitz.ps1 Server02 -SQLLogin DBA1 -SQLPass SuperSecurePassword -IsIndepth Y -CheckDB YourDatabase

Note that -ServerName is a positional parameter, so you don't necessarily have to specify the parameter's name as long as the first thing after the script's name is the instance or a question mark 

#MIT License

Copyright for sp_Blitz, sp_BlitzCache, sp_BlitzFirst, sp_BlitzIndex, 
sp_BlitzLock, and sp_BlitzWho is held by Brent Ozar Unlimited under MIT licence:
[SQL Server First Responder Kit](https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit)
Copyright for PSBlitz.ps1 is held by Vlad Drumea, 2023 as described below.

Copyright (c) 2023 Vlad Drumea

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
#>

###Input Params
##Params for running from command line
[cmdletbinding()]
param(
	[Parameter(Position = 0, Mandatory = $False)]
	[string[]]$ServerName,
	[Parameter(Mandatory = $False)]
	[string]$SQLLogin,
	[Parameter(Mandatory = $False)]
	[string]$SQLPass,
	[Parameter(Mandatory = $False)]
	[string]$IsIndepth,
	[Parameter(Mandatory = $False)]
	[string]$CheckDB,
	[Parameter(Mandatory = $False)]
	[string]$Help,
	[Parameter(Mandatory = $False)]
	[int]$BlitzWhoDelay = 10,
	[Parameter(Mandatory = $False)]
	[switch]$DebugInfo,
	[Parameter(Mandatory = $False)]
	[int]$MaxTimeout = 800,
	[Parameter(Mandatory = $False)]
	[int]$ConnTimeout = 15,
	[Parameter(Mandatory = $False)]
	[string]$OutputDir,
	[Parameter(Mandatory = $False)]
	[string]$ToHTML = "N",
	[Parameter(Mandatory = $False)]
	[string]$ZipOutput = "N"
)

###Internal params
#Version
$Vers = "3.0.0"
$VersDate = "20230411"
#Get script path
$ScriptPath = split-path -parent $MyInvocation.MyCommand.Definition
#Set resources path
$ResourcesPath = $ScriptPath + "\Resources"
#Set name of the input Excel file
$OrigExcelFName = "PSBlitzOutput.xlsx"
$ResourceList = @("PSBlitzOutput.xlsx", "spBlitz_NonSPLatest.sql",
	"spBlitzCache_NonSPLatest.sql", "spBlitzFirst_NonSPLatest.sql",
	"spBlitzIndex_NonSPLatest.sql", "spBlitzLock_NonSPLatest.sql",
	"spBlitzWho_NonSPLatest.sql",
	"GetStatsAndIndexInfoForWholeDB.sql",
	"GetBlitzWhoData.sql", "GetInstanceInfo.sql",
	"GetTempDBUsageInfo.sql")
#Set path+name of the input Excel file
$OrigExcelF = $ResourcesPath + "\" + $OrigExcelFName
#Set default start row for Excel output
$DefaultStartRow = 2
#BlitzWho initial pass number
$BlitzWhoPass = 1

if ($DebugInfo) {
	#Success
	$GreenCheck = @{
		Object          = [Char]8730
		ForegroundColor = 'Green'
		NoNewLine       = $true
	}
	#Failure
	$RedX = @{
		Object          = 'x (Failed)'
		ForegroundColor = 'Red'
		NoNewLine       = $true
	}
	#Command Timeout
	$RedXTimeout = @{
		Object          = 'x (Command timeout)'
		ForegroundColor = 'Red'
		NoNewLine       = $true
	}
	#Connection Timeout
	$RedXConnTimeout = @{
		Object          = 'x (Connection timeout)'
		ForegroundColor = 'Red'
		NoNewLine       = $true
	}
}
else {
	#Success
	$GreenCheck = @{
		Object          = [Char]8730
		ForegroundColor = 'Green'
		NoNewLine       = $false
	}
	#Failure
	$RedX = @{
		Object          = 'x (Failed)'
		ForegroundColor = 'Red'
		NoNewLine       = $false
	}
	#Command Timeout
	$RedXTimeout = @{
		Object          = 'x (Command timeout)'
		ForegroundColor = 'Red'
		NoNewLine       = $false
	}
	#Connection Timeout
	$RedXConnTimeout = @{
		Object          = 'x (Connection timeout)'
		ForegroundColor = 'Red'
		NoNewLine       = $false
	}
}

###Functions
#Function to properly output hex strings like Plan Handle and SQL Handle
function Get-HexString {
	param (
		[System.Array]$HexInput
	)
	if ($HexInput -eq [System.DBNull]::Value) {
		$HexString = ""
	}
 else {
		#Formatting value as hex and stripping extra stuff
		$HexSplit = ($HexInput | Format-Hex -ErrorAction Ignore | Select-String "00000")
		<#
	Converting to string, prepending 0x, removing spaces 
	and joining it in one single string
	#>
		$HexString = "0x"
		for ($i = 0; $i -lt $HexSplit.Length; $i++) {
			$HexString = $HexString + "$($HexSplit[$i].ToString().Substring(11,47).replace(' ','') )"
		}
	}
	Write-Output $HexString
}
#Function to return a brief help menu
function Get-PSBlitzHelp {
	Write-Host "`n######	PSBlitz		######`n Version $Vers - $VersDate
	`n Updates/more info: https://github.com/VladDBA/PSBlitz
	`n######	Parameters	######
-ServerName		- accepts either [hostname]\[instance] (for named instances), 
		[hostname,port], or just [hostname] for default instances
-SQLLogin		- the name of the SQL login used to run the script; if not provided, 
		the script will use integrated security
-SQLPass		- the password for the SQL login provided via the -SQLLogin parameter,
		omit if -SQLLogin was not used
-IsIndepth		- Y will run a more in-depth check against the instance/database, omit for a basic check
-CheckDB		- used to provide the name of a specific database to run some of the checks against, 
		omit to run against the whole instance
-OutputDir		- used to provide a path where the output directory should be saved to.
		Defaults to PSBlitz.ps1's directory if not specified or a non-existent path is provided.
-ToHTML			- Y will output the report as HTML instead of an Excel file.
-ZipOutput		- Y to also create a zip archive of the output files.
-BlitzWhoDelay	- used to sepcify the number of seconds between each sp_BlitzWho execution.
		Defaults to 10 if not specified
-MaxTimeout		- can be used to set a higher timeout for sp_BlitzIndex and Stats and Index info
		retrieval. Defaults to 800 (13.3 minutes)
-ConnTimeout	- used to increased the timeout limit in seconds for connecting to SQL Server.
		Defaults to 15 seconds if not specified
-DebugInfo		- switch used to get more information for debugging and troubleshooting purposes.
`n######	Execution	######
You can either run the script directly in PowerShell from its directory:
 Run it against the whole instance (named instance SQL01), with default checks via integrated security"
	Write-Host ".\PSBlitz.ps1 Server01\SQL01" -fore green
	Write-Host "`n Same as the above, but have sp_BlitzWho execute every 5 seconds instead of 10"
	Write-Host ".\PSBlitz.ps1 Server01\SQL01 -BlitzWhoDelay 5" -fore green
	Write-Host "`n Run it against an instance listening on port 1433 on Server01"
	Write-Host ".\PSBlitz.ps1 Server01,1433" -fore green
	Write-Host "`n Run it against a default instance installed on Server01"
	Write-Host ".\PSBlitz.ps1 Server01" -fore green
	Write-Host "`n Run it against the whole instance, with in-depth checks via integrated security"
	Write-Host ".\PSBlitz.ps1 Server01\SQL01 -IsIndepth Y" -fore green
	Write-Host "`n Run it against the whole instance and output the report as HTML"
	Write-Host ".\PSBlitz.ps1 Server01\SQL01 -IsIndepth Y -ToHTML Y" -fore green
	Write-Host "`n Run it with in-depth checks, limit sp_BlitzIndex, sp_BlitzCache, and sp_BlitzLock to 
YourDatabase only, via integrated security"
	Write-Host ".\PSBlitz.ps1 Server01\SQL01 -IsIndepth Y -CheckDB YourDatabase" -fore green
	Write-Host "`n Run it against the whole instance, with default checks via SQL login and password"
	Write-Host ".\PSBlitz.ps1 Server01\SQL01 -SQLLogin DBA1 -SQLPass SuperSecurePassword" -fore green
	Write-Host "`n Or you can run it in interactive mode by just right-clicking on the PSBlitz.ps1 file 
-> 'Run with PowerShell', and the script will prompt you for input.
`n######	What it runs	######
PSBlitz.ps1 uses slightly modified, non-stored procedure versions, of the following components 
from Brent Ozar's FirstResponderKit (https://www.brentozar.com/first-aid/):
   sp_Blitz
   sp_BlitzCache
   sp_BlitzFirst
   sp_BlitzIndex
   sp_BlitzLock
   sp_BlitzWho
`n You can find the scripts in the '$ResourcesPath' directory
"
}
#Function to execute sp_BlitzWho
function Invoke-BlitzWho {
	param (
		[string]$BlitzWhoQuery,
		[string]$IsInLoop
	)
	if ($IsInLoop -eq "Y") {
		Write-Host " ->Running sp_BlitzWho - pass $BlitzWhoPass... " -NoNewLine
	}
 else {
		Write-Host " Running sp_BlitzWho - pass $BlitzWhoPass... " -NoNewLine
	}
	$BlitzWhoCommand = new-object System.Data.SqlClient.SqlCommand
	$BlitzWhoCommand.CommandText = $BlitzWhoQuery
	$BlitzWhoCommand.CommandTimeout = 120
	$SqlConnection.Open()
	$BlitzWhoCommand.Connection = $SqlConnection
	Try {
		$BlitzWhoCommand.ExecuteNonQuery() | Out-Null -ErrorAction Stop
		$SqlConnection.Close()
		Write-Host @GreenCheck
	}
 Catch {
		Write-Host @RedX
	}
}

#Function to properly format XML contents for deadlock graphs and execution plans
function Format-XML {
	[CmdletBinding()]
	Param ([
		Parameter(ValueFromPipeline = $true, Mandatory = $true)]
		[string]$XMLContent)
	$XMLDoc = New-Object -TypeName System.Xml.XmlDocument
	$XMLDoc.LoadXml($XMLContent)
	$SW = New-Object System.IO.StringWriter
	$Writer = New-Object System.Xml.XmlTextwriter($SW)
	$Writer.Formatting = [System.XML.Formatting]::Indented
	$XMLDoc.WriteContentTo($Writer)
	$SW.ToString()
}

#Function to return error messages in the catch block
function Invoke-ErrMsg {
	$StepRunTime = (New-TimeSpan -Start $StepStart -End $StepEnd).TotalSeconds
	$RunTime = [Math]::Round($StepRunTime, 2)
	if ($RunTime -ge $CmdTimeout) {
		Write-Host @RedXTimeout
		if ($DebugInfo) {
			Write-Host " - $RunTime seconds" -Fore Yellow
		}
	}
 elseif ($RunTime -ge $ConnTimeout) {
		Write-Host @RedXConnTimeout
		if ($DebugInfo) {
			Write-Host " - $RunTime seconds" -Fore Yellow
		}
	}
 else {
		Write-Host @RedX
		if ($DebugInfo) {
			Write-Host " - $RunTime seconds" -Fore Yellow
		}
	}
}

function Get-ExecTime {
	$StepRunTime = (New-TimeSpan -Start $StepStart -End $StepEnd).TotalSeconds
	return [Math]::Round($StepRunTime, 2)
}

###Job preparation
#sp_BlitzWho
$InitScriptBlock = {
	function Invoke-BlitzWho {
		param (
			[string]$BlitzWhoQuery
		)
		$BlitzWhoCommand = new-object System.Data.SqlClient.SqlCommand
		$BlitzWhoCommand.CommandText = $BlitzWhoQuery
		$BlitzWhoCommand.CommandTimeout = 20
		$SqlConnection.Open()
		$BlitzWhoCommand.Connection = $SqlConnection
		$BlitzWhoCommand.ExecuteNonQuery() | Out-Null 
		$SqlConnection.Close()
	}
	function Invoke-FlagTableCheck {
		param (
			[string]$FlagTblDt
		)
		$CheckFlagTblQuery = new-object System.Data.SqlClient.SqlCommand
		$FlagTblQuery = "SELECT CASE `nWHEN OBJECT_ID(N'tempdb.dbo.BlitzWhoOutFlag_$FlagTblDt', N'U') "
		$FlagTblQuery = $FlagTblQuery + "IS NOT NULL THEN 'Y' `nELSE 'N' `nEND AS [FlagFound];"
		$CheckFlagTblQuery.CommandText = $FlagTblQuery
		$CheckFlagTblQuery.Connection = $SqlConnection
		$CheckFlagTblQuery.CommandTimeout = 30
		$CheckFlagTblAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
		$CheckFlagTblAdapter.SelectCommand = $CheckFlagTblQuery
		$CheckFlagTblSet = new-object System.Data.DataSet
		Try {
			$CheckFlagTblAdapter.Fill($CheckFlagTblSet) | Out-Null -ErrorAction Stop
			$SqlConnection.Close()
			[string]$IsFlagTbl = $CheckFlagTblSet.Tables[0].Rows[0]["FlagFound"]
            
		}
		Catch {
			[string]$IsFlagTbl = "X"
            
		}
		if ($IsFlagTbl -eq "Y") {
			$CleanupCommand = new-object System.Data.SqlClient.SqlCommand
			$Cleanup = "DROP TABLE tempdb.dbo.BlitzWhoOutFlag_$FlagTblDt;"
			$CleanupCommand.CommandText = $Cleanup
			$CleanupCommand.CommandTimeout = 20
			$SqlConnection.Open()
			$CleanupCommand.Connection = $SqlConnection
			$CleanupCommand.ExecuteNonQuery() | Out-Null 
			$SqlConnection.Close()
		}
		return $IsFlagTbl
	}
}

$MainScriptblock = {
	Param([string]$ConnStringIn , [string]$BlitzWhoIn, [string]$DirDateIn, [int]$BlitzWhoDelayIn)
	$SqlConnection = New-Object System.Data.SqlClient.SqlConnection
	$SqlConnection.ConnectionString = $ConnStringIn
	[int]$SuccessCount = 0
	[int]$FailedCount = 0
	[int]$FlagCheckRetry = 0    
	[string]$IsFlagTbl = "N"
	[string]$FlagErrCheck = "N"
	while (($IsFlagTbl -ne "Y") -and ($FlagCheckRetry -le 3)) {

		Try {
			Invoke-BlitzWho -BlitzWhoQuery $BlitzWhoIn 
			$SuccessCount += 1
		}
		Catch {
			$FailedCount += 1
		}
		[string]$IsFlagTbl = Invoke-FlagTableCheck -FlagTblDt $DirDateIn
		#Reset retry count if failures aren't consecutive
		if (($FlagErrCheck -eq "X") -and ($IsFlagTbl -ne "X")) {
			$FlagCheckRetry = 0
		}
		if ($IsFlagTbl -eq "N") {
			Start-Sleep -Seconds $BlitzWhoDelayIn
		}
		if ($IsFlagTbl -eq "X") {
            
			$FlagCheckRetry += 1
			$FlagErrCheck = $IsFlagTbl
			$IsFlagTbl = "N"
		}
	}
	if ($FailedCount -gt 0) {
		if ($SuccessCount -gt 0) {
			Write-Host " ->Successful runs: $SuccessCount" -NoNewLine
		}        
		Write-Host "; Failed runs: $FailedCount" -NoNewLine
		if ($FlagCheckRetry -gt 0) {
			Write-Host "; Retries: $FlagCheckRetry"
		}
		else {
			Write-Host ""
		}
	}
	else {
		Write-Host " ->Successful runs: $SuccessCount" -NoNewLine
		if ($FlagCheckRetry -gt 0) {
			Write-Host "; Consecutive retries: $FlagCheckRetry"
		}
		else {
			Write-Host ""
		}
	}
}

###Convert $ServerName from array to string 
[string]$ServerName = $ServerName -join ","

###Return help if requested during execution
if (("Y", "Yes" -Contains $Help) -or ("?", "Help" -Contains $ServerName)) {
	Get-PSBlitzHelp
	Exit
}

###Validate existence of dependencies
#Check resources path
if (!(Test-Path $ResourcesPath )) {
	Write-Host "The Resources directory was not found in $ScriptPath!" -fore red
	Write-Host " Make sure to download the latest release from https://github.com/VladDBA/PSBlitz/releases" -fore yellow
	Write-Host "and properly extract the contents" -fore yellow
	Read-Host -Prompt "Press Enter to close this window."
	Exit
}
#Check individual files
$MissingFiles = @()
foreach ($Rsc in $ResourceList) {
	$FileToTest = $ResourcesPath + "\" + $Rsc
	if (!(Test-Path $FileToTest -PathType Leaf)) {
		$MissingFiles += $Rsc
	}			
}
if ($MissingFiles.Count -gt 0) {
	Write-Host "The following files are missing from"$ResourcesPath":" -fore red
	foreach ($MIAFl in $MissingFiles) {
		Write-Host "  $MIAFl" -fore red
	}
	Write-Host " Make sure to download the latest release from https://github.com/VladDBA/PSBlitz/releases" -fore yellow
	Write-Host "and properly extract the contents" -fore yellow
	Read-Host -Prompt "Press Enter to close this window."
	Exit
}


	
###Switch to interactive mode if $ServerName is empty
if ([string]::IsNullOrEmpty($ServerName)) {
	Write-Host "Running in interactive mode"
	$InteractiveMode = 1
	##Instance
	$ServerName = Read-Host -Prompt "Server"
	#Make ServerName filename friendly and get host name
	if ($ServerName -like "*`"*") {
		$ServerName = $ServerName -replace "`"", ""
	}
	if ($ServerName -like "*\*") {
		$pos = $ServerName.IndexOf("\")
		$InstName = $ServerName.Substring($pos + 1)
		$HostName = $ServerName.Substring(0, $pos)
	}
 elseif ($ServerName -like "*,*") {
		$pos = $ServerName.IndexOf(",")
		$HostName = $ServerName.Substring(0, $pos)
		$InstName = $ServerName -replace ",", "-"
		if ($HostName -like "tcp:*") {
			$HostName = $HostName -replace "tcp:", ""
		}
		if ($HostName -like ".") {
			$pos = $HostName.IndexOf(".")
			$HostName = $HostName.Substring(0, $pos)

		}
	}
 else	{
		$InstName = $ServerName
		$HostName = $ServerName
	}
	if ($HostName -like "tcp:*") {
		$HostName = $HostName -replace "tcp:", ""
	}
	if ($HostName -like ".") {
		$pos = $HostName.IndexOf(".")
		$HostName = $HostName.Substring(0, $pos)
	}
	#Return help menu if $ServerName is ? or Help
	if ("?", "Help" -Contains $ServerName) {
		Get-PSBlitzHelp
		Read-Host -Prompt "Press Enter to close this window."
		Exit
	}

	##Have sp_BlitzIndex, sp_BlitzCache, sp_BlitzLock executed against a specific database
	$CheckDB = Read-Host -Prompt "Name of the database you want to check (leave empty for all)"
	##SQL Login
	$SQLLogin = Read-Host -Prompt "SQL login name (leave empty to use integrated security)"
	if (!([string]::IsNullOrEmpty($SQLLogin))) {
		##SQL Login pass
		$SQLPass = Read-Host -Prompt "Password "
	}
	##Indepth check 
	$IsIndepth = Read-Host -Prompt "Perform an in-depth check?[Y/N]"
	##sp_BlitzWho delay
	if (!([int]$BlitzWhoDelay = Read-Host "Seconds of delay between sp_BlizWho executions (empty defaults to 10)")) { 
		$BlitzWhoDelay = 10 
	}
	##Output file type
	if (!([string]$ToHTML = Read-Host -Prompt "Output the report as HTML instead of Excel?(empty defaults to N)[Y/N]")) {
		$ToHTML = "N"
	}
	##Zip output files
	if (!([string]$ZipOutput = Read-Host -Prompt "Create a zip archive of the output files?(empty defaults to N)[Y/N]")) {
		$ZipOutput = "N"
	}
}
else {
	$InteractiveMode = 0
	if ($ServerName -like "*\*") {
		$pos = $ServerName.IndexOf("\")
		$InstName = $ServerName.Substring($pos + 1)
		$HostName = $ServerName.Substring(0, $pos)
	}
 elseif ($ServerName -like "*,*") {
		$pos = $ServerName.IndexOf(",")
		$HostName = $ServerName.Substring(0, $pos)
		$InstName = $ServerName -replace ",", "-"
	}
 else	{
		$InstName = $ServerName
		$HostName = $ServerName
	}
}
	
#Set the string to replace for $CheckDB
if (!([string]::IsNullOrEmpty($CheckDB))) {
	$OldCheckDBStr = ";SET @DatabaseName = NULL;"
	$NewCheckDBStr = ";SET @DatabaseName = '" + $CheckDB + "';" 
}

###Define connection
$AppName = "PSBlitz " + $Vers
$SqlConnection = New-Object System.Data.SqlClient.SqlConnection
if (!([string]::IsNullOrEmpty($SQLLogin))) {
	$ConnString = "Server=$ServerName;Database=master;User Id=$SQLLogin;Password=$SQLPass;Connection Timeout=$ConnTimeout;Application Name=$AppName"
}
else {
	$ConnString = "Server=$ServerName;Database=master;trusted_connection=true;Connection Timeout=$ConnTimeout;Application Name=$AppName"
}
$SqlConnection.ConnectionString = $ConnString

###Test connection to instance
[int]$CmdTimeout = 100
Write-Host "Testing connection to instance $ServerName... " -NoNewLine
$ConnCheckQuery = new-object System.Data.SqlClient.SqlCommand
$Query = "SELECT GETDATE();"
$ConnCheckQuery.CommandText = $Query
$ConnCheckQuery.Connection = $SqlConnection
$ConnCheckQuery.CommandTimeout = $CmdTimeout
$ConnCheckAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
$ConnCheckAdapter.SelectCommand = $ConnCheckQuery
$ConnCheckSet = new-object System.Data.DataSet
Try {
	$StepStart = get-date
	$ConnCheckAdapter.Fill($ConnCheckSet) | Out-Null -ErrorAction Stop
	$SqlConnection.Close()
	$StepEnd = get-date
}
Catch {
	$StepEnd = get-date
	Invoke-ErrMsg
	$Help = Read-Host -Prompt "Need help?[Y/N]"
	if ($Help -eq "Y") {
		Get-PSBlitzHelp
		#Don't close the window automatically if in interactive mode
		if ($InteractiveMode -eq 1) {
			Read-Host -Prompt "Press Enter to close this window."
			Exit
		}
	}
 else {
		Exit
	}
}
if ($ConnCheckSet.Tables[0].Rows.Count -eq 1) {
	Write-Host @GreenCheck
	$StepRunTime = (New-TimeSpan -Start $StepStart -End $StepEnd).TotalSeconds
	$ConnTest = [Math]::Round($StepRunTime, 3)
	if ($DebugInfo) {
		Write-Host " - $ConnTest seconds"
	}
 else {
		if ($ConnTest -ge 2) {
			Write-Host "->Estimated response latency: $ConnTest seconds" -Fore Red
		}
		elseif ($ConnTest -ge 0.5) {
			Write-Host "->Estimated response latency: $ConnTest seconds" -Fore Yellow
		}
		elseif ($ConnTest -ge 0.2) {
			Write-Host "->Estimated response latency: $ConnTest seconds"
		}
		elseif ($ConnTest -lt 0.2) {
			Write-Host "->Estimated response latency: $ConnTest seconds" -Fore Green
		}

	}
}
###Test existence of value provided for $CheckDB
if (!([string]::IsNullOrEmpty($CheckDB))) {
	Write-Host "Checking existence of database $CheckDB..."
	$CheckDBQuery = new-object System.Data.SqlClient.SqlCommand
	$DBQuery = "SELECT [name] from sys.databases WHERE [name] = '$CheckDB' AND [state] = 0;"
	$CheckDBQuery.CommandText = $DBQuery
	$CheckDBQuery.Connection = $SqlConnection
	$CheckDBQuery.CommandTimeout = 100
	$CheckDBAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
	$CheckDBAdapter.SelectCommand = $CheckDBQuery
	$CheckDBSet = new-object System.Data.DataSet
	$CheckDBAdapter.Fill($CheckDBSet) | Out-Null
	$SqlConnection.Close()
	Try {
		if ($CheckDBSet.Tables[0].Rows[0]["name"] -eq $CheckDB) {
			Write-Host "->Database $CheckDB - " -NoNewLine -ErrorAction Stop
			Write-Host "is online" -fore green -ErrorAction Stop
		}
	}
 Catch {
		Write-Host "Database $CheckDB either does not exist or is offline" -fore red
		$InstanceWide = Read-Host -Prompt "Switch to instance-wide plan cache, index, and deadlock check?[Y/N]"
		if ($InstanceWide -eq "Y") {
			$CheckDB = ""
		}
		else {
			$Help = Read-Host -Prompt "Need help?[Y/N]"
			if ($Help -eq "Y") {
				Get-PSBlitzHelp
				#Don't close the window automatically if in interactive mode
				if ($InteractiveMode -eq 1) {
					Read-Host -Prompt "Press Enter to close this window."
					Exit
				}
			}
			else {
				Exit
			}
		}
	}

}

###Create directories
#Turn current date time into string for output directory name
$sdate = get-date
$DirDate = $sdate.ToString("yyyyMMddHHmm")
#Set output directory
#if (!([string]::IsNullOrEmpty($CheckDB))) {
#	$OutDir = $scriptPath + "\" + $HostName + "_" + $InstName + "_" + $CheckDB + "_" + $DirDate
#}
#else {
#	$OutDir = $scriptPath + "\" + $HostName + "_" + $InstName + "_" + $DirDate
#}
if ((!([string]::IsNullOrEmpty($OutputDir))) -and (Test-Path $OutputDir)) {
	if ($OutputDir -notlike "*\") {
		$OutputDir = $OutputDir + "\"
	}
	if (!([string]::IsNullOrEmpty($CheckDB))) {
		$OutDir = $OutputDir + $HostName + "_" + $InstName + "_" + $CheckDB + "_" + $DirDate
	}
	else {
		$OutDir = $OutputDir + $HostName + "_" + $InstName + "_" + $DirDate		
	}
}
else {
	if (!([string]::IsNullOrEmpty($CheckDB))) {
		$OutDir = $scriptPath + "\" + $HostName + "_" + $InstName + "_" + $CheckDB + "_" + $DirDate
	}
	else {
		$OutDir = $scriptPath + "\" + $HostName + "_" + $InstName + "_" + $DirDate
	}
}
if ($ZipOutput -eq "Y") {
	if (!([string]::IsNullOrEmpty($CheckDB))) {
		$ZipFile = $HostName + "_" + $InstName + "_" + $CheckDB + "_" + $DirDate + ".zip"
	}
 else {
		$ZipFile = $HostName + "_" + $InstName + "_" + $DirDate + ".zip"
	}
}
if ($DebugInfo) {
	Write-Host " Output directory: $OutDir" -Fore Yellow
}

#Check if output directory exists
if (!(Test-Path $OutDir)) {
	New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
}
#Set plan output directory
$PlanOutDir = $OutDir + "\" + "Plans"
#Check if plan output directory exists
if (!(Test-Path $PlanOutDir)) {
	New-Item -ItemType Directory -Force -Path $PlanOutDir | Out-Null
}
#Set deadlock graph output directory
$XDLOutDir = $OutDir + "\" + "Deadlocks"
#Check if deadlock graph output directory exists
if (!(Test-Path $XDLOutDir)) {
	New-Item -ItemType Directory -Force -Path $XDLOutDir | Out-Null
}

if ($ToHTML -eq "Y") {
	#Set HTML files output directory
	$HTMLOutDir = $OutDir + "\" + "HTMLFiles"
	if (!(Test-Path $HTMLOutDir)) {
		New-Item -ItemType Directory -Force -Path $HTMLOutDir | Out-Null
	}
	$HTMLPre = @"
	<!DOCTYPE html>
	<html>
	<head>
	<style>
	body 
	{ 
	background-color:#FFFFFF;
	font-family:Tahoma;
	font-size:11pt; 
	}
	table {
        margin-left: auto;
        margin-right: auto;
		border-spacing: 1px;
    }
	th {
		background-color: dodgerblue;
		color: white;
		font-weight: bold;
		padding: 5px;
		text-align: center;
	}
	td, th {
		border: 1px solid black;
		padding: 5px;
	}
	td:first-child {
		font-weight: bold;
		text-align: center;
	}
	h1 {
		text-align: center;
	}
	h2 {
		test-align: Left;
	}
	</style>
	
"@
	$URLRegex = '(?i)\b((?:https?://|www\d{0,3}[.]|[a-z0-9.\-]+[.][a-z]{2,4}/)(?:[^\s()<>]+|\(([^\s()<>]+|(\([^\s()<>]+\)))*\))+(?:\(([^\s()<>]+|(\([^\s()<>]+\)))*\)|[^\s`!()\[\]{};:\".,<>?«»“”]))'
}
else {
	###Set output Excel name and destination
	if (!([string]::IsNullOrEmpty($CheckDB))) {
		$OutExcelFName = "Active_$InstName_$CheckDB.xlsx"
	}
	else {
		$OutExcelFName = "Active_$InstName.xlsx"
	}
	$OutExcelF = $OutDir + "\" + $OutExcelFName
	###Copy Excel template to output directory
	<#
	This is a fix for https://github.com/VladDBA/PSBlitz/issues/4
	#>
	Copy-Item $OrigExcelF  -Destination $OutExcelF
}
#Set output table for sp_BlitzWho
#$BlitzWhoOut = "BlitzWho_" + $DirDate
#Set replace strings
$OldBlitzWhoOut = "@OutputTableName = 'BlitzWho_..PSBlitzReplace..',"
$NewBlitzWhoOut = "@OutputTableName = 'BlitzWho_$DirDate',"

if ($ToHTML -ne "Y") {
	###Open Excel
	if ($DebugInfo) {
		$ErrorActionPreference = "Continue"
		Write-Host "Opening excel file" -fore yellow
	}
	else {
		#Do not display the occasional "out of memory" errors
		$ErrorActionPreference = "SilentlyContinue"
	}

	$ExcelApp = New-Object -comobject Excel.Application
	if ($DebugInfo) {
		$ExcelApp.visible = $True
	}
	else {
		$ExcelApp.visible = $False
	}
	$ExcelFile = $ExcelApp.Workbooks.Open("$OutExcelF")
	$ExcelApp.DisplayAlerts = $False
}
###Check instance uptime
$UptimeQuery = new-object System.Data.SqlClient.SqlCommand
$Query = "SELECT CAST(DATEDIFF(HH, [sqlserver_start_time], GETDATE()) / 24.00 AS NUMERIC(23, 2)) AS [uptime_days]	"
$Query = $Query + "`nFROM [sys].[dm_os_sys_info];"
$UptimeQuery.CommandText = $Query
$UptimeQuery.Connection = $SqlConnection
$UptimeQuery.CommandTimeout = 100
$UptimeAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
$UptimeAdapter.SelectCommand = $UptimeQuery
$UptimeSet = new-object System.Data.DataSet
$UptimeAdapter.Fill($UptimeSet) | Out-Null
$SqlConnection.Close()
if ($UptimeSet.Tables[0].Rows[0]["uptime_days"] -lt 7.00) {
	[string]$DaysUp = $UptimeSet.Tables[0].Rows[0]["uptime_days"]
	Write-Host "Warning: Instance uptime is less than 7 days - $DaysUp" -Fore Red
	Write-Host "->Diagnostics data might not be reliable with less than 7 days of uptime." -Fore Red
}


#####################################################################################
#						Check start													#
#####################################################################################
try {
	###Set completion flag
	$TryCompleted = "N"

	Write-Host $("-" * 80)
	Write-Host "       Starting" -NoNewLine 
	if ($IsIndepth -eq "Y") {
		Write-Host " in-depth" -NoNewLine
	}
	if (!([string]::IsNullOrEmpty($CheckDB))) {
		Write-Host " database-specific" -NoNewLine
	}
	Write-Host " check for $ServerName" 
	Write-Host $("-" * 80)

	if (($DebugInfo) -and ($MaxTimeout -ne 800)) {
		Write-Host " ->MaxTimeout has been set to $MaxTimeout"
	}

	###Load sp_BlitzWho in memory
	[string]$Query = [System.IO.File]::ReadAllText("$ResourcesPath\spBlitzWho_NonSPLatest.sql")
	#Replace output table name
	[string]$BlitzWhoRepl = $Query -replace $OldBlitzWhoOut, $NewBlitzWhoOut

	###Execution start time
	$StartDate = get-date
	###Collecting first pass of sp_BlitzWho data
	$JobName = "BlitzWho"
	Write-Host " Starting BlitzWho background process... " -NoNewline
	
	$Job = Start-Job -Name $JobName -InitializationScript $InitScriptBlock -ScriptBlock $MainScriptblock -ArgumentList $ConnString, $BlitzWhoRepl, $DirDate, $BlitzWhoDelay
	$JobStatus = $Job | Select-Object -ExpandProperty State
	if ($JobStatus -ne "Running") {
		Write-Host @RedX
		if ($DebugInfo) {
			Write-Host ""
		}
		Write-Host " ->Switching to foreground execution."
		Invoke-BlitzWho -BlitzWhoQuery $BlitzWhoRepl -IsInLoop N
		$BlitzWhoPass += 1
	}
 else {
		Write-Host @GreenCheck
		if ($DebugInfo) {
			Write-Host ""
		}
		Write-Host " ->sp_BlitzWho will collect data every $BlitzWhoDelay seconds."
	}


	#####################################################################################
	#						Instance Info												#
	#####################################################################################
	Write-Host " Retrieving instance information... " -NoNewLine
	$CmdTimeout = 600
	[string]$Query = [System.IO.File]::ReadAllText("$ResourcesPath\GetInstanceInfo.sql")
	$InstanceInfoQuery = new-object System.Data.SqlClient.SqlCommand
	$InstanceInfoQuery.CommandText = $Query
	$InstanceInfoQuery.Connection = $SqlConnection
	$InstanceInfoQuery.CommandTimeout = $CmdTimeout
	$InstanceInfoAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
	$InstanceInfoAdapter.SelectCommand = $InstanceInfoQuery
	$InstanceInfoSet = new-object System.Data.DataSet
	try {
		$StepStart = get-date
		$InstanceInfoAdapter.Fill($InstanceInfoSet) | Out-Null -ErrorAction Stop
		$SqlConnection.Close()
		$StepEnd = get-date
		Write-Host @GreenCheck
		$StepRunTime = (New-TimeSpan -Start $StepStart -End $StepEnd).TotalSeconds
		$RunTime = [Math]::Round($StepRunTime, 2)
		if ($DebugInfo) {
			Write-Host " - $RunTime seconds" -Fore Yellow
		}
		$StepOutcome = "Success"
	}
 Catch {
		$StepEnd = get-date
		Invoke-ErrMsg
		$StepOutcome = "Failure"
	}
		
	if ($StepOutcome -eq "Success") {
		$InstanceInfoTbl = New-Object System.Data.DataTable
		$InstanceInfoTbl = $InstanceInfoSet.Tables[0]
		$ResourceInfoTbl = New-Object System.Data.DataTable
		$ResourceInfoTbl = $InstanceInfoSet.Tables[1]
		
		if ($ToHTML -eq "Y") {
			if ($DebugInfo) {
				Write-Host " ->Converting instance info to HTML" -fore yellow
			}
			$InstanceInfoTbl.Columns.Add("Estimated Response Latency (Sec)", [decimal]) | Out-Null
			$InstanceInfoTbl.Rows[0]["Estimated Response Latency (Sec)"] = $ConnTest

			$htmlTable1 = $InstanceInfoTbl | Select-Object  @{Name = "Machine Name"; Expression = { $_."machine_name" } },
			@{Name = "Instance Name"; Expression = { $_."instance_name" } }, 
			@{Name = "Version"; Expression = { $_."product_version" } }, 
			@{Name = "Product Level"; Expression = { $_."product_level" } },
			@{Name = "Patch Level"; Expression = { $_."patch_level" } },
			@{Name = "Edition"; Expression = { $_."edition" } }, 
			@{Name = "Is Clustered?"; Expression = { $_."is_clustered" } }, 
			@{Name = "Is AlwaysOnAG?"; Expression = { $_."always_on_enabled" } }, 
			@{Name = "Last Startup"; Expression = { $_."instance_last_startup" } },
			@{Name = "Uptime (days)"; Expression = { $_."uptime_days" } },
			"Estimated Response Latency (Sec)" | ConvertTo-Html -As Table -Fragment

			if ($DebugInfo) {
				Write-Host " ->Converting resource info to HTML" -fore yellow
			}    
			$htmlTable2 = $ResourceInfoTbl | Select-Object  @{Name = "Logical Cores"; Expression = { $_."logical_cpu_cores" } }, 
			@{Name = "Physical Cores"; Expression = { $_."physical_cpu_cores" } }, 
			@{Name = "Physical memory GB"; Expression = { $_."physical_memory_GB" } }, 
			@{Name = "Max Server Memory GB"; Expression = { $_."max_server_memory_GB" } }, 
			@{Name = "Target Server Memory GB"; Expression = { $_."target_server_memory_GB" } },
			@{Name = "Total Memory Used GB"; Expression = { $_."total_memory_used_GB" } } | ConvertTo-Html -As Table -Fragment
			$HtmlTabName = "Instance Overview"
			$html = $HTMLPre + @"
    <title>$HtmlTabName</title>
    </head>
    <body>
<h1>$HtmlTabName</h1>
<h2>Instance information</h2>
$htmlTable1
<b>
<h2>Resource information</h2>
$htmlTable2
</body>
</html>
"@
			if ($DebugInfo) {
				Write-Host " ->Writing HTML file." -fore yellow
			} 			
			$html | Out-File -Encoding utf8 -FilePath "$HTMLOutDir\InstanceInfo.html"
		}
		else {
			###Populating the "Instance Info" sheet
			$ExcelSheet = $ExcelFile.Worksheets.Item("Instance Info")
			##Instance Info section
			#Specify at which row in the sheet to start adding the data
			$ExcelStartRow = 3
			#Specify with which column in the sheet to start
			$ExcelColNum = 1
			#Set counter used for row retrieval
			$RowNum = 0

			#List of columns that should be returned from the data set
			$DataSetCols = @("machine_name", "instance_name", "product_version", "product_level",
				"patch_level", "edition", "is_clustered", "always_on_enabled", "instance_last_startup",
				"uptime_days", "net_latency")

			if ($DebugInfo) {
				Write-Host " ->Writing instance info to Excel" -fore yellow
			}
			#Loop through each Excel row
			foreach ($row in $InstanceInfoTbl) {
				<#
				Loop through each data set column of current row and fill the corresponding 
				Excel cell
				#>
				foreach ($col in $DataSetCols) {			
					#Fill Excel cell with value from the data set
					if ($col -eq "net_latency") {
						$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $ConnTest
					}
					else {
						$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $InstanceInfoTbl.Rows[$RowNum][$col]
					}
					$ExcelColNum += 1
				}

				#move to the next row in the spreadsheet
				$ExcelStartRow += 1
				#move to the next row in the data set
				$RowNum += 1
				# reset Excel column number so that next row population begins with column 1
				$ExcelColNum = 1
			}

			##Resource Info section
			#Specify at which row in the sheet to start adding the data
			$ExcelStartRow = 8
			#Specify with which column in the sheet to start
			$ExcelColNum = 1
			#Set counter used for row retrieval
			$RowNum = 0

			#List of columns that should be returned from the data set
			$DataSetCols = @("logical_cpu_cores", "physical_cpu_cores", "physical_memory_GB", "max_server_memory_GB", "target_server_memory_GB",
				"total_memory_used_GB")

			if ($DebugInfo) {
				Write-Host " ->Writing resource info to Excel" -fore yellow
			}
			#Loop through each Excel row
			foreach ($row in $ResourceInfoTbl) {
				<#
				Loop through each data set column of current row and fill the corresponding 
				Excel cell
				#>
				foreach ($col in $DataSetCols) {			
					#Fill Excel cell with value from the data set
					$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $ResourceInfoTbl.Rows[$RowNum][$col]
					$ExcelColNum += 1
				}

				#move to the next row in the spreadsheet
				$ExcelStartRow += 1
				#move to the next row in the data set
				$RowNum += 1
				# reset Excel column number so that next row population begins with column 1
				$ExcelColNum = 1
			}

			##Saving file 
			$ExcelFile.Save()
		}
		##Cleaning up variables 
		Remove-Variable -Name ResourceInfoTbl
		Remove-Variable -Name InstanceInfoTbl
		Remove-Variable -Name InstanceInfoSet
	}

	if ($JobStatus -ne "Running") {
		Invoke-BlitzWho -BlitzWhoQuery $BlitzWhoRepl -IsInLoop N
		$BlitzWhoPass += 1
	}

	#####################################################################################
	#						TempDB usage info	 										#
	#####################################################################################
	Write-Host " Retrieving TempDB usage data... " -NoNewLine
	$CmdTimeout = 600
	[string]$Query = [System.IO.File]::ReadAllText("$ResourcesPath\GetTempDBUsageInfo.sql")
	[string]$Query = $Query -replace "..PSBlitzReplace..", "$DirDate"
	$TempDBSelect = new-object System.Data.SqlClient.SqlCommand
	$TempDBSelect.CommandText = $Query
	$TempDBSelect.Connection = $SqlConnection
	$TempDBSelect.CommandTimeout = $CmdTimeout
	$TempDBAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
	$TempDBAdapter.SelectCommand = $TempDBSelect
	$TempDBSet = new-object System.Data.DataSet
	try {
		$StepStart = get-date
		$TempDBAdapter.Fill($TempDBSet) | Out-Null -ErrorAction Stop
		$SqlConnection.Close()
		$StepEnd = get-date
		Write-Host @GreenCheck
		$StepRunTime = (New-TimeSpan -Start $StepStart -End $StepEnd).TotalSeconds
		$RunTime = [Math]::Round($StepRunTime, 2)
		if ($DebugInfo) {
			Write-Host " - $RunTime seconds" -Fore Yellow
		}
		$StepOutcome = "Success"
	}
 Catch {
		$StepEnd = get-date
		Invoke-ErrMsg
		$StepOutcome = "Failure"
	}
		
	if ($StepOutcome -eq "Success") {
		$TempDBTbl = New-Object System.Data.DataTable
		$TempDBTbl = $TempDBSet.Tables[0]
		
		$TempTabTbl = New-Object System.Data.DataTable
		$TempTabTbl = $TempDBSet.Tables[1]

		$TempDBSessTbl = New-Object System.Data.DataTable
		$TempDBSessTbl = $TempDBSet.Tables[2]

		if ($ToHTML -eq "Y") {
			if ($DebugInfo) {
				Write-Host " ->Converting TempDB info to HTML" -fore yellow
			}
			$htmlTable1 = $TempDBTbl | Select-Object @{Name = "Data Files"; Expression = { $_."data_files" } },
			@{Name = "Total Size MB"; Expression = { $_."total_size_MB" } },
			@{Name = "Free Space MB"; Expression = { $_."free_space_MB" } },
			@{Name = "% Free"; Expression = { $_."percent_free" } },
			@{Name = "Internal Objects MB"; Expression = { $_."internal_objects_MB" } },
			@{Name = "User Objects MB"; Expression = { $_."user_objects_MB" } },
			@{Name = "Version Store MB"; Expression = { $_."version_store_MB" } } | ConvertTo-Html -As Table -Fragment

			if ($DebugInfo) {
				Write-Host " ->Converting TempDB table info to HTML" -fore yellow
			}
			$htmlTable2 = $TempTabTbl | Select-Object @{Name = "Table Name"; Expression = { $_."table_name" } }, 
			@{Name = "Rows"; Expression = { $_."rows" } },
			@{Name = "Used Space MB"; Expression = { $_."used_space_MB" } }, 
			@{Name = "Reserved Space MB"; Expression = { $_."reserved_space_MB" } } | ConvertTo-Html -As Table -Fragment
            
			if ($DebugInfo) {
				Write-Host " ->Converting TempDB session usage info to HTML" -fore yellow
			}
			$htmlTable3 = $TempDBSessTbl | Select-Object @{Name = "Session ID"; Expression = { $_."session_id" } },
			@{Name = "Request ID"; Expression = { $_."request_id" } },
			@{Name = "Database Name"; Expression = { $_."database" } },
			@{Name = "Total Allocation User Objects MB"; Expression = { $_."total_allocation_user_objects_MB" } },
			@{Name = "Net Allocation User Objects MB"; Expression = { $_."net_allocation_user_objects_MB" } },
			@{Name = "Total Allocation Internal Objects MB"; Expression = { $_."total_allocation_internal_objects_MB" } },
			@{Name = "Net Allocation Internal Objects MB"; Expression = { $_."net_allocation_internal_objects_MB" } },
			@{Name = "Total Allocation MB"; Expression = { $_."total_allocation_MB" } },
			@{Name = "Net Allocation MB"; Expression = { $_."net_allocation_MB" } },
			@{Name = "Query Text"; Expression = { $_."query_text" } },
			@{Name = "Query Hash"; Expression = { Get-HexString -HexInput $_."query_hash" } },
			@{Name = "Query Plan Hash"; Expression = { Get-HexString -HexInput $_."query_plan_hash" } } | ConvertTo-Html -As Table -Fragment
			$HtmlTabName = "TempDB Info"
			$html = $HTMLPre + @"
<title>$HtmlTabName</title>
</head>
<body>
<h1>$HtmlTabName</h1>
<h2>TempDB space usage</h2>
$htmlTable1
<br>
<h2>Top 30 temp tables by reserved space</h2>
$htmlTable2
<br>
<h2>Top 30 sessions using TempDB by total allocation</h2>
$htmlTable3
</body>
</html>
"@

			if ($DebugInfo) {
				Write-Host " ->Writing HTML file." -fore yellow
			}
			$html | Out-File -Encoding utf8 -FilePath "$HTMLOutDir\TempDBInfo.html"

		}
		else {

			###Populating the "TempDB" sheet
			$ExcelSheet = $ExcelFile.Worksheets.Item("TempDB")
			##TempDB space usage section
			#Specify at which row in the sheet to start adding the data
			$ExcelStartRow = 3
			#Specify with which column in the sheet to start
			$ExcelColNum = 1
			#Set counter used for row retrieval
			$RowNum = 0

			#List of columns that should be returned from the data set
			$DataSetCols = @("data_files", "total_size_MB", "free_space_MB", "percent_free", "internal_objects_MB",
				"user_objects_MB", "version_store_MB")

			if ($DebugInfo) {
				Write-Host " ->Writing TempDB space usage results to Excel" -fore yellow
			}
			#Loop through each Excel row
			foreach ($row in $TempDBTbl) {
				<#
				Loop through each data set column of current row and fill the corresponding 
				Excel cell
				#>
				foreach ($col in $DataSetCols) {			
					#Fill Excel cell with value from the data set
					$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $TempDBTbl.Rows[$RowNum][$col]
					$ExcelColNum += 1
				}

				#move to the next row in the spreadsheet
				$ExcelStartRow += 1
				#move to the next row in the data set
				$RowNum += 1
				# reset Excel column number so that next row population begins with column 1
				$ExcelColNum = 1
			}

			##Temp tables section
			#Specify at which row in the sheet to start adding the data
			$ExcelStartRow = 8
			#Specify with which column in the sheet to start
			$ExcelColNum = 1
			#Set counter used for row retrieval
			$RowNum = 0

			#List of columns that should be returned from the data set
			$DataSetCols = @("table_name", "rows", "used_space_MB", "reserved_space_MB")

			if ($DebugInfo) {
				Write-Host " ->Writing temp table results to Excel" -fore yellow
			}
			#Loop through each Excel row
			foreach ($row in $TempTabTbl) {
				<#
				Loop through each data set column of current row and fill the corresponding 
				Excel cell
				#>
				foreach ($col in $DataSetCols) {
					#Fill Excel cell with value from the data set
					$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $TempTabTbl.Rows[$RowNum][$col]
					$ExcelColNum += 1
				}

				#move to the next row in the spreadsheet
				$ExcelStartRow += 1
				#move to the next row in the data set
				$RowNum += 1
				# reset Excel column number so that next row population begins with column 1
				$ExcelColNum = 1
			}

			##TempDB session usage section
			#Specify at which row in the sheet to start adding the data
			$ExcelStartRow = 8
			#Specify with which column in the sheet to start
			$ExcelColNum = 6
			#Set counter used for row retrieval
			$RowNum = 0

			#List of columns that should be returned from the data set
			$DataSetCols = @("session_id", "request_id", "database", "total_allocation_user_objects_MB",
				"net_allocation_user_objects_MB", "total_allocation_internal_objects_MB", "net_allocation_internal_objects_MB",
				"total_allocation_MB", "net_allocation_MB", "query_text", "query_hash", "query_plan_hash")

			if ($DebugInfo) {
				Write-Host " ->Writing sessions using TempDB results to Excel" -fore yellow
			}
			#Loop through each Excel row
			foreach ($row in $TempDBSessTbl) {
				<#
				Loop through each data set column of current row and fill the corresponding 
				Excel cell
				#>
				foreach ($col in $DataSetCols) {			
					#Fill Excel cell with value from the data set
					#Properly handling Query Hash and Plan Hash hex values 
					if ("query_hash", "query_plan_hash" -Contains $col) {
						$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = Get-HexString -HexInput $TempDBSessTbl.Rows[$RowNum][$col]
						#move to the next column
						$ExcelColNum += 1
						#move to the top of the loop
						Continue
					}
					$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $TempDBSessTbl.Rows[$RowNum][$col]
					$ExcelColNum += 1
				}

				#move to the next row in the spreadsheet
				$ExcelStartRow += 1
				#move to the next row in the data set
				$RowNum += 1
				# reset Excel column number so that next row population begins with column 1
				$ExcelColNum = 6
			}
			##Saving file 
			$ExcelFile.Save()
		}
		##Cleaning up variables
		Remove-Variable -Name TempDBSessTbl
		Remove-Variable -Name TempTabTbl
		Remove-Variable -Name TempDBTbl
		Remove-Variable -Name TempDBSet		
	}

	if ($JobStatus -ne "Running") {
		Invoke-BlitzWho -BlitzWhoQuery $BlitzWhoRepl -IsInLoop N
		$BlitzWhoPass += 1
	}

	#####################################################################################
	#						sp_Blitz 													#
	#####################################################################################
	Write-Host " Running sp_Blitz... " -NoNewLine
	[string]$Query = [System.IO.File]::ReadAllText("$ResourcesPath\spBlitz_NonSPLatest.sql")
	if (($IsIndepth -eq "Y") -and ([string]::IsNullOrEmpty($CheckDB))) {
		[string]$Query = $Query -replace ";SET @CheckUserDatabaseObjects = 0;", ";SET @CheckUserDatabaseObjects = 1;"
	}
	$CmdTimeout = 600
	$BlitzQuery = new-object System.Data.SqlClient.SqlCommand
	$BlitzQuery.CommandText = $Query
	$BlitzQuery.Connection = $SqlConnection
	$BlitzQuery.CommandTimeout = $CmdTimeout
	$BlitzAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
	$BlitzAdapter.SelectCommand = $BlitzQuery
	$BlitzSet = new-object System.Data.DataSet
	Try {
		$StepStart = get-date
		$BlitzAdapter.Fill($BlitzSet) | Out-Null -ErrorAction Stop
		$SqlConnection.Close()
		$StepEnd = get-date
		Write-Host @GreenCheck
		$StepRunTime = (New-TimeSpan -Start $StepStart -End $StepEnd).TotalSeconds
		$RunTime = [Math]::Round($StepRunTime, 2)
		if ($DebugInfo) {
			Write-Host " - $RunTime seconds" -Fore Yellow
		}
		$StepOutcome = "Success"
	}
 Catch {
		$StepEnd = get-date
		Invoke-ErrMsg
		$StepOutcome = "Failure"
	}
		
	if ($StepOutcome -eq "Success") {
		$BlitzTbl = New-Object System.Data.DataTable
		$BlitzTbl = $BlitzSet.Tables[0]

		if ($ToHTML -eq "Y") {
			$tableName = "Instance Health"
			if ($DebugInfo) {
				Write-Host " ->Converting sp_Blitz output to HTML" -fore yellow
			}
			$htmlTable = $BlitzTbl | Select-Object "Priority", "FindingsGroup", "Finding", "DatabaseName", "Details", "URL" | Where-Object -FilterScript { ($_."Finding" -ne "SQL Server First Responder Kit" ) -and ("Rundate", "Thanks!" -notcontains $_."FindingsGroup") } | ConvertTo-Html -As Table -Fragment
			$htmlTable = $htmlTable -replace $URLRegex, '<a href="$&" target="_blank">$&</a>'
			$html = $HTMLPre + @"
<title>$tableName</title>
</head>
<body>
<h1>$tableName</h1>
$htmlTable
</body>
</html>
"@

			if ($DebugInfo) {
				Write-Host " ->Writing HTML file." -fore yellow
			} 
			$html | Out-File -Encoding utf8 -FilePath "$HTMLOutDir\spBlitz.html"

		}
		else {
			##Populating the "sp_Blitz" sheet
			$ExcelSheet = $ExcelFile.Worksheets.Item("sp_Blitz")
			#Specify at which row in the sheet to start adding the data
			$ExcelStartRow = $DefaultStartRow
			#Specify with which column in the sheet to start
			$ExcelColNum = 1
			#Set counter used for row retrieval
			$RowNum = 0

			#List of columns that should be returned from the data set
			$DataSetCols = @("Priority", "FindingsGroup", "Finding" , "DatabaseName",
				"Details", "URL")
			if ($DebugInfo) {
				Write-Host " ->Writing sp_Blitz results to Excel" -fore yellow
			}
			#Loop through each Excel row
			foreach ($row in $BlitzTbl) {
				<#
				Loop through each data set column of current row and fill the corresponding 
				Excel cell
				#>
				foreach ($col in $DataSetCols) {
					#Fill Excel cell with value from the data set
					if ($col -eq "URL") {
						#Make URLs clickable
						if ($BlitzTbl.Rows[$RowNum][$col] -like "http*") {
							$ExcelSheet.Hyperlinks.Add($ExcelSheet.Cells.Item($ExcelStartRow, 3),
								$BlitzTbl.Rows[$RowNum][$col], "", "Click for more info",
								$BlitzTbl.Rows[$RowNum]["Finding"]) | Out-Null
						}
					}
					else {
						$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $BlitzTbl.Rows[$RowNum][$col]
					}
					#move to the next column
					$ExcelColNum += 1
				}

				#move to the next row in the spreadsheet
				$ExcelStartRow += 1
				#move to the next row in the data set
				$RowNum += 1
				# reset Excel column number so that next row population begins with column 1
				$ExcelColNum = 1
			}

			##Saving file 
			$ExcelFile.Save()
		}
		##Cleaning up variables 
		Remove-Variable -Name BlitzTbl
		Remove-Variable -Name BlitzSet		
	}

	if ($JobStatus -ne "Running") {
		Invoke-BlitzWho -BlitzWhoQuery $BlitzWhoRepl -IsInLoop N
		$BlitzWhoPass += 1
	}


	#####################################################################################
	#						sp_BlitzFirst 30 seconds									#
	#####################################################################################
	Write-Host " Running sp_BlitzFirst @Seconds = 30... " -NoNewLine
	$CmdTimeout = 600
	[string]$Query = [System.IO.File]::ReadAllText("$ResourcesPath\spBlitzFirst_NonSPLatest.sql")
	$BlitzFirstQuery = new-object System.Data.SqlClient.SqlCommand
	$BlitzFirstQuery.CommandText = $Query
	$BlitzFirstQuery.Connection = $SqlConnection
	$BlitzFirstQuery.CommandTimeout = $CmdTimeout
	$BlitzFirstAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
	$BlitzFirstAdapter.SelectCommand = $BlitzFirstQuery
	$BlitzFirstSet = new-object System.Data.DataSet
	Try {
		$StepStart = get-date
		$BlitzFirstAdapter.Fill($BlitzFirstSet) | Out-Null -ErrorAction Stop
		$SqlConnection.Close()
		$StepEnd = get-date
		Write-Host @GreenCheck
		$StepRunTime = (New-TimeSpan -Start $StepStart -End $StepEnd).TotalSeconds
		$RunTime = [Math]::Round($StepRunTime, 2)
		if ($DebugInfo) {
			Write-Host " - $RunTime seconds" -Fore Yellow
		}
		$StepOutcome = "Success"
	}
 Catch {
		$StepEnd = get-date
		Invoke-ErrMsg
		$StepOutcome = "Failure"
	}
		
	if ($StepOutcome -eq "Success") {
		$BlitzFirstTbl = New-Object System.Data.DataTable
		$BlitzFirstTbl = $BlitzFirstSet.Tables[0]

		if ($ToHTML -eq "Y") {
			if ($DebugInfo) {
				Write-Host " ->Converting sp_BlitzFirst output to HTML" -fore yellow
			}
			$htmlTable = $BlitzFirstTbl | Select-Object "Priority", "FindingsGroup", "Finding", 
			@{Name = "Details"; Expression = { $_."Details".Replace('ClickToSeeDetails', '') } }, "URL" | Where-Object -FilterScript { ( "0", "255" -NotContains $_."Priority" ) } | ConvertTo-Html -As Table -Fragment
			$htmlTable = $htmlTable -replace $URLRegex, '<a href="$&" target="_blank">$&</a>'
			$HtmlTabName = "What's happening on the instance now?"
			$html = $HTMLPre + @"
<title>$HtmlTabName</title>
</head>
<body>
<h1>$HtmlTabName</h1>
<h2>30 seconds time-frame</h2>
$htmlTable
</body>
</html>
"@

			if ($DebugInfo) {
				Write-Host " ->Writing HTML file." -fore yellow
			} 
			$html | Out-File -Encoding utf8 -FilePath "$HTMLOutDir\BlitzFirst30s.html"
		}
		else {

			##Populating the "sp_BlitzFirst 30s" sheet
			$ExcelSheet = $ExcelFile.Worksheets.Item("sp_BlitzFirst 30s")
			#Specify at which row in the sheet to start adding the data
			$ExcelStartRow = $DefaultStartRow
			#Specify with which column in the sheet to start
			$ExcelColNum = 1
			#Set counter used for row retrieval
			$RowNum = 0

			$DataSetCols = @("Priority", "FindingsGroup", "Finding", "Details", "URL")

			if ($DebugInfo) {
				Write-Host " ->Writing sp_BlitzFirst results to Excel" -fore yellow
			}
			#Loop through each Excel row
			foreach ($row in $BlitzFirstTbl) {
				#Loop through each data set column of current row and fill the corresponding 
				# Excel cell
				foreach ($col in $DataSetCols) {
					#Fill Excel cell with value from the data set
					if ($col -eq "URL") {
						if ($BlitzFirstTbl.Rows[$RowNum][$col] -like "http*") {
							$ExcelSheet.Hyperlinks.Add($ExcelSheet.Cells.Item($ExcelStartRow, 3),
								$BlitzFirstTbl.Rows[$RowNum][$col], "", "Click for more info",
								$BlitzFirstTbl.Rows[$RowNum]["Finding"]) | Out-Null
						}
					}
					else {
						$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $BlitzFirstTbl.Rows[$RowNum][$col]
					}
					#move to the next column
					$ExcelColNum += 1
				}

				#move to the next row in the spreadsheet
				$ExcelStartRow += 1
				#move to the next row in the data set
				$RowNum += 1
				# reset Excel column number so that next row population begins with column 1
				$ExcelColNum = 1
			}
			##Saving file 
			$ExcelFile.Save()
		}
		Remove-Variable -Name BlitzFirstTbl
		Remove-Variable -Name BlitzFirstSet
	}
	if ($JobStatus -ne "Running") {
		Invoke-BlitzWho -BlitzWhoQuery $BlitzWhoRepl -IsInLoop N
		$BlitzWhoPass += 1
	}

	#####################################################################################
	#						sp_BlitzFirst since startup									#
	#####################################################################################
	if ($IsIndepth -eq "Y") {
		Write-Host " Running sp_BlitzFirst @SinceStartup = 1... " -NoNewLine
		$CmdTimeout = 600
		[string]$Query = [System.IO.File]::ReadAllText("$ResourcesPath\spBlitzFirst_NonSPLatest.sql")
		[string]$Query = $Query -replace ";SET @SinceStartup = 0;", ";SET @SinceStartup = 1;"
		$BlitzFirstQuery = new-object System.Data.SqlClient.SqlCommand
		$BlitzFirstQuery.CommandText = $Query
		$BlitzFirstQuery.Connection = $SqlConnection
		$BlitzFirstQuery.CommandTimeout = $CmdTimeout 
		$BlitzFirstAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
		$BlitzFirstAdapter.SelectCommand = $BlitzFirstQuery
		$BlitzFirstSet = new-object System.Data.DataSet
		Try {
			$StepStart = get-date
			$BlitzFirstAdapter.Fill($BlitzFirstSet) | Out-Null -ErrorAction Stop
			$SqlConnection.Close()
			$StepEnd = get-date
			Write-Host @GreenCheck
			$StepRunTime = (New-TimeSpan -Start $StepStart -End $StepEnd).TotalSeconds
			$RunTime = [Math]::Round($StepRunTime, 2)
			if ($DebugInfo) {
				Write-Host " - $RunTime seconds" -Fore Yellow
			}
			$StepOutcome = "Success"
		}
	 Catch {
			$StepEnd = get-date
			Invoke-ErrMsg
			$StepOutcome = "Failure"
		}
			
		if ($StepOutcome -eq "Success") {
			$WaitsTbl = New-Object System.Data.DataTable
			$WaitsTbl = $BlitzFirstSet.Tables[0]

			$StorageTbl = New-Object System.Data.DataTable
			$StorageTbl = $BlitzFirstSet.Tables[1]

			$PerfmonTbl = New-Object System.Data.DataTable
			$PerfmonTbl = $BlitzFirstSet.Tables[2]


			if ($ToHTML -eq "Y") {
				#Waits
				if ($DebugInfo) {
					Write-Host " ->Converting wait stats info to HTML" -fore yellow
				}
				$HtmlTabName = "Wait Stats Since Last Startup"

				$htmlTable = $WaitsTbl | Select-Object "Pattern", 
				@{Name = "Sample Ended"; Expression = { ($_."Sample Ended").ToString("yyyy-MM-dd HH:mm:ss") } },
				"Hours Sample", "Thread Time (Hours)",
				@{Name = "Wait Type"; Expression = { $_."wait_type" } }, 
				@{Name = "Wait Category"; Expression = { $_."wait_category" } }, 
				"Wait Time (Hours)", "Per Core Per Hour", 
				"Signal Wait Time (Hours)", "Percent Signal Waits", "Number of Waits",
				"Avg ms Per Wait", "URL" | ConvertTo-Html -As Table -Fragment
				$htmlTable = $htmlTable -replace $URLRegex, '<a href="$&" target="_blank">$&</a>'
			 
				$html = $HTMLPre + @"
<title>$HtmlTabName</title>
</head>
<body>
<h1>$HtmlTabName</h1>
<br>
$htmlTable
</body>
</html>
"@
				if ($DebugInfo) {
					Write-Host " ->Writing HTML file." -fore yellow
				} 
				$html | Out-File -Encoding utf8 -FilePath "$HTMLOutDir\BlitzFirst_Waits.html"
			 
				#Storage
				if ($DebugInfo) {
					Write-Host " ->Converting storage info to HTML" -fore yellow
				}
				$HtmlTabName = "Storage Throughput Since Instance Startup"
				$htmlTable = $StorageTbl | Select-Object "Pattern", 
				@{Name = "Sample Time"; Expression = { ($_."Sample Time").ToString("yyyy-MM-dd HH:mm:ss") } }, 
				"Sample (seconds)", 
				@{Name = "File Name [type]"; Expression = { $_."File Name" } },
				"Drive", "# Reads/Writes", "MB Read/Written", "Avg Stall (ms)", 
				@{Name = "Physical File Name"; Expression = { $_."file physical name" } },
				@{Name = "Database Name"; Expression = { $_."DatabaseName" } } | ConvertTo-Html -As Table -Fragment
			 
				$html = $HTMLPre + @"
<title>$HtmlTabName</title>
</head>
<body>
<h1>$HtmlTabName</h1>
<br>
$htmlTable
</body>
</html>
"@
				if ($DebugInfo) {
					Write-Host " ->Writing HTML file." -fore yellow
				} 
				$html | Out-File -Encoding utf8 -FilePath "$HTMLOutDIr\BlitzFirst_Storage.html"
			 
				#Perfmon
				if ($DebugInfo) {
					Write-Host " ->Converting perfmon stats to HTML" -fore yellow
				}
				$HtmlTabName = "Perfmon Stats Since Instance Startup"
				$htmlTable = $PerfmonTbl | Select-Object "Pattern", 
				@{Name = "ObjectName"; Expression = { $_."object_name" } }, 
				@{Name = "CounterName"; Expression = { $_."counter_name" } }, 
				@{Name = "InstanceName"; Expression = { $_."instance_name" } }, 
				@{Name = "FirstSampleTime"; Expression = { ($_."FirstSampleTime").ToString("yyyy-MM-dd HH:mm:ss") } }, 
				"FirstSampleValue", 
				@{Name = "LastSampleTime"; Expression = { ($_."LastSampleTime").ToString("yyyy-MM-dd HH:mm:ss") } }, 
				"LastSampleValue", "ValueDelta", "ValuePerSecond" | ConvertTo-Html -As Table -Fragment
			 
				$html = $HTMLPre + @"
<title>$HtmlTabName</title>
</head>
<body>
<h1>$HtmlTabName</h1>
<br>
$htmlTable
</body>
</html>
"@

				if ($DebugInfo) {
					Write-Host " ->Writing HTML file." -fore yellow
				} 
				$html | Out-File -Encoding utf8 -FilePath "$HTMLOutDIr\BlitzFirst_Perfmon.html"
			}
			else {
				##Populating the "Wait Stats" sheet
				$ExcelSheet = $ExcelFile.Worksheets.Item("Wait Stats")
				#Specify at which row in the sheet to start adding the data
				$ExcelStartRow = $DefaultStartRow
				#Specify with which column in the sheet to start
				$ExcelColNum = 1
				#Set counter used for row retrieval
				$RowNum = 0

				$DataSetCols = @("Pattern", "Sample Ended", "Hours Sample", "Thread Time (Hours)",
					"wait_type", "wait_category", "Wait Time (Hours)", "Per Core Per Hour", 
					"Signal Wait Time (Hours)", "Percent Signal Waits", "Number of Waits",
					"Avg ms Per Wait", "URL")

				if ($DebugInfo) {
					Write-Host " ->Writing sp_BlitzFirst results to sheet Wait Stats" -fore yellow
				}
				#Loop through each Excel row
				foreach ($row in $WaitsTbl) {
					#Loop through each data set column of current row and fill the corresponding 
					# Excel cell
					foreach ($col in $DataSetCols) {
						if ($col -eq "Sample Ended") {
							$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $WaitsTbl.Rows[$RowNum][$col].ToString("yyyy-MM-dd HH:mm:ss")
						}
						elseif ($col -eq "URL") {
							#Make URLs clickable
							if ($WaitsTbl.Rows[$RowNum][$col] -like "http*") {
								$ExcelSheet.Hyperlinks.Add($ExcelSheet.Cells.Item($ExcelStartRow, 5),
									$WaitsTbl.Rows[$RowNum][$col], "", "Click for more info",
									$WaitsTbl.Rows[$RowNum]["wait_type"]) | Out-Null
							}
						}
						else {
							$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $WaitsTbl.Rows[$RowNum][$col]
						}
						#move to the next column
						$ExcelColNum += 1
					}

					#move to the next row in the spreadsheet
					$ExcelStartRow += 1
					#move to the next row in the data set
					$RowNum += 1
					# reset Excel column number so that next row population begins with column 1
					$ExcelColNum = 1
				}

				##Saving file 
				$ExcelFile.Save()
				## populating the "Storage" sheet
				$ExcelSheet = $ExcelFile.Worksheets.Item("Storage")
				#Specify at which row in the sheet to start adding the data
				$ExcelStartRow = $DefaultStartRow
				#Specify with which column in the sheet to start
				$ExcelColNum = 1
				#Set counter used for row retrieval
				$RowNum = 0

				$DataSetCols = @("Pattern", "Sample Time", "Sample (seconds)", "File Name",
					"Drive", "# Reads/Writes", "MB Read/Written", "Avg Stall (ms)", "file physical name",
					"DatabaseName")
				if ($DebugInfo) {
					Write-Host " ->Writing sp_BlitzFirst results to sheet Storage" -fore yellow
				}
				#Loop through each Excel row
				foreach ($row in $StorageTbl) {
					#Loop through each data set column of current row and fill the corresponding 
					# Excel cell
					foreach ($col in $DataSetCols) {
						#Fill Excel cell with value from the data set
						if ($col -eq "Sample Time") {
							$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $StorageTbl.Rows[$RowNum][$col].ToString("yyyy-MM-dd HH:mm:ss")
						}
						else {
							$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $StorageTbl.Rows[$RowNum][$col]
						}
						#move to the next column
						$ExcelColNum += 1
					}

					#move to the next row in the spreadsheet
					$ExcelStartRow += 1
					#move to the next row in the data set
					$RowNum += 1
					# reset Excel column number so that next row population begins with column 1
					$ExcelColNum = 1
				}

				##Saving file 
				$ExcelFile.Save()
				## populating the "Perfmon" sheet
				$ExcelSheet = $ExcelFile.Worksheets.Item("Perfmon")
				#Specify at which row in the sheet to start adding the data
				$ExcelStartRow = $DefaultStartRow
				#Specify with which column in the sheet to start
				$ExcelColNum = 1
				#Set counter used for row retrieval
				$RowNum = 0

				$DataSetCols = @("Pattern", "object_name", "counter_name", "instance_name", 
					"FirstSampleTime", "FirstSampleValue", "LastSampleTime", "LastSampleValue",
					"ValueDelta", "ValuePerSecond")

				if ($DebugInfo) {
					Write-Host " ->Writing sp_BlitzFirst results to sheet Perfmon" -fore yellow
				}
				#Loop through each Excel row
				foreach ($row in $PerfmonTbl) {
					#Loop through each data set column of current row and fill the corresponding 
					# Excel cell
					foreach ($col in $DataSetCols) {
						#Fill Excel cell with value from the data set
						if ("FirstSampleTime", "LastSampleTime" -Contains $col) {
							$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $PerfmonTbl.Rows[$RowNum][$col].ToString("yyyy-MM-dd HH:mm:ss")
						}
						else {
							$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $PerfmonTbl.Rows[$RowNum][$col]
						}
						#move to the next column
						$ExcelColNum += 1
					}

					#move to the next row in the spreadsheet
					$ExcelStartRow += 1
					#move to the next row in the data set
					$RowNum += 1
					# reset Excel column number so that next row population begins with column 1
					$ExcelColNum = 1
				}

				
		
				##Saving file 
				$ExcelFile.Save()
			}

			##Cleaning up variables
			Remove-Variable -Name WaitsTbl
			Remove-Variable -Name StorageTbl
			Remove-Variable -Name PerfmonTbl
			Remove-Variable -Name BlitzFirstSet
		}
		if ($JobStatus -ne "Running") {
			Invoke-BlitzWho -BlitzWhoQuery $BlitzWhoRepl -IsInLoop N
			$BlitzWhoPass += 1
		}
	}
		

	#####################################################################################
	#						sp_BlitzCache												#
	#####################################################################################
	#Building a list of values for @SortOrder 
	<#
	Ony run through the other sort orders if $IsIndepth = "Y"
	otherwise just do duration and avg duration
	#>
	if ($IsIndepth -eq "Y") {
		$SortOrders = @("'CPU'", "'Average CPU'", "'Reads'", "'Average Reads'",
			"'Duration'", "'Average Duration'", "'Executions'", "'Executions per Minute'",
			"'Writes'", "'Average Writes'", "'Spills'", "'Average Spills'",
			"'Memory Grant'", "'Recent Compilations'")
	}
 else {
		$SortOrders = @("'CPU'", "'Average CPU'", "'Duration'",
			"'Average Duration'")
	}
	#Set initial SortOrder value
	$OldSortOrder = "'CPU'"
	[string]$Query = [System.IO.File]::ReadAllText("$ResourcesPath\spBlitzCache_NonSPLatest.sql")
	$CmdTimeout = $MaxTimeout
	#Set specific database to check if a name was provided
	if (!([string]::IsNullOrEmpty($CheckDB))) {
		[string]$Query = $Query -replace $OldCheckDBStr, $NewCheckDBStr
		Write-Host " Running sp_BlitzCache for $CheckDB"
	}
 else {
		Write-Host " Running sp_BlitzCache for all user databases"
		#Create array to store database names
		$DBArray = New-Object System.Collections.ArrayList
		[int]$BlitzCacheRecs = 0
	}
	#Loop through sort orders
	foreach ($SortOrder in $SortOrders) {
		#Filename sort order portion
		$FileSOrder = $SortOrder.Replace('Average', 'Avg')
		$FileSOrder = $SortOrder.Replace('Executions per Minute', 'ExPM')
		$FileSOrder = $SortOrder.Replace(' ', '_')
		$FileSOrder = $FileSOrder.Replace("'", '')

		#Replace old sort order with new one
		$OldSortString = ";SELECT @SortOrder = " + $OldSortOrder
		$NewSortString = ";SELECT @SortOrder = " + $SortOrder
		#Replace number of records returned if sorting by recent compilations
		if ($SortOrder -eq "'recent compilations'") {
			$OldSortString = $OldSortString + ", @Top = 10;"
			$NewSortString = $NewSortString + ", @Top = 50;"
		}
		if ($DebugInfo) {
			Write-Host " ->Replacing $OldSortString with $NewSortString" -fore yellow
		}		

		[string]$Query = $Query -replace $OldSortString, $NewSortString
		Write-Host " ->Running sp_BlitzCache with @SortOrder = $SortOrder... " -NoNewLine
		$BlitzCacheQuery = new-object System.Data.SqlClient.SqlCommand
		$BlitzCacheQuery.CommandText = $Query
		$BlitzCacheQuery.CommandTimeout = $CmdTimeout
		$BlitzCacheQuery.Connection = $SqlConnection
		$BlitzCacheAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
		$BlitzCacheAdapter.SelectCommand = $BlitzCacheQuery
		$BlitzCacheSet = new-object System.Data.DataSet
		Try {
			$StepStart = get-date
			$BlitzCacheAdapter.Fill($BlitzCacheSet) | Out-Null -ErrorAction Stop
			$SqlConnection.Close()
			$StepEnd = get-date
			Write-Host @GreenCheck
			$StepRunTime = (New-TimeSpan -Start $StepStart -End $StepEnd).TotalSeconds
			$RunTime = [Math]::Round($StepRunTime, 2)
			if ($DebugInfo) {
				Write-Host " - $RunTime seconds" -Fore Yellow
			}
			$StepOutcome = "Success"
		}
	 Catch {
			$StepEnd = get-date
			Invoke-ErrMsg
			$StepOutcome = "Failure"
		}
			
		if ($StepOutcome -eq "Success") {
			$BlitzCacheTbl = New-Object System.Data.DataTable
			$BlitzCacheTbl = $BlitzCacheSet.Tables[0]
			$BlitzCacheWarnTbl = New-Object System.Data.DataTable
			$BlitzCacheWarnTbl = $BlitzCacheSet.Tables[1]

			##Exporting execution plans to file
			if ($DebugInfo) {
				Write-Host " ->Exporting execution plans for $SortOrder" -fore yellow
			}
			#Set counter used for row retrieval
			$RowNum = 0
			#Setting $i to 0
			$i = 0

			foreach ($row in $BlitzCacheTbl) {
				#Increment file name counter	
				$i += 1
				#Get only the column storing the execution plan data that's not NULL and write it to a file
				if ($BlitzCacheTbl.Rows[$RowNum]["Query Plan"] -ne [System.DBNull]::Value) {
					$BlitzCacheTbl.Rows[$RowNum]["Query Plan"] | Format-XML | Set-Content -Path $PlanOutDir\$($FileSOrder)_$($i).sqlplan -Force
				}		
				#Increment row retrieval counter
				$RowNum += 1
			}

			##Add database names to array
			if ([string]::IsNullOrEmpty($CheckDB)) {
				foreach ($row in $BlitzCacheTbl."Database") {
					$DBArray.Add($row) | Out-Null
					$BlitzCacheRecs += 1
				}
			}

			##Export data to Excel
			#Set Excel sheet names based on $SortOrder
			$SheetName = "sp_BlitzCache "
			if ($SortOrder -like '*CPU*') {
				$SheetName = $SheetName + "CPU"
			}
			elseif ($SortOrder -like '*Reads*') {
				$SheetName = $SheetName + "Reads"
			}
			elseif ($SortOrder -like '*Duration*') {
				$SheetName = $SheetName + "Duration"
			}
			elseif ($SortOrder -like '*Executions*') {
				$SheetName = $SheetName + "Executions"
			}
			elseif ($SortOrder -like '*Writes*') {
				$SheetName = $SheetName + "Writes"
			}
			elseif ($SortOrder -like '*Spills*') {
				$SheetName = $SheetName + "Spills"
			}
			elseif ($SortOrder -like '*Memory*') {
				$SheetName = $SheetName + "Mem & Recent Comp"
			}
			elseif ($SortOrder -eq "'Recent compilations'") {
				$SheetName = $SheetName + "Mem & Recent Comp"
			}

			if ($ToHTML -eq "Y") {
				$SheetName = $SheetName -replace "sp_BlitzCache ", ""
				$BlitzCacheTbl.Columns.Add("SQLPlan File", [string]) | Out-Null
				$RowNum = 0
			
				foreach ($row in $BlitzCacheTbl) {
					if ($BlitzCacheTbl.Rows[$RowNum]["Query Plan"] -ne [System.DBNull]::Value) {
						$SQLPlanFile = $FileSOrder + "_" + $RowNum + ".sqlplan"
					
					}
					else { $SQLPlanFile = "-- N/A --" }
					$BlitzCacheTbl.Rows[$RowNum]["SQLPlan File"] = $SQLPlanFile
					$RowNum += 1
				}
				if ($DebugInfo) {
					Write-Host " ->Converting sp_BlitzCache output to HTML" -fore yellow
				}
				$htmlTable1 = $BlitzCacheTbl | Select-Object "Database", "Cost", "Query Text", "SQLPlan File", "Query Type", "Warnings", 
				@{Name = "Missing Indexes"; Expression = { $_."Missing Indexes".Replace('ClickMe', '').Replace('<?NoNeedTo -- N/A --?>', '') } },	
				@{Name = "Implicit Conversion Info"; Expression = { $_."Implicit Conversion Info".Replace('ClickMe', '').Replace('<?NoNeedTo -- N/A --?>', '') } },
				@{Name = "Cached Execution Parameters"; Expression = { $_."Cached Execution Parameters".Replace('ClickMe', '').Replace('<?NoNeedTo -- N/A --?>', '') } },
				"# Executions", "Executions / Minute", "Execution Weight",
				"% Executions (Type)", "Serial Desired Memory",
				"Serial Required Memory", "Total CPU (ms)", "Avg CPU (ms)", "CPU Weight", "% CPU (Type)",
				"Total Duration (ms)", "Avg Duration (ms)", "Duration Weight", "% Duration (Type)",
				"Total Reads", "Average Reads", "Read Weight", "% Reads (Type)", "Total Writes",
				"Average Writes", "Write Weight", "% Writes (Type)", "Total Rows", "Avg Rows", "Min Rows",
				"Max Rows", "# Plans", "# Distinct Plans", 
				@{Name = "Created At"; Expression = { ($_."Created At").ToString("yyyy-MM-dd HH:mm:ss") } }, 
				@{Name = "Last Execution"; Expression = { ($_."Last Execution").ToString("yyyy-MM-dd HH:mm:ss") } },
				"StatementStartOffset", "StatementEndOffset", 
				@{Name = "Query Hash"; Expression = { Get-HexString -HexInput $_."Query Hash" } }, 
				@{Name = "Query Plan Hash"; Expression = { Get-HexString -HexInput $_."Query Plan Hash" } },
				"SET Options", "Cached Plan Size (KB)", "Compile Time (ms)", "Compile CPU (ms)",
				"Compile memory (KB)", 
				@{Name = "Plan Handle"; Expression = { Get-HexString -HexInput $_."Plan Handle" } }, 
				@{Name = "SQL Handle"; Expression = { Get-HexString -HexInput $_."SQL Handle" } }, 
				"Minimum Memory Grant KB",
				"Maximum Memory Grant KB", "Minimum Used Grant KB", "Maximum Used Grant KB",
				"Average Max Memory Grant", "Min Spills", "Max Spills", "Total Spills", "Avg Spills" | ConvertTo-Html -As Table -Fragment
				$htmlTable1 = $htmlTable1 -replace $URLRegex, '<a href="$&" target="_blank">$&</a>'
		
				$htmlTable2 = $BlitzCacheWarnTbl | Select-Object "Priority", "FindingsGroup", "Finding", "Details", "URL" | ConvertTo-Html -As Table -Fragment
				$htmlTable2 = $htmlTable2 -replace $URLRegex, '<a href="$&" target="_blank">$&</a>'
		
				#pairing up related tables in the same HTML file
				if ("'CPU'", "'Reads'", "'Duration'", "'Executions'", "'Writes'",
					"'Spills'", "'Memory Grant'" -contains $SortOrder) {
					if ($SheetName -eq "Mem & Recent Comp") {
						$HtmlTabName = "Queries by Memory Grants & Recent Compilations"
					}
					else {
						$HtmlTabName = "Queries by $SheetName"
					}
					$HtmlFileName = $SheetName -replace " & ", "_"
					$HtmlFileName = $HtmlFileName -replace " ", "_"
					$HtmlFileName = "BlitzCache_$HtmlFileName.html"
					$HtmlTabName2 = $SortOrder -replace "'", ""
					$html = $HTMLPre + @"
<title>$HtmlTabName</title>
</head>
<body>
<h1>$HtmlTabName</h1>
<br>
<h2>Top 10 Queries by $HtmlTabName2</h2>
$htmlTable1
<br>
<h2>Warnings Explained</h2>
$htmlTable2
<br>        
				
"@
				}
		
				#adding the second half of each html page and writing to file
				if (($SortOrder -like '*Average*') -or ($SortOrder -eq "'Executions per Minute'") -or ($SortOrder -eq "'Recent Compilations'")) {
					$HtmlTabName2 = $SortOrder -replace "'", ""
					$html += @"
				<h2>Top 10 Queries by $HtmlTabName2</h2>
				$htmlTable1
				<br>
				<h2>Warnings Explained</h2>
				$htmlTable2
				</body>
				</html>
"@
				}
				if ($DebugInfo) {
					Write-Host " ->Writing HTML file." -fore yellow
				}
				$html | Out-File -Encoding utf8 -FilePath "$HTMLOutDir\$HtmlFileName"
			}
			else {
				#Specify worksheet
				$ExcelSheet = $ExcelFile.Worksheets.Item($SheetName)

				#Specify at which row in the sheet to start adding the data
				$ExcelStartRow = 3
				#$SortOrder containing avg or xpm will export data starting with row 16
				if (($SortOrder -like '*avg*') -or ($SortOrder -eq "'xpm'") -or ($SortOrder -eq "'recent compilations'")) {
					$ExcelStartRow = 17
				}
				#Set counter used for row retrieval
				$RowNum = 0
				#Set counter for sqlplan file names
				$SQLPlanNum = 1

				$ExcelColNum = 1

				#define column list to only get the sp_BlitzCache columns that are relevant in this case
				$DataSetCols = @("Database", "Cost", "Query Text", "Query Type", "Warnings", "Missing Indexes",	"Implicit Conversion Info", "Cached Execution Parameters",
					"# Executions", "Executions / Minute", "Execution Weight",
					"% Executions (Type)", "Serial Desired Memory",
					"Serial Required Memory", "Total CPU (ms)", "Avg CPU (ms)", "CPU Weight", "% CPU (Type)",
					"Total Duration (ms)", "Avg Duration (ms)", "Duration Weight", "% Duration (Type)",
					"Total Reads", "Average Reads", "Read Weight", "% Reads (Type)", "Total Writes",
					"Average Writes", "Write Weight", "% Writes (Type)", "Total Rows", "Avg Rows", "Min Rows",
					"Max Rows", "# Plans", "# Distinct Plans", "Created At", "Last Execution",
					"StatementStartOffset", "StatementEndOffset", "Query Hash", "Query Plan Hash",
					"SET Options", "Cached Plan Size (KB)", "Compile Time (ms)", "Compile CPU (ms)",
					"Compile memory (KB)", "Plan Handle", "SQL Handle", "Minimum Memory Grant KB",
					"Maximum Memory Grant KB", "Minimum Used Grant KB", "Maximum Used Grant KB",
					"Average Max Memory Grant", "Min Spills", "Max Spills", "Total Spills", "Avg Spills")
				if ($DebugInfo) {
					Write-Host " ->Writing sp_BlitzCache results to sheet $SheetName" -fore yellow
				}
				foreach ($row in $BlitzCacheTbl) {
					$SQLPlanFile = "-- N/A --"
					#Changing the value of $SQLPlanFile only for records where execution plan exists
					if ($BlitzCacheTbl.Rows[$RowNum]["Query Plan"] -ne [System.DBNull]::Value) {
						$SQLPlanFile = $FileSOrder + "_" + $SQLPlanNum + ".sqlplan"
					}
					#Loop through each column from $DataSetCols for curent row and retrieve data from 
					foreach ($col in $DataSetCols) {

						#Properly handling Query Hash, Plan Hash, Plan, and SQL Handle hex values 
						if ("Query Hash", "Query Plan Hash", "Plan Handle", "SQL Handle" -Contains $col) {
							$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = Get-HexString -HexInput $BlitzCacheTbl.Rows[$RowNum][$col]
							#move to the next column
							$ExcelColNum += 1
							#move to the top of the loop
							Continue
						}
						if ($BlitzCacheTbl.Rows[$RowNum][$col] -eq "<?NoNeedToClickMe -- N/A --?>") {
							$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = "   -- N/A --   "
							#move to the next column
							$ExcelColNum += 1
							#move to the top of the loop
							Continue
						}			
						$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $BlitzCacheTbl.Rows[$RowNum][$col]
						#move to the next column
						$ExcelColNum += 1			
						<# 
					If the next column is the SQLPlan Name column 
					fill it separately and then move to next column
					#>
						if ($ExcelColNum -eq 4) {
							$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $SQLPlanFIle
							#move to the next column
							$ExcelColNum += 1
						}
					}

					#move to the next row in the spreadsheet
					$ExcelStartRow += 1
					#move to the next row in the data set
					$RowNum += 1
					#Move to the next sqlplan file
					$SQLPlanNum += 1
					# reset Excel column number so that next row population begins with column 1
					$ExcelColNum = 1
				}

				####Plan Cache warning
				$SheetName = "Plan Cache Warnings"

				#Specify worksheet
				$ExcelSheet = $ExcelFile.Worksheets.Item($SheetName)

				#Specify at which row in the sheet to start adding the data
				$ExcelStartRow = 3
				#$SortOrder containing avg or xpm will export data starting with row 16
				if (($SortOrder -like '*Average*') -or ($SortOrder -eq "'Executions per Minute'") -or ($SortOrder -eq "'Recent Compilations'")) {
					$ExcelStartRow = 36
				}
				#Set counter used for row retrieval
				$RowNum = 0
				#Set counter for sqlplan file names
				$SQLPlanNum = 1


				if ($SortOrder -like '*CPU*') {
					$ExcelWarnInitCol = 1
				}
				elseif ($SortOrder -like '*Duration*') {
					$ExcelWarnInitCol = 6
				}
				elseif ($SortOrder -like '*Reads*') {
					$ExcelWarnInitCol = 11
				}
				elseif ($SortOrder -like '*Writes*') {
					$ExcelWarnInitCol = 16
				}
				elseif ($SortOrder -eq "'Executions'") {
					$ExcelWarnInitCol = 21
				}
				elseif ($SortOrder -eq "'Executions per Minute'") {
					$ExcelWarnInitCol = 21
				}
				elseif ($SortOrder -like '*Spills*') {
					$ExcelWarnInitCol = 26
				}
				elseif ($SortOrder -like '*Memory*') {
					$ExcelWarnInitCol = 31
				}
				elseif ($SortOrder -eq "'Recent Compilations'") {
					$ExcelWarnInitCol = 31
				}

				$ExcelURLCol = $ExcelWarnInitCol + 2
				$ExcelColNum = $ExcelWarnInitCol

				#define column list to only get the sp_BlitzCache columns that are relevant in this case
				$DataSetCols = @("Priority", "FindingsGroup", "Finding", "Details", "URL")
				if ($DebugInfo) {
					Write-Host " ->Writing sp_BlitzCache results to sheet $SheetName" -fore yellow
				}
				foreach ($row in $BlitzCacheWarnTbl) {
					#Loop through each column from $DataSetCols for curent row and retrieve data from 
					foreach ($col in $DataSetCols) {
						if ($col -eq "URL") {
							if ($BlitzCacheWarnTbl.Rows[$RowNum][$col] -like "http*") {
								$ExcelSheet.Hyperlinks.Add($ExcelSheet.Cells.Item($ExcelStartRow, $ExcelURLCol),
									$BlitzCacheWarnTbl.Rows[$RowNum][$col], "", "Click for more info",
									$BlitzCacheWarnTbl.Rows[$RowNum]["Finding"]) | Out-Null
							}
						}
						else {
							$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $BlitzCacheWarnTbl.Rows[$RowNum][$col] 
						} 
						#move to the next column
						$ExcelColNum += 1			
					}

					#move to the next row in the spreadsheet
					$ExcelStartRow += 1
					#move to the next row in the data set
					$RowNum += 1
					# reset Excel column number so that next row population begins with column 1
					$ExcelColNum = $ExcelWarnInitCol
					if ($RowNum -eq 31) {
						Continue
					}
				}
				##Saving file 
				$ExcelFile.Save()
			}	
		

		}

		$OldSortOrder = $SortOrder
		if ($DebugInfo) {
			Write-Host " ->old sort order is now $OldSortOrder" -fore yellow
		}

		if ($JobStatus -ne "Running") {
			Invoke-BlitzWho -BlitzWhoQuery $BlitzWhoRepl -IsInLoop Y
			$BlitzWhoPass += 1
		}

	}
	##Cleaning up variables 
	Remove-Variable -Name BlitzCacheWarnTbl
	Remove-Variable -Name BlitzCacheTbl
	Remove-Variable -Name BlitzCacheSet


	#####################################################################################
	#						sp_BlitzIndex												#
	#####################################################################################
	#Building a list of values for $Modes
	if ($IsIndepth -eq "Y") {
		$Modes = @("1", "2", "4")
	}
 else {
		$Modes = @("0")
	}
	# Set OldMode variable 
	$OldMode = ";SET @Mode = 0;"
	[string]$Query = [System.IO.File]::ReadAllText("$ResourcesPath\spBlitzIndex_NonSPLatest.sql")
	$CmdTimeout = $MaxTimeout
	#Set specific database to check if a name was provided
	if (!([string]::IsNullOrEmpty($CheckDB))) {
		[string]$Query = $Query -replace $OldCheckDBStr, $NewCheckDBStr
		[string]$Query = $Query -replace ";SET @GetAllDatabases = 1;", ";SET @GetAllDatabases = 0;"
		Write-Host " Running sp_BlitzIndex for $CheckDB"
	}
 else {
		Write-Host " Running sp_BlitzIndex for all user databases"
	}
	#Loop through $Modes
	foreach ($Mode in $Modes) {
		Write-Host " ->Running sp_BlitzIndex with @Mode = $Mode... " -NoNewLine
		$NewMode = ";SET @Mode = " + $Mode + ";"
		[string]$Query = $Query -replace $OldMode, $NewMode
		$BlitzIndexQuery = new-object System.Data.SqlClient.SqlCommand
		$BlitzIndexQuery.CommandText = $Query
		$BlitzIndexQuery.CommandTimeout = $CmdTimeout
		$BlitzIndexQuery.Connection = $SqlConnection
		$BlitzIndexAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
		$BlitzIndexAdapter.SelectCommand = $BlitzIndexQuery
		$BlitzIndexSet = new-object System.Data.DataSet
		Try {
			$StepStart = get-date
			$BlitzIndexAdapter.Fill($BlitzIndexSet) | Out-Null -ErrorAction Stop
			$SqlConnection.Close()
			$StepEnd = get-date
			Write-Host @GreenCheck
			$StepRunTime = (New-TimeSpan -Start $StepStart -End $StepEnd).TotalSeconds
			$RunTime = [Math]::Round($StepRunTime, 2)
			if ($DebugInfo) {
				Write-Host " - $RunTime seconds" -Fore Yellow
			}
			$StepOutcome = "Success"
		}
	 Catch {
			$StepEnd = get-date
			Invoke-ErrMsg
			$StepOutcome = "Failure"
		}
			
		if ($StepOutcome -eq "Success") {
			$BlitzIxTbl = New-Object System.Data.DataTable
			$BlitzIxTbl = $BlitzIndexSet.Tables[0]
			
			if ($ToHTML -eq "Y") {
				if ($DebugInfo) {
					Write-Host " ->Converting sp_BlitzIndex output to HTML" -fore yellow
				}
				if ($Mode -eq "0") {
					$HtmlTabName = "Index Diagnosis"
				}
				elseif ($Mode -eq "1") {
					$HtmlTabName = "Index Summary"
				}
				elseif ($Mode -eq "2") {
					$HtmlTabName = "Index Usage Details"
				}
				elseif ($Mode -eq "4") {
					$HtmlTabName = "Detailed Index Diagnosis"
				}
		
		
				if ("0", "4" -Contains $Mode) {
					#Export sample execution plans for missing indexes (SQL Server 2019 only)
					$RowNum = 0
					$i = 0
					foreach ($row in $BlitzIxTbl) {
						if ($BlitzIxTbl.Rows[$RowNum]["Finding"] -like "*Missing Index") {
							$i += 1
							if ($BlitzIxTbl.Rows[$RowNum]["Sample Query Plan"] -ne [System.DBNull]::Value) {
								$BlitzIxTbl.Rows[$RowNum]["Sample Query Plan"] | Format-XML | Set-Content -Path $PlanOutDir\MissingIndex_$($i).sqlplan -Force
							}
						}
						$RowNum += 1
					}					
					<#Renaming a column because apparently Select-Object and ConvertTo-HTML can't deal with curly braces or the long column name 
					or whatever regardless of how I try to escape them
					and it's 2AM and I'm done with trying to find elegant ways around this
					#>
					$BlitzIxTbl.Columns["Definition: [Property] ColumnName {datatype maxbytes}"].ColumnName = "Definition"
					$htmlTable = $BlitzIxTbl | Select-Object "Priority", "Finding", "Database Name", 
					"Details: schema.table.index(indexid)",   
					"Definition", 
					"Secret Columns", "Usage", "Size", "More Info", "Create TSQL", "URL" | Where-Object "Finding" -NotLike "sp_BlitzIndex*" | ConvertTo-Html -As Table -Fragment
		
					$htmlTable = $htmlTable -replace $URLRegex, '<a href="$&" target="_blank">$&</a>'
				}
				elseif ($Mode -eq "1") {
					$htmlTable = $BlitzIxTbl | Select-Object "Database Name", "Number Objects", "All GB", 
					"LOB GB", "Row Overflow GB", "Clustered Tables", 
					"Clustered Tables GB", "NC Indexes", "NC Indexes GB", 
					"ratio table: NC Indexes", "Heaps", "Heaps GB", "Partitioned Tables", 
					"Partitioned NCs", "Partitioned GB", "Filtered Indexes", 
					"Indexed Views", "Max Row Count", "Max Table GB", "Max NC Index GB", 
					"Count Tables > 1GB", "Count Tables > 10GB", "Count Tables > 100GB", 
					"Count NCs > 1GB", "Count NCs > 10GB", "Count NCs > 100GB", 
					@{Name = "Oldest Create Date"; Expression = { ($_."Oldest Create Date").ToString("yyyy-MM-dd HH:mm:ss") } }, 
					@{Name = "Most Recent Create Date"; Expression = { ($_."Most Recent Create Date").ToString("yyyy-MM-dd HH:mm:ss") } }, 
					@{Name = "Most Recent Modify Date"; Expression = { ($_."Most Recent Modify Date").ToString("yyyy-MM-dd HH:mm:ss") } } | ConvertTo-Html -As Table -Fragment
				}
				elseif ($Mode -eq "2") {
					$htmlTable = $BlitzIxTbl | Select-Object "Database Name", "Schema Name", "Object Name", 
					"Index Name", "Index ID", "Details: schema.table.index(indexid)", 
					"Object Type", "Definition: [Property] ColumnName {datatype maxbytes}", 
					"Key Column Names With Sort", "Count Key Columns", "Include Column Names", 
					"Count Included Columns", "Secret Column Names", "Count Secret Columns", 
					"Partition Key Column Name", "Filter Definition", "Is Indexed View", 
					"Is Primary Key", "Is XML", "Is Spatial", "Is NC Columnstore", 
					"Is CX Columnstore", "Is Disabled", "Is Hypothetical", "Is Padded", 
					"Fill Factor", "Is Reference by Foreign Key", 
					@{Name = "Last User Seek"; Expression = { ($_."Last User Seek").ToString("yyyy-MM-dd HH:mm:ss") } }, 
					@{Name = "Last User Scan"; Expression = { ($_."Last User Scan").ToString("yyyy-MM-dd HH:mm:ss") } }, 
					@{Name = "Last User Lookup"; Expression = { ($_."Last User Lookup").ToString("yyyy-MM-dd HH:mm:ss") } }, 
					@{Name = "Last User Update"; Expression = { ($_."Last User Update").ToString("yyyy-MM-dd HH:mm:ss") } }, 
					"Total Reads", 
					"User Updates", "Reads Per Write", "Index Usage", "Partition Count", 
					"Rows", "Reserved MB", "Reserved LOB MB", "Reserved Row Overflow MB", 
					"Index Size", "Row Lock Count", "Row Lock Wait Count", "Row Lock Wait ms", 
					"Avg Row Lock Wait ms", "Page Lock Count", "Page Lock Wait Count", 
					"Page Lock Wait ms", "Avg Page Lock Wait ms", "Lock Escalation Attempts", 
					"Lock Escalations", "Page Latch Wait Count", "Page Latch Wait ms", 
					"Page IO Latch Wait Count", "Page IO Latch Wait ms", "Data Compression", 
					@{Name = "Create Date"; Expression = { ($_."Create Date").ToString("yyyy-MM-dd HH:mm:ss") } }, 
					@{Name = "Modify Date"; Expression = { ($_."Modify Date").ToString("yyyy-MM-dd HH:mm:ss") } }, 
					"More Info" | ConvertTo-Html -As Table -Fragment
				}
		
				$html = $HTMLPre + @"
<title>$HtmlTabName</title>
</head>
<body>
<h1>$HtmlTabName</h1>
<br>
$htmlTable 
<br>
</body>
</html>
"@
				if ($DebugInfo) {
					Write-Host " ->Writing HTML file." -fore yellow
				} 
				$html | Out-File -Encoding utf8 -FilePath "$HTMLOutDIr\BlitzIndex_$Mode.html"        
			}
			else {
			
				$SheetName = "sp_BlitzIndex " + $Mode
			
				#Specify worksheet
				$ExcelSheet = $ExcelFile.Worksheets.Item($SheetName)
				if ("0", "4" -Contains $Mode) {
					$DataSetCols = @("Priority", "Finding", "Database Name", 
						"Details: schema.table.index(indexid)",   
						"Definition: [Property] ColumnName {datatype maxbytes}", 
						"Secret Columns", "Usage", "Size", "More Info", "Create TSQL", "URL")

					#Export sample execution plans for missing indexes (SQL Server 2019 only)
					$RowNum = 0
					$i = 0
					foreach ($row in $BlitzIxTbl) {
						if ($BlitzIxTbl.Rows[$RowNum]["Finding"] -like "*Missing Index") {
							$i += 1
							if ($BlitzIxTbl.Rows[$RowNum]["Sample Query Plan"] -ne [System.DBNull]::Value) {
								$BlitzIxTbl.Rows[$RowNum]["Sample Query Plan"] | Format-XML | Set-Content -Path $PlanOutDir\MissingIndex_$($i).sqlplan -Force
							}
						}
						$RowNum += 1
					}

				}
				elseif ($Mode -eq "1") {
					$DataSetCols = @("Database Name", "Number Objects", "All GB", 
						"LOB GB", "Row Overflow GB", "Clustered Tables", 
						"Clustered Tables GB", "NC Indexes", "NC Indexes GB", 
						"ratio table: NC Indexes", "Heaps", "Heaps GB", "Partitioned Tables", 
						"Partitioned NCs", "Partitioned GB", "Filtered Indexes", 
						"Indexed Views", "Max Row Count", "Max Table GB", "Max NC Index GB", 
						"Count Tables > 1GB", "Count Tables > 10GB", "Count Tables > 100GB", 
						"Count NCs > 1GB", "Count NCs > 10GB", "Count NCs > 100GB", 
						"Oldest Create Date", "Most Recent Create Date", 
						"Most Recent Modify Date")
				}
				elseif ($Mode -eq "2") {
					$DataSetCols = @("Database Name", "Schema Name", "Object Name", 
						"Index Name", "Index ID", "Details: schema.table.index(indexid)", 
						"Object Type", "Definition: [Property] ColumnName {datatype maxbytes}", 
						"Key Column Names With Sort", "Count Key Columns", "Include Column Names", 
						"Count Included Columns", "Secret Column Names", "Count Secret Columns", 
						"Partition Key Column Name", "Filter Definition", "Is Indexed View", 
						"Is Primary Key", "Is XML", "Is Spatial", "Is NC Columnstore", 
						"Is CX Columnstore", "Is Disabled", "Is Hypothetical", "Is Padded", 
						"Fill Factor", "Is Reference by Foreign Key", "Last User Seek", 
						"Last User Scan", "Last User Lookup", "Last User Update", "Total Reads", 
						"User Updates", "Reads Per Write", "Index Usage", "Partition Count", 
						"Rows", "Reserved MB", "Reserved LOB MB", "Reserved Row Overflow MB", 
						"Index Size", "Row Lock Count", "Row Lock Wait Count", "Row Lock Wait ms", 
						"Avg Row Lock Wait ms", "Page Lock Count", "Page Lock Wait Count", 
						"Page Lock Wait ms", "Avg Page Lock Wait ms", "Lock Escalation Attempts", 
						"Lock Escalations", "Page Latch Wait Count", "Page Latch Wait ms", 
						"Page IO Latch Wait Count", "Page IO Latch Wait ms", "Data Compression", 
						"Create Date", "Modify Date", "More Info")
				}
				#Specify at which row in the sheet to start adding the data
				$ExcelStartRow = $DefaultStartRow
				#Specify starting record from the data set
				$RowNum = 0
				#Specify at which column of the current $initRow of the sheet to start adding the data
				$ExcelColNum = 1

				#Loop through each Excel row
				if ($DebugInfo) {
					Write-Host " ->Writing sp_BlitzIndex results to sheet $SheetName" -fore yellow
				}
				foreach ($row in $BlitzIxTbl) {

					#Loop through each data set column of current row and fill the corresponding 
					# Excel cell
					foreach ($col in $DataSetCols) {
						if ($col -eq "URL") {
							if ($BlitzIxTbl.Rows[$RowNum][$col] -like "http*") {
								$ExcelSheet.Hyperlinks.Add($ExcelSheet.Cells.Item($ExcelStartRow, 2),
									$BlitzIxTbl.Rows[$RowNum][$col], "", "Click for more info",
									$BlitzIxTbl.Rows[$RowNum]["Finding"]) | Out-Null
							}
						}
						else {
							$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $BlitzIxTbl.Rows[$RowNum][$col]
						}
						#move to the next column
						$ExcelColNum += 1
					}

					#move to the next row in the spreadsheet
					$ExcelStartRow += 1
					#move to the next row in the data set
					$RowNum += 1
					# reset Excel column number so that next row population begins with column 1
					$ExcelColNum = 1
					#Exit this loop if $RowNum = 10000
					if ($RowNum -eq 10001) {
						Continue
					}
				}
			
				##Saving file 
				$ExcelFile.Save()
			}
		}
		#Update $OldMode
		$OldMode = $NewMode

		if ($JobStatus -ne "Running") {
			Invoke-BlitzWho -BlitzWhoQuery $BlitzWhoRepl -IsInLoop Y
			$BlitzWhoPass += 1
		}
	}
	##Cleaning up variables
	Remove-Variable -Name BlitzIxTbl
	Remove-Variable -Name BlitzIndexSet

	####################################################################
	#						sp_BlitzLock
	####################################################################
	$CurrTime = get-date
	$CurrRunTime = (New-TimeSpan -Start $StartDate -End $CurrTime).TotalMinutes
	if (!([string]::IsNullOrEmpty($CheckDB))) {
		Write-Host " Running sp_BlitzLock for $CheckDB... " -NoNewLine
	}
 else {
		Write-Host " Running sp_BlitzLock for all user databases... " -NoNewLine
	}
	[string]$Query = [System.IO.File]::ReadAllText("$ResourcesPath\spBlitzLock_NonSPLatest.sql")
	$CmdTimeout = $MaxTimeout
	#Set specific database to check if a name was provided
	if (!([string]::IsNullOrEmpty($CheckDB))) {
		[string]$Query = $Query -replace $OldCheckDBStr, $NewCheckDBStr
	}
	#Change date range if execution time so far > 15min
	if ([Math]::Round($CurrRunTime) -gt 15) {
		$CurrMin = [Math]::Round($CurrRunTime)
		Write-Host ""
		Write-Host " ->Current execution time is $CurrMin minutes"
		Write-Host " ->Retrieving deadlock info for the last 7 days instead of 15... " -NoNewLine
		[string]$Query = $Query -replace "@StartDate = DATEADD(DAY,-15, GETDATE()),", "@StartDate = DATEADD(DAY,-7, GETDATE()),"
	}
	$BlitzLockQuery = new-object System.Data.SqlClient.SqlCommand
	$BlitzLockQuery.CommandText = $Query
	$BlitzLockQuery.Connection = $SqlConnection
	$BlitzLockQuery.CommandTimeout = $CmdTimeout
	$BlitzLockAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
	$BlitzLockAdapter.SelectCommand = $BlitzLockQuery
	$BlitzLockSet = new-object System.Data.DataSet
	Try {
		$StepStart = get-date
		$BlitzLockAdapter.Fill($BlitzLockSet) | Out-Null -ErrorAction Stop
		$SqlConnection.Close()
		$StepEnd = get-date
		Write-Host @GreenCheck
		$StepRunTime = (New-TimeSpan -Start $StepStart -End $StepEnd).TotalSeconds
		$RunTime = [Math]::Round($StepRunTime, 2)
		if ($DebugInfo) {
			Write-Host " - $RunTime seconds" -Fore Yellow
		}
		$StepOutcome = "Success"
	}
 Catch {
		$StepEnd = get-date
		Invoke-ErrMsg
		$StepOutcome = "Failure"
	}
		
	if ($StepOutcome -eq "Success") {
		$TblLockDtl = New-Object System.Data.DataTable
		$TblLockOver = New-Object System.Data.DataTable

		$TblLockDtl = $BlitzLockSet.Tables[0]
		$TblLockOver = $BlitzLockSet.Tables[1]

		##Exporting deadlock graphs to file
		#Set counter used for row retrieval
		[int]$RowNum = 0
		#Setting $i to 0
		$i = 0
		if ($DebugInfo) {
			Write-Host " ->Exporting deadlock graphs (if any)" -fore yellow
		}
		foreach ($row in $TblLockDtl) {
			#Increment file name counter
			$i += 1
			<#
			Get only the column storing the deadlock graph data that's not NULL, limit to one export per event by filtering for VICTIM, and write it to a file
			#>
			if (($TblLockDtl.Rows[$RowNum]["deadlock_graph"] -ne [System.DBNull]::Value) -and ($TblLockDtl.Rows[$RowNum]["deadlock_group"] -like "*VICTIM*")) {
				#format the event date to append to file name
				$DLDate = $TblLockDtl.Rows[$RowNum]["event_date"].ToString("yyyyMMdd_HHmmss")
				#write .xdl file
				$TblLockDtl.Rows[$RowNum]["deadlock_graph"] | Format-XML | Set-Content -Path $XDLOutDir\$($DLDate)_$($i).xdl -Force
			}
			#Increment row retrieval counter
			$RowNum += 1
		}
		
		if ($ToHTML -eq "Y") {
			if ($DebugInfo) {
				Write-Host " ->Converting sp_BlitzLock output to HTML" -fore yellow
			}
			$HtmlTabName = "Deadlocks"
			$htmlTable1 = $TblLockOver | Select-Object @{Name = "Database"; Expression = { $_."database_name" } }, 
			@{Name = "Object"; Expression = { $_."object_name" } }, 
			@{Name = "Finding Group"; Expression = { $_."finding_group" } }, 
			@{Name = "Finding"; Expression = { $_."finding" } } | Where-Object "database_name" -NotLike "sp_BlitzLock*" | ConvertTo-Html -As Table -Fragment
			
			$htmlTable2 = $TblLockDtl | Select-Object @{Name = "Type"; Expression = { $_."deadlock_type" } }, 
			@{Name = "Event Date"; Expression = { ($_."event_date").ToString("yyyy-MM-dd HH:mm:ss") } },
			@{Name = "Database"; Expression = { $_."database_name" } }, 
			@{Name = "SPID"; Expression = { $_."spid" } },
			@{Name = "Deadlock Group"; Expression = { $_."deadlock_group" } }, 
			@{Name = "Query"; Expression = { $_."query" } }, 
			@{Name = "Object Names"; Expression = { $_."object_names" } }, 
			@{Name = "Isolation Level"; Expression = { $_."isolation_level" } },
			@{Name = "Owner Mode"; Expression = { $_."owner_mode" } }, 
			@{Name = "Waiter Mode"; Expression = { $_."waiter_mode" } }, 
			@{Name = "Tran Count"; Expression = { $_."transaction_count" } }, 
			@{Name = "Login"; Expression = { $_."login_name" } },
			@{Name = "Host Name"; Expression = { $_."host_name" } }, 
			@{Name = "Client App"; Expression = { $_."client_app" } }, 
			@{Name = "Wait Time"; Expression = { $_."wait_time" } }, 
			@{Name = "Wait Resource"; Expression = { $_."wait_resource" } }, 
			@{Name = "Priority"; Expression = { $_."priority" } }, 
			@{Name = "Log Used"; Expression = { $_."log_used" } }, 
			@{Name = "Last Tran Start"; Expression = { ($_."last_tran_started").ToString("yyyy-MM-dd HH:mm:ss") } }, 
			@{Name = "Last Batch Start"; Expression = { ($_."last_batch_started").ToString("yyyy-MM-dd HH:mm:ss") } },
			@{Name = "Last Batch Completed"; Expression = { ($_."last_batch_completed").ToString("yyyy-MM-dd HH:mm:ss") } },	
			@{Name = "Tran Name"; Expression = { $_."transaction_name" } } | ConvertTo-Html -As Table -Fragment
		
		
			$html = $HTMLPre + @"
		<title>$HtmlTabName</title>
		</head>
		<body>
		<h1>$HtmlTabName</h1>
		<h2>Deadlock Overview</h2>
		$htmlTable1
		<br>
		<h2>Deadlock Details</h2>
		$htmlTable2
		</body>
		</html>
"@
			if ($DebugInfo) {
				Write-Host " ->Writing HTML file." -fore yellow
			}			
			$html | Out-File -Encoding utf8 -FilePath "$HTMLOutDir\BlitzLock.html"
		}
		else {
			## populating the "sp_BlitzLock Details" sheet
			$ExcelSheet = $ExcelFile.Worksheets.Item("sp_BlitzLock Details")
			#Specify at which row in the sheet to start adding the data
			$ExcelStartRow = $DefaultStartRow
			#Specify with which column in the sheet to start
			$ExcelColNum = 1
			#Set counter used for row retrieval
			$RowNum = 0

			#List of columns that should be returned from the data set
			$DataSetCols = @("deadlock_type", "event_date", "database_name", "spid",
				"deadlock_group", "query", "object_names", "isolation_level",
				"owner_mode", "waiter_mode", "transaction_count", "login_name",
				"host_name", "client_app", "wait_time", "wait_resource", 
				"priority", "log_used", "last_tran_started", "last_batch_started",
				"last_batch_completed",	"transaction_name")
			if ($DebugInfo) {
				Write-Host " ->Writing sp_BlitzLock Details to Excel" -fore yellow
			}
			#Loop through each Excel row
			foreach ($row in $TblLockDtl) {
				<#
				Loop through each data set column of current row and fill the corresponding 
				 Excel cell
				 #>
				foreach ($col in $DataSetCols) {
					#Fill Excel cell with value from the data set
					$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $TblLockDtl.Rows[$RowNum][$col]
					#move to the next column
					$ExcelColNum += 1
				}

				#move to the next row in the spreadsheet
				$ExcelStartRow += 1
				#move to the next row in the data set
				$RowNum += 1
				# reset Excel column number so that next row population begins with column 1
				$ExcelColNum = 1
			}

			##Saving file 
			$ExcelFile.Save()

			## populating the "sp_BlitzLock Overview" sheet
			$ExcelSheet = $ExcelFile.Worksheets.Item("sp_BlitzLock Overview")
			#Specify at which row in the sheet to start adding the data
			$ExcelStartRow = $DefaultStartRow
			#Specify with which column in the sheet to start
			$ExcelColNum = 1
			#Set counter used for row retrieval
			$RowNum = 0

			#List of columns that should be returned from the data set
			$DataSetCols = @("database_name", "object_name", "finding_group", "finding")

			if ($DebugInfo) {
				Write-Host " ->Writing sp_BlitzLock Overview to Excel" -fore yellow
			}
			#Loop through each Excel row
			foreach ($row in $TblLockOver) {
				<#
				Loop through each data set column of current row and fill the corresponding 
				 Excel cell
				 #>
				foreach ($col in $DataSetCols) {
					#Fill Excel cell with value from the data set
					$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $TblLockOver.Rows[$RowNum][$col]
					#move to the next column
					$ExcelColNum += 1
				}

				#move to the next row in the spreadsheet
				$ExcelStartRow += 1
				#move to the next row in the data set
				$RowNum += 1
				# reset Excel column number so that next row population begins with column 1
				$ExcelColNum = 1
			}

			##Saving file 
			$ExcelFile.Save()
		}
		##Cleaning up variables
		Remove-Variable -Name TblLockOver
		Remove-Variable -Name TblLockDtl
		Remove-Variable -Name BlitzLockSet
	}

	if ($JobStatus -ne "Running") {
		Invoke-BlitzWho -BlitzWhoQuery $BlitzWhoRepl -IsInLoop N
		$BlitzWhoPass += 1
	}


	#####################################################################################
	#						Stats & Index info											#
	#####################################################################################

	<#
		if no specific database name has been provided, check BlitzCache results for any database that
		might account for 2/3 of the all the records returned by BlitzCache
	#>
	if ([string]::IsNullOrEmpty($CheckDB)) {
		[int]$TwoThirdsBlitzCache = [Math]::Floor([decimal]($BlitzCacheRecs / 1.5))
		[string]$DBName = $DBArray | Group-Object -NoElement | Sort-Object Count | ForEach-Object Name | Select-Object -Last 1
		[int]$DBCount = $DBArray | Group-Object -NoElement | Sort-Object Count | ForEach-Object Count | Select-Object -Last 1
		if (($DBCount -ge $TwoThirdsBlitzCache) -and ($DBName -ne "-- N/A --")) {
			Write-Host " $DBName accounts for at least 2/3 of the records returned by sp_BlitzCache"
			Write-Host " ->" -NoNewLine
			[string]$CheckDB = $DBName
			$DBSwitched = "Y"
		}
		
	}
	
	#Only run the check if a specific database name has been provided
	if (!([string]::IsNullOrEmpty($CheckDB))) {

		Write-Host " Getting stats and index info for $CheckDB... " -NoNewLine
		[string]$Query = [System.IO.File]::ReadAllText("$ResourcesPath\GetStatsAndIndexInfoForWholeDB.sql")
		[string]$Query = $Query -replace "..PSBlitzReplace.." , $CheckDB
		$CmdTimeout = $MaxTimeout

		$StatsIndexQuery = new-object System.Data.SqlClient.SqlCommand
		$StatsIndexQuery.CommandText = $Query
		$StatsIndexQuery.Connection = $SqlConnection
		$StatsIndexQuery.CommandTimeout = $CmdTimeout
		$StatsIndexAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
		$StatsIndexAdapter.SelectCommand = $StatsIndexQuery
		$StatsIndexSet = new-object System.Data.DataSet
		Try {
			$StepStart = get-date
			$StatsIndexAdapter.Fill($StatsIndexSet) | Out-Null -ErrorAction Stop
			$SqlConnection.Close()
			$StepEnd = get-date
			Write-Host @GreenCheck
			$StepRunTime = (New-TimeSpan -Start $StepStart -End $StepEnd).TotalSeconds
			$RunTime = [Math]::Round($StepRunTime, 2)
			if ($DebugInfo) {
				Write-Host " - $RunTime seconds" -Fore Yellow
			}
			$StepOutcome = "Success"
		}
	 Catch {
			$StepEnd = get-date
			Invoke-ErrMsg
			$StepOutcome = "Failure"
		}
			
		if ($StepOutcome -eq "Success") {
			$StatsTbl = New-Object System.Data.DataTable
			$StatsTbl = $StatsIndexSet.Tables[0]

			$IndexTbl = New-Object System.Data.DataTable
			$IndexTbl = $StatsIndexSet.Tables[1]

			if ($ToHTML -eq "Y") {
				if ($DebugInfo) {
					Write-Host " ->Converting stats info to HTML" -fore yellow
				}
				$htmlTable = $StatsTbl | Select-Object @{Name = "Database"; Expression = { $_."database" } },
				@{Name = "Object Name"; Expression = { $_."object_name" } },
				@{Name = "Object Type"; Expression = { $_."object_type" } },
				@{Name = "Stats Name"; Expression = { $_."stats_name" } },
				@{Name = "Origin"; Expression = { $_."origin" } },
				@{Name = "Filter Definition"; Expression = { $_."filter_definition" } },
				@{Name = "Last Updated"; Expression = { ($_."last_updated").ToString("yyyy-MM-dd HH:mm:ss") } },
				@{Name = "Rows"; Expression = { $_."rows" } },
				@{Name = "Unfiltered Rows"; Expression = { $_."unfiltered_rows" } },
				@{Name = "Rows Sampled"; Expression = { $_."rows_sampled" } },
				@{Name = "Sample %"; Expression = { $_."sample_percent" } },
				@{Name = "Modifications Count"; Expression = { $_."modification_counter" } },
				@{Name = "Modified %"; Expression = { $_."modified_percent" } },
				@{Name = "Steps"; Expression = { $_."steps" } },
				@{Name = "Partitioned"; Expression = { $_."partitioned" } },
				@{Name = "Partition No."; Expression = { $_."partition_number" } } | ConvertTo-Html -As Table -Fragment
				$HtmlTabName = "Statistics info for $CheckDB"
				$html = $HTMLPre + @"
			<title>$HtmlTabName</title>
			</head>
			<body>
			<h1>$HtmlTabName</h1>
			$htmlTable
			</body>
			</html>
"@
				if ($DebugInfo) {
					Write-Host " ->Writing HTML file." -fore yellow
				} 
				$html | Out-File -Encoding utf8 -FilePath "$HTMLOutDir\StatsInfo_$CheckDB.html"
				if ($DebugInfo) {
					Write-Host " ->Converting index info to HTML" -fore yellow
				}
				$htmlTable = $IndexTbl | Select-Object @{Name = "Database"; Expression = { $_."database" } },
				@{Name = "Object Name"; Expression = { $_."object_name" } },
				@{Name = "Object Type"; Expression = { $_."object_type" } },
				@{Name = "Index Name"; Expression = { $_."index_name" } }, 
				@{Name = "Index Type"; Expression = { $_."index_type" } }, 
				@{Name = "Avg. Frag. %"; Expression = { $_."avg_frag_percent" } },
				@{Name = "Page Count"; Expression = { $_."page_count" } },
				@{Name = "Record Count"; Expression = { $_."record_count" } } | ConvertTo-Html -As Table -Fragment
				$HtmlTabName = "Index fragmentation info for $CheckDB"
			
				$html = $HTMLPre + @"
			<title>$HtmlTabName</title>
			</head>
			<body>
			<h1>$HtmlTabName</h1>
			$htmlTable
			</body>
			</html>
"@
				if ($DebugInfo) {
					Write-Host " ->Writing HTML file." -fore yellow
				} 
				$html | Out-File -Encoding utf8 -FilePath "$HTMLOutDir\IndexFragInfo_$CheckDB.html"
			}
			else {

				$ExcelSheet = $ExcelFile.Worksheets.Item("Statistics Info")
				$ExcelStartRow = $DefaultStartRow
				$ExcelColNum = 1
				$RowNum = 0
				$DataSetCols = @("database", "object_name", "object_type", "stats_name", "origin", 
					"filter_definition", "last_updated", "rows", "unfiltered_rows", 
					"rows_sampled", "sample_percent", "modification_counter", 
					"modified_percent", "steps", "partitioned", "partition_number")

				if ($DebugInfo) {
					Write-Host " ->Writing Stats results to sheet Statistics Info" -fore yellow
				}

				foreach ($row in $StatsTbl) {
					foreach ($col in $DataSetCols) {
						if ($col -eq "last_updated") {
							$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $StatsTbl.Rows[$RowNum][$col].ToString("yyyy-MM-dd HH:mm:ss")
						}
						else {
							$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $StatsTbl.Rows[$RowNum][$col]
						}
						$ExcelColNum += 1
					}
					$ExcelStartRow += 1
					$RowNum += 1
					$ExcelColNum = 1
				}


				$ExcelSheet = $ExcelFile.Worksheets.Item("Index Fragmentation")
				$ExcelStartRow = $DefaultStartRow
				$ExcelColNum = 1
				$RowNum = 0
				$DataSetCols = @("database", "object_name", "object_type", "index_name", 
					"index_type", "avg_frag_percent", "page_count", "record_count")

				if ($DebugInfo) {
					Write-Host " ->Writing Stats results to sheet Index Fragmentation" -fore yellow
				}

				foreach ($row in $IndexTbl) {
					foreach ($col in $DataSetCols) {
						$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $IndexTbl.Rows[$RowNum][$col]
						$ExcelColNum += 1
					}
					$ExcelStartRow += 1
					$RowNum += 1
					$ExcelColNum = 1
				}

				##Saving file
				$ExcelFile.Save()
			}
			##Cleaning up variables
			Remove-Variable -Name IndexTbl
			Remove-Variable -Name StatsTbl
			Remove-Variable -Name StatsIndexSet

		}

		if ($JobStatus -ne "Running") {
			Invoke-BlitzWho -BlitzWhoQuery $BlitzWhoRepl -IsInLoop N
			$BlitzWhoPass += 1
		}
		
		if ($DBSwitched -eq "Y") {
			$CheckDB = ""
		}
	}

	$TryCompleted = "Y"
}

finally {
	if ($TryCompleted -eq "N") {
		Write-Host ""
		Write-Host " Script execution was interrupted." -Fore yellow
		Write-Host " Finishing up..." -Fore yellow
	}
	
	#####################################################################################
	#						sp_BlitzWho													#
	#####################################################################################
	###Create flag table to stop the job
	if ($JobStatus -eq "Running") {
		#Make sure the current state of the job is still Running
		$JobStatus = Get-Job -Name $JobName | Select-Object -ExpandProperty State
		if ($JobStatus -eq "Running") {
			if ($TryCompleted -eq "N") {
				Write-Host " Attempting to stop $JobName background process... " -NoNewline
			}
			else {
				Write-Host " Stopping $JobName background process... " -NoNewline
			}
			[string]$CreatFlagTbl = "CREATE TABLE [tempdb].[dbo].[BlitzWhoOutFlag_$DirDate](ID INT);"
			$CreatFlagTblCommand = new-object System.Data.SqlClient.SqlCommand
			$CreatFlagTblCommand.CommandText = $CreatFlagTbl
			$CreatFlagTblCommand.CommandTimeout = 30
			$SqlConnection.Open()
			$CreatFlagTblCommand.Connection = $SqlConnection
			Try {
				$CreatFlagTblCommand.ExecuteNonQuery() | Out-Null -ErrorAction Stop
				$SqlConnection.Close()
				$FlagCreated = "Y"
				if ($DebugInfo) {
					Write-Host ""
					Write-Host " ->Flag Table created" -Fore Yellow
				}
			}
			Catch {
				Stop-Job $JobName
				if ($DebugInfo) {
					Write-Host ""
					Write-Host " ->Failed to create [tempdb].[dbo].[BlitzWhoOutFlag_$DirDate]" -Fore Yellow
					Write-Host " ->Forcing background process stop." -Fore Yellow
				}
			}
			if ($FlagCreated -eq "Y") {
				$BlitzWhoDelay += 1
				Start-Sleep -Seconds $BlitzWhoDelay
				if ($DebugInfo) {
					Write-Host " ->Waiting for $BlitzWhoDelay seconds before getting job output." -Fore Yellow
				}
			}
			$JobStatus = Get-Job -Name $JobName | Select-Object -ExpandProperty State
			if ($JobStatus -ne "Running") {
				if ($DebugInfo) {
					Write-Host " ->$JobName process no longer running " -NoNewline -Fore Yellow
				}
				Write-Host @GreenCheck
				if ($DebugInfo) {
					Write-Host ""
				}
				Receive-Job -Name $JobName
				Remove-Job -Name $JobName
			}

		}
	}
	if ($TryCompleted -eq "N") {
		Write-Host	" Attempting to retrieve sp_BlitzWho data... " -NoNewLine
	}
	else {
		Write-Host " Retrieving sp_BlitzWho data... " -NoNewLine
	}
	[string]$Query = [System.IO.File]::ReadAllText("$ResourcesPath\GetBlitzWhoData.sql")
	[string]$Query = $Query -replace "BlitzWho_..BlitzWhoOut.." , "BlitzWho_$DirDate"
	[string]$Query = $Query -replace "BlitzWhoOutFlag_..BlitzWhoOut.." , "BlitzWhoOutFlag_$DirDate"
	$CmdTimeout = 800
	if (!([string]::IsNullOrEmpty($CheckDB))) {
		[string]$Query = $Query -replace "..PSBlitzReplace.." , $CheckDB
	}
	$BlitzWhoSelect = new-object System.Data.SqlClient.SqlCommand
	$BlitzWhoSelect.CommandText = $Query
	$BlitzWhoSelect.Connection = $SqlConnection
	$BlitzWhoSelect.CommandTimeout = $CmdTimeout 
	$BlitzWhoAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
	$BlitzWhoAdapter.SelectCommand = $BlitzWhoSelect
	$BlitzWhoSet = new-object System.Data.DataSet
	Try {
		$StepStart = get-date
		$BlitzWhoAdapter.Fill($BlitzWhoSet) | Out-Null -ErrorAction Stop
		$SqlConnection.Close()
		$StepEnd = get-date
		Write-Host @GreenCheck
		$StepRunTime = (New-TimeSpan -Start $StepStart -End $StepEnd).TotalSeconds
		$RunTime = [Math]::Round($StepRunTime, 2)
		if ($DebugInfo) {
			Write-Host " - $RunTime seconds" -Fore Yellow
		}
		$StepOutcome = "Success"
	}
 Catch {
		$StepEnd = get-date
		Invoke-ErrMsg
		$StepOutcome = "Failure"
	}
		
	if ($StepOutcome -eq "Success") {
		$BlitzWhoTbl = New-Object System.Data.DataTable
		$BlitzWhoTbl = $BlitzWhoSet.Tables[0]
		$BlitzWhoAggTbl = New-Object System.Data.DataTable
		$BlitzWhoAggTbl = $BlitzWhoSet.Tables[1]
		##Exporting execution plans to file
		#Set counter used for row retrieval
		[int]$RowNum = 0
		#loop through each row
		if ($DebugInfo) {
			Write-Host " ->Exporting execution plans" -fore yellow
		}
		foreach ($row in $BlitzWhoAggTbl) {
			<#
			Get only the column storing the execution plan data that's 
			not NULL and write it to a file
			#>
			if ($BlitzWhoAggTbl.Rows[$RowNum]["query_plan"] -ne [System.DBNull]::Value) {
				#Get session_id to append to filename
				[string]$SQLPlanFile = $BlitzWhoAggTbl.Rows[$RowNum]["sqlplan_file"]
				#Write execution plan to file
				$BlitzWhoAggTbl.Rows[$RowNum]["query_plan"] | Format-XML | Set-Content -Path $PlanOutDir\$($SQLPlanFile) -Force
			}		
			#Increment row retrieval counter
			$RowNum += 1
		}

		if ($ToHTML -eq "Y") {
			if ($DebugInfo) {
				Write-Host " ->Converting sp_BlitzWho output to HTML" -fore yellow
			}
			$HtmlTabName = "Session Activity"
			$htmlTable = $BlitzWhoTbl | Select-Object @{Name = "CheckDate"; Expression = { ($_."CheckDate").ToString("yyyy-MM-dd HH:mm:ss") } }, 
			"elapsed_time", 
			"session_id", "database_name", 
			"query_text", "query_cost", "sqlplan_file", "status", 
			"cached_parameter_info", "wait_info", "top_session_waits",
			"blocking_session_id", "open_transaction_count", "is_implicit_transaction",
			"nt_domain", "host_name", "login_name", "nt_user_name", "program_name",
			"fix_parameter_sniffing", "client_interface_name", 
			@{Name = "login_time"; Expression = { ($_."login_time").ToString("yyyy-MM-dd HH:mm:ss") } }, 
			@{Name = "start_time"; Expression = { ($_."start_time").ToString("yyyy-MM-dd HH:mm:ss") } },
			@{Name = "request_time"; Expression = { ($_."request_time").ToString("yyyy-MM-dd HH:mm:ss") } }, 
			"request_cpu_time", "request_logical_reads", "request_writes",
			"request_physical_reads", "session_cpu", "session_logical_reads",
			"session_physical_reads", "session_writes", "tempdb_allocations_mb", 
			"memory_usage", "estimated_completion_time", "percent_complete", 
			"deadlock_priority", "transaction_isolation_level", "degree_of_parallelism",
			@{Name = "grant_time"; Expression = { ($_."grant_time").ToString("yyyy-MM-dd HH:mm:ss") } }, 
			"requested_memory_kb", "grant_memory_kb", "is_request_granted",
			"required_memory_kb", "query_memory_grant_used_memory_kb", "ideal_memory_kb",
			"is_small", "timeout_sec", "resource_semaphore_id", "wait_order", "wait_time_ms",
			"next_candidate_for_memory_grant", "target_memory_kb", "max_target_memory_kb",
			"total_memory_kb", "available_memory_kb", "granted_memory_kb",
			"query_resource_semaphore_used_memory_kb", "grantee_count", "waiter_count",
			"timeout_error_count", "forced_grant_count", "workload_group_name",
			"resource_pool_name", "context_info" | ConvertTo-Html -As Table -Fragment
			$html = $HTMLPre + @"
			<title>$HtmlTabName</title>
			</head>
			<body>
		<h1>$HtmlTabName</h1>
		<br>
		$htmlTable 
		<br>
		</body>
		</html>
"@ 
			if ($DebugInfo) {
				Write-Host " ->Writing HTML file." -fore yellow
			} 

			$html | Out-File -Encoding utf8 -FilePath "$HTMLOutDir\BlitzWho.html"

			if ($DebugInfo) {
				Write-Host " ->Converting sp_BlitzWho aggregate output to HTML" -fore yellow
			}
			$HtmlTabName = "Aggregated Session Activity"
			$htmlTable = $BlitzWhoTbl | Select-Object @{Name = "start_time"; Expression = { ($_."start_time").ToString("yyyy-MM-dd HH:mm:ss") } }, 
			"elapsed_time", "session_id", "database_name", 
			"query_text", "outer_command", "query_cost", "sqlplan_file", "status", 
			"cached_parameter_info", "wait_info", "top_session_waits",
			"blocking_session_id", "open_transaction_count", "is_implicit_transaction",
			"nt_domain", "host_name", "login_name", "nt_user_name", "program_name",
			"fix_parameter_sniffing", "client_interface_name", 
			@{Name = "login_time"; Expression = { ($_."login_time").ToString("yyyy-MM-dd HH:mm:ss") } }, 
			@{Name = "request_time"; Expression = { ($_."request_time").ToString("yyyy-MM-dd HH:mm:ss") } }, 
			"request_cpu_time", "request_logical_reads", "request_writes",
			"request_physical_reads", "session_cpu", "session_logical_reads",
			"session_physical_reads", "session_writes", "tempdb_allocations_mb", 
			"memory_usage", 
			"estimated_completion_time", 
			"percent_complete", 
			"deadlock_priority", "transaction_isolation_level", "degree_of_parallelism",
			@{Name = "grant_time"; Expression = { ($_."grant_time").ToString("yyyy-MM-dd HH:mm:ss") } }, 
			"requested_memory_kb", "grant_memory_kb", "is_request_granted",
			"required_memory_kb", "query_memory_grant_used_memory_kb", "ideal_memory_kb",
			"is_small", "timeout_sec", "resource_semaphore_id", "wait_order", "wait_time_ms",
			"next_candidate_for_memory_grant", "target_memory_kb", "max_target_memory_kb",
			"total_memory_kb", "available_memory_kb", "granted_memory_kb",
			"query_resource_semaphore_used_memory_kb", "grantee_count", "waiter_count",
			"timeout_error_count", "forced_grant_count", "workload_group_name",
			"resource_pool_name", "context_info", 
			@{Name = "query_hash"; Expression = { Get-HexString -HexInput $_."query_hash" } },
			@{Name = "query_plan_hash"; Expression = { Get-HexString -HexInput $_."query_plan_hash" } } | ConvertTo-Html -As Table -Fragment
			$html = $HTMLPre + @"
				<title>$HtmlTabName</title>
				</head>
				<body>
			<h1>$HtmlTabName</h1>
			<br>
			$htmlTable 
			<br>
			</body>
			</html>
"@ 
			if ($DebugInfo) {
				Write-Host " ->Writing HTML file." -fore yellow
			}
			$html | Out-File -Encoding utf8 -FilePath "$HTMLOutDir\BlitzWho_Agg.html"

		}
		else {

			##Populating the "sp_BlitzWho" sheet
			$ExcelSheet = $ExcelFile.Worksheets.Item("sp_BlitzWho")
			#Specify at which row in the sheet to start adding the data
			$ExcelStartRow = $DefaultStartRow
			#Specify with which column in the sheet to start
			$ExcelColNum = 1
			#Set counter used for row retrieval
			$RowNum = 0

			#List of columns that should be returned from the data set
			$DataSetCols = @("CheckDate", "elapsed_time", "session_id", "database_name", 
				"query_text", "query_cost", "sqlplan_file", "status", 
				"cached_parameter_info", "wait_info", "top_session_waits",
				"blocking_session_id", "open_transaction_count", "is_implicit_transaction",
				"nt_domain", "host_name", "login_name", "nt_user_name", "program_name",
				"fix_parameter_sniffing", "client_interface_name", "login_time", "start_time",
				"request_time", "request_cpu_time", "request_logical_reads", "request_writes",
				"request_physical_reads", "session_cpu", "session_logical_reads",
				"session_physical_reads", "session_writes", "tempdb_allocations_mb", 
				"memory_usage", "estimated_completion_time", "percent_complete", 
				"deadlock_priority", "transaction_isolation_level", "degree_of_parallelism",
				"grant_time", "requested_memory_kb", "grant_memory_kb", "is_request_granted",
				"required_memory_kb", "query_memory_grant_used_memory_kb", "ideal_memory_kb",
				"is_small", "timeout_sec", "resource_semaphore_id", "wait_order", "wait_time_ms",
				"next_candidate_for_memory_grant", "target_memory_kb", "max_target_memory_kb",
				"total_memory_kb", "available_memory_kb", "granted_memory_kb",
				"query_resource_semaphore_used_memory_kb", "grantee_count", "waiter_count",
				"timeout_error_count", "forced_grant_count", "workload_group_name",
				"resource_pool_name", "context_info")

			if ($DebugInfo) {
				Write-Host " ->Writing sp_BlitzWho results to Excel" -fore yellow
			}
			#Loop through each Excel row
			foreach ($row in $BlitzWhoTbl) {
				<#
			Loop through each data set column of current row and fill the corresponding 
			Excel cell
			#>
				foreach ($col in $DataSetCols) {
					#Fill Excel cell with value from the data set
					if ($col -eq "CheckDate") {
						$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $BlitzWhoTbl.Rows[$RowNum][$col].ToString("yyyy-MM-dd HH:mm:ss")
					}
					else {
						$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $BlitzWhoTbl.Rows[$RowNum][$col]
					}
					$ExcelColNum += 1
				}
				#move to the next row in the spreadsheet
				$ExcelStartRow += 1
				#move to the next row in the data set
				$RowNum += 1
				# reset Excel column number so that next row population begins with column 1
				$ExcelColNum = 1
			}
			##Saving file 
			$ExcelFile.Save()

			##Populating the "sp_BlitzWho Aggregate" sheet
			$ExcelSheet = $ExcelFile.Worksheets.Item("sp_BlitzWho Aggregate")
			#Specify at which row in the sheet to start adding the data
			$ExcelStartRow = $DefaultStartRow
			#Specify with which column in the sheet to start
			$ExcelColNum = 1
			#Set counter used for row retrieval
			$RowNum = 0

			#List of columns that should be returned from the data set
			$DataSetCols = @("start_time", "elapsed_time", "session_id", "database_name", 
				"query_text", "outer_command", "query_cost", "sqlplan_file", "status", 
				"cached_parameter_info", "wait_info", "top_session_waits",
				"blocking_session_id", "open_transaction_count", "is_implicit_transaction",
				"nt_domain", "host_name", "login_name", "nt_user_name", "program_name",
				"fix_parameter_sniffing", "client_interface_name", "login_time", 
				"request_time", "request_cpu_time", "request_logical_reads", "request_writes",
				"request_physical_reads", "session_cpu", "session_logical_reads",
				"session_physical_reads", "session_writes", "tempdb_allocations_mb", 
				"memory_usage", "estimated_completion_time", "percent_complete", 
				"deadlock_priority", "transaction_isolation_level", "degree_of_parallelism",
				"grant_time", "requested_memory_kb", "grant_memory_kb", "is_request_granted",
				"required_memory_kb", "query_memory_grant_used_memory_kb", "ideal_memory_kb",
				"is_small", "timeout_sec", "resource_semaphore_id", "wait_order", "wait_time_ms",
				"next_candidate_for_memory_grant", "target_memory_kb", "max_target_memory_kb",
				"total_memory_kb", "available_memory_kb", "granted_memory_kb",
				"query_resource_semaphore_used_memory_kb", "grantee_count", "waiter_count",
				"timeout_error_count", "forced_grant_count", "workload_group_name",
				"resource_pool_name", "context_info", "query_hash", "query_plan_hash")

			if ($DebugInfo) {
				Write-Host " ->Writing sp_BlitzWho aggregate results to Excel" -fore yellow
			}
			#Loop through each Excel row
			foreach ($row in $BlitzWhoAggTbl) {
				<#
			Loop through each data set column of current row and fill the corresponding 
			Excel cell
			#>
				foreach ($col in $DataSetCols) {
					#Fill Excel cell with value from the data set
					#Properly handling Query Hash and Plan Hash hex values 
					if ("query_hash", "query_plan_hash" -Contains $col) {
						$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = Get-HexString -HexInput $BlitzWhoAggTbl.Rows[$RowNum][$col]
						#move to the next column
						$ExcelColNum += 1
						#move to the top of the loop
						Continue
					}
					$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $BlitzWhoAggTbl.Rows[$RowNum][$col]
					$ExcelColNum += 1
				}
				#move to the next row in the spreadsheet
				$ExcelStartRow += 1
				#move to the next row in the data set
				$RowNum += 1
				# reset Excel column number so that next row population begins with column 1
				$ExcelColNum = 1
			}
			##Saving file 
			$ExcelFile.Save()
		}
		##Cleaning up variables
		Remove-Variable -Name BlitzWhoTbl
		Remove-Variable -Name BlitzWhoAggTbl
		Remove-Variable -Name BlitzWhoSet
	}
	$SqlConnection.Dispose()

	#####################################################################################
	#						Delete unused sheets 										#
	#####################################################################################

	if ($ToHTML -ne "Y") {
		if ($IsIndepth -ne "Y") {
			$DeleteSheets = @("Wait Stats", "Storage", "Perfmon", "sp_BlitzIndex 1",
				"sp_BlitzIndex 2", "sp_BlitzIndex 4", 
				"sp_BlitzCache Reads", "sp_BlitzCache Executions", "sp_BlitzCache Writes",
				"sp_BlitzCache Spills", "sp_BlitzCache Mem & Recent Comp", "Intro")
			foreach ($SheetName in $DeleteSheets) {
				$ExcelSheet = $ExcelFile.Worksheets.Item($SheetName)
				#$ExcelSheet.Visible = $false
				$ExcelSheet.Delete()
			}
		}
		else {
			#Delete unused sheet (yes, this sheet has a space in its name)
			$DeleteSheets = @("Intro ", "sp_BlitzIndex 0")
			foreach ($SheetName in $DeleteSheets) {
				$ExcelSheet = $ExcelFile.Worksheets.Item($SheetName)
				$ExcelSheet.Delete()
			}

		}

		if (([string]::IsNullOrEmpty($CheckDB)) -and ([string]::IsNullOrEmpty($DBName))) {
			$DeleteSheets = @("Statistics Info", "Index Fragmentation")
			foreach ($SheetName in $DeleteSheets) {
				$ExcelSheet = $ExcelFile.Worksheets.Item($SheetName)
				$ExcelSheet.Delete()
			}
		}
	}

	#####################################################################################
	#							Check end												#
	#####################################################################################
	###Record execution start and end times
	$EndDate = get-date
	if ($ToHTML -ne "Y") {
		if ($IsIndepth -eq "Y") {
			$ExcelSheet = $ExcelFile.Worksheets.Item("Intro")
		}
		else {
			$ExcelSheet = $ExcelFile.Worksheets.Item("Intro ")
		}
		$ExcelSheet.Cells.Item(5, 6) = $StartDate.ToString("yyyy-MM-dd HH:mm:ss")
		$ExcelSheet.Cells.Item(6, 6) = $EndDate.ToString("yyyy-MM-dd HH:mm:ss")
		$ExcelSheet.Cells.Item(6, 4) = $Vers

		###Save and close Excel file and app
		$ExcelFile.Save()
	}

	$ExecTime = (New-TimeSpan -Start $StartDate -End $EndDate).ToString()
	$ExecTime = $ExecTime.Substring(0, $ExecTime.IndexOf('.'))
	if ($ToHTML -eq "Y") {
		if ($DebugInfo) {
			Write-Host " ->Generating index page." -fore yellow
		} 
		$IndexContent = @"
<!DOCTYPE html>
<html>
<head>
<style>
body { 
	background-color:#FFFFFF;
	font-family:Tahoma;
	font-size:11pt; 
	}
	table {
        margin-left: auto;
        margin-right: auto;
		border-spacing: 1px;
    }
    th {
        background-color: dodgerblue;
        color: white;
        font-weight: bold;
        padding: 5px;
        text-align: center;
    }
    td, th {
        border: 1px solid black;
        padding: 5px;
    }
    td:first-child {
        font-weight: bold;
        text-align: left;
    }
    h1 {
        text-align: center;
    }
    h2 {
        test-align: center;
    }
</style>
<title>PSBlitz Output For $InstName</title>
</head>
<body>
    <h1>PSBlitz Output For $InstName</h1>
    <table>
        <tr>
            <th>Generated With</th>
            <th>Version</th>
            <th>Execution start</th>
            <th>Execution end</th>
            <th>Duration (hh:mm:ss)</th>
        </tr>
        <tr>
            <td><a href='https://github.com/VladDBA/PSBlitz' target='_blank'>PSBlitz.ps1</a></td>
            <td>$Vers</td>
            <td>$($StartDate.ToString("yyyy-MM-dd HH:mm:ss"))</td>
            <td>$($EndDate.ToString("yyyy-MM-dd HH:mm:ss"))</td>
            <td>$ExecTime</td>
        </tr>
    </table>
    <br>
    <h1>Table of contents</h1>
    <table>
        <tr>
            <th>File Name</th>
            <th>Query Source</th>
            <th>Description</th>
            <th>Additional info</th>
        </tr>
"@

		# Get all HTML files in the same directory as the index.html file and create a row in the table for each file.

		
		$HtmlFiles = Get-ChildItem -Path $HTMLOutDir -Filter *.html | Sort-Object CreationTime
		foreach ($File in $HtmlFiles) {
			$AdditionalInfo = ""
			# Get the file name without the extension and replace any underscores with spaces for the description.
			$Description = $File.BaseName.Replace("_", " ")
			# Create a row in the table with a link to the file and its description.
			$RelativePath = $File.Name
			$RelativePath = ".\HTMLFiles\" + $RelativePath
			if ($File.Name -eq "spBlitz.html") {
				$Description = "Instance-level health information"
				if ($IsIndepth -eq "Y") {
					$QuerySource = "sp_Blitz @CheckServerInfo = 1, @CheckUserDatabaseObjects = 1;"
					$Description += " including a review of user databases for triggers, heaps, etc"
				}
				else {
					$QuerySource = "sp_Blitz @CheckServerInfo = 1;"
				}
				$Description += "."
			}
			elseif ($File.Name -like "InstanceInfo*") {
				$QuerySource = "sys.dm_os_sys_info, sys.dm_os_performance_counters and SERVERPROPERTY"
				$Description = "Summary informationa about the instance and its resources."
			}
			elseif ($File.Name -like "TempDBInfo*") {
				$QuerySource = "dm_db_file_space_usage, dm_db_partition_stats,dm_exec_requests"
				$Description = "Information pertaining to TempDB usage, size and configuration."
			}
			elseif ($File.Name -like "BlitzIndex*") {
				$Mode = $File.Name.Replace('BlitzIndex_', '')
				$Mode = $Mode.Replace('.html', '')
				$QuerySource = "sp_BlitzIndex @Mode = $Mode"
				if (!([string]::IsNullOrEmpty($CheckDB))) {
					$QuerySource += ", @DatabaseName = '$CheckDB';"
				}
				else {
					$QuerySource += ", @GetAllDatabases = 1;"
				}
				$AdditionalInfo = "Output limited to 10k records"
				if (($File.Name -like "BlitzIndex_0*") -or ($File.Name -like "BlitzIndex_4*")) {
					$Description = "Index-related diagnosis outlining high-value missing indexes, duplicate or almost duplicate indexes, indexes with more writes than reads, etc."
					$AdditionalInfo += "; for SQL Server 2019 - will output execution plans as .sqlplan files"
				}
				elseif ($File.Name -like "BlitzIndex_1*") {
					$Description = "Summary of database, tables and index sizes and counts."
				}
				elseif ($File.Name -like "BlitzIndex_2*") {
					$Description = "Index usage details."
				}
				$AdditionalInfo += "."
			}
			elseif ($File.Name -like "BlitzCache*") {
				$SortOrder = $File.Name.Replace('BlitzCache_', '')
				$SortOrder = $SortOrder.Replace('.html', '')
				$AdditionalInfo = "Outputs execution plans as .sqlplan files."
				if ($SortOrder -eq "Mem_Recent_Comp") {
					$QuerySource = "sp_BlitzCache @SortOrder = 'memory grant'/'recent compilations'"
					if (!([string]::IsNullOrEmpty($CheckDB))) {
						$QuerySource += ", @DatabaseName = '$CheckDB';"
					}
					else {
						$QuerySource += ";"
					}
					$Description = "Contains the top 10 queries sorted by memory grant size, and the top 50 most recently compiled queries"
					if (!([string]::IsNullOrEmpty($CheckDB))) {
						$Description += " for $CheckDB."
					}
					else {
						$Description += "."
					}
				}
				else {
					$QuerySource = "sp_BlitzCache @SortOrder = '$SortOrder'/'avg $SortOrder'"
					if (!([string]::IsNullOrEmpty($CheckDB))) {
						$QuerySource += ", @DatabaseName = '$CheckDB';"
					}
					else {
						$QuerySource += ";"
					}
					$Description = "Contains the top 10 queries sorted by $SortOrder and Average $SortOrder"
					if (!([string]::IsNullOrEmpty($CheckDB))) {
						$Description += " for $CheckDB."
					}
					else {
						$Description += "."
					}
				}
			}
			elseif ($File.Name -like "BlitzFirst3*") {
				$QuerySource = "sp_BlitzFirst @ExpertMode = 1, @Seconds = 30;"
				$Description = "What's happening on the instance during a 30 seconds time-frame."
			}
			elseif ($File.Name -like "BlitzFirst_*") {
				$QuerySource = "sp_BlitzFirst @SinceStartup = 1;"
				if ($File.Name -like "BlitzFirst_Perfmon*") {
					$Description = "Performance counters and their curent values since last instance restart from sys.dm_os_performance_counters."
				}
				elseif ($File.Name -like "BlitzFirst_Storage*") {
					$Description = "Information about each database's files, their usage an throughput since last instance restart."
				}
				elseif ($File.Name -like "BlitzFirst_Waits*") {
					$Description = "Information about wait stats recorded since last instance restart."
				}
			}
			elseif ($File.Name -like "BlitzWho*") {
				$QuerySource = "sp_BlitzWho @ExpertMode = 1"
				if (!([string]::IsNullOrEmpty($CheckDB))) {
					$QuerySource += ", @DatabaseName = '$CheckDB';"
				}
				else {
					$QuerySource += ";"
				}
				if ($File.Name -like "BlitzWho_Agg*") {
					$Description = "Aggregate of all the sp_BlitzWho passes."
					$AdditionalInfo = "Outputs execution plans as .sqlplan files."
				}
				else {
					$Description = "All the data that was collected repeatedly by sp_BlitzWho while PSBlitz was running."
				}
			}
			elseif ($File.Name -like "StatsInfo*") {
				$QuerySource = "sys.stats, sys.dm_db_stats_properties, dm_db_incremental_stats_properties"
				$Description = "Statistics information for $CheckDB."
			}
			elseif ($File.Name -like "IndexFragInfo*") {
				$QuerySource = "dm_db_index_physical_stats"
				$Description = "Index fragmentation information for $CheckDB."
			}
			elseif ($File.Name -like "BlitzLock*") {
				$QuerySource = "sp_BlitzLock @StartDate = DATEADD(DAY,-15, GETDATE()), @EndDate = GETDATE();"
				$Description = "Information about the deadlocks recorded in the default extended events session."
				$AdditionalInfo = "Outputs deadlock graphs as .xdl files."
			}
			$IndexContent += "<tr><td><a href='$RelativePath' target='_blank'>$($File.Name.Replace('.html',''))</a></td><td>$QuerySource</td><td>$Description</td><td>$AdditionalInfo</td></tr>"
		}

		# Close the HTML tags.
		$IndexContent += @"
    </table>
<br>
</body>
</html>
"@
		if (!([string]::IsNullOrEmpty($CheckDB))) {
			$IndexFile = "PSBlitzOutput_$InstName_$CheckDB.html"
		}
		else {
			$IndexFile = "PSBlitzOutput_$InstName.html"
		}
		if ($DebugInfo) {
			Write-Host " ->Writing HTML file." -fore yellow
		} 
		$IndexContent | Out-File -Encoding utf8 -FilePath "$OutDir\$IndexFile"
	}
	Write-Host $("-" * 80)
	Write-Host "Execution completed in: " -NoNewLine
	Write-Host $ExecTime -fore green
	if ($OutDir.Length -gt 40) {
		Write-Host "Generated files have been saved in: "
		Write-Host " $OutDir\"
	}
 else {
		Write-Host "Generated files have been saved in: " -NoNewLine
		Write-Host "$OutDir\"
	}
	
	if ($ToHTML -ne "Y") {
		$ExcelFile.Close()
		$ExcelApp.Quit()
		[System.Runtime.Interopservices.Marshal]::ReleaseComObject($ExcelApp) | Out-Null
		Remove-Variable -Name ExcelApp
		###Rename output file 
		if (!([string]::IsNullOrEmpty($CheckDB))) {
			$OutExcelFName = "PSBlitzOutput_$InstName_$CheckDB.xlsx"
		}
		else {
			$OutExcelFName = "PSBlitzOutput_$InstName.xlsx"
		}
		Rename-Item -Path $OutExcelF -NewName $OutExcelFName
	}
	if ($ZipOutput -eq "Y") {
		Compress-Archive -Path "$OutDir" -DestinationPath "$OutDir\..\$ZipFile"
		
		if ($ZipFile.Length -gt 30) {
			Write-Host "The following zip archive has also been created: "
			Write-Host " $ZipFile"
		}
	 else {
			Write-Host "The following zip archive has also been created: " -NoNewLine
			Write-Host " $ZipFile"
		}
	}
	Write-Host " "
	Write-Host $("-" * 80)
	if (($DebugInfo) -or ($InteractiveMode -eq 1)) {
		Read-Host -Prompt "Done. Press Enter to close this window."
	}
}