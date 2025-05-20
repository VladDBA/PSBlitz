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
SET NOCOUNT ON;

DECLARE @TimeOfCheck DATETIME = GETDATE();

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT COUNT([file_id])                                                                                                             AS [data_files],
       CAST(SUM([total_page_count]) * 1.0 / 128 AS DECIMAL(15, 2))                                                                  AS [total_size_MB],
       CAST(SUM([unallocated_extent_page_count]) * 1.0 / 128 AS DECIMAL(15, 2))                                                     AS [free_space_MB],
       CAST((SUM([unallocated_extent_page_count]) * 1.0 / 128 ) * 100 / (SUM([total_page_count]) * 1.0 / 128 ) AS DECIMAL(15, 2))   AS [percent_free],
       CAST(SUM([internal_object_reserved_page_count]) * 1.0 / 128 AS DECIMAL(15, 2))                                               AS [internal_objects_MB],
       CAST(SUM([user_object_reserved_page_count]) * 1.0 / 128 AS DECIMAL(15, 2))                                                   AS [user_objects_MB],
       CAST(SUM([version_store_reserved_page_count]) * 1.0 / 128 AS DECIMAL(15, 2))                                                 AS [version_store_MB]
FROM   [tempdb].[sys].[dm_db_file_space_usage];

SELECT TOP(30) [tb].[name]                                             AS [table_name],
       [pst].[row_count]                                               AS [rows],
       CAST([pst].[used_page_count] * 1.0 / 128 AS DECIMAL(15, 2))     AS [used_space_MB],
       CAST([pst].[reserved_page_count] * 1.0 / 128 AS DECIMAL(15, 2)) AS [reserved_space_MB],
	   CONVERT(VARCHAR(25), [tb].[create_date], 121)                   AS [created],
	   DATEDIFF(MINUTE,[tb].[create_date],@TimeOfCheck)                AS [table_lifespan_minutes],
	   CONVERT(VARCHAR(25), @TimeOfCheck, 121)                         AS [time_of_check]
FROM   [tempdb].[sys].[partitions] AS [prt]
       INNER JOIN [tempdb].[sys].[dm_db_partition_stats] AS [pst]
               ON [prt].[partition_id] = [pst].[partition_id]
                  AND [prt].[partition_number] = [pst].[partition_number]
       INNER JOIN [tempdb].[sys].[tables] AS [tb]
               ON [pst].[object_id] = [tb].[object_id]
/*Ignoring current BlitzWho output table*/			   
WHERE [tb].[name] <> N'BlitzWho_..PSBlitzReplace..'
ORDER  BY [reserved_space_MB] DESC;

SELECT TOP(30) [tsu].[session_id],
               [tsu].[request_id],
			   CAST('' AS VARCHAR(20)) AS [query],
               DB_NAME([tsu].[database_id]) AS [database],
               CAST([tsu].[user_objects_alloc_page_count] / 128 AS DECIMAL(15, 2))                                                                                                   [total_allocation_user_objects_MB],
               CAST(( [tsu].[user_objects_alloc_page_count] - [tsu].[user_objects_dealloc_page_count] ) / 128 AS DECIMAL(15, 2))                                                     [net_allocation_user_objects_MB],
               CAST([tsu].[internal_objects_alloc_page_count] / 128 AS DECIMAL(15, 2))                                                                                               [total_allocation_internal_objects_MB],
               CAST(( [tsu].[internal_objects_alloc_page_count] - [tsu].[internal_objects_dealloc_page_count] ) / 128 AS DECIMAL(15, 2))                                             [net_allocation_internal_objects_MB],
               CAST(( [tsu].[user_objects_alloc_page_count]
                      + [tsu].[internal_objects_alloc_page_count] ) / 128 AS DECIMAL(15, 2))                                                                                         [total_allocation_MB],
               CAST(( [tsu].[user_objects_alloc_page_count]
                      + [tsu].[internal_objects_alloc_page_count] - [tsu].[internal_objects_dealloc_page_count] - [tsu].[user_objects_dealloc_page_count] ) / 128 AS DECIMAL(15, 2)) [net_allocation_MB],
               [t].[text]                                                                                                                                                            [query_text],
               CONVERT(VARCHAR(256),[er].[query_hash],1) AS [query_hash],
               CONVERT(VARCHAR(256),[er].[query_plan_hash],1) AS [query_plan_hash]
FROM   [sys].[dm_db_task_space_usage] [tsu]
       INNER JOIN [sys].[dm_exec_requests] [er]
               ON [er].[request_id] = [tsu].[request_id]
                  AND [er].session_id = [tsu].[session_id]
       OUTER APPLY [sys].[dm_exec_sql_text]([er].[sql_handle]) AS [t]
WHERE  [tsu].[session_id] > 50
       AND ( [tsu].[user_objects_alloc_page_count] > 0
              OR [tsu].[internal_objects_alloc_page_count] > 0 )
ORDER  BY [total_allocation_MB] DESC; 