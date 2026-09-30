# PSBlitz Minimum Permissions

PSBlitz runs Brent Ozar's [First Responder Kit](https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit) (sp_Blitz, sp_BlitzCache, sp_BlitzFirst, sp_BlitzIndex, sp_BlitzLock, sp_BlitzWho) and Erik Darling's [sp_QuickieStore](https://github.com/erikdarlingdata/DarlingData). The permissions required are the union of what those components need.

---

## Minimum Permissions (non-sysadmin)

### Server-level

| Permission | Required by | Notes |
|---|---|---|
| `VIEW SERVER STATE` | All sp_Blitz* | Required — script fails without it |
| `VIEW ANY DEFINITION` | sp_BlitzIndex | Needed to read catalog views across databases |
| `ALTER TRACE` | sp_Blitz | Optional — some trace checks skipped without it |

### Database-level

| Database | Permission | Required by | Notes |
|---|---|---|---|
| `msdb` | `SELECT` on `dbo.sysjobs`, `dbo.sysjobsteps`, `dbo.sysjobhistory` | sp_Blitz, sp_BlitzWho, sp_BlitzLock | Job names and history; checks skipped if absent |
| `msdb` | `SELECT` on `dbo.sysjobschedules`, `dbo.syscategories` | sp_Blitz | Agent schedule checks; skipped if absent |
| `model` | `SELECT` (any object) | sp_Blitz | Database defaults checks; skipped if absent |
| Target DB(s) | `VIEW DATABASE STATE` | sp_QuickieStore (Query Store) | Required to read Query Store DMVs |
| Target DB(s) | `db_datareader` or equivalent | sp_BlitzIndex, stats/index queries | Needed for index and statistics analysis |

### Object-level (optional, improves results)

| Object | Permission | Required by | Without it |
|---|---|---|---|
| `master.sys.xp_fixeddrives` | `EXECUTE` | sp_Blitz | Disk space check (CheckID 92) skipped |
| `master.sys.xp_cmdshell` | `EXECUTE` | sp_Blitz | Some checks skipped |
| `master.dbo.sp_MSgetalertinfo` | `EXECUTE` | sp_Blitz | Alert check skipped |

---

## Full Results: sysadmin

Running PSBlitz with `sysadmin` membership gives complete output with no skipped checks.
Non-sysadmin logins will still produce useful output, but sp_Blitz will include a result noting which checks were skipped due to permissions.

---

## Role Template

```sql
-- =============================================
-- PSBlitz minimal permissions role template
-- Run on the SQL Server instance as sysadmin
-- Replace [PSBlitzLogin] with your login name
-- =============================================

USE [master];
GO

-- Server-level permissions
GRANT VIEW SERVER STATE   TO [PSBlitzLogin];
GRANT VIEW ANY DEFINITION TO [PSBlitzLogin];
-- Uncomment if you want trace-related checks:
-- GRANT ALTER TRACE TO [PSBlitzLogin];
GO

-- msdb: Agent job visibility
USE [msdb];
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'PSBlitzLogin')
    CREATE USER [PSBlitzLogin] FOR LOGIN [PSBlitzLogin];
GRANT SELECT ON dbo.sysjobs          TO [PSBlitzLogin];
GRANT SELECT ON dbo.sysjobsteps      TO [PSBlitzLogin];
GRANT SELECT ON dbo.sysjobhistory    TO [PSBlitzLogin];
GRANT SELECT ON dbo.sysjobschedules  TO [PSBlitzLogin];
GRANT SELECT ON dbo.syscategories    TO [PSBlitzLogin];
GO

-- model: database defaults checks
USE [model];
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'PSBlitzLogin')
    CREATE USER [PSBlitzLogin] FOR LOGIN [PSBlitzLogin];
GRANT SELECT ON SCHEMA::dbo TO [PSBlitzLogin];
GO

-- Per target database: index analysis and Query Store
-- Repeat for each database you want PSBlitz to analyze
USE [YourDatabase];
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'PSBlitzLogin')
    CREATE USER [PSBlitzLogin] FOR LOGIN [PSBlitzLogin];
GRANT VIEW DATABASE STATE   TO [PSBlitzLogin];
GRANT SELECT ON SCHEMA::dbo TO [PSBlitzLogin];
GO
```

---

## What Works at Each Permission Level

| Feature | sysadmin | VIEW SERVER STATE + template above | VIEW SERVER STATE only |
|---|:---:|:---:|:---:|
| Wait stats (sp_BlitzFirst) | ✅ | ✅ | ✅ |
| Plan cache analysis (sp_BlitzCache) | ✅ | ✅ | ✅ |
| Deadlock info (sp_BlitzLock) | ✅ | ✅ | ✅ |
| Current sessions (sp_BlitzWho) | ✅ | ✅ | ✅ |
| Instance health checks (sp_Blitz) — full | ✅ | ✅ | ⚠️ some skipped |
| Agent job names in sp_BlitzWho/Lock | ✅ | ✅ | ❌ |
| Disk space checks | ✅ | ⚠️ needs xp_fixeddrives EXECUTE | ❌ |
| Index analysis (sp_BlitzIndex) | ✅ | ✅ | ⚠️ cross-DB limited |
| Query Store (sp_QuickieStore) | ✅ | ✅ | ❌ needs VIEW DATABASE STATE |
| Security checks | ✅ | ⚠️ partial | ⚠️ partial |
| Trace flag checks | ✅ | ⚠️ needs ALTER TRACE | ❌ |

---

## Azure SQL Database

Azure SQL DB has no server-level scope, so some permissions differ:

| Permission | Notes |
|---|---|
| `VIEW DATABASE STATE` | Replaces `VIEW SERVER STATE` — grant on the target database |
| `VIEW ANY DEFINITION` | Grant on the target database |
| No `sysadmin` | Not available; Entra admin (Active Directory admin) is the closest equivalent |
| No Agent / msdb | SQL Agent not available; agent-related checks are skipped automatically |
| No trace flags | Skipped automatically |
| No xp_fixeddrives / xp_cmdshell | Skipped automatically |

Minimum for Azure SQL DB:
```sql
-- Run as the Azure AD admin of the database
GRANT VIEW DATABASE STATE   TO [user@domain.com];
GRANT VIEW ANY DEFINITION   TO [user@domain.com];
GRANT SELECT ON SCHEMA::dbo TO [user@domain.com];
```

The Azure AD admin of the server automatically has full access and no additional grants are needed.

---

## Azure SQL Managed Instance

Behaves like on-premises SQL Server. All server-level permissions apply. The role template above works as-is.

---

## Google Cloud SQL for SQL Server

Behaves similarly to on-premises but without sysadmin access. Grant `VIEW SERVER STATE` and `VIEW ANY DEFINITION` at minimum. Some system extended procedures (xp_fixeddrives, xp_cmdshell) are unavailable — those checks are skipped automatically.
