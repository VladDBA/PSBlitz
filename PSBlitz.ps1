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
	[string]$OutputDir
)

###Internal params
#Version
$Vers = "2.3.1"
$VersDate = "20230331"
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
	} else {
		if ($ConnTest -ge 2){
			Write-Host "->Estimated response latency: $ConnTest seconds" -Fore Red
		} elseif ($ConnTest -ge 0.5) {
			Write-Host "->Estimated response latency: $ConnTest seconds" -Fore Yellow
		} elseif ($ConnTest -ge 0.2) {
			Write-Host "->Estimated response latency: $ConnTest seconds"
		} elseif ($ConnTest -lt 0.2) {
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
	if($OutputDir -notlike "*\"){
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
if($DebugInfo){
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
#Set output table for sp_BlitzWho
#$BlitzWhoOut = "BlitzWho_" + $DirDate
#Set replace strings
$OldBlitzWhoOut = "@OutputTableName = 'BlitzWho_..PSBlitzReplace..',"
$NewBlitzWhoOut = "@OutputTableName = 'BlitzWho_$DirDate',"
Copy-Item $OrigExcelF  -Destination $OutExcelF

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
		$SortOrders = @("'CPU'", "'avg cpu'", "'reads'", "'avg reads'",
			"'duration'", "'avg duration'", "'executions'", "'xpm'",
			"'writes'", "'avg writes'", "'spills'", "'avg spills'",
			"'memory grant'", "'recent compilations'")
	}
 else {
		$SortOrders = @("'CPU'", "'avg cpu'", "'duration'",
			"'avg duration'")
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
			if ($SortOrder -like '*reads*') {
				$SheetName = $SheetName + "Reads"
			}
			if ($SortOrder -like '*duration*') {
				$SheetName = $SheetName + "Duration"
			}
			if ($SortOrder -like '*executions*') {
				$SheetName = $SheetName + "Executions"
			}
			if ($SortOrder -eq "'xpm'") {
				$SheetName = $SheetName + "Executions"
			}
			if ($SortOrder -like '*writes*') {
				$SheetName = $SheetName + "Writes"
			}
			if ($SortOrder -like '*spills*') {
				$SheetName = $SheetName + "Spills"
			}
			if ($SortOrder -like '*memory*') {
				$SheetName = $SheetName + "Mem & Recent Comp"
			}
			if ($SortOrder -eq "'recent compilations'") {
				$SheetName = $SheetName + "Mem & Recent Comp"
			}

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
			if (($SortOrder -like '*avg*') -or ($SortOrder -eq "'xpm'") -or ($SortOrder -eq "'recent compilations'")) {
				$ExcelStartRow = 36
			}
			#Set counter used for row retrieval
			$RowNum = 0
			#Set counter for sqlplan file names
			$SQLPlanNum = 1


			if ($SortOrder -like '*CPU*') {
				$ExcelWarnInitCol = 1
			}
			if ($SortOrder -like '*duration*') {
				$ExcelWarnInitCol = 6
			}
			if ($SortOrder -like '*reads*') {
				$ExcelWarnInitCol = 11
			}
			if ($SortOrder -like '*writes*') {
				$ExcelWarnInitCol = 16
			}
			if ($SortOrder -like '*executions*') {
				$ExcelWarnInitCol = 21
			}
			if ($SortOrder -eq "'xpm'") {
				$ExcelWarnInitCol = 21
			}
			if ($SortOrder -like '*spills*') {
				$ExcelWarnInitCol = 26
			}
			if ($SortOrder -like '*memory*') {
				$ExcelWarnInitCol = 31
			}
			if ($SortOrder -eq "'recent compilations'") {
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
		}

		$OldSortOrder = $SortOrder
		if ($DebugInfo) {
			Write-Host " ->old sort order is now $OldSortOrder" -fore yellow
		}

		if ($JobStatus -ne "Running") {
			Invoke-BlitzWho -BlitzWhoQuery $BlitzWhoRepl -IsInLoop Y
			$BlitzWhoPass += 1
		}
		##Saving file 
		$ExcelFile.Save()
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
			#Write-Host "Mode is $Mode"
			$SheetName = "sp_BlitzIndex " + $Mode
			#Write-Host "SheetName is $SheetName"

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
			if ($Mode -eq "1") {
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
			if ($Mode -eq "2") {
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
			if ($Mode -eq "4") {
				$DataSetCols = @("Priority", "Finding", "Database Name", 
					"Details: schema.table.index(indexid)",   
					"Definition: [Property] ColumnName {datatype maxbytes}", 
					"Secret Columns", "Usage", "Size", "More Info", "Create TSQL", "URL")
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
		}
		#Update $OldMode
		$OldMode = $NewMode

		if ($JobStatus -ne "Running") {
			Invoke-BlitzWho -BlitzWhoQuery $BlitzWhoRepl -IsInLoop Y
			$BlitzWhoPass += 1
		}

		##Saving file 
		$ExcelFile.Save()
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
		##Cleaning up variables
		Remove-Variable -Name BlitzWhoTbl
		Remove-Variable -Name BlitzWhoAggTbl
		Remove-Variable -Name BlitzWhoSet
	}
	$SqlConnection.Dispose()

	#####################################################################################
	#						Delete unused sheets 										#
	#####################################################################################

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

	#####################################################################################
	#							Check end												#
	#####################################################################################
	###Record execution start and end times
	$EndDate = get-date
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
	$ExecTime = (New-TimeSpan -Start $StartDate -End $EndDate).ToString()
	$ExecTime = $ExecTime.Substring(0, $ExecTime.IndexOf('.'))
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
	Write-Host $("-" * 80)
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
	Write-Host " "
	if (($DebugInfo) -or ($InteractiveMode -eq 1)) {
		Read-Host -Prompt "Done. Press Enter to close this window."
	}
}