/*
	Part of PSBlitz - https://github.com/VladDBA/PSBlitz
	License - https://github.com/VladDBA/PSBlitz/blob/main/LICENSE
*/
/*Index Fragmentation Info*/
USE [..PSBlitzReplace..];

SET NOCOUNT ON;
SET STATISTICS XML OFF;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

      SELECT DB_NAME()                                                              AS [database],
             SCHEMA_NAME([obj].[schema_id]) + '.'
             + [obj].[name]                                                         AS [object_name],
             [obj].[type_desc]                                                      AS [object_type],
             ISNULL([ix].[name], '')                                                AS [index_name],
             [ips].[index_type_desc]                                                AS [index_type],
             SUM(CAST([ips].[avg_fragmentation_in_percent] AS DECIMAL(5, 2)))       AS [avg_frag_percent],
             SUM([ips].[page_count]) AS [page_count],
             CAST(( CAST(SUM([ips].[page_count]) AS BIGINT) * 8 ) / 1024.00 / 1024.00 AS NUMERIC(20, 2)) AS [size_in_GB],
             SUM(CASE WHEN [ips].[alloc_unit_type_desc] = N'IN_ROW_DATA' THEN CAST([ips].[record_count] AS BIGINT) ELSE 0 END) AS [record_count],
			 SUM([ips].[forwarded_record_count]) AS [forwarded_record_count]
      FROM   [sys].[indexes] AS [ix] 
             INNER JOIN [sys].[objects] AS [obj]
                     ON [ix].[object_id] = [obj].[object_id]
             CROSS APPLY [sys].[dm_db_index_physical_stats](DB_ID(), [obj].[object_id], [ix].[index_id], NULL, 'SAMPLED') AS [ips]
      WHERE   [ix].[type] IN(0, 1,2,3,4,5,6,7)
			 AND [obj].[name] <> N'BlitzWho_AzureSQLDBReplace'
			 AND [obj].[type] in ('U', 'V')
             --AND [ips].[avg_fragmentation_in_percent] > 0
             /*only tables larger than ~400MB */
             --AND [ips].[page_count] >= 52000
			 AND obj.object_id not in 
			 (SELECT l.resource_associated_entity_id 
      FROM   sys.dm_tran_locks l
      WHERE  l.request_mode = N'X'
             AND l.request_type = N'LOCK'
             AND l.resource_type = N'OBJECT'
             AND l.resource_database_id = DB_ID()
      GROUP  BY l.resource_database_id,
                l.resource_associated_entity_id)
	  GROUP BY SCHEMA_NAME([obj].[schema_id]) + '.'
             + [obj].[name],  [obj].[type_desc], [ix].[name] ,  [ips].[index_type_desc] 
      ORDER  BY SUM(CAST([ips].[avg_fragmentation_in_percent] AS DECIMAL(5, 2))) DESC;


      SELECT 'Exclusive Lock'                             AS [xlocked],
             OBJECT_NAME(l.resource_associated_entity_id) AS [object_name]
      FROM   sys.dm_tran_locks l
      WHERE  l.request_mode = N'X'
             AND l.request_type = N'LOCK'
             AND l.resource_type = N'OBJECT'
             AND l.resource_database_id = DB_ID()
      GROUP  BY l.resource_database_id,
                l.resource_associated_entity_id;