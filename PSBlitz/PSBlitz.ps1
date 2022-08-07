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

3. Run it against the whole instance, with in-depth checks via integrated security
.\PSBlitz.ps1 Server01\SQL01 -IsIndepth Y

4. Run it with in-depth checks, limit sp_BlitzIndex, sp_BlitzCache, and sp_BlitzLock to YourDatabase only, via integrated security
.\PSBlitz.ps1 Server01\SQL01 -IsIndepth Y -CheckDB YourDatabase

5. Run it against the whole instance, with default checks via SQL login and password
.\PSBlitz.ps1 Server01\SQL01 -SQLLogin DBA1 -SQLPass SuperSecurePassword

6. Run it against a default instance residing on Server02, with in-depth checks via SQL login and password, while limmiting sp_BlitzIndex, sp_BlitzCache, and sp_BlitzLock to YourDatabase only
.\PSBlitz.ps1 Server02 -SQLLogin DBA1 -SQLPass SuperSecurePassword -IsIndepth Y -CheckDB YourDatabase

Note that -ServerName is a positional parameter, so you don't necessarily have to specify the parameter's name as long as the first thing after the script's name is the instance or a question mark 

#MIT License

Copyright for sp_Blitz, sp_BlitzCache, sp_BlitzFirst, sp_BlitzIndex, 
sp_BlitzLock, and sp_BlitzWho is held by Brent Ozar Unlimited under MIT licence:
[SQL Server First Responder Kit](https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit)
Copyright for PSBlitz.ps1 is held by Vlad Drumea, 2022 as described below.

Copyright (c) 2022 Vlad Drumea

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
	[Parameter(Position=0,Mandatory=$False)]
		[string]$ServerName,
	[Parameter(Mandatory=$False)]
		[string]$SQLLogin,
	[Parameter(Mandatory=$False)]
		[string]$SQLPass,
	[Parameter(Mandatory=$False)]
		[string]$IsIndepth,
	[Parameter(Mandatory=$False)]
		[string]$CheckDB,
	[Parameter(Mandatory=$False)]
		[string]$Help		
	  )

#Version
$Vers = "1.00"
$VersDate = "20220801"
#Get script ptah
$ScriptPath = split-path -parent $MyInvocation.MyCommand.Definition
#Set resources path
$ResourcesPath = $ScriptPath + "\Resources"

###Functions
#Function to properly output hex strings like Plan Handle and SQL Handle
function Get-HexString{
	param (
	[System.Array]$HexInput
	)
	if($HexInput -eq [System.DBNull]::Value) {
		$HexString = ""
	} else {
	#Formatting value as hex and stripping extra stuff
	$HexSplit = ($HexInput | Format-Hex -ErrorAction Ignore | Select-String "00000")
	<#
	Converting to string, prepending 0x, removing spaces 
	and joining it in one single string
	#>
	$HexString = "0x"
	for($i=0;$i -lt $HexSplit.Length; $i++)
	{
		$HexString = $HexString + "$($HexSplit[$i].ToString().Substring(11,47).replace(' ','') )"
	}
	}
	Write-Output $HexString
}
#Function to return a brief help menu
function Get-PSBlitzHelp{
	Write-Host "`n######	PSBlitz		######`n Version $Vers - $VersDate
	`n Updates/more info: https://github.com/VladDBA/PSBlitz
	`n######	Parameters	######
-ServerName	- accepts either [hostname]\[instance] (for named instances) or just [hostname] for default instances
-SQLLogin	- the name of the SQL login used to run the script; if not provided, the script will use 
		integrated security
-SQLPass	- the password for the SQL login provided via the -SQLLogin parameter, omit if -SQLLogin was not used
-IsIndepth	- Y will run a more in-depth check against the instance/database, omit for a basic check
-CheckDB	- used to provide the name of a specific database to run some of the checks against, 
		omit to run against the whole instance
`n######	Execution	######
You can either run the script directly in PowerShell from its directory:
 Run it against the whole instance (named instance SQL01), with default checks via integrated security"
	Write-Host ".\PSBlitz.ps1 Server01\SQL01" -fore green
	Write-Host "`n Run it against a default instance installed on Server01"
	Write-Host ".\PSBlitz.ps1 Server01" -fore green
	Write-Host "`n Run it against the whole instance , with in-depth checks via integrated security"
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
if(("Y", "Yes" -Contains $Help) -or ("?", "Help" -Contains $ServerName))
{
	Get-PSBlitzHelp
	Exit
}
	
##Switch to interactive mode if $ServerName is empty
if([string]::IsNullOrEmpty($ServerName))
{
	Write-Host "Running in interactive mode"
	$InteractiveMode = 1
	##Instance
	$ServerName = Read-Host -Prompt "Server"
	#Make ServerName filename friendly and get host name 
	if($ServerName -like "*\*")
	{
		$pos = $ServerName.IndexOf("\")
		$InstName = $ServerName.Substring($pos+1)
		$HostName = $ServerName.Substring(0,$pos)
	} else {
		$InstName = $ServerName
		$HostName = $ServerName
	}
	#Return help menu if $ServerName is ? or Help
	if("?", "Help" -Contains $ServerName)
	{
		Get-PSBlitzHelp
		Read-Host -Prompt "Press Enter to exit."
		Exit
	}
	#Test if the host server is reachable
	Write-Host "->Host $HostName appears to be... " -NoNewline
	if(Test-Connection -ComputerName $HostName -Count 1 -Quiet) 
	{
		Write-Host "up" -NoNewline -fore green
		Write-Host "."
		Write-Host "Proceeding."
	} else {
		Write-Host "unreachable" -NoNewline -fore red
		Write-Host "."
		$Help = Read-Host -Prompt "Need help?[Y/N]"
		if($Help -eq "Y")
		{
			Get-PSBlitzHelp
			Read-Host -Prompt "Press Enter to exit."
		}
		Exit
	}
	##Have sp_BlitzIndex, sp_BlitzCache, sp_BlitzCache executed against a specific database
	$CheckDB = Read-Host -Prompt "Name of the database you want to check (leave empty for all)"
	##SQL Login
	$SQLLogin = Read-Host -Prompt "SQL login name (leave empty to use integrated security)"
	if(!([string]::IsNullOrEmpty($SQLLogin)))
	{
		##SQL Login pass
		$SQLPass = Read-Host -Prompt "Password "
	}
	##Indepth check 
	$IsIndepth = Read-Host -Prompt "Perform an in-depth check?[Y/N]"
} else {
	$InteractiveMode = 0
	# check if the host is reachable when in non-interactive mode
	if($ServerName -like "*\*")
	{
		$pos = $ServerName.IndexOf("\")
		$InstName = $ServerName.Substring($pos+1)
        $HostName = $ServerName.Substring(0,$pos)
	} else {
		$InstName = $ServerName
		$HostName = $ServerName
	}
	#Test if the host server is reachable
	Write-Host "->Host $HostName appears to be... " -NoNewline
	if(Test-Connection -ComputerName $HostName -Count 1 -Quiet) 
	{
		Write-Host "up" -NoNewline -fore green
		Write-Host "."
		Write-Host "Proceeding."
	} else {
		Write-Host "unreachable" -NoNewline -fore red
		Write-Host "."
		$Help = Read-Host -Prompt "Need help?[Y/N]"
		if($Help -eq "Y")
		{
			Get-PSBlitzHelp
		}
		#Read-Host -Prompt "Press Enter to exit."
		Exit
	}
}
	
###Params
##Debug - set to 1 for debugging purposes
$Debug = 0
#Turn current date time into string for output directory name
$sdate = get-date
$DirDate = $sdate.ToString("yyyyMMddHHmm")

#Set name of the input Excel file
$OrigExcelFName = "PSBlitzOutput.xlsx"
#Set path+name of the input Excel file
$OrigExcelF = $ResourcesPath + "\" + $OrigExcelFName
#Set default start row for Excel output
$DefaultStartRow = 2

#Set the string to replace for $CheckDB
if(!([string]::IsNullOrEmpty($CheckDB)))
{
	$OldCheckDBStr = ";SET @DatabaseName = NULL;"
	$NewCheckDBStr = ";SET @DatabaseName = '" + $CheckDB + "';" 
}

###Define connection
$SqlConnection = New-Object System.Data.SqlClient.SqlConnection
if(!([string]::IsNullOrEmpty($SQLLogin))) 
{
	$SqlConnection.ConnectionString ="Server=$ServerName;Database=master;User Id=$SQLLogin;Password=$SQLPass"
} else {
	$SqlConnection.ConnectionString = "Server=$ServerName;Database=master;trusted_connection=true"
}

###Test connection to instance
Write-Host "Testing connection to instance $ServerName..."
$ConnCheckQuery = new-object System.Data.SqlClient.SqlCommand
$Query = "SELECT GETDATE();"
$ConnCheckQuery.CommandText = $Query
$ConnCheckQuery.Connection = $SqlConnection
$ConnCheckQuery.CommandTimeout = 100
$ConnCheckAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
$ConnCheckAdapter.SelectCommand = $ConnCheckQuery
$ConnCheckSet = new-object System.Data.DataSet
Try 
{
	$ConnCheckAdapter.Fill($ConnCheckSet) | Out-Null -ErrorAction Stop
	$SqlConnection.Close()
} Catch {
	Write-Host "Cannot connect to instance $ServerName" -fore red
	$Help = Read-Host -Prompt "Need help?[Y/N]"
	if($Help -eq "Y")
	{
		Get-PSBlitzHelp
		#Don't close the window automatically if in interactive mode
		if($InteractiveMode -eq 1)
		{
			Read-Host -Prompt "Press Enter to exit."
			Exit
		}
	} else {
		Exit
	}
}
if($ConnCheckSet.Tables[0].Rows.Count -eq 1) 
{
	Write-Host "->Connection to $ServerName - " -NoNewLine 
	Write-Host "Ok" -fore green
}
###Test existence of value provided for $CheckDB ##not working for some reason
if(!([string]::IsNullOrEmpty($CheckDB)))
{
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
	Try
	{
		if($CheckDBSet.Tables[0].Rows[0]["name"] -eq $CheckDB) 
		{
			#Write-Host "->Database $CheckDB - exists on $ServerName" -fore green -ErrorAction Stop
			Write-Host "->Database $CheckDB - " -NoNewLine -ErrorAction Stop
			Write-Host "exists/is online" -fore green -ErrorAction Stop
		}
	} Catch {
		Write-Host "Database $CheckDB either does not exist or is not online" -fore red
		$InstanceWide = Read-Host -Prompt "Switch to instance-wide plan cache, index, and deadlock check?[Y/N]"
		if($InstanceWide -eq "Y")
		{
			$CheckDB = ""
		} else {
			$Help = Read-Host -Prompt "Need help?[Y/N]"
			if($Help -eq "Y")
			{
				Get-PSBlitzHelp
				#Don't close the window automatically if in interactive mode
				if($InteractiveMode -eq 1)
				{
					Read-Host -Prompt "Press Enter to exit."
					Exit
				}
			} else {
				Exit
			}
		}
	}

}

###Create directories
#Set output directory
if(!([string]::IsNullOrEmpty($CheckDB)))
{
	$OutDir = $scriptPath + "\" + $InstName +"_"+ $CheckDB +"_"+ $DirDate
} else {
	$OutDir = $scriptPath + "\" + $InstName +"_"+$DirDate
}
#Check if output directory exists
If(!(Test-Path $OutDir)) 
{
	New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
}
#Set plan output directory
$PlanOutDir = $OutDir + "\" + "Plans"
#Check if plan output directory exists
if(!(Test-Path $PlanOutDir)) 
{
	New-Item -ItemType Directory -Force -Path $PlanOutDir | Out-Null
}
#Set deadlock graph output directory
$XDLOutDir = $OutDir + "\" + "Deadlocks"
#Check if deadlock graph output directory exists
If(!(Test-Path $XDLOutDir)) {
	New-Item -ItemType Directory -Force -Path $XDLOutDir | Out-Null
}

###Open Excel
if($Debug -eq 1)
{
	$ErrorActionPreference = "Continue"
	Write-Host "Opening excel file" -fore yellow
} else {
	#Do not display the occasional "out of memory" errors
	$ErrorActionPreference = "SilentlyContinue"
}

$ExcelApp = New-Object -comobject Excel.Application
if($Debug -eq 1)
{
	$ExcelApp.visible = $True
} else {
	$ExcelApp.visible = $False
}
$ExcelFile = $ExcelApp.Workbooks.Open("$OrigExcelF")
$ExcelApp.DisplayAlerts = $False


###Work

####################################################################
#						sp_Blitz 
####################################################################
Write-Host " Runing sp_Blitz" -fore green
[string]$Query = [System.IO.File]::ReadAllText("$ResourcesPath\spBlitz_NonSPLatest.sql")
if($IsIndepth -eq "Y")
{
	[string]$Query = $Query -replace ";SET @CheckUserDatabaseObjects = 0;", ";SET @CheckUserDatabaseObjects = 1;"
}
$BlitzQuery = new-object System.Data.SqlClient.SqlCommand
$BlitzQuery.CommandText = $Query
$BlitzQuery.Connection = $SqlConnection
$BlitzQuery.CommandTimeout = 600
$BlitzAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
$BlitzAdapter.SelectCommand = $BlitzQuery
$BlitzSet = new-object System.Data.DataSet
$BlitzAdapter.Fill($BlitzSet) | Out-Null
$SqlConnection.Close()

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
$DataSetCols = @("Priority", "FindingsGroup", "Finding" ,"DatabaseName",
				"Details", "URL")
if($Debug -eq 1)
{
	Write-Host " ->Writing sp_Blitz results to Excel" -fore yellow
}
#Loop through each Excel row
foreach($row in $BlitzTbl)
	{
		<#
		Loop through each data set column of current row and fill the corresponding 
		Excel cell
		#>
		foreach($col in $DataSetCols)
		{
			#Fill Excel cell with value from the data set
			if($col -eq "URL")
			{
				#Make URLs clickable
				$ExcelSheet.Hyperlinks.Add($ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum),
				$BlitzTbl.Rows[$RowNum][$col],"","Click for more info",
				$BlitzTbl.Rows[$RowNum][$col]) | Out-Null
			} else {
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

####################################################################
#						sp_BlitzWho
####################################################################
Write-Host " Runing sp_BlitzWho" -fore green
[string]$Query = [System.IO.File]::ReadAllText("$ResourcesPath\spBlitzWho_NonSPLatest.sql")
$BlitzWhoQuery = new-object System.Data.SqlClient.SqlCommand
$BlitzWhoQuery.CommandText = $Query
$BlitzWhoQuery.Connection = $SqlConnection
$BlitzWhoQuery.CommandTimeout = 600
$BlitzWhoAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
$BlitzWhoAdapter.SelectCommand = $BlitzWhoQuery
$BlitzWhoSet = new-object System.Data.DataSet
$BlitzWhoAdapter.Fill($BlitzWhoSet) | Out-Null
$SqlConnection.Close()

$BlitzWhoTbl = New-Object System.Data.DataTable
$BlitzWhoTbl = $BlitzWhoSet.Tables[0]

##Exporting deadlock graphs to file
#Set counter used for row retrieval
[int]$RowNum = 0
#loop through each row
if($Debug -eq 1)
{
	Write-Host " ->Exporting execution plans" -fore yellow
}
foreach($row in $BlitzWhoTbl)
	{
		<#
		Get only the column storing the execution plan data that's 
		not NULL and write it to a file
		#>
		if($BlitzWhoTbl.Rows[$RowNum]["query_plan"] -ne [System.DBNull]::Value)
			{
				#Get session_id to append to filename
				[string]$SessionID = $BlitzWhoTbl.Rows[$RowNum]["session_id"]
				#Format the event date to append to file name
				$RunDate = $BlitzWhoTbl.Rows[$RowNum]["run_date"].ToString("yyyyMMdd_HHmmss")
				#Write execution plan to file
				$BlitzWhoTbl.Rows[$RowNum]["query_plan"] | Out-File -FilePath $PlanOutDir\RunningNow_$($RunDate)_session_$($SessionID).sqlplan
			}		
		#Increment row retrieval counter
		$RowNum+=1
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
$DataSetCols = @("run_date", "elapsed_time", "session_id", "database_name", 
 "query_text", "query_cost", "status", "wait_info", 
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

if($Debug -eq 1)
{
	Write-Host " ->Writing sp_BlitzWho results to Excel" -fore yellow
}
#Loop through each Excel row
foreach($row in $BlitzWhoTbl)
	{
		<#
		Loop through each data set column of current row and fill the corresponding 
		Excel cell
		#>
		foreach($col in $DataSetCols)
		{
			#Fill Excel cell with value from the data set
			$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $BlitzWhoTbl.Rows[$RowNum][$col]
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

####################################################################
#						sp_BlitzCache
####################################################################
#Building a list of values for @SortOrder 
<#
Ony run through the other sort orders if $IsIndepth = "Y"
otherwise just do duration and avg duration
#>
if($IsIndepth -eq "Y")
{
	$SortOrders = @("'CPU'","'avg cpu'","'reads'","'avg reads'",
	"'duration'","'avg duration'","'executions'","'xpm'",
	"'writes'","'avg writes'","'spills'","'avg spills'",
	"'memory grant'", "'recent compilations'")
} else {
	$SortOrders = @("'CPU'","'avg cpu'","'duration'",
	"'avg duration'")
}
#Set initial SortOrder value
$OldSortOrder = "'CPU'"
[string]$Query = [System.IO.File]::ReadAllText("$ResourcesPath\spBlitzCache_NonSPLatest.sql")
#Set specific database to check if a name was provided
if(!([string]::IsNullOrEmpty($CheckDB)))
{
	[string]$Query = $Query -replace $OldCheckDBStr, $NewCheckDBStr
	Write-Host " Runing sp_BlitzCache for $CheckDB" -fore green
} else {
	Write-Host " Runing sp_BlitzCache for all user databases" -fore green
}
#Loop through sort orders
foreach($SortOrder in $SortOrders)
{
	#Filename sort order portion
	$FileSOrder = $SortOrder.Replace(' ','_')
	$FileSOrder = $FileSOrder.Replace("'",'')
	
	#Replace old sort order with new one
	$OldSortString = ";SELECT @SortOrder = " + $OldSortOrder
	$NewSortString = ";SELECT @SortOrder = " + $SortOrder
	#Replace number of records returned if sorting by recent compilations
	if($SortOrder -eq "'recent compilations'") {
		$OldSortString = $OldSortString + ", @Top = 10;"
		$NewSortString = $NewSortString + ", @Top = 50;"
	}
	if($Debug -eq 1)
	{
		Write-Host " ->Replacing $OldSortString with $NewSortString" -fore yellow
	}		
	
	[string]$Query = $Query -replace $OldSortString, $NewSortString
	Write-Host " ->Runing sp_BlitzCache with @SortOrder = $SortOrder" -fore green
	$BlitzCacheQuery = new-object System.Data.SqlClient.SqlCommand
	$BlitzCacheQuery.CommandText = $Query
	$BlitzCacheQuery.CommandTimeout = 900
	$BlitzCacheQuery.Connection = $SqlConnection
	$BlitzCacheAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
	$BlitzCacheAdapter.SelectCommand = $BlitzCacheQuery
	$BlitzCacheSet = new-object System.Data.DataSet
	$BlitzCacheAdapter.Fill($BlitzCacheSet) | Out-Null
	$SqlConnection.Close()
	
	$BlitzCacheTbl = New-Object System.Data.DataTable
	$BlitzCacheTbl = $BlitzCacheSet.Tables[0]
	
	##Exporting deadlock graphs to file
	if($Debug -eq 1)
	{
		Write-Host " ->Exporting execution plans for $SortOrder" -fore yellow
	}
	#Set counter used for row retrieval
	$RowNum = 0
	#Setting $i to 0
	$i = 0

	foreach($row in $BlitzCacheTbl)
	{
		#Increment file name counter	
		$i+=1
		#Get only the column storing the execution plan data that's not NULL and write it to a file
		if($BlitzCacheTbl.Rows[$RowNum]["Query Plan"] -ne [System.DBNull]::Value){
			$BlitzCacheTbl.Rows[$RowNum]["Query Plan"] | Out-File -FilePath $PlanOutDir\$($FileSOrder)_$($i).sqlplan
			}		
		#Increment row retrieval counter
		$RowNum+=1
	}
	
	#Set Excel sheet names based on $SortOrder
	$SheetName = "sp_BlitzCache "
	if($SortOrder -like '*CPU*') 
	{
		$SheetName = $SheetName + "CPU"
	}
	if($SortOrder -like '*reads*') 
	{
		$SheetName = $SheetName + "Reads"
	}
	if($SortOrder -like '*duration*') 
	{
		$SheetName = $SheetName + "Duration"
	}
	if($SortOrder -like '*executions*') 
	{
		$SheetName = $SheetName + "Executions"
	}
	if($SortOrder -eq "'xpm'") 
	{
		$SheetName = $SheetName + "Executions"
	}
	if($SortOrder -like '*writes*') 
	{
		$SheetName = $SheetName + "Writes"
	}
	if($SortOrder -like '*spills*') 
	{
		$SheetName = $SheetName + "Spills"
	}
	if($SortOrder -like '*memory*') 
	{
		$SheetName = $SheetName + "Memory"
	}
	if($SortOrder -eq "'recent compilations'") 
	{
		$SheetName = $SheetName + "Recent Comp"
	}

	#Specify worksheet
	$ExcelSheet = $ExcelFile.Worksheets.Item($SheetName)

	#Specify at which row in the sheet to start adding the data
	$ExcelStartRow = $DefaultStartRow
	#$SortOrder containing avg or xpm will export data starting with row 16
	if(($SortOrder -like '*avg*') -or ($SortOrder -eq "'xpm'"))
	{
		$ExcelStartRow = 16
	}
	#Set counter used for row retrieval
	$RowNum = 0
	#Set counter for sqlplan file names
	$SQLPlanNum = 1
	
	$ExcelColNum = 1
		
	#define column list to only get the sp_BlitzCache columns that are relevant in this case
	$DataSetCols = @("Database","Cost","Query Text","Query Type","Warnings","# Executions","Executions / Minute","Execution Weight","% Executions (Type)","Serial Desired Memory",
	"Serial Required Memory","Total CPU (ms)","Avg CPU (ms)","CPU Weight","% CPU (Type)",
	"Total Duration (ms)","Avg Duration (ms)","Duration Weight","% Duration (Type)",
	"Total Reads","Average Reads","Read Weight","% Reads (Type)","Total Writes",
	"Average Writes","Write Weight","% Writes (Type)","Total Rows","Avg Rows","Min Rows",
	"Max Rows","# Plans","# Distinct Plans","Created At","Last Execution",
	"StatementStartOffset","StatementEndOffset","Query Hash","Query Plan Hash",
	"SET Options","Cached Plan Size (KB)","Compile Time (ms)","Compile CPU (ms)",
	"Compile memory (KB)","Plan Handle","SQL Handle","Minimum Memory Grant KB",
	"Maximum Memory Grant KB","Minimum Used Grant KB","Maximum Used Grant KB",
	"Average Max Memory Grant","Min Spills","Max Spills","Total Spills","Avg Spills")
	if($Debug -eq 1)
	{
		Write-Host " ->Writing sp_BlitzCache results to sheet $SheetName" -fore yellow
	}
	foreach($row in $BlitzCacheTbl)
	{
		$SQLPlanFile = "N/A"
		# changing the value of $SQLPlanFile only for records where execution plan info exists
		if($BlitzCacheTbl.Rows[$RowNum]["Query Plan"] -ne [System.DBNull]::Value) {
			$SQLPlanFile = $FileSOrder + "_" + $SQLPlanNum + ".sqlplan"
		}
		#Loop through each column from $DataSetCols for curent row and retrieve data from 
		foreach($col in $DataSetCols)
		{
			
			#Properly handling Query Hash, Plan Hash, Plan, and SQL Handle hex values 
			if("Query Hash", "Query Plan Hash", "Plan Handle", "SQL Handle" -Contains $col)
			{
				$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = Get-HexString -HexInput $BlitzCacheTbl.Rows[$RowNum][$col]
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
			if($ExcelColNum -eq 4) 
			{
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
	$OldSortOrder = $SortOrder
	if($Debug -eq 1)
	{
		Write-Host " ->old sort order is now $OldSortOrder" -fore yellow
	}
}

####################################################################
#						sp_BlitzFirst 30 seconds
####################################################################
Write-Host " Running sp_BlitzFirst @Seconds = 30" -fore green
[string]$Query = [System.IO.File]::ReadAllText("$ResourcesPath\spBlitzFirst_NonSPLatest.sql")
$BlitzFirstQuery = new-object System.Data.SqlClient.SqlCommand
$BlitzFirstQuery.CommandText = $Query
$BlitzFirstQuery.Connection = $SqlConnection
$BlitzFirstQuery.CommandTimeout = 600
$BlitzFirstAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
$BlitzFirstAdapter.SelectCommand = $BlitzFirstQuery
$BlitzFirstSet = new-object System.Data.DataSet
$BlitzFirstAdapter.Fill($BlitzFirstSet) | Out-Null
$SqlConnection.Close()

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

$DataSetCols = @("Priority", "FindingsGroup", "Finding", "URL", "Details")

if($Debug -eq 1)
{
	Write-Host " ->Writing sp_BlitzFirst results to Excel" -fore yellow
}
#Loop through each Excel row
foreach($row in $BlitzFirstTbl)
	{
		#Loop through each data set column of current row and fill the corresponding 
		# Excel cell
		foreach($col in $DataSetCols)
		{
			#Fill Excel cell with value from the data set
			if($col -eq "URL")
			{
				$ExcelSheet.Hyperlinks.Add($ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum),
				$BlitzFirstTbl.Rows[$RowNum][$col],"","Click for more info",
				$BlitzFirstTbl.Rows[$RowNum][$col]) | Out-Null
			} else {
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

####################################################################
#						sp_BlitzFirst since startup
####################################################################
if($IsIndepth -eq "Y")
{
	Write-Host " Running sp_BlitzFirst @SinceStartup = 1" -fore green
	[string]$Query = [System.IO.File]::ReadAllText("$ResourcesPath\spBlitzFirst_NonSPLatest.sql")
	[string]$Query = $Query -replace ";SET @SinceStartup = 0;", ";SET @SinceStartup = 1;"
	$BlitzFirstQuery = new-object System.Data.SqlClient.SqlCommand
	$BlitzFirstQuery.CommandText = $Query
	$BlitzFirstQuery.Connection = $SqlConnection
	$BlitzFirstQuery.CommandTimeout = 600
	$BlitzFirstAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
	$BlitzFirstAdapter.SelectCommand = $BlitzFirstQuery
	$BlitzFirstSet = new-object System.Data.DataSet
	$BlitzFirstAdapter.Fill($BlitzFirstSet) | Out-Null
	$SqlConnection.Close()

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

	if($Debug -eq 1)
	{
		Write-Host " ->Writing sp_BlitzFirst results to sheet Wait Stats" -fore yellow
	}
	#Loop through each Excel row
	foreach($row in $WaitsTbl)
		{
			#Loop through each data set column of current row and fill the corresponding 
			# Excel cell
			foreach($col in $DataSetCols)
			{
				if($col -eq "Sample Ended")
				{
					$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $WaitsTbl.Rows[$RowNum][$col].ToString("yyyy-MM-dd HH:mm:ss")
				} elseif($col -eq "URL") {
					#Make URLs clickable
					$ExcelSheet.Hyperlinks.Add($ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum),
					$WaitsTbl.Rows[$RowNum][$col],"","Click for more info",
					$WaitsTbl.Rows[$RowNum][$col]) | Out-Null					
				} else {
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

	## populating the "Storage" sheet
	$ExcelSheet = $ExcelFile.Worksheets.Item("Storage")
	#Specify at which row in the sheet to start adding the data
	$ExcelStartRow = $DefaultStartRow
	#Specify with which column in the sheet to start
	$ExcelColNum = 1
	#Set counter used for row retrieval
	$RowNum = 0
	
	$DataSetCols = @("Pattern", "Sample Time", "Sample (seconds)", "File Name",
		"Drive", "# Reads/Writes","MB Read/Written","Avg Stall (ms)", "file physical name",
		"DatabaseName")
	if($Debug -eq 1)
	{
		Write-Host " ->Writing sp_BlitzFirst results to sheet Storage" -fore yellow
	}
	#Loop through each Excel row
	foreach($row in $StorageTbl)
		{
			#Loop through each data set column of current row and fill the corresponding 
			# Excel cell
			foreach($col in $DataSetCols)
			{
				#Fill Excel cell with value from the data set
				if($col -eq "Sample Time")
				{
					$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $StorageTbl.Rows[$RowNum][$col].ToString("yyyy-MM-dd HH:mm:ss")
				} else {
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

	if($Debug -eq 1)
	{
		Write-Host " ->Writing sp_BlitzFirst results to sheet Perfmon" -fore yellow
	}
	#Loop through each Excel row
	foreach($row in $PerfmonTbl)
		{
			#Loop through each data set column of current row and fill the corresponding 
			# Excel cell
			foreach($col in $DataSetCols)
			{
				#Fill Excel cell with value from the data set
				if("FirstSampleTime","LastSampleTime" -Contains $col)
				{
					$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $PerfmonTbl.Rows[$RowNum][$col].ToString("yyyy-MM-dd HH:mm:ss")
				} else {
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
}

####################################################################
#						sp_BlitzIndex
####################################################################
#Building a list of values for $Modes
if($IsIndepth -eq "Y")
{
	$Modes = @("0", "1", "2", "4")
} else {
	$Modes = @("0")
}
# Set OldMode variable 
$OldMode = ";SET @Mode = 0;"
[string]$Query = [System.IO.File]::ReadAllText("$ResourcesPath\spBlitzIndex_NonSPLatest.sql")
#Set specific database to check if a name was provided
if(!([string]::IsNullOrEmpty($CheckDB)))
{
	[string]$Query = $Query -replace $OldCheckDBStr, $NewCheckDBStr
	[string]$Query = $Query -replace ";SET @GetAllDatabases = 1;", ";SET @GetAllDatabases = 0;"
	Write-Host " Runing sp_BlitzIndex for $CheckDB" -fore green
} else {
	Write-Host " Runing sp_BlitzIndex for all user databases" -fore green
}
#Loop through $Modes
foreach($Mode in $Modes)
{
	Write-Host " ->Runing sp_BlitzIndex with @Mode = $Mode" -fore green
	$NewMode = ";SET @Mode = " + $Mode + ";"
	[string]$Query = $Query -replace $OldMode, $NewMode
	$BlitzIndexQuery = new-object System.Data.SqlClient.SqlCommand
	$BlitzIndexQuery.CommandText = $Query
	$BlitzIndexQuery.CommandTimeout = 900
	$BlitzIndexQuery.Connection = $SqlConnection
	$BlitzIndexAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
	$BlitzIndexAdapter.SelectCommand = $BlitzIndexQuery
	$BlitzIndexSet = new-object System.Data.DataSet
	$BlitzIndexAdapter.Fill($BlitzIndexSet) | Out-Null
	$SqlConnection.Close()

	
	$BlitzIxTbl = New-Object System.Data.DataTable
	$BlitzIxTbl = $BlitzIndexSet.Tables[0]
	#Write-Host "Mode is $Mode"
	$SheetName = "sp_BlitzIndex " + $Mode
	#Write-Host "SheetName is $SheetName"
	
	#Specify worksheet
	$ExcelSheet = $ExcelFile.Worksheets.Item($SheetName)
	if($Mode -eq "0") {
		$DataSetCols = @("Finding", "Database Name", 
		"Details: schema.table.index(indexid)",   
		"Definition: [Property] ColumnName {datatype maxbytes}", 
		"Secret Columns", "Usage", "Size", "More Info", "Create TSQL") 
	}
	if($Mode -eq "1") {
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
	if($Mode -eq "2") {
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
	if($Mode -eq "4") {
		$DataSetCols = @("Finding", "Database Name", 
		"Details: schema.table.index(indexid)",   
		"Definition: [Property] ColumnName {datatype maxbytes}", 
		"Secret Columns", "Usage", "Size", "More Info", "Create TSQL")
	}
	#$BlitzIndexCols > $OutDir\BlitzIndexCols_$($Mode).sql

	#Specify at which row in the sheet to start adding the data
	$ExcelStartRow = $DefaultStartRow
	#Specify starting record from the data set
	$RowNum = 0
	#Specify at which column of the current $initRow of the sheet to start adding the data
	$ExcelColNum = 1
	
	#Loop through each Excel row
	if($Debug -eq 1)
	{
		Write-Host " ->Writing sp_BlitzIndex results to sheet $SheetName" -fore yellow
	}
	foreach($row in $BlitzIxTbl)
	{

		#Loop through each data set column of current row and fill the corresponding 
		# Excel cell
		foreach($col in $DataSetCols)
		{
			#Fill Excel cell with value from the data set
			$ExcelSheet.Cells.Item($ExcelStartRow, $ExcelColNum) = $BlitzIxTbl.Rows[$RowNum][$col]
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
		if($RowNum -eq 10000){
			Continue
		}
	}
	#Remove-Variable -Name BlitzIndexCols
	#Remove-Variable -Name TblIx
	#Update $OldMode
	$OldMode = $NewMode
}



####################################################################
#						sp_BlitzLock
####################################################################

if(!([string]::IsNullOrEmpty($CheckDB)))
{
	Write-Host " Runing sp_BlitzLock for $CheckDB" -fore green
} else {
	Write-Host " Runing sp_BlitzLock for all user databases" -fore green
}
[string]$Query = [System.IO.File]::ReadAllText("$ResourcesPath\spBlitzLock_NonSPLatest.sql")
#Set specific database to check if a name was provided
if(!([string]::IsNullOrEmpty($CheckDB)))
{
	[string]$Query = $Query -replace $OldCheckDBStr, $NewCheckDBStr
}
$BlitzLockQuery = new-object System.Data.SqlClient.SqlCommand
$BlitzLockQuery.CommandText = $Query
$BlitzLockQuery.Connection = $SqlConnection
$BlitzLockQuery.CommandTimeout = 900
$BlitzLockAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
$BlitzLockAdapter.SelectCommand = $BlitzLockQuery
$BlitzLockSet = new-object System.Data.DataSet
$BlitzLockAdapter.Fill($BlitzLockSet) | Out-Null
$SqlConnection.Close()

$TblLockDtl = New-Object System.Data.DataTable
$TblLockOver = New-Object System.Data.DataTable

$TblLockDtl = $BlitzLockSet.Tables[0]
$TblLockOver = $BlitzLockSet.Tables[1]

##Exporting deadlock graphs to file
#Set counter used for row retrieval
[int]$RowNum = 0
#Setting $i to 0
$i = 0
if($Debug -eq 1)
{
	Write-Host " ->Exporting deadlock graphs" -fore yellow
}
foreach($row in $TblLockDtl)
{
	#Increment file name counter
	$i+=1
	<#
	Get only the column storing the deadlock graph data that's not NULL, limit to one export per event by filtering for VICTIM, and write it to a file
	#>
	if(($TblLockDtl.Rows[$RowNum]["deadlock_graph"] -ne [System.DBNull]::Value) -and ($TblLockDtl.Rows[$RowNum]["deadlock_group"] -like "*VICTIM*"))
	{
		#format the event date to append to file name
		$DLDate = $TblLockDtl.Rows[$RowNum]["event_date"].ToString("yyyyMMdd_HHmmss")
		#write .xdl file
		$TblLockDtl.Rows[$RowNum]["deadlock_graph"] | Out-File -FilePath $XDLOutDir\$($DLDate)_$($i).xdl
	}
	#Increment row retrieval counter
	$RowNum+=1
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
$DataSetCols = @("deadlock_type", "event_date", "database_name","spid",
				"deadlock_group", "query","object_names", "isolation_level",
				"owner_mode", "waiter_mode", "transaction_count", "login_name",
				"host_name", "client_app", "wait_time", "wait_resource", 
				"priority", "log_used", "last_tran_started", "last_batch_started",
				"last_batch_completed",	"transaction_name")
if($Debug -eq 1)
{
	Write-Host " ->Writing sp_BlitzLock results to Excel" -fore yellow
}
#Loop through each Excel row
foreach($row in $TblLockDtl)
	{
		<#
		Loop through each data set column of current row and fill the corresponding 
		 Excel cell
		 #>
		foreach($col in $DataSetCols)
		{
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

#Loop through each Excel row
foreach($row in $TblLockOver)
	{
		<#
		Loop through each data set column of current row and fill the corresponding 
		 Excel cell
		 #>
		foreach($col in $DataSetCols)
		{
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


####################################################################
#						If IsIndepth <> Y delete unused sheets 
####################################################################

if($IsIndepth -ne "Y")
{
	$IndepthSheets = @("Wait Stats", "Storage", "Perfmon", "sp_BlitzIndex 1",
		"sp_BlitzIndex 2", "sp_BlitzIndex 4", 
		"sp_BlitzCache Reads", "sp_BlitzCache Executions", "sp_BlitzCache Writes",
		"sp_BlitzCache Spills", "sp_BlitzCache Memory", "sp_BlitzCache Recent Comp", 
		"Intro")
	foreach($SheetName in $IndepthSheets)
	{
		$ExcelSheet = $ExcelFile.Worksheets.Item($SheetName)
		#$ExcelSheet.Visible = $false
		$ExcelSheet.Delete()
	}
	
} else {
	#Delete unused sheet (yes, this sheet has a space in its name)
	$SheetName = "Intro "
	$ExcelSheet = $ExcelFile.Worksheets.Item($SheetName)
	$ExcelSheet.Delete()

}

####################################################################
#						Save Excel file  
####################################################################
if(!([string]::IsNullOrEmpty($CheckDB)))
{
	$ExcelFile.SaveAs("$OutDir\PSBlitzOutput_$InstName_$CheckDB.xlsx")
} else {
	$ExcelFile.SaveAs("$OutDir\PSBlitzOutput_$InstName.xlsx")
}
Write-Host " ";
Write-Host "All generated files have been saved in $OutDir\"
$ExcelFile.Close()
$ExcelApp.Quit()
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($ExcelApp) | Out-Null
Remove-Variable -Name ExcelApp
Write-Host " "
if(($Debug -eq 1) -or ($InteractiveMode -eq 1))
{
	Read-Host -Prompt "Done. Press Enter to exit."
}
