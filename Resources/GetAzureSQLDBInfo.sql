/*
	Part of PSBlitz - https://github.com/VladDBA/PSBlitz
	License - https://github.com/VladDBA/PSBlitz/blob/main/LICENSE
*/
SET NOCOUNT ON;
SET STATISTICS XML OFF;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

/*configuration and capacity settings for the current database*/
SELECT [database_name]                                                     AS [Database],
       [slo_name]                                                          AS [Service level objective],
       [dtu_limit]                                                         AS [DTU limit(empty for vCore)],
       [cpu_limit]                                                         AS [vCore limit(empty for DTU databases)],
       [min_cpu]                                                           AS [Min CPU%],
       [max_cpu]                                                           AS [Max CPU%],
       [cap_cpu]                                                           AS [Cap CPU%],
       [max_dop]                                                           AS [Max DOP],
       [min_memory]                                                        AS [Min Memory%],
       [max_memory]                                                        AS [Max Memory%],
       [max_sessions]                                                      AS [Max allowed sessions],
       [max_memory_grant]                                                  AS [Req Max Memory Grant%],
       [min_db_max_size_in_mb]                                             AS [Min Max DataFile Size(MB)],
       [max_db_max_size_in_mb]                                             AS [Max Max DataFile Size(MB)],
       [default_db_max_size_in_mb]                                         AS [Default Max DataFile Size(MB)],
       [db_file_growth_in_mb]                                              AS [Default DataFile Growth Increment(MB)],
       [initial_db_file_size_in_mb]                                        AS [Default Size New DataFile(MB)],
       [log_size_in_mb]                                                    AS [Default Size New LogFile(MB)],
       CAST([instance_max_log_rate] / 1024.00 / 1024.00 AS NUMERIC(23, 3)) AS [Instnace Max Log Rate MB/s],
       [instance_max_worker_threads]                                       AS [Instance Max Worker Threads],
       CASE
         WHEN [replica_type] = 0 THEN 'Primary'
         ELSE 'Secondary'
       END                                                                 AS [Replica Type],
       [max_transaction_size]                                              AS [Max TLog Space/Transaction(KB)],
       [last_updated_date_utc]                                             AS [Settings Last Changed],
       [primary_group_max_workers]                                         AS [User Workload Max Worker Threads],
       CAST([primary_min_log_rate] / 1024.00 / 1024.00 AS NUMERIC(23, 3))  AS [User Workload Min Log Rate MB/s],
       CAST([primary_max_log_rate] / 1024.00 / 1024.00 AS NUMERIC(23, 3))  AS [User Workload Max Log Rate MB/s],
       [primary_group_min_io]                                              AS [User Workload Min IOPS],
       [primary_group_max_io]                                              AS [User Workload Max IOPS],
       [primary_group_min_cpu]                                             AS [User Workload Min CPU%],
       [primary_group_max_cpu]                                             AS [User Workload Max CPU%],
       [primary_pool_max_workers]                                          AS [User Workload Max Worker Threads],
       [pool_max_io]                                                       AS [User Workload Pool Max IOPS ],
       [user_data_directory_space_quota_mb]                                AS [Max Local Storage(MB)],
       [user_data_directory_space_usage_mb]                                AS [Used Local Storage(MB)],
       CAST([pool_max_log_rate] / 1024.00 / 1024.00 AS NUMERIC(23, 3))     AS [Pool Max Log Rate MB/s],
       [primary_group_max_outbound_connection_workers],
       [primary_pool_max_outbound_connection_workers],
       CASE
         WHEN [replica_role] = 0 THEN 'Primary'
         WHEN [replica_role] = 1 THEN 'HA Secondary'
         WHEN [replica_role] = 2 THEN 'Geo-replication forwarder'
         WHEN [replica_role] = 3 THEN 'Named replica'
         ELSE 'N/A'
       END                                                                 AS [Replica Role]
FROM   sys.[dm_user_db_resource_governance]; 


/*DB overview*/
;WITH FSFiles([database_id], [FSFilesCount], [FSFilesSizeGB])
     AS (SELECT DB_ID() AS [database_id],
                COUNT([type]),
                CAST(SUM(CAST([size] AS BIGINT) * 8 / 1024.00 / 1024.00) AS NUMERIC(23, 3))
         FROM   sys.[database_files]
         WHERE  [type] = 2
         GROUP  BY [type])
SELECT DB_NAME()                                                                                                       AS [Database],
       DATABASEPROPERTYEX(DB_NAME(), 'ServiceObjective')                                                               AS [Service Objective],
       [d].[create_date] AS [Created],
       [d].[state_desc]                                                                                                AS [Database State],
       SUM(CASE
             WHEN [f].[type] = 0 THEN 1
             ELSE 0
           END)                                                                                                        AS [Data Files],
       CAST(SUM(CASE
                  WHEN [f].[type] = 0 THEN ( CAST([f].[size] AS BIGINT) * 8 / 1024.00 / 1024.00 )
                  ELSE 0.00
                END) AS NUMERIC(23, 3))                                                                                AS [Data Files Size GB],
       SUM(CASE
             WHEN [f].[type] = 1 THEN 1
             ELSE 0
           END)                                                                                                        AS [Log Files],
       CAST(SUM(CASE
                  WHEN [f].[type] = 1 THEN ( CAST([f].[size] AS BIGINT) * 8 / 1024.00 / 1024.00 )
                  ELSE 0.00
                END) AS NUMERIC(23, 3))                                                                                AS [LogFilesSizeGB],
       [l].[VirtualLogFiles],
       ISNULL([fs].[FSFilesCount], 0)                                                                                  AS [FILESTREAM Containers],
       ISNULL([fs].[FSFilesSizeGB], 0.000)                                                                             AS [FS Containers Size GB],
       CAST(SUM(CAST([f].[size] AS BIGINT) * 8 / 1024.00 / 1024.00) AS NUMERIC(23, 3))
       + ISNULL([fs].[FSFilesSizeGB], 0.000)                                                                           AS [Database Size GB],
       CAST(CAST(DATABASEPROPERTYEX(DB_NAME(), 'MaxSizeInBytes') AS BIGINT) / 1024. / 1024. / 1024. AS NUMERIC(18, 2)) AS [Database MaxSize GB],
       [d].[log_reuse_wait_desc]                                                                                       AS [Current Log Reuse Wait],
       [d].[compatibility_level]                                                                                       AS [Compatibility Level],
       [d].[page_verify_option_desc]                                                                                   AS [Page Verify Option],
       [d].[containment_desc]                                                                                          AS [Containment],
       [d].[collation_name]                                                                                            AS [Collation],
       [d].[snapshot_isolation_state_desc]                                                                             AS [Snapshot Isolation State],
       CASE
         WHEN [d].[is_read_committed_snapshot_on] = 1 THEN 'Yes'
         ELSE 'No'
       END                                                                                                             AS [Read Committed Snapshot On],
       [d].[recovery_model_desc]                                                                                       AS [Recovery Model],
       CASE
         WHEN [d].[is_auto_close_on] = 1 THEN 'Yes'
         ELSE 'No'
       END                                                                                                             AS [AutoClose On],
       CASE
         WHEN [d].[is_auto_shrink_on] = 1 THEN 'Yes'
         ELSE 'No'
       END                                                                                                             AS [AutoShrink On],
       CASE
         WHEN [d].[is_query_store_on] = 1 THEN 'Yes'
         ELSE 'No'
       END                                                                                                             AS [QueryStore On],
       CASE
         WHEN [d].[is_trustworthy_on] = 1 THEN 'Yes'
         ELSE 'No'
       END                                                                                                             AS [Trustworthy On]
FROM   sys.[database_files] AS [f]
       INNER JOIN sys.[databases] AS [d]
               ON DB_ID() = [d].[database_id]
       LEFT JOIN FSFiles AS [fs]
              ON DB_ID() = [fs].[database_id]
       CROSS APPLY (SELECT [file_id],
                           COUNT(*) AS [VirtualLogFiles]
                    FROM   sys.dm_db_log_info ([d].[database_id])
                    GROUP  BY [file_id]) AS [l]
GROUP  BY [d].[name],
          [fs].[FSFilesCount],
          [d].[create_date],
          [fs].[FSFilesSizeGB],
          [d].[compatibility_level],
          [d].[log_reuse_wait_desc],
          [d].[containment_desc],
          [d].[page_verify_option_desc],
          [d].[state_desc],
          [d].[collation_name],
          [d].[snapshot_isolation_state_desc],
          [d].[is_read_committed_snapshot_on],
          [d].[recovery_model_desc],
          [d].[is_auto_close_on],
          [d].[is_auto_shrink_on],
          [d].[is_query_store_on],
          [d].[is_trustworthy_on],
          [l].[VirtualLogFiles]
OPTION (RECOMPILE); 

/*Database resource usage  -- most likely different file and report pages*/
/*AVG and MAX in the past 64 minutes*/
DECLARE @MaxEndTime DATETIME;

SELECT @MaxEndTime = MAX([end_time])
FROM   sys.[dm_db_resource_stats];

SELECT DATEADD(SECOND, -15, MIN([end_time]))                  AS [Sample Start],
       MAX([end_time])                                        AS [Sample end],
	   DATEDIFF(MINUTE, MIN([end_time]), MAX([end_time]))     AS [Sample(Minutes)],
       CAST(AVG([avg_cpu_percent]) AS NUMERIC(5, 2))          AS [Avg CPU Usage %],
       CAST(MAX([avg_cpu_percent]) AS NUMERIC(5, 2))          AS [Max CPU Usage %],
       CAST(AVG([avg_data_io_percent]) AS NUMERIC(5, 2))      AS [Avg Data IO %],
       CAST(MAX([avg_data_io_percent]) AS NUMERIC(5, 2))      AS [Max Data IO %],
       CAST(AVG([avg_log_write_percent]) AS NUMERIC(5, 2))    AS [Avg Log Write Usage %],
       CAST(MAX([avg_log_write_percent]) AS NUMERIC(5, 2))    AS [Max Log Write Usage %],
       CAST(AVG([avg_memory_usage_percent]) AS NUMERIC(5, 2)) AS [Avg Memory Usage %],
       CAST(MAX([avg_memory_usage_percent]) AS NUMERIC(5, 2)) AS [Max Memory Usage %]
FROM   sys.[dm_db_resource_stats]
UNION
SELECT DATEADD(SECOND, -15, MIN([end_time]))                  AS [Sample start],
       MAX([end_time])                                        AS [Sample end],
       DATEDIFF(MINUTE, MIN([end_time]), MAX([end_time]))     AS [Sample(Minutes)],
	   CAST(AVG([avg_cpu_percent]) AS NUMERIC(5, 2))          AS [Avg CPU Usage %],
       CAST(MAX([avg_cpu_percent]) AS NUMERIC(5, 2))          AS [Max CPU Usage %],
       CAST(AVG([avg_data_io_percent]) AS NUMERIC(5, 2))      AS [Avg Data IO %],
       CAST(MAX([avg_data_io_percent]) AS NUMERIC(5, 2))      AS [Max Data IO %],
       CAST(AVG([avg_log_write_percent]) AS NUMERIC(5, 2))    AS [Avg Log Write Usage %],
       CAST(MAX([avg_log_write_percent]) AS NUMERIC(5, 2))    AS [Max Log Write Usage %],
       CAST(AVG([avg_memory_usage_percent]) AS NUMERIC(5, 2)) AS [Avg Memory Usage %],
       CAST(MAX([avg_memory_usage_percent]) AS NUMERIC(5, 2)) AS [Max Memory Usage %]
FROM   sys.[dm_db_resource_stats]
WHERE  [end_time] >= DATEADD(MINUTE, -30, @MaxEndTime)
UNION
SELECT DATEADD(SECOND, -15, MIN([end_time]))                  AS [Sample start],
       MAX([end_time])                                        AS [Sample end],
	   DATEDIFF(MINUTE, MIN([end_time]), MAX([end_time]))     AS [Sample(Minutes)],
       CAST(AVG([avg_cpu_percent]) AS NUMERIC(5, 2))          AS [Avg CPU Usage %],
       CAST(MAX([avg_cpu_percent]) AS NUMERIC(5, 2))          AS [Max CPU Usage %],
       CAST(AVG([avg_data_io_percent]) AS NUMERIC(5, 2))      AS [Avg Data IO %],
       CAST(MAX([avg_data_io_percent]) AS NUMERIC(5, 2))      AS [Max Data IO %],
       CAST(AVG([avg_log_write_percent]) AS NUMERIC(5, 2))    AS [Avg Log Write Usage %],
       CAST(MAX([avg_log_write_percent]) AS NUMERIC(5, 2))    AS [Max Log Write Usage %],
       CAST(AVG([avg_memory_usage_percent]) AS NUMERIC(5, 2)) AS [Avg Memory Usage %],
       CAST(MAX([avg_memory_usage_percent]) AS NUMERIC(5, 2)) AS [Max Memory Usage %]
FROM   sys.[dm_db_resource_stats]
WHERE  [end_time] >= DATEADD(MINUTE, -15, @MaxEndTime)
UNION
SELECT DATEADD(SECOND, -15, MIN([end_time]))                  AS [Sample start],
       MAX([end_time])                                        AS [Sample end],
	   DATEDIFF(MINUTE, MIN([end_time]), MAX([end_time]))     AS [Sample(Minutes)],
       CAST(AVG([avg_cpu_percent]) AS NUMERIC(5, 2))          AS [Avg CPU Usage %],
       CAST(MAX([avg_cpu_percent]) AS NUMERIC(5, 2))          AS [Max CPU Usage %],
       CAST(AVG([avg_data_io_percent]) AS NUMERIC(5, 2))      AS [Avg Data IO %],
       CAST(MAX([avg_data_io_percent]) AS NUMERIC(5, 2))      AS [Max Data IO %],
       CAST(AVG([avg_log_write_percent]) AS NUMERIC(5, 2))    AS [Avg Log Write Usage %],
       CAST(MAX([avg_log_write_percent]) AS NUMERIC(5, 2))    AS [Max Log Write Usage %],
       CAST(AVG([avg_memory_usage_percent]) AS NUMERIC(5, 2)) AS [Avg Memory Usage %],
       CAST(MAX([avg_memory_usage_percent]) AS NUMERIC(5, 2)) AS [Max Memory Usage %]
FROM   sys.[dm_db_resource_stats]
WHERE  [end_time] >= DATEADD(MINUTE, -5, @MaxEndTime)
UNION
SELECT DATEADD(SECOND, -15, MIN([end_time]))                  AS [Sample start],
       MAX([end_time])                                        AS [Sample end],
	   DATEDIFF(MINUTE, MIN([end_time]), MAX([end_time]))     AS [Sample(Minutes)],
       CAST(AVG([avg_cpu_percent]) AS NUMERIC(5, 2))          AS [Avg CPU Usage %],
       CAST(MAX([avg_cpu_percent]) AS NUMERIC(5, 2))          AS [Max CPU Usage %],
       CAST(AVG([avg_data_io_percent]) AS NUMERIC(5, 2))      AS [Avg Data IO %],
       CAST(MAX([avg_data_io_percent]) AS NUMERIC(5, 2))      AS [Max Data IO %],
       CAST(AVG([avg_log_write_percent]) AS NUMERIC(5, 2))    AS [Avg Log Write Usage %],
       CAST(MAX([avg_log_write_percent]) AS NUMERIC(5, 2))    AS [Max Log Write Usage %],
       CAST(AVG([avg_memory_usage_percent]) AS NUMERIC(5, 2)) AS [Avg Memory Usage %],
       CAST(MAX([avg_memory_usage_percent]) AS NUMERIC(5, 2)) AS [Max Memory Usage %]
FROM   sys.[dm_db_resource_stats]
WHERE  [end_time] >= DATEADD(MINUTE, -1, @MaxEndTime)
ORDER  BY 1 DESC
OPTION(RECOMPILE); 


/*top 10 waits since startup*/
DECLARE @StartTime DATETIME;

SELECT @StartTime = [sqlserver_start_time]
FROM   sys.[dm_os_sys_info];

WITH [WaitsAgg]
     AS (SELECT TOP 10 [wait_type],
                       [wait_time_ms] / 1000.00                             AS [wait_time_s],
                       ( [wait_time_ms] - [signal_wait_time_ms] ) / 1000.00 AS [resource_seconds],
                       [signal_wait_time_ms] / 1000.00                      AS [signal_wait_time_s],
                       [waiting_tasks_count],
                       100. * [wait_time_ms] / SUM([wait_time_ms])
                                                 OVER()                     AS [percent],
                       ROW_NUMBER()
                         OVER(
                           ORDER BY [wait_time_ms] DESC)                    AS [row_num]
         FROM   sys.[dm_db_wait_stats] WITH (NOLOCK))
SELECT @StartTime                                                                           AS [Sample start],
       GETDATE()                                                                            AS [Sample End],
       DATEDIFF(HOUR, @StartTime, GETDATE())                                                [Sample(Hours)],
       [wa1].[wait_type]                                                                    AS [Wait Type],
       [wa1].[waiting_tasks_count]                                                          AS [Wait Count],
       CAST([wa1].[percent] AS NUMERIC(5, 2))                                               AS [Wait %],
       CAST([wa1].[wait_time_s] AS NUMERIC(16, 2))                                          AS [Total Wait Time(Sec)],
       CAST(( [wa1].[wait_time_s] / [wa1].[waiting_tasks_count] ) AS NUMERIC(23, 3))        AS [Avg Wait Time(Sec)],
       CAST([wa1].[resource_seconds] AS NUMERIC(16, 2))                                     AS [Total Resource Time(Sec)],
       CAST(( [wa1].[resource_seconds] / [wa1].[waiting_tasks_count] ) AS NUMERIC(23, 3))   AS [Avg Resource Time(Sec)],
       CAST([wa1].[signal_wait_time_s] AS NUMERIC(23, 3))                                   AS [Total Signal Time(Sec)],
       CAST(( [wa1].[signal_wait_time_s] / [wa1].[waiting_tasks_count] ) AS NUMERIC(23, 3)) AS [Avg Signal Time(Sec)],
       N'https://www.sqlskills.com/help/waits/'
       + LOWER([wa1].[wait_type]) + N'/'                                                    AS [URL]
FROM   [WaitsAgg] AS [wa1]
       INNER JOIN [WaitsAgg] AS [wa2]
               ON [wa2].[row_num] <= [wa1].[row_num]
GROUP  BY [wa1].[row_num],
          [wa1].[wait_type],
          [wa1].[waiting_tasks_count],
          [wa1].[percent],
          [wa1].[wait_time_s],
          [wa1].[resource_seconds],
          [wa1].[signal_wait_time_s]
ORDER  BY [Wait %] DESC
OPTION (RECOMPILE); 


/*database files details*/
SELECT DB_NAME()                                                                                                                                  AS [Database],
       [f].[file_id]                                                                                                                              AS [FileID],
       [f].[name]                                                                                                                                 AS [File Logical Name],
       [f].[physical_name]                                                                                                                        AS [File Physical Name],
       [f].[type_desc]                                                                                                                            AS [File Type],
       [state_desc]                                                                                                                               AS [State],
       CAST(( CAST([f].[size] AS BIGINT) * 8 / 1024.00 / 1024.00 ) AS NUMERIC(23, 3))                                                             AS [SizeGB],
       CAST(( ( CAST([f].[size] AS BIGINT) - CAST(FILEPROPERTY([f].[name], 'SpaceUsed') AS BIGINT) ) * 8 / 1024.00 / 1024.00 ) AS NUMERIC(23, 3)) AS [Available SpaceGB],
       CASE
         WHEN [max_size] = 0
               OR [growth] = 0 THEN 'File autogrowth is disabled'
         WHEN [max_size] = -1
              AND [growth] > 0 THEN 'Unlimited'
         WHEN [max_size] > 0 THEN CAST(CAST (CAST([max_size] AS BIGINT) * 8 / 1024.00 / 1024.00 AS NUMERIC(23, 3)) AS VARCHAR(20))
       END                                                                                                                                        AS [Max File SizeGB],
       CASE
         WHEN [is_percent_growth] = 1 THEN CAST([growth] AS NVARCHAR(2)) + N' %'
         WHEN [is_percent_growth] = 0 THEN CAST(CAST(CAST([growth] AS BIGINT)*8/1024.00/1024.00 AS NUMERIC(23, 3)) AS VARCHAR(20))
                                           + ' GB'
       END                                                                                                                                        AS [Growth Increment]
FROM   sys.[database_files] AS [f]
OPTION(RECOMPILE);

/* Objects that might be impacted by a version change

*/
SELECT [oi].[class_desc] AS [Object Type],
       [ob].[name] AS [Object Name],
       [ix].[name] AS [Index Name],
       [oi].[dependency] AS [Dependency]
FROM   sys.[dm_db_objects_impacted_on_version_change] AS [oi]
       INNER JOIN sys.[objects] AS [ob]
               ON [oi].[major_id] = [ob].[object_id]
       LEFT JOIN sys.[indexes] AS [ix]
              ON [oi].[minor_id] = [ix].[index_id]; 

 /*Database scoped config*/
SELECT [name] AS [Config Name],
       CASE
         WHEN [value] = 0
              AND [name] <> N'MAXDOP' THEN 'Off'
         WHEN [value] = 1 THEN 'On'
		 WHEN CAST([value] AS VARCHAR(3)) IN ('OFF', 'ON')
		 THEN REPLACE(REPLACE(CAST([value] AS VARCHAR(3)),'FF','ff'),'N','n')
         ELSE [value]
       END AS [Value],
       CASE
         WHEN [is_value_default] = 1 THEN 'Yes'
         ELSE 'No'
       END AS [IsDefault]
FROM   sys.[database_scoped_configurations]; 