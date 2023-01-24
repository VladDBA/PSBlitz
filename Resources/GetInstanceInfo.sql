SET NOCOUNT ON;
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
       [sqlserver_start_time]                                                              AS [instance_last_startup],
       CAST(DATEDIFF(HH, [sqlserver_start_time], GETDATE()) / 24.00 AS NUMERIC(23, 2))     AS [uptime_days]
FROM   [sys].[dm_os_sys_info];


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
+ @LineFeed + N'CAST(ROUND(( [physical_memory_kb] / 1024.0 / 1024 ), 1) AS INT) AS [physical_memory_GB],'
+ @LineFeed + N'(SELECT CAST(CAST([value_in_use] AS INT) / 1024.0 AS DECIMAL(15, 2))' 
+ @LineFeed + N'FROM   [sys].[configurations]'
+ @LineFeed + N'WHERE  [name] = N''max server memory (MB)'')                     AS [max_server_memory_GB],'
+ @LineFeed + N'(SELECT TOP(1) CAST([cntr_value] / 1024.0 / 1024 AS DECIMAL(15, 2))'
+ @LineFeed + N'FROM   [sys].[dm_os_performance_counters]'
+ @LineFeed + N'WHERE  [object_name] LIKE N''%Memory Manager%'''
+ @LineFeed + N'AND [counter_name] LIKE N''Target Server Memory (KB)%'''
+ @LineFeed + N'ORDER  BY [cntr_value] DESC) AS [target_server_memory_GB],'
+ @LineFeed + N'(SELECT TOP(1) CAST([cntr_value] / 1024.0 / 1024 AS DECIMAL(15, 2))'
+ @LineFeed + N'FROM   [sys].[dm_os_performance_counters]'
+ @LineFeed + N'WHERE  [object_name] LIKE N''%Memory Manager%'''
+ @LineFeed + N'AND [counter_name] LIKE N''Total Server Memory (KB)%'')   AS [total_memory_used_GB]'
+ @LineFeed + N'FROM   [sys].[dm_os_sys_info];'

BEGIN
EXEC(@SQL);
END;
