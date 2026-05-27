# PSBlitz Security Check Findings

| Priority | Findings Group | Finding |
|----------|---------------|---------|
| 1 | Excessive Privileges | sa login is enabled |
| 1 | Excessive Privileges | [Member of local Administrators group](https://vladdba.com/AdministratorsToSysadmin) *(Windows only)* |
| 1 | Excessive Privileges | [SQL Server service account in Administrators group](https://vladdba.com/SQLServerSvcAccount) *(Windows only)* |
| 1 | Excessive Privileges | [SQL Server Agent service account in Administrators group](https://vladdba.com/SQLServerSvcAccount) *(Windows only)* |
| 1 | Excessive Privileges | [SQL Server Agent service using built-in elevated account](https://vladdba.com/SQLServerSvcAccount) *(Windows only)* |
| 1 | Excessive Privileges | [SQL Server service using built-in elevated account](https://vladdba.com/SQLServerSvcAccount) *(Windows only)* |
| 1 | Excessive Privileges | [sysadmin role member](https://learn.microsoft.com/en-us/sql/relational-databases/security/authentication-access/server-level-roles?view=sql-server-ver17#fixed-server-level-roles) |
| 1 | Excessive Privileges | [securityadmin role member](https://vladdba.com/PrivEscPermissions) |
| 1 | Excessive Privileges | db_owner role membership in system database [1] |
| 1 | Excessive Privileges | Powerful database role membership in system database [1] |
| 1 | Excessive Privileges | Nested roles in system database [1] |
| 1 | Failed Login Attempts | Failed login attempts detected [2] |
| 1 | Insufficient Auditing | Failed login auditing not enabled |
| 1 | Linked Server Security | [Linked server with \[sa\] as catch-all](https://vladdba.com/LinkedServers) |
| 1 | Privilege Escalation Path | [Login with CONTROL SERVER permission](https://vladdba.com/PrivEscPermissions) |
| 1 | Privilege Escalation Path | [Login with IMPERSONATE ANY LOGIN permission](https://vladdba.com/PrivEscPermissions) |
| 1 | Privilege Escalation Path | [Login with IMPERSONATE permission on privileged logins](https://vladdba.com/PrivEscPermissions) |
| 1 | Privilege Escalation Path | [High-privilege permission granted to public server role](https://vladdba.com/PrivEscPermissions) |
| 1 | Privilege Escalation Path | [Trustworthy database with sysadmin owner](https://vladdba.com/TrustworthySysadmin) |
| 1 | Remote Code Execution | [xp_cmdshell enabled - sysadmin privileged OS access](https://vladdba.com/xp-cmdshell) *(Windows only)* [3] |
| 1 | Remote Code Execution | [xp_cmdshell enabled - privileged OS access](https://vladdba.com/xp-cmdshell) *(Windows only)* [3] |
| 1 or 2 | Remote Code Execution | SQL Server Agent job executing OS commands *(Windows only)* [4] |
| 1 | Weak Passwords | Password same as login name |
| 1 | Weak Passwords | Common password |
| 1 | Weak Passwords | Blank password |
| 2 | Attack Surface | Database Mail XPs enabled |
| 2 | Attack Surface | [Ad Hoc Distributed Queries enabled](https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/ad-hoc-distributed-queries-server-configuration-option?view=sql-server-ver17) |
| 2 | Attack Surface | Agent job runs at startup |
| 2 | Attack Surface | [Remote access enabled](https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/configure-the-remote-access-server-configuration-option) |
| 2 | Attack Surface | [Startup stored procedure](https://vladdba.com/StartupProcs) |
| 2 | Excessive Privileges | [dbcreator role member](https://learn.microsoft.com/en-us/sql/relational-databases/security/authentication-access/server-level-roles?view=sql-server-ver17#fixed-server-level-roles) |
| 2 | Excessive Privileges | [##MS_DatabaseManager## role member](https://learn.microsoft.com/en-us/sql/relational-databases/security/authentication-access/server-level-roles?view=sql-server-ver17#fixed-server-level-roles-introduced-in-sql-server-2022) *(SQL Server 2022+ only)* |
| 2 | Excessive Privileges | SQL Server service account in sysadmin *(Windows only)* |
| 2 | Excessive Privileges | SQL Server Agent service account in sysadmin *(Windows only)* |
| 2 | Excessive Privileges | Permission granted to public server role |
| 2 | Excessive Privileges | Permission granted to public database role |
| 2 | Excessive Privileges | db_owner role membership [1] |
| 2 | Excessive Privileges | Powerful database role membership [1] |
| 2 | Failed Login Attempts | Failed login attempts detected [2] |
| 2 | Insufficient Auditing | Limited number of error logs retained |
| 2 | Insufficient Hardening | sa login is enabled and renamed |
| 2 | Linked Server Security | [Linked server with catch-all](https://vladdba.com/LinkedServers) |
| 2 | Linked Server Security | [Linked server using self-mapping](https://vladdba.com/LinkedServers) |
| 2 | Privilege Escalation Path | Cross-database ownership chaining enabled |
| 2 | Privilege Escalation Path | [Trustworthy database with non-sysadmin owner](https://vladdba.com/TrustworthySysadmin) |
| 2 | Privilege Escalation Path | [Database owned by sysadmin](https://vladdba.com/TrustworthySysadmin) |
| 2 | Remote Code Execution | [CLR enabled](https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/clr-enabled-server-configuration-option?view=sql-server-ver16) |
| 2 | Remote Code Execution | [OLE Automation Procedures enabled](https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/ole-automation-procedures-server-configuration-option?view=sql-server-ver17) |
| 2 | Remote Code Execution | [xp_cmdshell enabled - SQL Server service account](https://vladdba.com/xp-cmdshell) *(Windows only)* [3] |
| 2 | Weak Passwords | Login with potentially weak password |
| 3 | Excessive Privileges | Nested roles [1] |
| 3 | Linked Server Security | [Linked server without a security context](https://vladdba.com/LinkedServers) |
| 3 | Linked Server Security | [Linked server with explicit mapping to remote login](https://vladdba.com/LinkedServers) |
| 3 | Linked Server Security | [Linked server using impersonation](https://vladdba.com/LinkedServers) |
| 3 | Remote Code Execution | [xp_cmdshell enabled - proxy account](https://vladdba.com/xp-cmdshell) *(Windows only)* [3] |
| 50 | Check Failed | Check failed for [database] |

---

**[1] - Priority escalates to 1 in system databases**
`db_owner role membership`, `Powerful database role membership`, and `Nested roles` are normally Priority 2, 2, and 3 respectively. If the finding is in `master` or `msdb`, all three are bumped to Priority 1 and ` in system database` is appended to the finding name.

**[2] - Priority depends on volume of failed login attempts**
Priority 1 if 10 or more failed login attempts are found across the current and previous error logs; Priority 2 if fewer than 10.

**[3] - xp_cmdshell findings are mutually exclusive**
Only one of the four xp_cmdshell findings fires per run depending on the service account and proxy account configuration: (a) Priority 1 - service account is admin/LocalSystem *and* a non-admin proxy exists; (b) Priority 1 - service account is admin/LocalSystem with no proxy, *or* the proxy account is an admin; (c) Priority 2 - no proxy and service account is not admin/LocalSystem; (d) Priority 3 - non-admin proxy exists and service account is not admin/LocalSystem.

**[4] - Agent job OS command findings escalate with the service account**
Priority 1 if the SQL Agent service account runs as LocalSystem/NT AUTHORITY\SYSTEM or is a member of the local Administrators group; Priority 2 otherwise.
