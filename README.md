# PSBlitz

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Windows PowerShell](https://img.shields.io/badge/Windows-PowerShell%207.x-5E5E5E.svg)](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows)
[![Linux](https://img.shields.io/badge/Linux-PowerShell%207.x-orange.svg)](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux)
[![SQL Server](https://img.shields.io/badge/SQL%20Server-2014%2B-0078D4.svg)](https://learn.microsoft.com/en-us/sql/sql-server)
[![Azure SQL DB](https://img.shields.io/badge/Azure%20SQL-Database-0078D4.svg)](https://learn.microsoft.com/en-us/azure/azure-sql/database/sql-database-paas-overview)
[![Azure SQL MI](https://img.shields.io/badge/Azure%20SQL-Managed%20Instance-0078D4.svg)](https://learn.microsoft.com/en-us/azure/azure-sql/managed-instance/sql-managed-instance-paas-overview)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

> A PowerShell-based SQL Server performance diagnostics and health check tool.

<a name="header1"></a>
## Navigation
- [Intro](#Intro)
- [Features overview](#Features-overview)
- [Compatibility](#Compatibility)
- [Prerequisites](#Prerequisites)
- [Installation](#Installation)
- [What it does](#What-it-does)

- [Default check VS in-depth check](#Default-check-VS-in-depth-check)
- [Output files](#Output-files)
- [Usage examples](#Usage-examples)
- [Report a bug](#Report-a-Bug)
- [Screenshots](#Screenshots)
- [License](/LICENSE)

## Intro

Since I'm a big fan of [Brent Ozar's](https://www.brentozar.com/) [SQL Server First Responder Kit](https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit) and I've found myself in many situations where I would have liked a quick way to easily export the output of sp_Blitz, sp_BlitzCache, sp_BlitzFirst, sp_BlitzIndex, sp_BlitzLock, and sp_BlitzWho to Excel, as well as saving to disk the execution plans identified by sp_BlitzCache and deadlock graphs from sp_BlitzLock, I've decided to put together a PowerShell script that does just that.<br><br>
As of version 3.0.0, PSBlitz is also capable of exporting the report to HTML making Excel/Office no longer a hard requirement for running PSBlitz.<br>
As of version 4.0.1, PSBlitz is also compatible with Azure SQL DB and Azure SQL Managed Instance. <br>
As of version 4.3.4, PSBlitz can be executed using PowerShell on Linux, the output will default to HTML regardless of the option used.

## Features overview

- SQL Server health checks
- Performance diagnostics
- Query analysis
- Deadlock investigation
- Azure SQL DB support
- Cross-platform compatibility

## Compatibility 

PSBlitz can be executed with:
- Windows PowerShell  5.1
- PowerShell 7.x
- PowerShell 7.x on Linux

## Prerequisites
1. In order to be able to run the PSBlitz.ps1 script, you'll need to unblock it:
    ```PowerShell
    Unblock-File .\PSBlitz.ps1
    ```
2. If you want the report to be in Excel format, then the MS Office suite needs to be installed on the machine where you're executing PSBlitz, otherwise use the HTML format.
3. Sufficient permissions to query DMVs, server state, and get database objects' definitions.

You __don't need__ to have any of the sp_Blitz stored procedures present on the instance that you're executing PSBlitz.ps1 for, all the scripts are contained in the `PSBlitz\Resources` directory in non-stored procedure format.

## Installation

Download the latest zip file from the [Releases](https://github.com/VladDBA/PSBlitz/releases) section of the repository and extract its contents. 

Do not change the directory structure and file names.

[*Back to top*](#header1)

## What it does

PSBlitz.ps1 uses slightly modified, non-stored procedure versions, of the following components 
from [Brent Ozar's](https://www.brentozar.com/) [SQL Server First Responder Kit](https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit).
<br>You can find the all the scripts in the repository's [Resources](/Resources) directory

#### Outputs the following to an Excel spreadsheet or to an HTML report:
- Instance information
- Currently opened transactions (if any)
- Wait stats - from sp_BlitzFirst
- Currently running queries - from sp_BlitzWho
- Instance health-related findings - from sp_Blitz
- tempdb size and usage information per object and session
- Index-related issues and recommendations - from sp_BlitzIndex
- Top 10 most resource intensive queries - from sp_BlitzCache
- Deadlock related information from the past 15 days - from sp_BlitzLock
- Information about Azure SQL DB resources, resource usage, database and database configuration
- Information about all databases and their files or for a single database in case of a database-specific check
- Query Store information in the case of a database-specific check on an eligible database - from sp_BlitzQueryStore
- Statistics details for a given database - in the case of database-specific check or if a database accounts for at least 2/3 of the sp_BlitzCache data
- Index Fragmentation information for a given database - in the case of database-specific check or if a database accounts for at least 2/3 of the sp_BlitzCache data

Exports the following files:
- Execution plans (as .sqlplan files) - from the same dataset generated by sp_BlitzCache
- Execution plans (as .sqlplan files) - from the sample execution plans provided by `sp_BlitzIndex @Mode = 0` and `sp_BlitzIndex @Mode = 4` for missing index suggestions (only on SQL Server 2019)
- Execution plans (as .sqlplan files) of currently running sessions - from the same dataset generated by sp_BlitzWho
- Deadlock graphs (as .xdl files) - from the same dataset generated by sp_BlitzLock
- Execution plans (as .sqlplan files) - from sp_BlitzLock if any of the execution plans involved in deadlocks are still	in the plan cache at the time of the check
- Execution plans (as .sqlplan files) - from sp_BlitzQueryStore in the case of a database-specific check on an eligible database

### Note
- If the execution of PSBlitz took longer than 15 minutes up until the call to sp_BlitzLock, the timeframe for sp_BlitzLock will be narrowed down to the last 7 days in order to keep execution time within a reasonable amount.<br>
- If PSBlitz detects an exclusive lock being held on a table or index it will automatically skip that table/index from the index fragmentation information and will make a note of that in the Execution Log.
- If the instance has 50 or more user databases, PSBlitz will automatically limit the following checks to the database that appears the most in the data returned by the cache related checks:
   - Index Summary
   - Index Usage Details
   - (Detailed) Index Diagnosis

  The behavior can be controlled via the `-MaxUsrDBs` parameter, but only change the value if most of those databases don't have too many tables, or you've opted to output to HTML and have enough RAM for PS to handle the data (PSBlitz will limit the output to 10k records if more rows are returned)

- If the database targeted by the "stats info" and "index fragmentation info" steps have lots of tables/indexes/partitions/statistics, the following limits will be applied:
    - Stats Info - Limited to 10k records ordered by modified percent descending.
    - Index Fragmentation Info - Limited to 20k records ordered by avg fragmentation percent descending, size descending.

## Limitations

### Check targets
- For the time being PSBlitz.ps1 can only run against SQL Server instances, Azure SQL DB, and Azure SQL Managed Instance, but not against Amazon RDS.

### Excel
- If you're using a 32bit installation of Excel and opt for the xlsx output, you might run into "out of memory" errors. <br>That's not an issue with PSBlitz, it's the direct result of opting to still use 32bit software in `SELECT DATEPART(YEAR,GETDATE())`.

## Known issues:
When running PSBlitz with the Excel output, if you (open and) close an Excel window in parallel with PSBlitz's execution you'll also cause the Excel session used by PSBlitz to close, leading to the following error message:
- `You cannot call a method on a null-valued expression.`


[*Back to top*](#header1)

## Paramaters
| Parameter | Description|
|-----------|------------|
|`-ServerName`| The name of your SQL Server instance or Azure SQL DB connection info. <br><br> Accepted input format: <br> `HostName\InstanceID` for named instances. <br> `HostName,Port` when using a port number instead of an instance ID. <br> `HostName` for default instances. <br><br>For Azure SQL DB the format is: <br> `YourServer.database.windows.net,PortNumber:YourDatabase` if you want to specify the port number. <br> `YourServer.database.windows.net:YourDatabase` if you don't want to specify the port number. <br> If your Azure SQL DB instance doesn't use the `database.windows.net` portion (e.g.: it's configured to use an IP instead) then you should provide the database name via the `-CheckDB` parameter.<br><br>Other options:<br> If you provide `?` or `Help` as a value for `-ServerName`, the script will return a brief help menu. <br> If no value is provided, the script will go into interactive mode and prompt for the appropriate input |
|`-SQLLogin`| The name of the SQL login used to run the script. If not provided, the script will use integrated security. |
|`-SQLPass` | The password for the SQL login provided via the -SQLLogin parameter, omit if `-SQLLogin` was not used. |
|`-IsIndepth` | Providing Y as a value will tell PSBlitz.ps1 to run a more in-depth check against the instance/database. Omit for default check. |
|`-CheckDB` | Used to provide the name of a specific database against which sp_BlitzIndex, sp_BlitzCache, and sp_BlitzLock will be ran. Omit to run against the whole instance.<br><br>__For Azure SQL DB__<br>Can also be used to provide the name of the Azure SQL DB database if you haven't provided it as part of the <br>`-ServerName` paramter.<br>If the database name is not provided here, nor as part of the `-ServerName`, and the environment is detected as Azure SQL DB, then you'll be prompted to provide the database name.|
|`-CacheTop`| Used to specify if more/less than the default top 10 queries should be returned for the sp_BlitzCache step. Only works for HTML output (`-ToHTM Y`). Has no effect on the `recent compilations` sort order.<br>Defaults to 10.|
|`-CacheMinutesBack`| Used to specify how many minutes back to begin plan cache analysis. <br>Defaults to entire contents of the plan cache since instance startup.<br> In order to avoid missing the desired timeframe, the value is dynamically adjusted based on the runtime of PSBlitz up until the plan cache analysis point.|
|`-OutputDir`| Used to provide a path where the output directory should be saved to. <br>Defaults to PSBlitz.ps1's directory if not specified or a non-existent path is provided.|
|`-ToHTML`| Providing Y as a value will tell PSBlitz.ps1 to output the report as HTML instead of an Excel file. This is perfect when running PSBlitz from a machine that doesn't have Office installed.|
|`-ZipOutput`| Providing Y as a value will tell PSBlitz.ps1 to also create a zip archive of the output files.<br>Defaults to N.|
|`-BlitzWhoDelay` | Used to sepcify the number of seconds between each sp_BlitzWho execution. <br>Defaults to 10 if not specified.|
|`-ConnTimeout`| Can be used to increased the timeout limit in seconds for connecting to SQL Server. <br>Defaults to 15 seconds if not specified.|
|`-MaxTimeout`| Can be used to set a higher timeout for sp_BlitzIndex and Stats and Index info retrieval. <br>Defaults to 1000 (16.6 minutes).|
|`-MaxUsrDBs`| Can be used to tell PSBlitz to raise the limit of user databases based on which index-related info is limited to only the "loudest" database in the cache results. <br>Defaults to 50. <br>Only change it if you're using using HTML output and have enough RAM to handle the increased data that PS will have to process.|
|`-DebugInfo`| Switch used to get more information for debugging and troubleshooting purposes.|

[*Back to top*](#header1)

## Default check VS in-depth check

_Note that I'm using the original stored procedure names puerly for example purposes, PSBlitz does not create or require the sp_Blitz* stored procedures to exist on the instance._

- The default check will run the following:
```SQL
sp_Blitz @CheckServerInfo = 1
sp_BlitzFirst @ExpertMode = 1, @Seconds = 30
sp_BlitzIndex @GetAllDatabases = 1, @Mode = 0
sp_BlitzCache @ExpertMode = 1, @SortOrder = 'CPU'/'avg cpu'	
sp_BlitzCache @ExpertMode = 1, @SortOrder = 'duration'/'avg duration'
sp_BlitzWho @ExpertMode = 1
sp_BlitzLock @StartDate = DATEADD(DAY,-15, GETDATE()), @EndDate = GETDATE()
```

- The in-depth check will run the following:
```SQL
sp_Blitz @CheckServerInfo = 1, @CheckUserDatabaseObjects = 1	
sp_BlitzFirst @ExpertMode = 1, @Seconds = 30	
sp_BlitzFirst @SinceStartup = 1	
sp_BlitzIndex @GetAllDatabases = 1, @Mode = 1	
sp_BlitzIndex @GetAllDatabases = 1, @Mode = 2	
sp_BlitzIndex @GetAllDatabases = 1, @Mode = 4	
sp_BlitzCache @ExpertMode = 1, @SortOrder = 'CPU'/'avg cpu'	
sp_BlitzCache @ExpertMode = 1, @SortOrder = 'reads'/'avg reads'	
sp_BlitzCache @ExpertMode = 1, @SortOrder = 'writes'/'avg writes'
sp_BlitzCache @ExpertMode = 1, @SortOrder = 'duration'/'avg duration'	
sp_BlitzCache @ExpertMode = 1, @SortOrder = 'executions'/'xpm'	
sp_BlitzCache @ExpertMode = 1, @SortOrder = 'memory grant'	
sp_BlitzCache @ExpertMode = 1, @SortOrder = 'recent compilations', @Top = 50	
sp_BlitzCache @ExpertMode = 1, @SortOrder = 'spills'/'avg spills'	
sp_BlitzWho @ExpertMode = 1	
sp_BlitzLock @StartDate = DATEADD(DAY,-15, GETDATE()), @EndDate = GETDATE()
```

- sp_BlitzWho will be executed as part of a background process at every 10 seconds. The frequency can be changed using the `-BlitzWhoDelay` parameter. Note that I don't recommend going with values lower than 5 for -BlitzWhoDelay, especially in a production environment.

- Using `-CheckDB SomeDB` will modify the executions of sp_Blitz, sp_BlitzCache, sp_BlitzIndex, and sp_BlitzLock as follows:
```SQL
sp_Blitz @CheckServerInfo = 1, @CheckUserDatabaseObjects = 0
sp_BlitzIndex @GetAllDatabases = 0, @DatabaseName = 'SomeDB', @Mode = ...
sp_BlitzCache @ExpertMode = 1, @DatabaseName = 'SomeDB', @SortOrder = ...
sp_BlitzLock @StartDate = DATEADD(DAY,-15, GETDATE()), @EndDate = GETDATE(), @DatabaseName = 'SomeDB'
```
- Using `-CheckDB SomeDB` will also retrieve current statistics data and index fragmentation data for said database.
[*Back to top*](#header1)

## Output files
The output directory will be created by default in the PSBlitz directory where the PSBlitz.ps1 script lives.<br>
If you want to script to write the output directory to another path, use the `-OutputDir` parameter followed by the desired path (the path has to be valid otherwise PSBlitz will use the default output path).

Output directory name `[HostName]_[Instance]_[TimeStamp]` for an instance-wide check, or `[HostName]_[Instance]_[TimeStamp]_[Database]` for a database-specific check.

Deadlocks will be saved in the Deadlocks directory under the output directory.

Deadlock file naming convention - `Deadlock_[DeadlockNumber].xdl`

Execution plans will be saved in the Plans directory under the output directory.

Execution plans file naming convention:
 - for plans obtained through sp_BlitzCache - `[SortOrder]_[RowNumber].sqlplan`.
 - for plans obtained through sp_BlitzIndex (only available in SQL Server 2019 and above) - `MissingIndex_[MissingIndexNumber].sqlplan`.
 - for plans obtained through the open transactions check - `OpenTranCurrent_[SPID].sqlplan` and/or `OpenTranRecent_[SPID].sqlplan`.
 - for plans obtained through sp_BlitzQueryStore - `QueryStore_[RowNumber].sqlplan`
 - for plans obtained through sp_BlitzWho - `RunningNow_[RowNumber].sqlplan`. If no query plan hash is returned by sp_BlitzWho, then 0x00 will be used.

[*Back to top*](#header1)

## Usage examples
You can run PSBlitz.ps1 by simply right-clicking on the script and then clicking on "Run With PowerShell" which will execute the script in interactive mode, prompting you for the required input.<br>
Note that parameters like `-DebugMode`, `-OutputDir`, `-CacheTop`, and `-MaxTimeout` are only available in command line mode.

Otherwise you can navigate in PowerShell to the directory where the script is and execute it by providing parameters and appropriate values.
- Examples:
1. Print the help menu
    ```PowerShell
    .\PSBlitz.ps1 ?
    ```
    or
    ```PowerShell
    .\PSBlitz.ps1 Help
    ```
    or (recommended for detailed and well-structured help info)
   ```PowerShell
   Get-Help .\PSBlitz.ps1 -Full
   ```
3. Run it against the whole instance (named instance SQL01), with default checks via integrated security
    ```PowerShell
    .\PSBlitz.ps1 Server01\SQL01
    ```
4. Run it against the whole instance listening on port 1433 on host Server01, with default checks via integrated security
    ```PowerShell
    .\PSBlitz.ps1 Server01,1433
    ```
5. Run it against the whole instance, with in-depth checks via integrated security
    ```PowerSHell
    .\PSBlitz.ps1 Server01\SQL01 -IsIndepth Y
    ```
6. Run it against the whole instance, with in-depth checks via integrated security, and have sp_BlitzWho execute every 5 seconds
    ```PowerSHell
    .\PSBlitz.ps1 Server01\SQL01 -IsIndepth Y -BlitzWhoDelay 5
    ```
7. Run it with in-depth checks, limit sp_BlitzIndex, sp_BlitzCache, and sp_BlitzLock to YourDatabase only, via integrated security
    ```PowerShell
    .\PSBlitz.ps1 Server01\SQL01 -IsIndepth Y -CheckDB YourDatabase
    ```
8. Run it against the whole instance, with default checks via SQL login and password
    ```PowerShell
    .\PSBlitz.ps1 Server01\SQL01 -SQLLogin DBA1 -SQLPass SuperSecurePassword
    ```
9. Run it against a default instance residing on Server02, with in-depth checks via SQL login and password, while limmiting sp_BlitzIndex, sp_BlitzCache, and sp_BlitzLock to YourDatabase only
    ```PowerShell
    .\PSBlitz.ps1 Server02 -SQLLogin DBA1 -SQLPass SuperSecurePassword -IsIndepth Y -CheckDB YourDatabase
    ```
10. Run the same command as above, but increase execution timeout for sp_BlitzIndex, stats and index info retrieval, while also increasing delay between sp_BlitzWHo executions as well as getting more verbose console output and saving the output directory to C:\temp
    ```PowerShell
    .\PSBlitz.ps1 Server02 -SQLLogin DBA1 -SQLPass SuperSecurePassword -IsIndepth Y -CheckDB YourDatabase -MaxTimeout 1200 -BlitzWhoDelay 20 -DebugInfo -OutputDir C:\Temp
    ```
11. Run PSBlitz but return the report as HTML instead of XLSX while also creating a zip archive of the output files.
    ```PowerShell
    .\PSBlitz.ps1 Server01\SQL01 -ToHTML Y -ZipOutput Y 
    ```
12. Run it against the YourDatabase database hosted in Azure SQL DB at yourserver.database.windows.net port 1433 via SQL login and password
    ```PowerShell
    .\PSBlitz.ps1 yourserver.database.windows.net,1433:YourDatabase -SQLLogin DBA1 -SQLPass SuperSecurePassword
    ```
13. Run it against the Azure SQL Managed Instance yourserver.database.windows.net
    ```PowerShell
    .\PSBlitz.ps1 yourserver.database.windows.net -SQLLogin DBA1 -SQLPass SuperSecurePassword
    ```
14. Run it against the Azure SQL Managed Instance yourserver.database.windows.net with an in-depth check while limiting index, stats, plan cache, and database info to YourDatabase
    ```PowerShell
    .\PSBlitz.ps1 yourserver.database.windows.net -SQLLogin DBA1 -SQLPass SuperSecurePassword -IsIndepth Y -CheckDB YourDatabase
    ```
Note that `-ServerName` is a positional parameter, so you don't necessarily have to specify the parameter's name as long as the first thing after the script's name is the instance 

[*Back to top*](#header1)

## Report a Bug
If you've ran into an error while running PSBlitz, please read [this](https://github.com/VladDBA/PSBlitz/issues/216) before opening an issue.

## Screenshots
![GIF](https://raw.githubusercontent.com/VladDBA/PSBlitz/main/Screenshots/GIF_000.gif)
![Screenshot1](https://raw.githubusercontent.com/VladDBA/PSBlitz/main/Screenshots/Img001.png)
![Screenshot2](https://raw.githubusercontent.com/VladDBA/PSBlitz/main/Screenshots/Img002.png)
![Screenshot4](https://raw.githubusercontent.com/VladDBA/PSBlitz/main/Screenshots/Img004.png)

[*Back to top*](#header1)
