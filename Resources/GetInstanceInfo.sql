/*
	Part of PSBlitz - https://github.com/VladDBA/PSBlitz
	License - https://github.com/VladDBA/PSBlitz/blob/main/LICENSE
*/
SET NOCOUNT ON;
SET STATISTICS XML OFF;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/*Get instance info*/
SELECT SERVERPROPERTY('MachineName')                                                       AS [machine_name],
       ISNULL(CAST(SERVERPROPERTY('InstanceName') AS NVARCHAR(100)), '(default instance)') AS [instance_name],
       SERVERPROPERTY('ProductVersion')                                                    AS [product_version],
       SERVERPROPERTY('ProductLevel')                                                      AS [product_level],
       SERVERPROPERTY('ProductUpdateLevel')                                                AS [patch_level],
       SERVERPROPERTY('Edition')                                                           AS [edition],
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
       END                                                                                 AS [mem_optimized_tempdb_metadata],
       CASE
         WHEN SERVERPROPERTY('IsFullTextInstalled') = 1 THEN 'Yes'
         WHEN SERVERPROPERTY('IsFullTextInstalled') = 0 THEN 'No'
         ELSE 'N/A'
       END                                                                                 AS [fulltext_installed],
       SERVERPROPERTY('Collation')                                                         AS [instance_collation],
       [sqlserver_start_time]                                                              AS [instance_last_startup],
       SERVERPROPERTY('ProcessID')                                                         AS [process_id],
       CAST(DATEDIFF(HH, [sqlserver_start_time], GETDATE()) / 24.00 AS NUMERIC(23, 2))     AS [uptime_days],
       (SELECT COUNT(*)
        FROM   [sys].[dm_exec_connections])                                                AS [client_connections]
FROM   [sys].[dm_os_sys_info]
OPTION(RECOMPILE); 


/*Get resource info*/
DECLARE @SQL NVARCHAR(MAX);
DECLARE @LineFeed NVARCHAR(5);

SET @LineFeed = CHAR(13) + CHAR(10);

SELECT @SQL = N'SELECT [cpu_count] AS [logical_cpu_cores],' 
+ @LineFeed + CASE 
				WHEN /*If running on SQL Server 2016 SP1 or lower, don't retrieve physical_cpu_cores*/ 
					(CAST(SERVERPROPERTY('ProductMajorVersion') AS TINYINT) = 13
					AND CAST(SERVERPROPERTY('ProductLevel') AS NVARCHAR(128)) IN ( N'RTM', N'SP1' )) 
					OR CAST(SERVERPROPERTY('ProductMajorVersion') AS TINYINT) < 13  
				THEN N'''-- N/A --'''
				ELSE N'( [socket_count] * [cores_per_socket] )'
			END +N' AS [physical_cpu_cores],'
+ @LineFeed + N'CAST(ROUND(( [physical_memory_kb] / 1024.00 / 1024.00 ), 1) AS DECIMAL(15, 2)) AS [physical_memory_GB],'
+ @LineFeed + N'(SELECT CAST(CAST([value_in_use] AS INT) / 1024.00 AS DECIMAL(15, 2))' 
+ @LineFeed + N'FROM [sys].[configurations]'
+ @LineFeed + N'WHERE [name] = N''max server memory (MB)'')                     AS [max_server_memory_GB],'
+ @LineFeed + N'(SELECT TOP(1) CAST([cntr_value] / 1024.00 / 1024.00 AS DECIMAL(15, 2))'
+ @LineFeed + N'FROM [sys].[dm_os_performance_counters]'
+ @LineFeed + N'WHERE  [object_name] LIKE N''%Memory Manager%'''
+ @LineFeed + N'AND [counter_name] LIKE N''Target Server Memory (KB)%'''
+ @LineFeed + N'ORDER  BY [cntr_value] DESC) AS [target_server_memory_GB],'
+ @LineFeed + N'(SELECT TOP(1) CAST([cntr_value] / 1024.00 / 1024.00 AS DECIMAL(15, 2))'
+ @LineFeed + N'FROM [sys].[dm_os_performance_counters]'
+ @LineFeed + N'WHERE  [object_name] LIKE N''%Memory Manager%'''
+ @LineFeed + N'AND [counter_name] LIKE N''Total Server Memory (KB)%'') AS [total_memory_used_GB],'
+ @LineFeed + N'(SELECT CASE WHEN [process_physical_memory_low] = 1 THEN ''Yes'''
+ @LineFeed + N'ELSE ''No'' END FROM sys.dm_os_process_memory) AS [proc_physical_memory_low],'
+ @LineFeed + N'(SELECT CASE WHEN [process_virtual_memory_low] = 1 THEN ''Yes'''
+ @LineFeed + N'ELSE ''No'' END FROM sys.dm_os_process_memory) AS [proc_virtual_memory_low]'
+ @LineFeed + N'FROM [sys].[dm_os_sys_info] OPTION(RECOMPILE);'

BEGIN
    EXEC(@SQL);
END;

/*Get connection info*/
SELECT TOP 10 [d].[name]                                                       AS [DatabaseName],
              COUNT([s].[status])                                              AS [ConnectionsCount],
              RTRIM(LTRIM([s].[login_name]))                                   AS [LoginName],
              ISNULL([s].[host_name], N'N/A')                                  AS [ClientHostName],
              REPLACE(REPLACE([c].[client_net_address], N'<', N''), N'>', N'') AS [ClientIP],
              [c].[net_transport]                                              AS [ProtocolUsed],
			  MAX([c].[connect_time])                                          AS [OldestConnectionTime],
              [s].[program_name]                                               AS [Program]              
FROM   sys.dm_exec_sessions AS [s]
       LEFT JOIN sys.databases AS [d]
              ON [d].[database_id] = [s].[database_id]
       INNER JOIN sys.dm_exec_connections AS [c]
               ON [s].[session_id] = [c].[session_id]
GROUP  BY [d].[database_id],
          [d].[name],
          [s].[login_name],
          [s].[security_id],
          [s].[host_name],
          [c].[client_net_address],
          [c].[net_transport],
          [s].[program_name]
ORDER  BY [ConnectionsCount] DESC
OPTION(RECOMPILE); 
