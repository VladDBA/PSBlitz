/*
	Part of PSBlitz - https://github.com/VladDBA/PSBlitz
	License - https://github.com/VladDBA/PSBlitz/blob/main/LICENSE
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
/*Get instance info*/
SELECT ISNULL(SERVERPROPERTY('MachineName'),'N/A')                                         AS [machine_name],
       ISNULL(CAST(SERVERPROPERTY('InstanceName') AS NVARCHAR(100)), '(default instance)') AS [instance_name],
       SERVERPROPERTY('ProductVersion')                                                    AS [product_version],
       SERVERPROPERTY('ProductLevel')                                                      AS [product_level],
       SERVERPROPERTY('ProductUpdateLevel')                                                AS [patch_level],
	   CASE 
         WHEN CAST(SERVERPROPERTY('EngineEdition') AS INT) = 8 THEN 'Azure SQL Managed Instance'
         ELSE SERVERPROPERTY('Edition')   
       END                                                                                 AS [edition],
       CASE
         WHEN SERVERPROPERTY('IsClustered') = 1 THEN 'Yes'
         WHEN SERVERPROPERTY('IsClustered') = 0 THEN 'No'
         ELSE 'N/A'
       END                                                                                 AS [is_clustered],
       CASE
         WHEN SERVERPROPERTY('IsHadrEnabled') = 1 THEN 'Yes'
         WHEN SERVERPROPERTY('IsHadrEnabled') = 0 THEN 'No'
         ELSE 'N/A'
       END                                                                                 AS [always_on_enabled],
       CASE
         WHEN SERVERPROPERTY('FilestreamConfiguredLevel') = 0 THEN '0 - Disabled'
         WHEN SERVERPROPERTY('FilestreamConfiguredLevel') = 1 THEN '1 - T-SQL'
         WHEN SERVERPROPERTY('FilestreamConfiguredLevel') = 2 THEN '2 - T-SQL & local streaming'
         WHEN SERVERPROPERTY('FilestreamConfiguredLevel') = 3 THEN '3 - T-SQL & remote streaming'
         ELSE 'N/A'
       END                                                                                 AS [filestream_access_level],
       CASE
         WHEN SERVERPROPERTY('IsTempdbMetadataMemoryOptimized') = 1 THEN 'Yes'
         WHEN SERVERPROPERTY('IsTempdbMetadataMemoryOptimized') = 0 THEN 'No'
         ELSE 'N/A'
       END                                                                                 AS [tempdb_metadata_memory_optimized],
       CASE
         WHEN SERVERPROPERTY('IsFullTextInstalled') = 1 THEN 'Yes'
         WHEN SERVERPROPERTY('IsFullTextInstalled') = 0 THEN 'No'
         ELSE 'N/A'
       END                                                                                 AS [fulltext_installed],
       CASE
         WHEN SERVERPROPERTY('IsXTPSupported') = 1 THEN 'Yes'
         WHEN SERVERPROPERTY('IsXTPSupported') = 0 THEN 'No'
         ELSE 'N/A'
       END                                                                                 AS [in-memory_oltp_supported],
       CASE
         WHEN SERVERPROPERTY('IsServerSuspendedForSnapshotBackup') = 1 THEN 'Yes'
         WHEN SERVERPROPERTY('IsServerSuspendedForSnapshotBackup') = 0 THEN 'No'
         ELSE 'N/A'
       END                                                                                 AS [server_suspended_for_snapshot],
       SERVERPROPERTY('Collation')                                                         AS [instance_collation],
	   (SELECT COUNT([database_id]) FROM [sys].[databases] WHERE [database_id] > 4)        AS [user_db_count],
       ISNULL(CAST(SERVERPROPERTY('SuspendedDatabaseCount') AS NVARCHAR(10)),'N/A')        AS [suspended_db_count],
       CONVERT(VARCHAR(22),[sqlserver_start_time],120)                                     AS [instance_last_startup],
       SERVERPROPERTY('ProcessID')                                                         AS [process_id],
       CAST(DATEDIFF(HH, [sqlserver_start_time], GETDATE()) / 24.00 AS NUMERIC(23, 2))     AS [uptime_days],
       (SELECT COUNT(*)
        FROM   [sys].[dm_exec_connections])                                                AS [client_connections],
		CAST(0 AS DECIMAL(6,3))                                                            AS [estimated_response_latency(sec)],
		CONVERT(VARCHAR(30),SYSDATETIMEOFFSET(),120)                                       AS [server_time]
FROM   [sys].[dm_os_sys_info]
OPTION(RECOMPILE); 


/*Get resource info*/
DECLARE @SQL NVARCHAR(MAX);
DECLARE @LineFeed NVARCHAR(5);

SET @LineFeed = CHAR(13) + CHAR(10);

SELECT @SQL = CASE
              /*Skipping this query on Azure SQL DB*/
                WHEN CAST(SERVERPROPERTY('Edition') AS NVARCHAR(100)) = N'SQL Azure'
                     AND SERVERPROPERTY('EngineEdition') IN ( 5, 6 ) THEN /*This fake result set is only used in the Excel version of the report*/
                                                                          CAST(N'SELECT ''Not available'' AS [logical_cpu_cores], '' in Azure '' AS [physical_CPU_cores], ''SQL DB'' ' AS NVARCHAR(MAX))
                                                                          + N'AS [physical_memory_GB], NULL AS [max_server_memory_GB], NULL AS [target_server_memory_GB], '
                                                                          + N'NULL AS [total_memory_used_GB], NULL AS [proc_physical_memory_low], NULL AS [proc_virtual_memory_low], '
                                                                          + N'NULL AS [available_physical_memory_GB], NULL AS [os_memory_state], NULL AS [CTP], NULL AS [MAXDOP]'
                ELSE CAST(N'SELECT [cpu_count] AS [logical_cpu_cores],' AS NVARCHAR(MAX))
                     + @LineFeed
                     + CASE
                         WHEN /*If running on SQL Server 2016 SP1 or lower, don't retrieve physical_cpu_cores*/
                       ( CAST(SERVERPROPERTY('ProductMajorVersion') AS TINYINT) = 13
                         AND CAST(SERVERPROPERTY('ProductLevel') AS NVARCHAR(128)) IN ( N'RTM', N'SP1' ) )
                        OR CAST(ISNULL(SERVERPROPERTY('ProductMajorVersion'),0) AS TINYINT) < 13 THEN N'''-- N/A --'''
                         ELSE N'( [socket_count] * [cores_per_socket] )'
                       END
                     + N' AS [physical_cpu_cores],' + @LineFeed
                     + N'CAST(ROUND(( [physical_memory_kb] / 1024.00 / 1024.00 ), 1) AS DECIMAL(15, 2)) AS [physical_memory_GB],'
                     + @LineFeed
                     + N'(SELECT CAST(CAST([value_in_use] AS INT) / 1024.00 AS DECIMAL(15, 2))'
                     + @LineFeed + N'FROM [sys].[configurations]'
                     + @LineFeed
                     + N'WHERE [name] = N''max server memory (MB)'')                     AS [max_server_memory_GB],'
                     + @LineFeed
                     + N'(SELECT TOP(1) CAST([cntr_value] / 1024.00 / 1024.00 AS DECIMAL(15, 2))'
                     + @LineFeed
                     + N'FROM [sys].[dm_os_performance_counters]'
                     + @LineFeed
                     + N'WHERE  [object_name] LIKE N''%Memory Manager%'''
                     + @LineFeed
                     + N'AND [counter_name] LIKE N''Target Server Memory (KB)%'''
                     + @LineFeed
                     + N'ORDER  BY [cntr_value] DESC) AS [target_server_memory_GB],'
                     + @LineFeed
                     + N'(SELECT TOP(1) CAST([cntr_value] / 1024.00 / 1024.00 AS DECIMAL(15, 2))'
                     + @LineFeed
                     + N'FROM [sys].[dm_os_performance_counters]'
                     + @LineFeed
                     + N'WHERE  [object_name] LIKE N''%Memory Manager%'''
                     + @LineFeed
                     + N'AND [counter_name] LIKE N''Total Server Memory (KB)%'') AS [total_memory_used_GB],'
                     + @LineFeed
					 + N'(SELECT CAST(COUNT(*) * 8/1024.0/1024.0 AS DECIMAL (15,2))'
                     + @LineFeed
					 + N' FROM sys.dm_os_buffer_descriptors WHERE database_id <> 32767)   AS [buffer_pool_usage_GB],'
					 + @LineFeed
                     + N'(SELECT CAST(([locked_page_allocations_kb] / 1024.00/1024.00) AS DECIMAL(15, 2)) '
                     + @LineFeed
                     + N' FROM sys.dm_os_process_memory) AS [locked_pages_allocated_GB],'
                     + @LineFeed
                     + N'(SELECT CAST(([large_page_allocations_kb] / 1024.00/1024.00) AS DECIMAL(15, 2)) '
                     + @LineFeed
                     + N' FROM sys.dm_os_process_memory) AS [large_pages_allocated_GB],'
                     + @LineFeed
                     + N'(SELECT CASE WHEN [process_physical_memory_low] = 1 THEN ''Yes'''
                     + @LineFeed
                     + N'ELSE ''No'' END FROM sys.dm_os_process_memory) AS [process_physical_memory_low],'
                     + @LineFeed
                     + N'(SELECT CASE WHEN [process_virtual_memory_low] = 1 THEN ''Yes'''
                     + @LineFeed
                     + N'ELSE ''No'' END FROM sys.dm_os_process_memory) AS [process_virtual_memory_low],'
                     + @LineFeed
                     + N'(SELECT CAST(([available_physical_memory_kb]/1024.00/1024.00) AS DECIMAL(15, 2))'
                     + @LineFeed
                     + N' FROM [sys].[dm_os_sys_memory]) AS [available_physical_memory_GB],'
                     + @LineFeed
                     + N'(SELECT [system_memory_state_desc] FROM [sys].[dm_os_sys_memory]) AS [OS_memory_state],'
                     + @LineFeed
                     + N'(SELECT [value] FROM [sys].[configurations]'
                     + @LineFeed
                     + N' WHERE [name] = N''cost threshold for parallelism'') AS [CTP],'
                     + @LineFeed
                     + N'(SELECT [value] FROM [sys].[configurations]'
                     + @LineFeed
                     + N' WHERE [name] = N''max degree of parallelism'') AS [MAXDOP]'
                     + @LineFeed
                     + N'FROM [sys].[dm_os_sys_info] OPTION(RECOMPILE);'
              END; 

BEGIN
    EXEC(@SQL);
END;

/*Get connection info*/
SELECT TOP 10 [d].[name]                                                                         AS [database],
              COUNT([c].[connection_id])                                                         AS [connections_count],
              RTRIM(LTRIM([s].[login_name]))                                                     AS [login_name],
              ISNULL([s].[host_name], N'N/A')                                                    AS [client_host_name],
              REPLACE(REPLACE([c].[client_net_address], N'<', N''), N'>', N'')                   AS [client_IP],
              [c].[net_transport]                                                                AS [protocol],
              ISNULL(NULLIF(CAST(SUM(CASE 
			                           WHEN LOWER([s].[status]) = N'preconnect' 
			  						   THEN 1 ELSE 0 
			  						 END) AS VARCHAR(20))+ ' preconnect', '0 preconnect')+'; ', '')
			  
			  +ISNULL(NULLIF(CAST(SUM(CASE 
			                            WHEN LOWER([s].[status]) = N'dormant' 
			  							THEN 1 ELSE 0 
			  						  END) AS VARCHAR(20))+' dormant', '0 dormant')+'; ', '')
			  +ISNULL(NULLIF(CAST(SUM(CASE 
			                            WHEN LOWER([s].[status]) = N'running' 
			  							THEN 1 ELSE 0 
			  						  END) AS VARCHAR(20))+' running', '0 running')+'; ', '')
			  +ISNULL(NULLIF(CAST(SUM(CASE 
			                            WHEN LOWER([s].[status]) = N'sleeping' 
			  							THEN 1 ELSE 0 
			  						  END) AS VARCHAR(20))+' sleeping', '0 sleeping'), '')       AS [sessions_by_state],
              CONVERT(VARCHAR(25), MAX([c].[connect_time]), 121)                                 AS [oldest_connection_time],
              CONVERT(VARCHAR(25), MIN([c].[connect_time]), 121)                                 AS [newest_connection_time],
              [s].[program_name]                                                                 AS [program]
FROM   sys.[dm_exec_sessions] AS [s]
       LEFT JOIN sys.[databases] AS [d]
              ON [d].[database_id] = [s].[database_id]
       INNER JOIN sys.[dm_exec_connections] AS [c]
               ON [s].[session_id] = [c].[session_id]
GROUP  BY [d].[database_id],
          [d].[name],
          [s].[login_name],
          [s].[security_id],
          [s].[host_name],
          [c].[client_net_address],
          [c].[net_transport],
          [s].[program_name]
ORDER  BY [connections_count] DESC
OPTION(RECOMPILE);

/*Get SET options from both session and instance*/
DECLARE @InstanceLevelOption INT;
SELECT @InstanceLevelOption = CAST([value_in_use] AS INT)
FROM   sys.configurations
WHERE  [name] = N'user options';

;
WITH OPTCTE
     AS (SELECT Options.[id],
                Options.[Option],
                Options.[Description],
                ROW_NUMBER()
                  OVER (
                    PARTITION BY 1
                    ORDER BY id) AS [bitNum]
         FROM   (VALUES (1,
                'DISABLE_DEF_CNST_CHK',
                'Controls interim or deferred constraint checking. - obsolete and should not be on!'),
                        (2,
                'IMPLICIT_TRANSACTIONS',
                'Controls whether a transaction is started implicitly when a statement is executed.'),
                        (4,
                'CURSOR_CLOSE_ON_COMMIT',
                'Controls behavior of cursors after a commit operation has been performed.'),
                        (8,
                'ANSI_WARNINGS',
                'Controls truncation and NULL in aggregate warnings.'),
                        (16,
                'ANSI_PADDING',
                'Controls padding of fixed-length variables.'),
                        (32,
                'ANSI_NULLS',
                'Controls NULL handling when using equality operators.'),
                        (64,
                'ARITHABORT',
                'Terminates a query when an overflow or divide-by-zero error occurs during query execution.'),
                        (128,
                'ARITHIGNORE',
                'Returns NULL when an overflow or divide-by-zero error occurs during a query.'),
                        (256,
                'QUOTED_IDENTIFIER',
                'Differentiates between single and double quotation marks when evaluating an expression.'),
                        (512,
                'NOCOUNT',
                'Turns off the message returned at the end of each statement that states how many rows were affected.'),
                        (1024,
                'ANSI_NULL_DFLT_ON',
                'Alters the session''s behavior to use ANSI compatibility for nullability. New columns defined without explicit nullability are defined to allow nulls.'),
                        (2048,
                'ANSI_NULL_DFLT_OFF',
                'Alters the session''s behavior not to use ANSI compatibility for nullability. New columns defined without explicit nullability do not allow nulls.'),
                        (4096,
                'CONCAT_NULL_YIELDS_NULL',
                'Returns NULL when concatenating a NULL value with a string.'),
                        (8192,
                'NUMERIC_ROUNDABORT',
                'Generates an error when a loss of precision occurs in an expression.'),
                        (16384,
                'XACT_ABORT',
                'Rolls back a transaction if a Transact-SQL statement raises a run-time error.') ) AS Options([id], [Option], [Description]))
SELECT [Option],
       CASE
         WHEN [Description] LIKE '%obsolete%' THEN [Option]
		 ELSE '<a href=''https://learn.microsoft.com/en-us/sql/t-sql/statements/set-'+
		 LOWER(REPLACE([Option], '_', '-')) + '-transact-sql'' target=''_blank''>'+[Option]+'</a>'
		 END AS [OptionHL],
       CASE
         WHEN ( @@OPTIONS & id ) = id THEN 'ON'
         ELSE 'OFF'
       END AS [Session_Setting],
       CASE
         WHEN ( @InstanceLevelOption & id ) = id THEN 'ON'
         ELSE 'OFF'
       END AS [Instance_Setting],
       [Description],
       CASE
         WHEN [Description] LIKE '%obsolete%' THEN ''
         ELSE 'https://learn.microsoft.com/en-us/sql/t-sql/statements/set-'
              + LOWER(REPLACE([Option], '_', '-'))
              + '-transact-sql'
       END AS [URL]
FROM   OPTCTE
ORDER BY [Option]
OPTION(RECOMPILE);

/*plan cache distribution by type*/
SELECT '_Total_'                                                                    AS [cache_type],
       COUNT_BIG(*)                                                                 AS [total_plans],
       SUM(CAST(CAST([size_in_bytes] AS BIGINT) / 1024. / 1024. AS DECIMAL(23, 3))) AS [plan_cache_used_mb],
       AVG(CAST([usecounts] AS BIGINT))                                                             AS [avg_use_count],
       SUM(CAST(CAST(
                (
                  CASE
                    WHEN [usecounts] = 1 THEN CAST([size_in_bytes] AS BIGINT)
                    ELSE 0
                  END
                )
                AS BIGINT) / 1024. / 1024. AS DECIMAL(23, 3)))                      AS [single_use_plans_total_mb],
       SUM(CASE
             WHEN CAST([usecounts] AS BIGINT) = 1 THEN 1
             ELSE 0
           END)                                                                     AS [total_single_use_plans]
FROM   sys.[dm_exec_cached_plans]
UNION
SELECT [objtype]                                                                    AS [cache_type],
       COUNT_BIG(*)                                                                 AS [total_plans],
       SUM(CAST(CAST([size_in_bytes] AS BIGINT) / 1024. / 1024. AS DECIMAL(23, 3))) AS [plan_cache_used_mb],
       AVG(CAST([usecounts] AS BIGINT))                                                             AS [avg_use_count],
       SUM(CAST(CAST(
                (
                  CASE
                    WHEN [usecounts] = 1 THEN CAST([size_in_bytes] AS BIGINT)
                    ELSE 0
                  END
                )
                AS BIGINT) / 1024. / 1024. AS DECIMAL(23, 3)))                      AS [single_use_plans_total_mb],
       SUM(CASE
             WHEN CAST([usecounts] AS BIGINT) = 1 THEN 1
             ELSE 0
           END)                                                                     AS [total_single_use_plans]
FROM   sys.[dm_exec_cached_plans]
GROUP  BY [objtype]
ORDER  BY [single_use_plans_total_mb] DESC
OPTION(RECOMPILE);

/*plan cache usage by db*/
SELECT TOP(10) [d].name                                                                          AS [database],
               COUNT_BIG(*)                                                                      AS [total_plans],
               SUM(CAST(CAST([cp].[size_in_bytes] AS BIGINT) / 1024. / 1024. AS DECIMAL(23, 3))) AS [plan_cache_used_mb]
FROM   sys.[dm_exec_query_stats]
       CROSS APPLY sys.dm_exec_sql_text([dm_exec_query_stats].[plan_handle]) AS [qt]
       INNER JOIN sys.[databases] AS [d]
               ON [qt].[dbid] = [d].[database_id]
       INNER JOIN sys.[dm_exec_cached_plans] AS [cp]
               ON [cp].[plan_handle] = [dm_exec_query_stats].[plan_handle]
WHERE  [d].[database_id] <> 32767
GROUP  BY [d].name
ORDER  BY [total_plans] DESC
OPTION(RECOMPILE); 