SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
/*Get instance info*/
SELECT SERVERPROPERTY('MachineName')                                                       AS [machine_name],
       ISNULL(CAST(SERVERPROPERTY('InstanceName') AS NVARCHAR(100)), '(default instance)') AS [instance_name],
       SERVERPROPERTY('ProductVersion')                                                    AS [product_version],
       SERVERPROPERTY('ProductLevel')                                                      AS [patch_level],
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
/*If running on SQL Server 2016 SP1 or lower, don't retrieve physical_cpu_cores*/
IF ( (SELECT CAST(SERVERPROPERTY('ProductMajorVersion') AS TINYINT)) = 13
     AND (SELECT CAST(SERVERPROPERTY('ProductLevel') AS NVARCHAR(128))) IN ( N'RTM', N'SP1' ) )
    OR ( (SELECT CAST(SERVERPROPERTY('ProductMajorVersion') AS TINYINT)) < 13 )
  BEGIN
      SELECT [cpu_count]                                                     AS [logical_cpu_cores],
             '-- N/A --'                                                           AS [physical_cpu_cores],
             CAST(ROUND(( [physical_memory_kb] / 1024.0 / 1024 ), 1) AS INT) AS [physical_memory_GB],
             (SELECT CAST(CAST([value_in_use] AS INT) / 1024.0 AS DECIMAL(15, 2))
              FROM   [sys].[configurations]
              WHERE  [name] = N'max server memory (MB)')                     AS [max_server_memory_GB],
             (SELECT TOP(1) CAST([cntr_value] / 1024.0 / 1024 AS DECIMAL(15, 2))
              FROM   [sys].[dm_os_performance_counters]
              WHERE  [object_name] LIKE N'%Memory Manager%'
                     AND [counter_name] LIKE N'Target Server Memory (KB)%'
              ORDER  BY [cntr_value] DESC)                                   AS [target_server_memory_GB],
             (SELECT TOP(1) CAST([cntr_value] / 1024.0 / 1024 AS DECIMAL(15, 2))
              FROM   [sys].[dm_os_performance_counters]
              WHERE  [object_name] LIKE N'%Memory Manager%'
                     AND [counter_name] LIKE N'Total Server Memory (KB)%')   AS [total_memory_used_GB]
      FROM   [sys].[dm_os_sys_info];
  END;
ELSE
  BEGIN
      SELECT [cpu_count]                                                   AS [logical_cpu_cores],
             ( [socket_count] * [cores_per_socket] )                       AS [physical_cpu_cores],
             CAST(ROUND(( physical_memory_kb / 1024.0 / 1024 ), 1) AS INT) AS [physical_memory_GB],
             (SELECT CAST(CAST([value_in_use] AS INT) / 1024.0 AS DECIMAL(15, 2))
              FROM   [sys].[configurations]
              WHERE  [name] = N'max server memory (MB)')                   AS [max_server_memory_GB],
             (SELECT TOP(1) CAST([cntr_value] / 1024.0 / 1024 AS DECIMAL(15, 2))
              FROM   [sys].[dm_os_performance_counters]
              WHERE  [object_name] LIKE N'%Memory Manager%'
                     AND [counter_name] LIKE N'Target Server Memory (KB)%'
              ORDER  BY [cntr_value] DESC)                                 AS [target_server_memory_GB],
             (SELECT TOP(1) CAST([cntr_value] / 1024.0 / 1024 AS DECIMAL(15, 2))
              FROM   [sys].[dm_os_performance_counters]
              WHERE  [object_name] LIKE N'%Memory Manager%'
                     AND [counter_name] LIKE N'Total Server Memory (KB)%') AS [total_memory_used_GB]
      FROM   [sys].[dm_os_sys_info];
  END; 
