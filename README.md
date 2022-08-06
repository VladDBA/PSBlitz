# PSBlitz
Since I'm a big fan of [Brent Ozar's](https://www.brentozar.com/) [SQL Server First Responder Kit](https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit) and I've found myself in many situations where I would have liked a quick way to easily export the output of sp_Blitz, sp_BlitzCache, sp_BlitzFirst, sp_BlitzIndex, sp_BlitzLock, and sp_BlitzWho to Excel and saving to disk execution plans identified by sp_BlitzCache and deadlock graphs from sp_BlitzLock, I've decided to put together a PowerShell script that does just that.

## What it does

Outputs relevant diagnostics data about your instance and database(s) to an Excel file, as well as writing execution plans and deadlock graphs to disk.

## What it runs
PSBlitz.ps1 uses slightly modified, non-stored procedure versions, of the following components 
from [Brent Ozar's](https://www.brentozar.com/) [SQL Server First Responder Kit](https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit):
- sp_Blitz
- sp_BlitzCache
- sp_BlitzFirst
- sp_BlitzIndex
- sp_BlitzLock
- sp_BlitzWho

## Paramaters
| Parameter | Description|
|-----------|------------|
|-ServerName| Accepts either `HostName\InstanceID` (for named instances) or just `HostName` for default instances. If you provide either `?` or `Help` as a value for `-ServerName`, the script will return a brief help menu. | your SQL Server instance, `?`, `Help` |
|-SQLLogin| The name of the SQL login used to run the script. If not provided, the script will use integrated security. | the name of your SQL Login, empty | empty|
|-SQLPass | The password for the SQL login provided via the -SQLLogin parameter, omit if `-SQLLogin` was not used. |
|-IsIndepth | Providing Y as a value will tell PSBlitz.ps1 to run a more in-depth check against the instance/database. Omit for default check. |
|-CheckDB | Used to provide the name of a specific database against which sp_BlitzIndex, sp_BlitzCache, and sp_BlitzLock will be ran. Omit to run against the whole instance.|

## Default check vs. in-depth check

- The default check will run the following:
```SQL
sp_Blitz @CheckServerInfo = 1
sp_BlitzFirst @ExpertMode = 1, @Seconds = 30
sp_BlitzIndex @GetAllDatabases = 1, @Mode = 0
sp_BlitzCache @ExpertMode = 1, @SortOrder = 'duration'/'avg duration'
sp_BlitzWho @ExpertMode = 1
sp_BlitzLock @StartDate = DATEADD(DAY,-30, GETDATE()), @EndDate = GETDATE()
```

- The in-depth check will run the following:
```SQL
sp_Blitz @CheckServerInfo = 1, @CheckUserDatabaseObjects = 1	
sp_BlitzFirst @ExpertMode = 1, @Seconds = 30	
sp_BlitzFirst @SinceStartup = 1
sp_BlitzIndex @GetAllDatabases = 1, @Mode = 0	
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
sp_BlitzLock @StartDate = DATEADD(DAY,-30, GETDATE()), @EndDate = GETDATE()
```

- Using `-CheckDB SomeDB` will modify the executions of sp_BlitzCache, sp_BlitzIndex, and sp_BlitzLoc as follows:
```SQL
sp_BlitzIndex @GetAllDatabases = 0, @DatabaseName = 'SomeDB', @Mode = ...
sp_BlitzCache @ExpertMode = 1, @DatabaseName = 'SomeDB', @SortOrder = ...
sp_BlitzLock @StartDate = DATEADD(DAY,-30, GETDATE()), @EndDate = GETDATE(), @DatabaseName = 'SomeDB'
```

## Usage examples


