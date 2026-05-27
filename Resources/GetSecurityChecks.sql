/*
	Part of PSBlitz - https://github.com/VladDBA/PSBlitz
	License - https://github.com/VladDBA/PSBlitz/blob/main/LICENSE
    Script to run instance wide security check for misconfiguration that might be causing security issues. This is not an exhaustive list of all possible security misconfigurations, 
    but it covers some of the most common ones.
    
    Copyright (c) 2026 Vlad Drumea - <https://vladdba.com/>

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
*/
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
SET STATISTICS XML OFF;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

/*
Variables
*/
DECLARE @xp_cmdshell_init_state BIT,
        @crlf                   NVARCHAR(5) = NCHAR(13) + NCHAR(10),
        @sql                    NVARCHAR(MAX),
        /*using sys.dm_os_host_info would be simpler, but I want this to work on pre-2017 instances too*/
        @OS                     VARCHAR(10) = (SELECT CASE
                    WHEN LOWER(@@VERSION) LIKE '%linux%' THEN 'linux'
                    WHEN LOWER(@@VERSION) LIKE '%windows%' THEN 'windows'
                    ELSE 'huh?'
                  END),
        @instance_name          NVARCHAR(128),
        @version                TINYINT = ISNULL(CAST(SERVERPROPERTY('ProductMajorVersion') AS TINYINT), 0),
        @is_sysadmin            BIT = 0,
        @db_name                NVARCHAR(128),
        @quoted_db_name         NVARCHAR(130),
        @safe_for_ppc           BIT,
        @error_message           NVARCHAR(4000);

IF ( @OS = 'huh?' )
  BEGIN
      RAISERROR ('Cannot detect host OS',16,1) WITH NOWAIT;

      RETURN;
  END;

SELECT @is_sysadmin = IS_SRVROLEMEMBER(N'sysadmin');

SELECT @instance_name = ISNULL(CAST(SERVERPROPERTY('InstanceName') AS NVARCHAR(128)), @@SERVERNAME);

/*
Temp table setup
*/
/*Results*/
IF OBJECT_ID('tempdb..#Results') IS NOT NULL
  BEGIN
      DROP TABLE #Results;
  END;

CREATE TABLE #Results
  (
     [Id]               INT NOT NULL IDENTITY(1, 1) PRIMARY KEY CLUSTERED,
     [Priority]       TINYINT,
     [Findings Group] VARCHAR(60),
     [Finding]          NVARCHAR(200),
     [Database]       NVARCHAR(128),
     [Details]        NVARCHAR(2000),
     [Recommendation] NVARCHAR(1000),
     [URL]            NVARCHAR(200),
     [FindingHL] AS ISNULL(N'<a href=''' + [URL]
               + N''' target=''_blank''>' + [Finding] + N'</a>', [Finding])
  );

/*Password candidates*/
IF OBJECT_ID('tempdb..#PassCandidates') IS NOT NULL
  BEGIN
      DROP TABLE #PassCandidates;
  END;

CREATE TABLE #PassCandidates
  (
     [Candidates]      NVARCHAR(128),
     [CandidateSource] VARCHAR(100)
  );

INSERT INTO #PassCandidates
            ([Candidates],
             [CandidateSource])
VALUES      ('123456','Common password'),
            ('admin','Common password'),
            ('12345678','Common password'),
            ('123456789','Common password'),
            ('12345','Common password'),
            ('password','Common password'),
            ('Aa123456','Common password'),
            ('1234567890','Common password'),
            ('Pass@123','Common password'),
            ('admin123','Common password'),
            ('1234567','Common password'),
            ('123123','Common password'),
            ('111111','Common password'),
            ('12345678910','Common password'),
            ('P@ssw0rd','Common password'),
            ('Password','Common password'),
            ('Aa@123456','Common password'),
            ('admintelecom','Common password'),
            ('Admin@123','Common password'),
            ('112233','Common password'),
            ('','Blank password');

IF OBJECT_ID('tempdb..#FoundPasswords') IS NOT NULL
  BEGIN
      DROP TABLE #FoundPasswords;
  END;

CREATE TABLE #FoundPasswords
  (
     [LoginName]      NVARCHAR(128),
     [FoundPassword]  NVARCHAR(128),
     [PasswordSource] VARCHAR(100)
  );

IF OBJECT_ID('tempdb..#Databases') IS NOT NULL
  BEGIN
      DROP TABLE #Databases;
  END;

CREATE TABLE #Databases
  (
     [ID]     INT NOT NULL PRIMARY KEY CLUSTERED,
     [DBName] NVARCHAR(128),
     [SFPPC]  BIT NOT NULL DEFAULT 0
  );

/*
Instance configuration and objects
*/
/*checks we can only do on Windows*/
IF ( @OS = 'windows' )
  BEGIN
      DECLARE @has_proxy_account            BIT = 0,
              @proxy_is_admin               BIT = 0,
              @local_admins_group_name      NVARCHAR(256),
              @sql_svc                      NVARCHAR(256),
              @sql_svc_account              NVARCHAR(256),
              @sql_svc_is_admin             BIT = 0,
              @sql_svc_is_localsystem       BIT = 0,
              @sql_agent_svc                NVARCHAR(256),
              @sql_agent_svc_account        NVARCHAR(256),
              @sql_agent_svc_is_admin       BIT = 0,
              @sql_agent_svc_is_localsystem BIT = 0,
              @proxy_win_user               NVARCHAR(256) = NULL,
              @could_not_get_local_admins   BIT = 0;
      DECLARE @LocalAdmins TABLE
        (
           [ID]              INT NOT NULL IDENTITY(1, 1),
           [WinUserName]     NVARCHAR(1000),
           [WinUserType]     NVARCHAR(8),
           [Privilege]       NVARCHAR(9),
           [MappedLoginName] NVARCHAR(256),
           [PermissionPath]  NVARCHAR(256)
        );

      /*get sql server svc info */
      SELECT @sql_svc = [servicename],
             @sql_svc_account = [service_account],
             @sql_svc_is_localsystem = CASE
                                         WHEN LOWER([service_account]) IN ( N'localsystem', N'nt authority\system' ) THEN 1
                                         ELSE 0
                                       END
      FROM   [sys].[dm_server_services]
      WHERE  [servicename] LIKE N'SQL Server%'
             AND [servicename] NOT LIKE N'SQL Server%Agent%';

      SELECT @sql_agent_svc = [servicename],
             @sql_agent_svc_account = [service_account],
             @sql_agent_svc_is_localsystem = CASE
                                               WHEN LOWER([service_account]) IN ( N'localsystem', N'nt authority\system' ) THEN 1
                                               ELSE 0
                                             END
      FROM   [sys].[dm_server_services]
      WHERE  [servicename] LIKE N'SQL Server%Agent%';

      SELECT @xp_cmdshell_init_state = COUNT(1)
      FROM   sys.[configurations]
      WHERE  [name] = 'xp_cmdshell'
             AND [value_in_use] = 1;

      /*if xp_cmdshell is enabled, we're doing some more checks*/
      IF ( @xp_cmdshell_init_state = 1 AND @is_sysadmin = 1 )
        BEGIN
            SELECT @has_proxy_account = COUNT(1)
            FROM   sys.[credentials]
            WHERE  [name] = N'##xp_cmdshell_proxy_account##';

        /*xp_cmdshell is already enabled, might as well use it to get the list of local admins*/
            /*detect the administrators group based on SID so we don't have issues with different languages*/
            IF OBJECT_ID('tempdb..#LocalAdminGroupName') IS NOT NULL
              BEGIN
                  DROP TABLE #LocalAdminGroupName;
              END;

            CREATE TABLE #LocalAdminGroupName
              (
                 [GroupName] NVARCHAR(1000)
              );
            DECLARE @cmd NVARCHAR(300);
            SET @cmd = N'wmic group where "sid=''S-1-5-32-544''" get name /format:list'

            INSERT INTO #LocalAdminGroupName
            EXEC /**/xp_cmdshell/**/ @cmd/* added comments around command since some 
            firewalls block this string TL 20210221 */;

            SELECT @local_admins_group_name = REPLACE(REPLACE(RTRIM(LTRIM([GroupName])), NCHAR(13), N''), NCHAR(10), N'')
            FROM   #LocalAdminGroupName
            WHERE  [GroupName] LIKE N'%=%'; /*the relevant row has the format Name=Administrators, the rest is noise*/

            SELECT @local_admins_group_name = SUBSTRING(@local_admins_group_name, CHARINDEX(N'=', @local_admins_group_name)
                                                                                  + 1, LEN(@local_admins_group_name));
            /*fallback*/
            IF @local_admins_group_name IS NULL OR @local_admins_group_name = N''
              BEGIN
                  SET @local_admins_group_name = N'Administrators';
              END;
            
            SET @cmd = N'net localgroup ' + @local_admins_group_name;

            INSERT INTO @LocalAdmins
                        ([WinUserName])
            EXEC /**/xp_cmdshell/**/ @cmd /* added comments around command since some 
            firewalls block this string TL 20210221 */;

            /*clean results*/
            DELETE FROM @LocalAdmins
            WHERE  [ID] >= (SELECT MAX([ID]) - 2
                          FROM   @LocalAdmins);

            DELETE FROM @LocalAdmins
            WHERE  [ID] <= 6;

            /*if we're using a proxy account: is it a local admin? what's the win user name?*/
            IF ( @has_proxy_account = 1 )
              BEGIN
                  SELECT @proxy_is_admin = CASE
                                             WHEN [la].[WinUserName] IS NULL THEN 0
                                             ELSE 1
                                           END,
                         @proxy_win_user = [c].[credential_identity]
                  FROM   sys.[credentials] AS [c]
                         LEFT JOIN @LocalAdmins AS [la]
                                ON LOWER([c].[credential_identity]) = LOWER([la].[WinUserName])
                  WHERE  [c].[name] = N'##xp_cmdshell_proxy_account##';
              END;

            IF ( @sql_svc_is_localsystem = 0 )
              BEGIN
                  SELECT @sql_svc_is_admin = COUNT(1)
                  FROM   @LocalAdmins
                  WHERE  LOWER([WinUserName]) = LOWER(@sql_svc_account);
              END;

            IF ( @sql_agent_svc IS NOT NULL
                 AND @sql_agent_svc_is_localsystem = 0 )
              BEGIN
                  SELECT @sql_agent_svc_is_admin = COUNT(1)
                  FROM   @LocalAdmins
                  WHERE  LOWER([WinUserName]) = LOWER(@sql_agent_svc_account);
              END;

            /*at this point we can start writing xp_cmdshell findings to */
            SELECT @sql = N'SELECT ''Remote Code Execution'','
                          + CASE
                              WHEN 1 IN ( @sql_svc_is_admin, @sql_svc_is_localsystem )
                                   AND @has_proxy_account = 1
                                   AND @proxy_is_admin = 0 THEN N'1, N''xp_cmdshell enabled - sysadmin privileged OS access'', N''xp_cmdshell is enabled with the proxy account '
                                                                + QUOTENAME(@proxy_win_user, N'"')
                                                                + N' configured for non-sysadmin users, which does not appear to be a member of the local Administrators group.'
                                                                + @crlf
                                                                + N'However, sysadmin members always bypass the proxy and execute xp_cmdshell as the SQL Server service account '
                                                                + QUOTENAME(@sql_svc_account, N'"')
                                                                + N' which is '
                                                                + CASE
                                                                    WHEN @sql_svc_is_admin = 1 THEN N'a member of the local Administrators group - meaning any sysadmin can do anything on the host via xp_cmdshell.'
                                                                    WHEN @sql_svc_is_localsystem = 1 THEN N'the most powerful Windows account - meaning any sysadmin can do absolutely anything on the host via xp_cmdshell.'
                                                                  END
                                                                + @crlf
                                                                + N''',''See service account related findings for specific recommendations.'
                              WHEN
                            (
                              1 IN ( @sql_svc_is_admin, @sql_svc_is_localsystem )
                              AND @has_proxy_account = 0
                             )
                             OR @proxy_is_admin = 1 THEN N'1, N''xp_cmdshell enabled - privileged OS access'', N''xp_cmdshell is enabled and interacting with the OS as the '
                                                         + ISNULL(N'proxy account '+ QUOTENAME(@proxy_win_user, N'"'), N'SQL Server service account '+QUOTENAME(@sql_svc_account, N'"'))
                                                         + @crlf + N'which is '
                                                         + CASE
                                                             WHEN 1 IN ( @sql_svc_is_admin, @proxy_is_admin ) THEN N'a member of the local Administrators group - meaning that anyone who can use xp_cmdshell can do anything on the host.'
                                                             WHEN @sql_svc_is_localsystem = 1
                                                                  AND @has_proxy_account = 0 THEN 'the most powerful Windows account - meaning that anyone who can use xp_cmdshell can do absolutely anything on the host.'
                                                           END
                                                         + CASE
                                                             WHEN @has_proxy_account = 1 THEN N''',''Disable xp_cmdshell. If you really need it, remove '
                                                                                              + QUOTENAME(@proxy_win_user, N'"')
                                                                                              + N' from the local Administrators group,'
                                                                                              + @crlf
                                                                                              + 'limit OS level permissions and ensure thorough control and audit of the executed code.'
                                                             ELSE N''',''If you really need xp_cmdshell, configure it with a proxy account, limited OS level permissions and thorough control and audit of the executed code.'
                                                                  + @crlf
                                                                  + N'See service account related findings for specific recommendations.'
                                                           END
                              WHEN @has_proxy_account = 0
                                   AND @sql_svc_is_admin = 0
                                   AND @sql_svc_is_localsystem = 0 THEN N'2, N''xp_cmdshell enabled - SQL Server service account'', N''xp_cmdshell is enabled and interacting with the OS as the '
                                                                        + N'SQL Server service account '
                                                                        + QUOTENAME(@sql_svc_account, N'"') + @crlf
                                                                        + N'which does not appear to be a member of the local Administrators group.'
                                                                        + @crlf
                                                                        + N'Anyone who can use xp_cmdshell will interact with the same permissions as the service account.'
                                                                        + @crlf
                                                                        + N'This means they will also be able to read/modify/delete database and backup files belonging to this instance.'','
                                                                        + @crlf
                                                                        + N'''If you really need xp_cmdshell, configure it with a proxy account, limited OS level permissions and thorough control and audit of the executed code.'
                              WHEN @has_proxy_account = 1
                                   AND @proxy_is_admin = 0 THEN N'3, N''xp_cmdshell enabled - proxy account'', N''xp_cmdshell is enabled and interacting with the OS as the '
                                                                + N'proxy account '
                                                                + QUOTENAME(@proxy_win_user, N'"') + @crlf
                                                                + N' which does not appear to be a member of the local Administrators group.'
                                                                + @crlf
                                                                + N'Note: sysadmin members bypass the proxy account and always execute xp_cmdshell as the SQL Server service account '
                                                                + QUOTENAME(@sql_svc_account, N'"')
                                                                + N', which has read/write access to database and backup files.'','
                                                                + @crlf
                                                                + N'''You should still make sure that the proxy account has very limited permissions and file system access,'
                                                                + @crlf
                                                                + N'and you have full control and audit of the code that gets executed via xp_cmdshell.'
                            END
                          + N''',''https://vladdba.com/xp-cmdshell''';

            INSERT INTO #Results
                        ([Findings Group],
                         [Priority],
                         [Finding],
                         [Details],
                         [Recommendation],
                         [URL])
            EXEC sp_executesql
              @sql;
        END; /*xp_cmdshell enabled*/

      IF ( @xp_cmdshell_init_state = 0 )
        BEGIN
            /*if xp_cmdshell isn't enabled, we'll be a bit sneaky about seeing who is in the local admin group*/
            BEGIN TRANSACTION;

            IF NOT EXISTS (SELECT 1
                           FROM   sys.[server_principals]
                           WHERE  LOWER([name]) = N'builtin\administrators')
              BEGIN
                  BEGIN TRY
                      CREATE LOGIN [BUILTIN\Administrators] FROM WINDOWS WITH DEFAULT_DATABASE = [master];
                  END TRY
                  BEGIN CATCH
                      SET @could_not_get_local_admins = 1;
                      RAISERROR ('Could not create BUILTIN\Administrators login',1,1) WITH NOWAIT;
                  END CATCH;
              END;
           IF ( @could_not_get_local_admins = 0 )
             BEGIN
            INSERT @LocalAdmins
                   ([WinUserName],
                    [WinUserType],
                    [Privilege],
                    [MappedLoginName],
                    [PermissionPath])
            EXECUTE xp_logininfo
              'BUILTIN\Administrators',
              'members';
               END;

            ROLLBACK TRANSACTION;
        END; /*xp_cmdshell disabled*/
  /* at this point we have a list of members of the local admin group */
      /*Win users that are in the Administrators group (except svc accounts)*/
      INSERT INTO #Results
                  ([Priority],
                   [Findings Group],
                   [Finding],
                   [Details],
                   [Recommendation],
                   [URL])
      SELECT 1,
             'Excessive Privileges',
             N'Member of local Administrators group',
             N'The '
             + ISNULL(CAST([WinUserType] AS NVARCHAR(256))+ N' ', N'user/group ')
             + [WinUserName]
             + N' is a member of the Windows local Administrators group.'
             + @crlf
             + N'Members of the Windows local Administrators group on the SQL Server host can add themselves to the sysadmin role at any time, even if they are not currently in it.'
             + @crlf
             + N'This represents an uncontrolled privilege escalation path that bypasses SQL Server permission management entirely.',
             N'Assess which of these users/groups really need to be members of the Administrators group, remove any users/groups that shouldn''t be there',
             N'https://vladdba.com/AdministratorsToSysadmin'
      FROM   @LocalAdmins
      WHERE  [WinUserName] NOT IN ( @sql_svc_account, ISNULL(@sql_agent_svc_account, N'') );

      /*Service accounts are privileged accounts - admins*/
      INSERT INTO #Results
                  ([Priority],
                   [Findings Group],
                   [Finding],
                   [Details],
                   [Recommendation],
                   [URL])
      SELECT 1,
             'Excessive Privileges',
             N'SQL Server'
             + CASE
                 WHEN [WinUserName] = @sql_agent_svc_account THEN N' Agent'
                 ELSE N''
               END
             + ' service account in Administrators group',
             N'The ' + [WinUserName]
             + N' service account is a member of the local Administrators group.'
             + @crlf + N'Any login that can '
             + CASE
                 WHEN [WinUserName] = @sql_agent_svc_account THEN N'create and run jobs'
                 ELSE N'execute xp_cmdshell'
               END
             + N' can run commands with local administrator privileges on the host OS.',
             N'Remove the service account from the local Administrators group and adhere to the principle of least privilege.',
             N'https://vladdba.com/SQLServerSvcAccount'
      FROM   @LocalAdmins
      WHERE  [WinUserName] IN ( @sql_svc_account, ISNULL(@sql_agent_svc_account, N'') )
      UNION ALL
      SELECT 1,
             'Excessive Privileges',
             N'SQL Server Agent service using built-in elevated account',
             N'Running SQL Server Agent as '
             + @sql_agent_svc_account
             + N' means any Agent job step that runs OS commands executes with full system privileges on the host.'
             + @crlf
             + N'Anyone who can create or modify a job can take complete control of the host server.',
             N'Use SQL Server Configuration Manager to switch the service account to either the default one "NT Service\SQLAgent$'
             + @instance_name
             + N'" or to a dedicated local/domain account with a strong password and minimal privileges.',
             N'https://vladdba.com/SQLServerSvcAccount'
      WHERE  @sql_agent_svc_account IS NOT NULL
             AND @sql_agent_svc_is_localsystem = 1
      UNION ALL
      SELECT 1,
             'Excessive Privileges',
             N'SQL Server service using built-in elevated account',
             N'Running SQL Server as '
             + @sql_svc_account
             + N' means the service has full system privileges on the host.'
             + @crlf
             + N'Any user who can execute xp_cmdshell, either legitimately or as a result of privilege escalation to sysadmin, can run arbitrary OS commands with unrestricted system privileges.',
             N'Use SQL Server Configuration Manager to switch the service account to either the default one "NT Service\MSSQL$'
             + @instance_name
             + N'" or to a dedicated local/domain account with a strong password and minimal privileges.',
             N'https://vladdba.com/SQLServerSvcAccount'
      WHERE  @sql_svc_is_localsystem = 1;

      /*agent jobs running OS commands - priority bumped up when svc account is high privilege account*/
      IF ( @sql_agent_svc_account IS NOT NULL )
        BEGIN
            INSERT INTO #Results
                        ([Priority],
                         [Findings Group],
                         [Finding],
                         [Details],
                         [Recommendation],
                         [URL])
            SELECT CASE
                     WHEN 1 IN ( @sql_agent_svc_is_localsystem, @sql_agent_svc_is_admin ) THEN 1
                     ELSE 2
                   END                                           AS [Priority],
                   'Remote Code Execution'                       [Findings Group],
                   N'SQL Server Agent job executing OS commands' AS [Finding],
                   N'Agent job "' + [j].[name]
                   + N'" executes commands at the OS level via '
                   + [js].[subsystem] + N' in step "' + [js].[step_name]
                   + N'".'
                   + CASE
                       WHEN [js].[command] LIKE N'%.ps1%'
                             OR [js].[command] LIKE N'%.bat%'
                             OR [js].[command] LIKE N'%.py%' THEN + @crlf
                                                              + N'It also appears that the step executes at least one '
                                                              + CASE
                                                                  WHEN [js].[command] LIKE N'%.ps1%' THEN N'PowerShell'
                                                                  WHEN [js].[command] LIKE N'%.bat%' THEN N'Batch'
                                                                  WHEN [js].[command] LIKE N'%.py%' THEN N'Python'
                                                                END
                                                              + N' script.'
                       ELSE N''
                     END
                   + CASE
                       WHEN 1 IN ( @sql_agent_svc_is_localsystem, @sql_agent_svc_is_admin ) THEN + @crlf
                                                                                                 + N'Note:This finding gets a priority bump because your SQL Server Agent is '
                                                                                                 + CASE
                                                                                                     WHEN @sql_agent_svc_is_admin = 1 THEN N'a member of the local Administrators group.'
                                                                                                     ELSE @sql_agent_svc_account + N'.'
                                                                                                   END
                       ELSE N''
                     END                                         AS [Details],
                   +CASE
                      WHEN [js].[command] LIKE N'%.ps1%'
                            OR [js].[command] LIKE N'%.bat%'
                            OR [js].[command] LIKE N'%.py%' THEN N'Make sure you know exactly what those scripts do and that it''s nothing malicious.'
                                                             + @crlf
                                                             + N'If they''re required, limit who can make changes to them, and always have changes go through a review process.'
                      ELSE N'Make sure you know exactly what the code does and that it''s nothing malicious.'
                    END                                          AS [Recommendation],
                   NULL                                          AS [URL]
            FROM   msdb.dbo.[sysjobs] AS [j]
                   INNER JOIN msdb.dbo.[sysjobsteps] AS [js]
                           ON [j].[job_id] = [js].[job_id]
            WHERE  [js].[subsystem] IN ( N'PowerShell', N'CmdExec' )
                   AND [j].[name] <> N'syspolicy_purge_history';
        END;

      /*service accounts are members of the sysadmin role*/
      INSERT INTO #Results
                  ([Priority],
                   [Findings Group],
                   [Finding],
                   [Details],
                   [Recommendation],
                   [URL])
      SELECT 2                                                                                                                                              AS [Priority],
             'Excessive Privileges'                                                                                                                         AS [Findings Group],
             LEFT([servicename], CHARINDEX(N'(', [servicename])-2)
             + N' service account in sysadmin'                                                                                                              AS [Finding],
             N'The '
             + LEFT([servicename], CHARINDEX(N'(', [servicename])-2)
             + N' service account "' + [service_account]
             + N'" being a sysadmin creates a privilege escalation path.'
             + @crlf
             + N'If an attacker gains access to the service account they''ll be able to connect to the instance with full sysadmin permissions.'            AS [Details],
             N'Remove the service account from the sysadmin role and only grant the specific permissions and/or low privilege roles required for its tasks.'AS [Recommendation],
             NULL                                                                                                                                           AS [URL]
      FROM   sys.[dm_server_services]
      WHERE
      (
        [servicename] LIKE N'SQL Server Agent (%'
         OR [servicename] LIKE N'SQL Server (%'
       )
      AND IS_SRVROLEMEMBER(N'sysadmin', [service_account]) = 1;
  END; /*Windows */
/*sa state*/
SELECT @sql = N'SELECT '
              + CASE
                  WHEN [name] = N'sa' THEN N'1 AS [Priority], ''Excessive Privileges'' AS [Findings Group], N''sa login is enabled'' AS Finding,'
                                           + N'N''The sa login is a well-known target for brute-force attacks because its name is predictable and it is always a member of the sysadmin role.'
                                           + @crlf
                                           + N'An attacker with sa access can do anything on the instance, including reading all data, dropping databases, or executing OS commands via xp_cmdshell.'' AS [Details],'
                                           + N'''Disable it so it can no longer be used as a login for connections. '
                  ELSE N'2 AS [Priority], ''Insufficient Hardening'' AS [Findings Group], N''sa login is enabled and renamed'' AS Finding,'
                       + N'N''The sa login is identified by its fixed SID (0x01), not its name.'
                       + @crlf
                       + N'While renaming it obscures it, any login can query sys.sql_logins and find the account by SID.'' AS [Details],'
                       + N'''The more meaningful protection is disabling the account entirely.'
                END
              + @crlf
              + N'It can still be used internally as a database owner, to own and execute jobs, etc.'' AS [Recommendation], NULL;'
FROM   sys.[sql_logins]
WHERE  [sid] = 0x01
       AND [is_disabled] = 0;

INSERT INTO #Results
            ([Priority],
             [Findings Group],
             [Finding],
             [Details],
             [Recommendation],
             [URL])
EXEC sp_executesql
  @sql;

/*sysadmins members*/
INSERT INTO #Results
            ([Priority],
             [Findings Group],
             [Finding],
             [Details],
             [Recommendation],
             [URL])
SELECT 1                                                                                                                AS [Priority],
       'Excessive Privileges'                                                                                           AS [Findings Group],
       'sysadmin role member'                                                                                           AS [Finding],
       QUOTENAME([name])
       + N' is a member of the sysadmin fixed server role.'
       + @crlf
       + N'Members of the sysadmin fixed server role have unrestricted access to every object and operation on the instance.'
       + @crlf
       + 'There is no action they cannot perform, including dropping databases, modifying permissions, reading all data,'
       + @crlf
       + 'or executing OS-level commands through xp_cmdshell. The membership list should be kept as short as possible.' AS [Details],
       N'Review if ' + QUOTENAME([name])
       + ' actually needs sysadmin level privileges.'                                                                   AS [Recommendation],
       N'https://learn.microsoft.com/en-us/sql/relational-databases/security/authentication-access/server-level-roles?view=sql-server-ver17#fixed-server-level-roles'
FROM   master.sys.[syslogins]
WHERE  [sysadmin] = 1
       AND [sid] <> 0x01
       AND [denylogin] = 0
       AND [name] NOT LIKE N'NT SERVICE\%'
       AND [name] <> N'l_certSignSmDetach';

/*securityadmins*/
INSERT INTO #Results
            ([Priority],
             [Findings Group],
             [Finding],
             [Details],
             [Recommendation],
             [URL])
SELECT 1                                                                                                                AS [Priority],
       'Excessive Privileges'                                                                                           AS [Findings Group],
       'securityadmin role member'                                                                                      AS [Finding],
       QUOTENAME([name])
       + N' is a member of the securityadmin fixed server role.'
       + @crlf
       + N'Members of the securityadmin fixed server role manage logins and their properties.'
       + @crlf
       + N'They can GRANT, DENY, and REVOKE server-level permissions, they can also GRANT, DENY, and REVOKE database-level permissions if they have access to a database.'
       + @crlf
       + N'Additionally, securityadmin can reset passwords for SQL Server logins.'
       + @crlf
       + N'An attacker who compromises a securityadmin account can trivially escalate to full control of the instance.' AS [Details],
       N'Review if ' + QUOTENAME([name])
       + ' actually needs securityadmin level privileges.'
       + CASE
           WHEN @version >= 16 THEN + @crlf
                                    + N'Consider using the new fixed server role ##MS_LoginManager##.'
           ELSE N''
         END                                                                                                            AS [Recommendation],
       N'https://vladdba.com/PrivEscPermissions'
FROM   master.sys.[syslogins]
WHERE  [securityadmin] = 1
       AND [denylogin] = 0
       AND [name] NOT LIKE N'NT SERVICE\%'
       AND [name] <> N'l_certSignSmDetach';

/*dbcreator role members*/
INSERT INTO #Results
            ([Priority],
             [Findings Group],
             [Finding],
             [Details],
             [Recommendation],
             [URL])
SELECT 2,
       'Excessive Privileges',
       'dbcreator role member',
       QUOTENAME([name])
       + N' is a member of the dbcreator fixed server role.'
       + @crlf
       + N'Besides creating databases, members of the dbcreator fixed server role can alter, drop, and restore any database, including ones they do not own.'
       + @crlf
       + N'While this role doesn''t have as many privileges as sysadmin, it still represents a significant risk if misused or compromised.',
       N'Review if ' + QUOTENAME([name])
       + ' actually needs dbcreator level privileges.',
       N'https://learn.microsoft.com/en-us/sql/relational-databases/security/authentication-access/server-level-roles?view=sql-server-ver17#fixed-server-level-roles'
FROM   master.sys.[syslogins]
WHERE  [dbcreator] = 1
       AND [denylogin] = 0
       AND [name] NOT LIKE N'NT SERVICE\%'
       AND [name] <> N'l_certSignSmDetach';    

/*##MS_DatabaseManager## role member*/
IF @version >= 16
   BEGIN
       SET @sql = N'SELECT 2, ''Excessive Privileges'',
               ''##MS_DatabaseManager## role member'', QUOTENAME([name])'
               + N'+N'' is a member of the ##MS_DatabaseManager## fixed server role.'
               + @crlf
               + N'Besides creating databases, members of the ##MS_DatabaseManager## fixed server role can alter any database, including ones they do not own.'
               + @crlf 
               + N'Additionally, members of this role can potentially elevate their privileges under certain conditions.'','
               + @crlf
               + N'N''Review if '' + QUOTENAME([name]) + N'' actually needs ##MS_DatabaseManager## level privileges.'','
               + @crlf
               + N'N''https://learn.microsoft.com/en-us/sql/relational-databases/security/authentication-access/server-level-roles?view=sql-server-ver17#fixed-server-level-roles-introduced-in-sql-server-2022'''
               + @crlf 
               + N'FROM   master.sys.[syslogins]'
               + @crlf 
               + N'WHERE  [##MS_DatabaseManager##] = 1'
               + @crlf 
               + N'AND [denylogin] = 0'
               + @crlf 
               + N'AND [name] NOT LIKE N''NT SERVICE\%'''
               + @crlf 
               + N'AND [name] <> N''l_certSignSmDetach''';
       INSERT INTO #Results
                   ([Priority],
                    [Findings Group],
                    [Finding],
                    [Details],
                    [Recommendation],
                    [URL])
      EXEC sp_executesql   @sql;
   END;

/*CONTROL SERVER permission*/
INSERT INTO #Results
            ([Priority],
             [Findings Group],
             [Finding],
             [Details],
             [Recommendation],
             [URL])
SELECT 1,
       'Privilege Escalation Path',
       N'Login with CONTROL SERVER permission',
       QUOTENAME([pri].[name])
       + N' has CONTROL SERVER permission, which is almost as powerful as being a sysadmin role member.'
       + @crlf
       + N'With CONTROL SERVER, a login can impersonate any other login, including sysadmins, effectively giving them full control over the instance.',
       N'Review if ' + QUOTENAME([pri].name)
       + N' really needs CONTROL SERVER level privileges. If not, revoke the permission.',
       N'https://vladdba.com/PrivEscPermissions'
FROM   sys.[server_principals] AS [pri]
       INNER JOIN sys.[server_permissions] AS [perm]
               ON [perm].[grantee_principal_id] = [pri].[principal_id]
WHERE  [perm].[state] IN ( 'G', 'W' )
       AND [perm].[class] = 100
       AND [perm].[type] = 'CL'
       AND [pri].[type] IN ( 'R', 'S', 'U', 'G' );

/*IMPERSONATE ANY LOGIN*/
INSERT INTO #Results
            ([Priority],
             [Findings Group],
             [Finding],
             [Details],
             [Recommendation],
             [URL])
SELECT 1,
       'Privilege Escalation Path',
       N'Login with IMPERSONATE ANY LOGIN permission',
       QUOTENAME([pri].[name])
       + N' has IMPERSONATE ANY LOGIN permission, which allows them to impersonate any login on the instance.'
       + @crlf
       + N'This permission allows them to effectively escalate their privileges to those of any other login, including sysadmins, by impersonating them.',
       N'Review if ' + QUOTENAME([pri].name)
       + N' really needs IMPERSONATE ANY LOGIN level privileges. If not, revoke the permission.',
       N'https://vladdba.com/PrivEscPermissions'
FROM   sys.[server_principals] AS [pri]
       INNER JOIN sys.[server_permissions] AS [perm]
               ON [perm].[grantee_principal_id] = [pri].[principal_id]
WHERE  [perm].[state] IN ( 'G', 'W' )
       AND [perm].[class] = 100
       AND [perm].[type] = 'IAL'
       AND [pri].[type] IN ( 'R', 'S', 'U', 'G' );

/*IMPERSONATE PRIVILEGED LOGINS */
INSERT INTO #Results
            ([Priority],
             [Findings Group],
             [Finding],
             [Details],
             [Recommendation],
             [URL])
SELECT 1,
       'Privilege Escalation Path',
       N'Login with IMPERSONATE permission on privileged logins',
       QUOTENAME([pri].[name])
       + N' has IMPERSONATE permission on '
       + QUOTENAME([target].name) + N', which '
       + CASE
           WHEN [perm2].[permission_name] = N'CONNECT SQL'
                AND [l].[sysadmin] = 1 THEN N'is a member of the sysadmin role'
           WHEN [perm2].[permission_name] = N'CONNECT SQL'
                AND [l].[securityadmin] = 1 THEN N'is a member of the securityadmin role'
           ELSE N'has the ' + [perm2].[permission_name]
                + N' permission'
         END
       + N'.',
       N'Review if ' + QUOTENAME([pri].name)
       + N' really needs to impersonate '
       + QUOTENAME([target].name) + N'.' + @crlf
       + N'If not, revoke the permission.',
       N'https://vladdba.com/PrivEscPermissions'
FROM   sys.[server_principals] AS [pri]
       INNER JOIN sys.[server_permissions] AS [perm]
               ON [perm].[grantee_principal_id] = [pri].[principal_id]
       INNER JOIN sys.[server_principals] AS [target]
               ON [perm].[major_id] = [target].[principal_id]
       INNER JOIN sys.[syslogins] AS [l]
               ON [target].[sid] = [l].[sid]
       LEFT JOIN sys.[server_permissions] AS [perm2]
              ON [perm2].[grantee_principal_id] = [target].[principal_id]
WHERE  [perm].[state] IN ( 'G', 'W' )
       AND [perm].[class] = 101
       AND [perm].[type] = 'IM'
       AND [pri].[type] IN ( 'R', 'S', 'U', 'G' )
       AND
       (
         (
           [l].[sysadmin] = 1
            OR [l].[securityadmin] = 1
          )
          OR
         (
           [perm2].[type] IN ( 'IAL', 'CL' )
           AND [perm2].[state] IN ( 'G', 'W' )
          )
        )
;

/*Weak passwords*/
INSERT INTO #FoundPasswords
            ([LoginName],
             [FoundPassword],
             [PasswordSource])
SELECT [name],
       [name],
       'Password same as login name'
FROM   sys.[sql_logins]
WHERE  [is_disabled] = 0
       AND [name] NOT LIKE N'##%'
       AND PWDCOMPARE([name], [password_hash]) = 1;

INSERT INTO #FoundPasswords
            ([LoginName],
             [FoundPassword],
             [PasswordSource])
SELECT [l].[name],
       [c].[Candidates],
       [c].[CandidateSource]
FROM   sys.[sql_logins] AS [l]
       INNER JOIN #PassCandidates AS [c]
               ON PWDCOMPARE([c].[Candidates], [l].[password_hash]) = 1
WHERE  [l].[is_disabled] = 0
       AND [l].[name] NOT LIKE N'##%'
       AND NOT EXISTS (SELECT 1
                       FROM   #FoundPasswords
                       WHERE  [LoginName] = [l].[name]);

INSERT INTO #Results
            ([Priority],
             [Findings Group],
             [Finding],
             [Details],
             [Recommendation],
             [URL])
SELECT 1                AS [Priority],
       'Weak Passwords' AS [Findings Group],
       [PasswordSource]   AS [Finding],
       N'Login ' + QUOTENAME([LoginName])
       + N' has a weak password: '
       + QUOTENAME([FoundPassword], N'"') + N'.',
       N'Change the password to a strong, unique one that is not based on common words or patterns.',
       NULL
FROM   #FoundPasswords;

INSERT INTO #Results
            ([Priority],
             [Findings Group],
             [Finding],
             [Details],
             [Recommendation],
             [URL])
SELECT 2                                       AS [Priority],
       'Weak Passwords'                        AS [Findings Group],
       N'Login with potentially weak password' AS [Finding],
       N'Login ' + QUOTENAME([l].[name])
       + N' has a weak password that was not identified, but was set with CHECK_POLICY = OFF.'
       + @crlf
       + N'While the password itself could be strong, the fact that it''s not being checked against the password policy means it could be weak and you wouldn''t know it.',
       N'Update the login with a strong password and CHECK_POLICY = ON to ensure that the password is compliant with the password policy.',
       NULL
FROM   sys.[sql_logins] AS [l]
WHERE  [l].[is_disabled] = 0
       AND [l].[name] NOT LIKE N'##%'
       AND NOT EXISTS (SELECT 1
                       FROM   #FoundPasswords
                       WHERE  [LoginName] = [l].[name])
       AND [l].[is_policy_checked] = 0;

/*No audit for failed logins*/
DECLARE @audit_level INT = NULL;

EXEC master.dbo.xp_instance_regread
  @rootkey    = 'HKEY_LOCAL_MACHINE',
  @key        = 'SOFTWARE\Microsoft\MSSQLServer\MSSQLServer',
  @value_name = 'AuditLevel',
  @value      = @audit_level OUTPUT,
  @no_output  = 'no_output';

IF ISNULL(@audit_level, 0) < 2
  BEGIN
      INSERT INTO #Results
                  ([Priority],
                   [Findings Group],
                   [Finding],
                   [Details],
                   [Recommendation],
                   [URL])
      VALUES      (1,'Insufficient Auditing','Failed login auditing not enabled',N'Failed login attempts are not being audited.'
                                                                                 + @crlf
                                                                                 + N'This means that if an attacker is trying to brute-force passwords, there will be no record of these attempts in the SQL Server logs.',N'Enable auditing of failed login attempts to ensure that you have visibility into potential unauthorized access attempts.',NULL);
  END;

/*Failed logins in the current and previous log*/
IF @audit_level >= 2
  BEGIN
      IF OBJECT_ID('tempdb..#FailedLogins') IS NOT NULL
        BEGIN
            DROP TABLE #FailedLogins;
        END;

      CREATE TABLE #FailedLogins
        (
           [LogDate]     DATETIME,
           [ProcessInfo] NVARCHAR(50),
           [Text]      NVARCHAR(800)
        );

      /*previous log*/
      INSERT #FailedLogins
      EXEC sp_readerrorlog
        1,
        1,
        N'Login failed';

      /*current log*/
      INSERT #FailedLogins
      EXEC sp_readerrorlog
        0,
        1,
        N'Login failed';

      DECLARE @failed_login_counts BIGINT,
              @min_date            DATETIME,
              @max_date            DATETIME;

      SELECT @failed_login_counts = COUNT(1),
             @min_date = MIN([LogDate]),
             @max_date = MAX([LogDate])
      FROM   #FailedLogins;

      IF @failed_login_counts > 0
        BEGIN
            INSERT INTO #Results
                        ([Priority],
                         [Findings Group],
                         [Finding],
                         [Details],
                         [Recommendation],
                         [URL])
            SELECT CASE
                     WHEN @failed_login_counts < 10 THEN 2
                     ELSE 1
                   END                               AS [Priority],
                   'Failed Login Attempts'           AS [Findings Group],
                   N'Failed login attempts detected' AS [Finding],
                   CAST(@failed_login_counts AS NVARCHAR(20))
                   + N' failed login attempts were detected in the SQL Server error logs between '
                   + CONVERT(VARCHAR(25), @min_date, 120)
                   + N' and '
                   + CONVERT(VARCHAR(25), @max_date, 120) + N'.',
                   N'Review the failed login attempts to identify any potential unauthorized access attempts.'
                   + @crlf
                   + N'If you see a high number of failed logins, consider implementing additional security measures such as account lockout.',
                   NULL;
        END;
  END;

/*error logs count*/
DECLARE @error_log_count INT;

EXEC master.dbo.xp_instance_regread
  @rootkey    = N'HKEY_LOCAL_MACHINE',
  @key        = N'Software\Microsoft\MSSQLServer\MSSQLServer',
  @value_name = N'NumErrorLogs',
  @value      = @error_log_count OUTPUT,
  @no_output  = 'no_output';

IF (SELECT ISNULL(@error_log_count, 6)) < 20
  BEGIN
      INSERT INTO #Results
                  ([Priority],
                   [Findings Group],
                   [Finding],
                   [Details],
                   [Recommendation])
      SELECT 2,
             'Insufficient Auditing',
             N'Limited number of error logs retained',
             N'The instance is configured to retain only '
             + CAST(ISNULL(@error_log_count, 6) AS NVARCHAR(10))
             + N' error logs.' + @crlf
             + N'This limits your ability to review historical failed login attempts and other important events that may be relevant for security investigations.',
             N'Configure the instance to retain a minimum of 20 of error logs to allow for effective security monitoring and investigations.';
  END;

/*linked server connections*/
/*sa catch-all*/
INSERT INTO #Results
            ([Priority],
             [Findings Group],
             [Finding],
             [Details],
             [Recommendation],
             [URL])
SELECT 1                                                                                                                                                AS [Priority],
       'Linked Server Security'                                                                                                                                  AS [Findings Group],
       N'Linked server with [sa] as catch-all'                                                                                                          AS [Finding],
       N'Linked server ' + QUOTENAME([s].[name])
       + N' allows connections to "'
       + [s].[data_source]
       + N'" using [sa] as a catch-all.' + @crlf
       + N'This means that everyone on this instance ('
       + @@SERVERNAME + N') interacts with "'
       + [s].[data_source]
       + N'" using sysadmin privileges via the'
       + QUOTENAME([s].[name])
       + N' linked server connection.'                                                                                                                  AS [Details],
       N'Change the linked server security configuration to not use sa as a catch-all for logins that don''t have an explicit mapping.'
       + @crlf
       + N'Ideally, create specific mappings for each login that needs access and use a low-privilege account on the remote server for these mappings.' AS [Recommendation],
       N'https://vladdba.com/LinkedServers'                                                                                                             AS [URL]
FROM   sys.[servers] [s]
       INNER JOIN sys.[linked_logins] [l]
               ON [s].[server_id] = [l].[server_id]
WHERE  [s].[is_linked] = 1
       AND [l].[local_principal_id] = 0
       AND [l].[uses_self_credential] = 0
       AND [l].[remote_name] = N'sa'
/*non-sa catch-all*/
UNION ALL
SELECT 2,
       'Linked Server Security',
       N'Linked server with catch-all',
       N'Linked server ' + QUOTENAME([s].[name])
       + N' allows connections to "'
       + [s].[data_source] + N'" using '
       + QUOTENAME([l].[remote_name])
       + N' as a catch-all.' + @crlf
       + N'This means that everyone on this instance ('
       + @@SERVERNAME + N') interacts with "'
       + [s].[data_source]
       + N'" using the same privileges as '
       + QUOTENAME([l].[remote_name]) + N' via the '
       + QUOTENAME([s].[name])
       + N' linked server connection.',
       N'Change the linked server security configuration to not use '
       + QUOTENAME([s].[name])
       + N' as a catch-all for logins that don''t have an explicit mapping.'
       + @crlf
       + N'Ideally, create explicit mappings for each login that needs access and use a low-privilege account on the remote server for these mappings.',
       N'https://vladdba.com/LinkedServers'
FROM   sys.[servers] [s]
       INNER JOIN sys.[linked_logins] [l]
               ON [s].[server_id] = [l].[server_id]
WHERE  [s].[is_linked] = 1
       AND [l].[local_principal_id] = 0
       AND [l].[uses_self_credential] = 0
       AND ISNULL([l].[remote_name], N'') NOT IN ( N'sa', N'' )
/*use self catch-all*/
UNION ALL
SELECT 2,
       'Linked Server Security',
       N'Linked server using self-mapping',
       N'Linked server ' + QUOTENAME([s].[name])
       + N' allows connections to "'
       + [s].[data_source] + N'" using self-mapping.'
       + @crlf
       + N'This means that logins on this instance ('
       + @@SERVERNAME + N') can interact with "'
       + [s].[data_source]
       + N'" if they have a matching login on the remote instance.',
       N'Review if the self-mapping configuration for '
       + QUOTENAME([s].[name])
       + N' is appropriate for your environment.'
       + @crlf
       + N'If not, consider changing the linked server security configuration to use explicit mappings for each login that needs access and'
       + @crlf
       + N'use a low-privilege account on the remote server for these mappings.',
       N'https://vladdba.com/LinkedServers'
FROM   sys.[servers] [s]
       INNER JOIN sys.[linked_logins] [l]
               ON [s].[server_id] = [l].[server_id]
WHERE  [s].[is_linked] = 1
       AND [l].[local_principal_id] = 0
       AND [l].[uses_self_credential] = 1
       AND [l].[remote_name] IS NULL
/*without a security context*/
UNION ALL
SELECT 3,
       'Linked Server Security',
       N'Linked server without a security context',
       N'Linked server ' + QUOTENAME([s].[name])
       + N' allows connections to "'
       + [s].[data_source]
       + N' without a security context.' + @crlf
       + N'This means that logins on this instance ('
       + @@SERVERNAME
       + N') can''t do anything on the remote instance if they''re not explicitly mapped to a remote login.',
       N'This is likely a misconfiguration, as there''s usually no reason to have a linked server that doesn''t allow any level of access.',
       N'https://vladdba.com/LinkedServers'
FROM   sys.[servers] [s]
       INNER JOIN sys.[linked_logins] [l]
               ON [s].[server_id] = [l].[server_id]
WHERE  [s].[is_linked] = 1
       AND [l].[local_principal_id] = 0
       AND [l].[uses_self_credential] = 0
       AND [l].[remote_name] IS NULL
/*explicit mapping to remote login*/
UNION ALL
SELECT 3,
       'Linked Server Security',
       N'Linked server with explicit mapping to remote login',
       N'Linked server ' + QUOTENAME([s].[name])
       + N' allows connections to "'
       + [s].[data_source] + N'" for '
       + QUOTENAME([p].name)
       + N' using explicit mapping to remote login '
       + QUOTENAME([l].[remote_name]) + N'.' + @crlf
       + N'This means that ' + QUOTENAME([p].name)
       + N' can interact with "' + [s].[data_source]
       + N'" using the privileges of '
       + QUOTENAME([l].[remote_name]) + N' via the '
       + QUOTENAME([s].[name])
       + N' linked server connection.',
       N'Review if the remote login '
       + QUOTENAME([l].[remote_name])
       + N' respects the principle of least privilege for the tasks that '
       + QUOTENAME([p].name)
       + N' needs to perform on the remote server.',
       N'https://vladdba.com/LinkedServers'
FROM   sys.[servers] [s]
       INNER JOIN sys.[linked_logins] [l]
               ON [s].[server_id] = [l].[server_id]
       INNER JOIN sys.[server_principals] [p]
               ON [l].[local_principal_id] = [p].[principal_id]
WHERE  [s].[is_linked] = 1
       AND [l].[local_principal_id] <> 0
       AND [l].[uses_self_credential] = 0
       AND [l].[remote_name] IS NOT NULL
/*using impersonation*/
UNION ALL
SELECT 3,
       'Linked Server Security',
       N'Linked server using impersonation',
       N'Linked server ' + QUOTENAME([s].[name])
       + N' allows connections to "'
       + [s].[data_source] + N'" for '
       + QUOTENAME([p].name)
       + N' using impersonation.' + @crlf
       + N'This means that ' + QUOTENAME([p].name)
       + N' can interact with "' + [s].[data_source]
       + N'" using their own privileges on the remote server via the '
       + QUOTENAME([s].[name])
       + N' linked server connection.',
       N'Review if the impersonation configuration for '
       + QUOTENAME([s].[name])
       + N' is appropriate for your environment'
       + @crlf + N'and if ' + QUOTENAME([p].name)
       + N' has the appropriate level of privileges on the remote server.',
       N'https://vladdba.com/LinkedServers'
FROM   sys.[servers] [s]
       INNER JOIN sys.[linked_logins] [l]
               ON [s].[server_id] = [l].[server_id]
       INNER JOIN sys.[server_principals] [p]
               ON [l].[local_principal_id] = [p].[principal_id]
WHERE  [s].[is_linked] = 1
       AND [l].[local_principal_id] <> 0
       AND [l].[uses_self_credential] = 1
       AND [l].[remote_name] IS NULL;

/*Database mail XPs*/
INSERT INTO #Results
            ([Priority],
             [Findings Group],
             [Finding],
             [Details],
             [Recommendation],
             [URL])
SELECT 2,
       'Attack Surface',
       N'Database Mail XPs enabled',
       N'Database Mail extended stored procedures are enabled. This allows SQL Server to send emails, which can be used for alerts, notifications, or by applications.'
       + @crlf
       + N'While this is a common requirement, it can be abused by attackers to exfiltrate data, send phishing emails, or initiate denial of service attacks if they gain access to the instance.',
       N'If you don''t need Database Mail functionality, disable the Database Mail XPs configuration option.'
       + @crlf
       + N'If you do need it, make sure to have proper monitoring in place for any emails sent from the instance and review the Database Mail configuration to ensure it''s not being abused.',
       NULL
FROM   sys.[configurations]
WHERE  [name] = N'Database Mail XPs'
       AND [value_in_use] = 1;

/*clr enabled*/
INSERT INTO #Results
            ([Priority],
             [Findings Group],
             [Finding],
             [Details],
             [Recommendation],
             [URL])
SELECT 2,
       'Remote Code Execution',
       N'CLR enabled',
       N'CLR integration allows .NET assemblies to run inside SQL Server. Even assemblies marked SAFE have had historical vulnerabilities allowing external resource access,'
       + @crlf
       + N'and UNSAFE assemblies can call unmanaged code with SQL Server process privileges.'
       + @crlf
       + N'On SQL Server 2017+, clr strict security should be used instead of relying on SAFE marking.',
       N'If you don''t need CLR integration, disable the CLR enabled configuration option.'
       + @crlf
       + N'If you do need it, make sure to use CLR strict security, follow Microsoft''s recommendation about CLR assembly security,'
       + @crlf
       + N'and have proper monitoring in place for any unusual activity related to CLR assemblies.',
       N'https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/clr-enabled-server-configuration-option?view=sql-server-ver16'
FROM   sys.[configurations]
WHERE  [name] = N'clr enabled'
       AND [value_in_use] = 1
       AND NOT EXISTS (SELECT 1
                       FROM   sys.[databases]
                       WHERE  [name] = 'SSISDB');

/*OLE automation procedures*/
INSERT INTO #Results
            ([Priority],
             [Findings Group],
             [Finding],
             [Details],
             [Recommendation],
             [URL])
SELECT 2,
       'Remote Code Execution',
       N'OLE Automation Procedures enabled',
       N'OLE Automation allows SQL Server code to create and interact with COM objects, which can be used to interact with the file system,'
       + @crlf
       + N'registry, or network in ways similar to xp_cmdshell.',
       N'If not actively needed, it should be disabled to minimize the OS attack surface.',
       N'https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/ole-automation-procedures-server-configuration-option?view=sql-server-ver17'
FROM   master.sys.[configurations]
WHERE  [name] = N'Ole Automation Procedures'
       AND [value_in_use] = 1;

/*ad hoc distributed queries*/
INSERT INTO #Results
            ([Priority],
             [Findings Group],
             [Finding],
             [Details],
             [Recommendation],
             [URL])
SELECT 2,
       'Attack Surface',
       N'Ad Hoc Distributed Queries enabled',
       N'OPENROWSET and OPENDATASOURCE with ad hoc distributed queries enabled allow SQL Server to read from external data sources, including local files.'
       + @crlf
       + N'In a SQL injection scenario, an attacker could leverage this to read arbitrary files accessible to the SQL Server service account.',
       N'If you don''t need ad hoc distributed query functionality, disable the Ad Hoc Distributed Queries configuration option.',
       N'https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/ad-hoc-distributed-queries-server-configuration-option?view=sql-server-ver17'
FROM   sys.[configurations]
WHERE  [name] = N'Ad Hoc Distributed Queries'
       AND [value_in_use] = 1;

/*cross-db ownership chaining*/
INSERT INTO #Results
            ([Priority],
             [Findings Group],
             [Finding],
             [Details],
             [Recommendation],
             [URL])
SELECT 2,
       'Privilege Escalation Path',
       N'Cross-database ownership chaining enabled',
       N'Cross-database ownership chaining allows stored procedures and views in one database to access objects'
       + @crlf
       + N'in another database as long as the objects are owned by the same login, without needing explicit permissions.'
       + @crlf
       + N'While this can be useful for certain applications, it can also lead to users getting access to data they should not normally be able to access.',
       N'Review if cross-database ownership chaining is necessary for your environment.'
       + @crlf
       + N'If not, disable it to prevent unintended access across databases.',
       NULL
FROM   sys.[configurations]
WHERE  [name] = 'cross db ownership chaining'
       AND [value_in_use] = 1;

/*startup stored procedures */
INSERT INTO #Results
            ([Priority],
             [Findings Group],
             [Finding],
             [Details],
             [Recommendation],
             [URL])
SELECT 2,
       'Attack Surface',
       N'Startup stored procedure',
       N'Stored procedure [master].'
       + QUOTENAME(SCHEMA_NAME([schema_id])) + N'.'
       + QUOTENAME([name])
       + N' is configured to run automatically at SQL Server startup.'
       + @crlf
       + N'Startup stored procedures run with sysadmin privileges.'
       + @crlf
       + N'If an attacker can modify the code of a startup stored procedure, they can execute arbitrary code with those privileges every time SQL Server starts.'
       + @crlf
       + N'This makes startup stored procedures a high-value target for attackers looking to maintain persistence on an instance.',
       +N'Review the code of any stored procedures configured to run at startup and ensure they are secure and necessary.',
       N'https://vladdba.com/StartupProcs'
FROM   sys.[procedures]
WHERE  [is_auto_executed] = 1;

/*agent jobs running on startup*/
INSERT INTO #Results
            ([Priority],
             [Findings Group],
             [Finding],
             [Details],
             [Recommendation],
             [URL])
SELECT 2                            AS [Priority],
       'Attack Surface'     AS [Findings Group],
       N'Agent job runs at startup' AS [Finding],
       N'Agent job "' + [j].[name]
       + N'" is configured to run automatically at SQL Server Agent startup.'
       + @crlf
       + N'If a malicious job step is introduced, it runs with the Agent service account''s privileges'
       + @crlf
       + N'without requiring any explicit invocation, making it a viable persistence mechanism.',
       N'Review any agent jobs configured to run at startup and ensure they are secure and necessary.',
       NULL
FROM   msdb.dbo.[sysschedules] [s]
       JOIN msdb.dbo.[sysjobschedules] [js]
         ON [s].[schedule_id] = [js].[schedule_id]
       JOIN msdb.dbo.[sysjobs] [j]
         ON [js].[job_id] = [j].[job_id]
WHERE  [s].[freq_type] = 64
       AND [s].[enabled] = 1
       AND [j].[enabled] = 1;

/*remote access enabled*/
INSERT INTO #Results
            ([Priority],
             [Findings Group],
             [Finding],
             [Details],
             [Recommendation],
             [URL])
SELECT 2,
       'Attack Surface',
       N'Remote access enabled',
       N'The remote access configuration allows stored procedure calls between SQL Server instances.'
       + @crlf
       + N'This is an older feature that is generally unnecessary in modern architectures.'
       + @crlf
       + 'Leaving it enabled when not needed increases the attack surface for lateral movement between servers.',
       N'If you don''t need remote access functionality, disable the Remote Access configuration option.',
       N'https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/configure-the-remote-access-server-configuration-option'
FROM   sys.[configurations]
WHERE  [name] = N'remote access'
       AND [value_in_use] = 1;

/*trustworthy database with sysadmin owner*/
INSERT INTO #Results
            ([Priority],
             [Findings Group],
             [Finding],
             [Database],
             [Details],
             [Recommendation],
             [URL])
SELECT 1,
       'Privilege Escalation Path',
       N'Trustworthy database with sysadmin owner',
       [d].[name],
       N'Database ' + QUOTENAME([d].[name])
       + N' has the TRUSTWORTHY property enabled and is owned by '
       + QUOTENAME([l].[name])
       + ' who is a member of the sysadmin role.'
       + @crlf
       + N'If an attacker can create or modify objects in this database, they can leverage the TRUSTWORTHY setting to escalate their privileges to sysadmin.',
       N'Review if the TRUSTWORTHY property needs to be enabled for '
       + QUOTENAME([d].[name]) + N'.' + @crlf
       + N'Consider changing the database owner to a non-sysadmin, ideally disabled, login, and ensure that only trusted principals have access to modify objects in the database.',
       N'https://vladdba.com/TrustworthySysadmin'
FROM   sys.[databases] [d]
       INNER JOIN sys.[syslogins] [l]
               ON [d].[owner_sid] = [l].[sid]
WHERE  [d].[database_id] > 4
       AND [d].[is_trustworthy_on] = 1
       AND [l].[sysadmin] = 1;

/*trustworthy database*/
INSERT INTO #Results
            ([Priority],
             [Findings Group],
             [Finding],
             [Database],
             [Details],
             [Recommendation],
             [URL])
SELECT 2,
       'Privilege Escalation Path',
       N'Trustworthy database with non-sysadmin owner',
       [d].[name],
       N'Database ' + QUOTENAME([d].[name])
       + N' has the TRUSTWORTHY property enabled.'
       + @crlf
       + N'Even when the database owner is not a sysadmin, TRUSTWORTHY ON allows code running in the database to be trusted in a broader server context.'
       + @crlf
       + N'This loosens the default security boundary between the database and the instance.',
       N'Review if the TRUSTWORTHY property needs to be enabled for '
       + QUOTENAME([d].[name]) + N'.',
       N'https://vladdba.com/TrustworthySysadmin'
FROM   sys.[databases] AS [d]
       INNER JOIN sys.[syslogins] [l]
               ON [d].[owner_sid] = [l].[sid]
WHERE  [d].[database_id] > 4
       AND [d].[is_trustworthy_on] = 1
       AND [l].[sysadmin] <> 1;

/*database owner is sysadmin role member*/
INSERT INTO #Results
            ([Priority],
             [Findings Group],
             [Finding],
             [Database],
             [Details],
             [Recommendation],
             [URL])
SELECT 2,
       'Privilege Escalation Path',
       N'Database owned by sysadmin',
       [d].[name],
       N'When a database is owned by a sysadmin login, db_owner members can impersonate the database owner within the database,'
       + @crlf
       + N'and depending on TRUSTWORTHY state, this can extend to server-level sysadmin privileges.',
       N'Consider changing the database owner to a non-sysadmin, ideally disabled, login, and ensure that only trusted principals have access to modify objects in the database.',
       N'https://vladdba.com/TrustworthySysadmin'
FROM   sys.[databases] AS [d]
       INNER JOIN sys.[syslogins] [l]
               ON [d].[owner_sid] = [l].[sid]
WHERE  [d].[database_id] > 4
       AND [d].[is_trustworthy_on] = 0
       AND [l].[sysadmin] = 1;

/*permissions granted to public server role*/
INSERT INTO #Results
            ([Priority],
             [Findings Group],
             [Finding],
             [Details],
             [Recommendation],
             [URL])
SELECT 2,
       'Excessive Privileges',
       N'Permission granted to public server role',
       N'The ' + [perm].[permission_name]
       + N' permission is granted to the public server role.'
       + @crlf
       + N'Since every login is a member of the public role, this permission is effectively granted to all logins on the instance.',
       N'Revoke the ' + [perm].[permission_name]
       + N' permission from the public server role.'
       + @crlf
       + N'If it''s necessary for some logins to have this permission, consider creating a custom server role,'
       + @crlf
       + N'granting the permission to that role, and then adding only the necessary logins to it.',
       NULL
FROM   sys.[server_permissions] AS [perm]
       INNER JOIN sys.[server_principals] AS [pri]
               ON [perm].[grantee_principal_id] = [pri].[principal_id]
WHERE  [pri].[name] = N'public'
       AND [perm].[type] NOT IN ( 'VWDB', 'CO', 'IAL', 'CL' )

/*high privilege permissions granted to public server role*/
INSERT INTO #Results
            ([Priority],
             [Findings Group],
             [Finding],
             [Details],
             [Recommendation],
             [URL])
SELECT 1,
       'Privilege Escalation Path',
       N'High-privilege permission granted to public server role',
       N'The ' + [perm].[permission_name]
       + N' permission is granted to the public server role, which is a high-privilege permission.'
       + @crlf
       + N'This permission can be leveraged to perform a privilege escalation to sysadmin.'
       + @crlf
       + N'Since every login is a member of the public role, this permission is effectively granted to all logins on the instance.',
       N'Revoke the ' + [perm].[permission_name]
       + N' permission from the public server role immediately.',
       N'https://vladdba.com/PrivEscPermissions'
FROM   sys.[server_permissions] AS [perm]
       INNER JOIN sys.[server_principals] AS [pri]
               ON [perm].[grantee_principal_id] = [pri].[principal_id]
WHERE  [pri].[name] = N'public'
       AND [perm].[type] IN ( 'IAL', 'CL' )

/*database level checks*/
INSERT INTO #Databases
            ([ID],
             [DBName])
SELECT [d].[database_id],
       [d].[name]
FROM   sys.[databases] [d]
       CROSS APPLY fn_my_permissions([d].name, 'DATABASE') AS [p]
WHERE  [p].[permission_name] = 'SELECT'
       AND LOWER([d].[name]) NOT IN ( N'dbatools', N'dbadmin', N'dbmaintenance', N'gcloud_cloudsqladmin',
                                      N'rdsadmin', N'rdsadmininternal', N'ssisdb', N'tempdb')
       AND [d].[state] = 0;

UPDATE #Databases
SET    [SFPPC] = 1
WHERE  [ID] IN (SELECT [database_id]
              FROM   sys.[databases]
              WHERE  [database_id] > 4
                     AND [state] = 0
                     AND [source_database_id] IS NULL /* exclude snapshot databases */
                     AND [name] NOT IN (SELECT [adc].[database_name]
                                        FROM   sys.[availability_replicas] AS [ar]
                                               JOIN sys.[availability_databases_cluster] [adc]
                                                 ON [adc].[group_id] = [ar].[group_id]
                                        WHERE  [ar].[secondary_role_allow_connections] = 0
                                               AND [ar].[replica_server_name] = @@SERVERNAME
                                               AND sys.fn_hadr_is_primary_replica([adc].[database_name]) = 0));

DECLARE db_cursor CURSOR LOCAL STATIC READ_ONLY FORWARD_ONLY FOR
  SELECT [SFPPC],
         [DBName]
  FROM   #Databases;

OPEN db_cursor;

FETCH NEXT FROM db_cursor INTO @safe_for_ppc, @db_name;

WHILE @@FETCH_STATUS = 0
  BEGIN
         SET @quoted_db_name = QUOTENAME(@db_name);
      /*db_owner role membership*/
      SELECT @sql = N'USE ' + @quoted_db_name + N';' + @crlf
                    + N'SELECT 2, ''Excessive Privileges'', N''db_owner role membership'','
                    + @crlf + N'DB_NAME(), N''In ' + @quoted_db_name
                    + N', the user ''+QUOTENAME(u.[name]) +N'' is a member of the db_owner role.'
                    + @crlf
                    + N'The db_owner role grants complete control over the database, including the ability to change permissions for other users,'
                    + @crlf
                    + N'drop any object, and in some configurations execute commands as the database owner.'','
                    + @crlf
                    + N'N''Review if db_owner role membership is required for this user. If not, remove them from the db_owner role.'''
                    + @crlf + N'FROM sys.database_role_members m'
                    + @crlf
                    + N'INNER JOIN sys.database_principals u ON m.member_principal_id = u.principal_id'
                    + @crlf
                    + N'INNER JOIN sys.database_principals r ON m.role_principal_id = r.principal_id'
                    + @crlf
                    + N'WHERE u.name NOT IN (N''dbo'',N''RSExecRole'') AND u.[type] <> ''R'' AND r.name = ''db_owner'' OPTION (RECOMPILE);';
      BEGIN TRY
      INSERT INTO #Results
                  ([Priority],
                   [Findings Group],
                   [Finding],
                   [Database],
                   [Details],
                   [Recommendation])
      EXEC sp_executesql
        @sql;
      END TRY
        BEGIN CATCH
            SET @error_message = ERROR_MESSAGE();
            INSERT INTO #Results
                        ([Priority],
                         [Findings Group],
                         [Finding],
                         [Database],
                         [Details],
                         [Recommendation])
            VALUES (50,
                    'Check Failed',
                    N'db_owner role membership - failed',
                    @db_name,
                    @error_message,
                    N'Review the error message for details on what went wrong and address any issues with the dynamic SQL execution.');
        END CATCH;

      /*db_accessadmin ,db_securityadmin ,db_ddladmin role membership*/
      SELECT @sql = N'USE ' + @quoted_db_name + N';' + @crlf
                    + N'SELECT 2, ''Excessive Privileges'', N''Powerful database role membership'','
                    + @crlf + N'DB_NAME(), N''In ' + @quoted_db_name
                    + N', the user ''+QUOTENAME(u.[name]) +N'' is a member of the ''+QUOTENAME(r.[name]) +N'' role.'
                    + @crlf
                    + N'db_accessadmin, db_securityadmin, and db_ddladmin roles grant elevated abilities including managing user access, modifying permissions, and altering schema.'
                    + @crlf
                    + N'These roles are often assigned unnecessarily and can be used to create backdoor accounts or escalate permissions within the database.'','
                    + @crlf
                    + N'N''Review if membership in the ''+QUOTENAME(r.[name]) +N'' role is required for ''+QUOTENAME(u.[name]) +N''. If not, remove them from these roles.'''
                    + @crlf + N'FROM sys.database_role_members m'
                    + @crlf
                    + N'INNER JOIN sys.database_principals u ON m.member_principal_id = u.principal_id'
                    + @crlf
                    + N'INNER JOIN sys.database_principals r ON m.role_principal_id = r.principal_id'
                    + @crlf
                    + N'WHERE u.name NOT IN (N''dbo'',N''RSExecRole'') AND u.[type] <> ''R'' AND r.name IN (N''db_accessadmin'' , N''db_securityadmin'' , N''db_ddladmin'') OPTION (RECOMPILE);';
         BEGIN TRY
      INSERT INTO #Results
                  ([Priority],
                   [Findings Group],
                   [Finding],
                   [Database],
                   [Details],
                   [Recommendation])
      EXEC sp_executesql
        @sql;
        END TRY
        BEGIN CATCH
            SET @error_message = ERROR_MESSAGE();
            INSERT INTO #Results
                        ([Priority],
                         [Findings Group],
                         [Finding],
                         [Database],
                         [Details],
                         [Recommendation])
            VALUES (50,
                    'Check Failed',
                    N'Powerful database role membership - failed',
                    @db_name,
                    @error_message,
                    N'Review the error message for details on what went wrong and address any issues with the dynamic SQL execution.');
        END CATCH;

      /*nested roles*/
      SELECT @sql = N'USE ' + @quoted_db_name + N';' + @crlf
                    + N'SELECT 3, ''Excessive Privileges'', N''Nested roles'','
                    + @crlf + N'DB_NAME(), N''In ' + @quoted_db_name
                    + N', the role ''+QUOTENAME(u.[name]) +N'' is a member of the ''+QUOTENAME(r.[name]) +N'' role.'
                    + @crlf
                    + N'Nested role memberships can lead to unintended privilege escalation if not properly managed, as permissions granted to a role are inherited by all its members.'','
                    + @crlf
                    + N'''Remove ''+QUOTENAME(u.[name]) +N'' from ''+QUOTENAME(r.[name]) +N'' and explicitly grant it the required permissions.'''
                    + @crlf + N'FROM sys.database_role_members m'
                    + @crlf
                    + N'INNER JOIN sys.database_principals u ON m.member_principal_id = u.principal_id'
                    + @crlf
                    + N'INNER JOIN sys.database_principals r ON m.role_principal_id = r.principal_id'
                    + @crlf
                    + N'WHERE u.name NOT IN (''dbo'',''RSExecRole'') AND u.[type] = ''R'''
                    + @crlf
                    + N'AND (r.principal_id >= 16384 AND r.principal_id <= 16393)  OPTION (RECOMPILE);';
      BEGIN TRY
      INSERT INTO #Results
                  ([Priority],
                   [Findings Group],
                   [Finding],
                   [Database],
                   [Details],
                   [Recommendation])
      EXEC sp_executesql
        @sql;
        END TRY
        BEGIN CATCH
            SET @error_message = ERROR_MESSAGE();
            INSERT INTO #Results
                        ([Priority],
                         [Findings Group],
                         [Finding],
                         [Database],
                         [Details],
                         [Recommendation])
            VALUES (50,
                    'Check Failed',
                    N'Nested roles - failed',
                    @db_name,
                    @error_message,
                    N'Review the error message for details on what went wrong and address any issues with the dynamic SQL execution.');
        END CATCH;

      /*explicit permissions granted to public*/
      IF ( @safe_for_ppc = 1
           AND @version >= 12 )
        BEGIN
            SELECT @sql = CAST(N'USE ' + @quoted_db_name + N';' AS NVARCHAR(MAX)) + @crlf
                          + N'SELECT 2, ''Excessive Privileges'','
                          + @crlf
                          + N'N''Permission granted to public database role'','
                          + @crlf + N'DB_NAME(), N''In ' + @quoted_db_name
                          + N' the [public] role has been granted the "'' + per.permission_name + N''" permission on the object ['''
                          + N'+ CASE per.class' + @crlf
                          + N'WHEN 0 THEN db_name()' + @crlf
                          + N'WHEN 3 THEN schema_name(major_id)'
                          + @crlf + N'WHEN 4 THEN printarget.NAME' + @crlf
                          + N'WHEN 5 THEN asm.NAME' + @crlf
                          + N'WHEN 6 THEN type_name(major_id)' + @crlf
                          + N'WHEN 10 THEN xmlsc.NAME' + @crlf
                          + N'WHEN 15 THEN msgt.NAME COLLATE DATABASE_DEFAULT'
                          + @crlf
                          + N'WHEN 16 THEN svcc.NAME COLLATE DATABASE_DEFAULT'
                          + @crlf
                          + N'WHEN 17 THEN svcs.NAME COLLATE DATABASE_DEFAULT'
                          + @crlf
                          + N'WHEN 18 THEN rsb.NAME COLLATE DATABASE_DEFAULT'
                          + @crlf
                          + N'WHEN 19 THEN rts.NAME COLLATE DATABASE_DEFAULT'
                          + @crlf + N'WHEN 23 THEN ftc.NAME' + @crlf
                          + N'WHEN 24 THEN sym.NAME' + @crlf
                          + N'WHEN 25 THEN crt.NAME' + @crlf
                          + N'WHEN 26 THEN asym.NAME' + @crlf
                          + N'END + '']' + @crlf
                          + N'Permissions granted to the public fixed database role apply to all users of the database, including any potential attackers who gain access'','
                          + @crlf
                          + N'N''Revoke the "'' + per.permission_name + ''" permission from the public database role and grant it only to specific users, groups, or roles that require it.'''
                          + @crlf
                          + N'FROM sys.database_permissions AS per'
                          + @crlf
                          + N'LEFT JOIN sys.database_principals AS prin ON per.grantee_principal_id = prin.principal_id'
                          + @crlf
                          + N'LEFT JOIN sys.assemblies AS asm ON per.major_id = asm.assembly_id'
                          + @crlf
                          + N'LEFT JOIN sys.xml_schema_collections AS xmlsc ON per.major_id = xmlsc.xml_collection_id'
                          + @crlf
                          + N'LEFT JOIN sys.service_message_types AS msgt ON per.major_id = msgt.message_type_id'
                          + @crlf
                          + N'LEFT JOIN sys.service_contracts AS svcc ON per.major_id = svcc.service_contract_id'
                          + @crlf
                          + N'LEFT JOIN sys.services AS svcs ON per.major_id = svcs.service_id'
                          + @crlf
                          + N'LEFT JOIN sys.remote_service_bindings AS rsb ON per.major_id = rsb.remote_service_binding_id'
                          + @crlf
                          + N'LEFT JOIN sys.routes AS rts ON per.major_id = rts.route_id'
                          + @crlf
                          + N'LEFT JOIN sys.database_principals AS printarget ON per.major_id = printarget.principal_id'
                          + @crlf
                          + N'LEFT JOIN sys.symmetric_keys AS sym ON per.major_id = sym.symmetric_key_id'
                          + @crlf
                          + N'LEFT JOIN sys.asymmetric_keys AS asym ON per.major_id = asym.asymmetric_key_id'
                          + @crlf
                          + N'LEFT JOIN sys.certificates AS crt ON per.major_id = crt.certificate_id'
                          + @crlf
                          + N'LEFT JOIN sys.fulltext_catalogs AS ftc ON per.major_id = ftc.fulltext_catalog_id'
                          + @crlf
                          + N'WHERE per.grantee_principal_id = DATABASE_PRINCIPAL_ID(''public'')'
                          + @crlf
                          + N'AND class <> 1 /* Object or Columns (class = 1) are handled by VA1054 and have different remediation syntax */'
                          + @crlf + N'AND [state] IN (''G'',''W'')'
                          + @crlf + N'AND NOT (' + @crlf + N'  per.class = 0'
                          + @crlf + N'AND prin.NAME = ''public''' + @crlf
                          + N'AND per.major_id = 0' + @crlf
                          + N'AND per.minor_id = 0' + @crlf
                          + N'AND permission_name IN (N''VIEW ANY COLUMN ENCRYPTION KEY DEFINITION'''
                          + @crlf
                          + N',N''VIEW ANY COLUMN MASTER KEY DEFINITION''));';
            BEGIN TRY
            INSERT INTO #Results
                        ([Priority],
                         [Findings Group],
                         [Finding],
                         [Database],
                         [Details],
                         [Recommendation])
            EXEC sp_executesql
              @sql;
            END TRY
            BEGIN CATCH
                SET @error_message = ERROR_MESSAGE();
                INSERT INTO #Results
                            ([Priority],
                             [Findings Group],
                             [Finding],
                             [Database],
                             [Details],
                             [Recommendation])
                VALUES (50,
                        'Check Failed',
                        N'Permission granted to public database role - failed',
                        @db_name,
                        @error_message,
                        N'Review the error message for details on what went wrong and address any issues with the dynamic SQL execution.');
            END CATCH;
        END;
      FETCH NEXT FROM db_cursor INTO @safe_for_ppc, @db_name;
  END;

CLOSE db_cursor;

DEALLOCATE db_cursor;

/*update for master and msdb*/
      UPDATE #Results
      SET    [Priority] = 1,
             [Finding] = [Finding] + N' in system database'
      WHERE  [Database] IN ( N'master', N'msdb' )
             AND [Finding] IN ( N'db_owner role membership', N'Powerful database role membership', N'Nested roles' );


/*return result*/
SELECT [Priority],
       [Findings Group],
       [Finding],
       [FindingHL],
       [Database],
       [Details],
       [Recommendation],
       [URL]
FROM   #Results
ORDER  BY [Priority] ASC,
          [Id] ASC;

/*cleanup temp tables */
DROP TABLE #Results;

DROP TABLE #Databases;

DROP TABLE #PassCandidates;

DROP TABLE #FoundPasswords;