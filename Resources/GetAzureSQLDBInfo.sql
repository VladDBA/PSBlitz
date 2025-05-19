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
       CAST([instance_max_log_rate] / 1024. / 1024. AS NUMERIC(23, 3))     AS [Instnace Max Log Rate MB/s],
       [instance_max_worker_threads]                                       AS [Instance Max Worker Threads],
       CASE
         WHEN [replica_type] = 0 THEN 'Primary'
         ELSE 'Secondary'
       END                                                                 AS [Replica Type],
       [max_transaction_size]                                              AS [Max TLog Space/Transaction(KB)],
       CONVERT(VARCHAR(25),[last_updated_date_utc],120)                    AS [Settings Last Changed],
       [primary_group_max_workers]                                         AS [User Workload Max Worker Threads],
       CAST([primary_min_log_rate] / 1024. / 1024. AS NUMERIC(23, 3))      AS [User Workload Min Log Rate MB/s],
       CAST([primary_max_log_rate] / 1024. / 1024. AS NUMERIC(23, 3))      AS [User Workload Max Log Rate MB/s],
       [primary_group_min_io]                                              AS [User Workload Min IOPS],
       [primary_group_max_io]                                              AS [User Workload Max IOPS],
       [primary_group_min_cpu]                                             AS [User Workload Min CPU%],
       [primary_group_max_cpu]                                             AS [User Workload Max CPU%],
       [primary_pool_max_workers]                                          AS [User Workload Max Worker Threads],
       [pool_max_io]                                                       AS [User Workload Pool Max IOPS ],
       [user_data_directory_space_quota_mb]                                AS [Max Local Storage(MB)],
       [user_data_directory_space_usage_mb]                                AS [Used Local Storage(MB)],
       CAST([pool_max_log_rate] / 1024. / 1024. AS NUMERIC(23, 3))         AS [Pool Max Log Rate MB/s],
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
                CAST(SUM(CAST([size] AS BIGINT) * 8 / 1024. / 1024.) AS NUMERIC(23, 3))
         FROM   sys.[database_files]
         WHERE  [type] = 2
         GROUP  BY [type])
SELECT DB_NAME()                                                                                                       AS [Database],
       DATABASEPROPERTYEX(DB_NAME(), 'ServiceObjective')                                                               AS [Service Objective],
       CONVERT(VARCHAR(25),[d].[create_date],120)                                                                      AS [Created],
       [d].[state_desc]                                                                                                AS [Database State],
       SUM(CASE
             WHEN [f].[type] = 0 THEN 1
             ELSE 0
           END)                                                                                                        AS [Data Files],
       CAST(SUM(CASE
                  WHEN [f].[type] = 0 THEN ( CAST([f].[size] AS BIGINT) * 8 / 1024. / 1024. )
                  ELSE 0.00
                END) AS NUMERIC(23, 3))                                                                                AS [Data Files Size GB],
       SUM(CASE
             WHEN [f].[type] = 1 THEN 1
             ELSE 0
           END)                                                                                                        AS [Log Files],
       CAST(SUM(CASE
                  WHEN [f].[type] = 1 THEN ( CAST([f].[size] AS BIGINT) * 8 / 1024. / 1024. )
                  ELSE 0.00
                END) AS NUMERIC(23, 3))                                                                                AS [Log Files Size GB],
       [l].[Virtual Log Files],
       ISNULL([fs].[FSFilesCount], 0)                                                                                  AS [FILESTREAM Containers],
       ISNULL([fs].[FSFilesSizeGB], 0.000)                                                                             AS [FS Containers Size GB],
       CAST(SUM(CAST([f].[size] AS BIGINT) * 8 / 1024. / 1024.) AS NUMERIC(23, 3))
       + ISNULL([fs].[FSFilesSizeGB], 0.000)                                                                           AS [Database Size GB],
       CAST(CAST(DATABASEPROPERTYEX(DB_NAME(), 'MaxSizeInBytes') AS BIGINT) / 1024. / 1024. / 1024. AS NUMERIC(23, 3)) AS [Database MaxSize GB],
       [d].[log_reuse_wait_desc]                                                                                       AS [Current Log Reuse Wait],
       [d].[compatibility_level]                                                                                       AS [Compatibility Level],
       [d].[page_verify_option_desc]                                                                                   AS [Page Verify Option],
       [d].[containment_desc]                                                                                          AS [Containment],
       [d].[collation_name]                                                                                            AS [Collation],
       [d].[snapshot_isolation_state_desc]                                                                             AS [Snapshot Isolation State],
       CASE
         WHEN [d].[is_read_committed_snapshot_on] = 1 THEN 'On'
         ELSE 'Off'
       END                                                                                                             AS [Read Committed Snapshot],
       [d].[recovery_model_desc]                                                                                       AS [Recovery Model],
       CASE
         WHEN [d].[is_auto_close_on] = 1 THEN 'On'
         ELSE 'Off'
       END                                                                                                             AS [Auto Close],
       CASE
         WHEN [d].[is_auto_shrink_on] = 1 THEN 'On'
         ELSE 'Off'
       END                                                                                                             AS [Auto Shrink],
       CASE
         WHEN [d].[is_query_store_on] = 1 THEN 'On'
         ELSE 'Off'
       END                                                                                                             AS [Query Store],
       CASE
         WHEN [d].[is_trustworthy_on] = 1 THEN 'On'
         ELSE 'Off'
       END                                                                                                             AS [Trustworthy]
FROM   sys.[database_files] AS [f]
       INNER JOIN sys.[databases] AS [d]
               ON DB_ID() = [d].[database_id]
       LEFT JOIN FSFiles AS [fs]
              ON DB_ID() = [fs].[database_id]
       CROSS APPLY (SELECT [file_id],
                           COUNT(*) AS [Virtual Log Files]
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
          [l].[Virtual Log Files]
OPTION (RECOMPILE); 

/*Database resource usage  
AVG and MAX in the past 64 minutes*/
DECLARE @MaxEndTime DATETIME;

SELECT @MaxEndTime = MAX([end_time])
FROM   sys.[dm_db_resource_stats];

SELECT CONVERT(VARCHAR(25),DATEADD(SECOND, -15, MIN([end_time])),120)   AS [Sample Start],
       CONVERT(VARCHAR(25),MAX([end_time]),120)                         AS [Sample End],
	   DATEDIFF(MINUTE, MIN([end_time]), MAX([end_time]))               AS [Sample(Minutes)],
       CAST(AVG([avg_cpu_percent]) AS NUMERIC(5, 2))                    AS [Avg CPU Usage %],
       CAST(MAX([avg_cpu_percent]) AS NUMERIC(5, 2))                    AS [Max CPU Usage %],
       CAST(AVG([avg_data_io_percent]) AS NUMERIC(5, 2))                AS [Avg Data IO %],
       CAST(MAX([avg_data_io_percent]) AS NUMERIC(5, 2))                AS [Max Data IO %],
       CAST(AVG([avg_log_write_percent]) AS NUMERIC(5, 2))              AS [Avg Log Write Usage %],
       CAST(MAX([avg_log_write_percent]) AS NUMERIC(5, 2))              AS [Max Log Write Usage %],
       CAST(AVG([avg_memory_usage_percent]) AS NUMERIC(5, 2))           AS [Avg Memory Usage %],
       CAST(MAX([avg_memory_usage_percent]) AS NUMERIC(5, 2))           AS [Max Memory Usage %]
FROM   sys.[dm_db_resource_stats]
UNION
SELECT CONVERT(VARCHAR(25),DATEADD(SECOND, -15, MIN([end_time])),120)   AS [Sample Start],
       CONVERT(VARCHAR(25),MAX([end_time]),120)                         AS [Sample End],
       DATEDIFF(MINUTE, MIN([end_time]), MAX([end_time]))               AS [Sample(Minutes)],
	   CAST(AVG([avg_cpu_percent]) AS NUMERIC(5, 2))                    AS [Avg CPU Usage %],
       CAST(MAX([avg_cpu_percent]) AS NUMERIC(5, 2))                    AS [Max CPU Usage %],
       CAST(AVG([avg_data_io_percent]) AS NUMERIC(5, 2))                AS [Avg Data IO %],
       CAST(MAX([avg_data_io_percent]) AS NUMERIC(5, 2))                AS [Max Data IO %],
       CAST(AVG([avg_log_write_percent]) AS NUMERIC(5, 2))              AS [Avg Log Write Usage %],
       CAST(MAX([avg_log_write_percent]) AS NUMERIC(5, 2))              AS [Max Log Write Usage %],
       CAST(AVG([avg_memory_usage_percent]) AS NUMERIC(5, 2))           AS [Avg Memory Usage %],
       CAST(MAX([avg_memory_usage_percent]) AS NUMERIC(5, 2))           AS [Max Memory Usage %]
FROM   sys.[dm_db_resource_stats]
WHERE  [end_time] >= DATEADD(MINUTE, -30, @MaxEndTime)
UNION
SELECT CONVERT(VARCHAR(25),DATEADD(SECOND, -15, MIN([end_time])),120)   AS [Sample Start],
       CONVERT(VARCHAR(25),MAX([end_time]),120)                         AS [Sample End],
	   DATEDIFF(MINUTE, MIN([end_time]), MAX([end_time]))               AS [Sample(Minutes)],
       CAST(AVG([avg_cpu_percent]) AS NUMERIC(5, 2))                    AS [Avg CPU Usage %],
       CAST(MAX([avg_cpu_percent]) AS NUMERIC(5, 2))                    AS [Max CPU Usage %],
       CAST(AVG([avg_data_io_percent]) AS NUMERIC(5, 2))                AS [Avg Data IO %],
       CAST(MAX([avg_data_io_percent]) AS NUMERIC(5, 2))                AS [Max Data IO %],
       CAST(AVG([avg_log_write_percent]) AS NUMERIC(5, 2))              AS [Avg Log Write Usage %],
       CAST(MAX([avg_log_write_percent]) AS NUMERIC(5, 2))              AS [Max Log Write Usage %],
       CAST(AVG([avg_memory_usage_percent]) AS NUMERIC(5, 2))           AS [Avg Memory Usage %],
       CAST(MAX([avg_memory_usage_percent]) AS NUMERIC(5, 2))           AS [Max Memory Usage %]
FROM   sys.[dm_db_resource_stats]
WHERE  [end_time] >= DATEADD(MINUTE, -15, @MaxEndTime)
UNION
SELECT CONVERT(VARCHAR(25),DATEADD(SECOND, -15, MIN([end_time])),120)   AS [Sample Start],
       CONVERT(VARCHAR(25),MAX([end_time]),120)                         AS [Sample End],
	   DATEDIFF(MINUTE, MIN([end_time]), MAX([end_time]))               AS [Sample(Minutes)],
       CAST(AVG([avg_cpu_percent]) AS NUMERIC(5, 2))                    AS [Avg CPU Usage %],
       CAST(MAX([avg_cpu_percent]) AS NUMERIC(5, 2))                    AS [Max CPU Usage %],
       CAST(AVG([avg_data_io_percent]) AS NUMERIC(5, 2))                AS [Avg Data IO %],
       CAST(MAX([avg_data_io_percent]) AS NUMERIC(5, 2))                AS [Max Data IO %],
       CAST(AVG([avg_log_write_percent]) AS NUMERIC(5, 2))              AS [Avg Log Write Usage %],
       CAST(MAX([avg_log_write_percent]) AS NUMERIC(5, 2))              AS [Max Log Write Usage %],
       CAST(AVG([avg_memory_usage_percent]) AS NUMERIC(5, 2))           AS [Avg Memory Usage %],
       CAST(MAX([avg_memory_usage_percent]) AS NUMERIC(5, 2))           AS [Max Memory Usage %]
FROM   sys.[dm_db_resource_stats]
WHERE  [end_time] >= DATEADD(MINUTE, -5, @MaxEndTime)
UNION
SELECT CONVERT(VARCHAR(25),DATEADD(SECOND, -15, MIN([end_time])),120)   AS [Sample Start],
       CONVERT(VARCHAR(25),MAX([end_time]),120)                         AS [Sample End],
	   DATEDIFF(MINUTE, MIN([end_time]), MAX([end_time]))               AS [Sample(Minutes)],
       CAST(AVG([avg_cpu_percent]) AS NUMERIC(5, 2))                    AS [Avg CPU Usage %],
       CAST(MAX([avg_cpu_percent]) AS NUMERIC(5, 2))                    AS [Max CPU Usage %],
       CAST(AVG([avg_data_io_percent]) AS NUMERIC(5, 2))                AS [Avg Data IO %],
       CAST(MAX([avg_data_io_percent]) AS NUMERIC(5, 2))                AS [Max Data IO %],
       CAST(AVG([avg_log_write_percent]) AS NUMERIC(5, 2))              AS [Avg Log Write Usage %],
       CAST(MAX([avg_log_write_percent]) AS NUMERIC(5, 2))              AS [Max Log Write Usage %],
       CAST(AVG([avg_memory_usage_percent]) AS NUMERIC(5, 2))           AS [Avg Memory Usage %],
       CAST(MAX([avg_memory_usage_percent]) AS NUMERIC(5, 2))           AS [Max Memory Usage %]
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
SELECT CONVERT(VARCHAR(25),@StartTime,120)                                                  AS [Sample Start],
       CONVERT(VARCHAR(25),GETDATE(),120)                                                   AS [Sample End],
       DATEDIFF(HOUR, @StartTime, GETDATE())                                                AS [Sample(Hours)],
       [wa1].[wait_type]                                                                    AS [Wait Type],
	   '<a href=''https://www.sqlskills.com/help/waits/' 
	   + LOWER([wa1].[wait_type]) + '/'' target=''_blank''>'+[wa1].[wait_type]+'</a>'       AS [Wait TypeHL],
       [wa1].[waiting_tasks_count]                                                          AS [Wait Count],
       CAST([wa1].[percent] AS NUMERIC(5, 2))                                               AS [Wait%],
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
ORDER  BY [Wait%] DESC
OPTION (RECOMPILE); 


/*database files details*/
SELECT DB_NAME()                                                                                                                              AS [database],
       [f].[file_id]                                                                                                                          AS [file_id],
       [f].[name]                                                                                                                             AS [file_logical_name],
       [f].[physical_name]                                                                                                                    AS [file_physical_name],
       CASE [f].[type]
         WHEN 0 THEN 'Data'
         WHEN 1 THEN 'Transaction Log'
         WHEN 2 THEN 'Filestream'
         WHEN 4 THEN 'Full-Text'
         ELSE [f].[type_desc]
       END                                                                                                                                    AS [file_type],
       [state_desc]                                                                                                                           AS [state],
       CAST(( CAST([f].[size] AS BIGINT) * 8 / 1024. / 1024. ) AS NUMERIC(23, 3))                                                             AS [size_GB],
       CAST(( ( CAST([f].[size] AS BIGINT) - CAST(FILEPROPERTY([f].[name], 'SpaceUsed') AS BIGINT) ) * 8 / 1024. / 1024. ) AS NUMERIC(23, 3)) AS [available_space_GB],
       CASE
         WHEN [ios].[num_of_bytes_read] > 0 THEN CAST([ios].[num_of_bytes_read] / 1024. / 1024. / 1024. AS NUMERIC(23, 3))
         ELSE 0
       END                                                                                                                                      AS [total_read_GB],
       [ios].[num_of_reads]                                                                                                                     AS [total_reads],
       [ios].[io_stall_read_ms]                                                                                                                 AS [total_read_stall_time(ms)],
       CASE
         WHEN [ios].[num_of_reads] = 0 THEN 0.000
         ELSE CAST([ios].[io_stall_read_ms] / CAST([ios].[num_of_reads] AS NUMERIC(38, 3)) AS NUMERIC(23, 3))
       END                                                                                                                                    AS [avg_read_stall(ms)],
       CASE
         WHEN [ios].[num_of_bytes_written] > 0 THEN CAST([ios].[num_of_bytes_written] / 1024. / 1024. / 1024. AS NUMERIC(23, 3))
         ELSE 0
       END                                                                                                                                    AS [total_written_GB],
       [ios].[num_of_writes]                                                                                                                    AS [total_writes],
       [ios].[io_stall_write_ms]                                                                                                                AS [total_write_stall_time(ms)],
       CASE
         WHEN [ios].[num_of_writes] = 0 THEN 0.000
         ELSE CAST([ios].[io_stall_write_ms] / CAST([ios].[num_of_writes] AS NUMERIC(38, 3)) AS NUMERIC(23, 3))
       END                                                                                                                                    AS [avg_write_stall(ms)],
       CASE
         WHEN [max_size] = 0
               OR [growth] = 0 THEN 'File autogrowth is disabled'
         WHEN [max_size] = -1
              AND [growth] > 0 THEN 'Unlimited'
         WHEN [max_size] > 0 THEN CAST(CAST (CAST([max_size] AS BIGINT) * 8 / 1024. / 1024. AS NUMERIC(23, 3)) AS VARCHAR(24))
       END                                                                                                                                    AS [max_file_size_GB],
       CASE
         WHEN [is_percent_growth] = 1 THEN CAST([growth] AS VARCHAR(2)) + ' %'
         WHEN [is_percent_growth] = 0 THEN CAST(CAST(CAST([growth] AS BIGINT)*8/1024./1024. AS NUMERIC(23, 3)) AS VARCHAR(24))
                                           + ' GB'
       END                                                                                                                                    AS [growth_increment]
FROM   sys.[database_files] AS [f]
       CROSS APPLY sys.[dm_io_virtual_file_stats](DB_ID(), [f].[file_id]) AS [ios]
OPTION(MAXDOP 1, RECOMPILE); 


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
              ON [oi].[minor_id] = [ix].[index_id]
OPTION(RECOMPILE);

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