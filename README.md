# PSBlitz
Since I'm a big fan of [Brent Ozar's](https://www.brentozar.com/) [SQL Server First Responder Kit](https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit) and I've found myself in many situations where I would have liked a quick way to easily export the output of sp_Blitz, sp_BlitzCache, sp_BlitzFirst, sp_BlitzIndex, sp_BlitzLock, and sp_BlitzWho, to Excel and saving to disk execution plans identified by sp_BlitzCache and deadlock graphs from sp_BlitzLock, I've decided to put together a PowerShell script that does just that.

## What it does

## What it runs

## Paramaters
| Parameter | Description|
|-----------|------------|
|-ServerName| Accepts either `HostName\InstanceID` (for named instances) or just `HostName` for default instances. If you provide either `?` or `Help` as a value for `-ServerName`, the script will return a brief help menu. | your SQL Server instance, `?`, `Help` |
|-SQLLogin| The name of the SQL login used to run the script. If not provided, the script will use integrated security. | the name of your SQL Login, empty | empty|
|-SQLPass | The password for the SQL login provided via the -SQLLogin parameter, omit if `-SQLLogin` was not used. |
|-IsIndepth | Providing Y as a value will tell PSBlitz.ps1 to run a more in-depth check against the instance/database. Omit for default check. |
|-CheckDB | Used to provide the name of a specific database against which sp_BlitzIndex, sp_BlitzCache, and sp_BlitzLock will be ran. Omit to run against the whole instance.|

## Default check vs. in-depth check

