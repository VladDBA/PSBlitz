/*Index Fragmentation Info*/
USE [..PSBlitzReplace..];

SET NOCOUNT ON;
SET STATISTICS XML OFF;

IF EXISTS (SELECT 1
           FROM   sys.dm_tran_locks AS l
           WHERE  l.request_mode = N'X'
                  AND l.request_type = N'LOCK'
                  AND l.resource_type = N'OBJECT'
                  AND l.resource_database_id = DB_ID())
  BEGIN
      SELECT 'Exclusive Lock'                             AS [xlocked],
             OBJECT_NAME(l.resource_associated_entity_id) AS [object_name]
      FROM   sys.dm_tran_locks l
      WHERE  l.request_mode = N'X'
             AND l.request_type = N'LOCK'
             AND l.resource_type = N'OBJECT'
             AND l.resource_database_id = DB_ID()
      GROUP  BY l.resource_database_id,
                l.resource_associated_entity_id
  END
ELSE
  BEGIN
      SELECT DB_NAME()                                                              AS [database],
             SCHEMA_NAME([obj].[schema_id]) + '.'
             + [obj].[name]                                                         AS [object_name],
             [obj].[type_desc]                                                      AS [object_type],
             [ix].[name]                                                            AS [index_name],
             [ips].[index_type_desc]                                                AS [index_type],
             CAST([ips].[avg_fragmentation_in_percent] AS DECIMAL(5, 2))            AS [avg_frag_percent],
             [ips].[page_count],
             CAST(( [ips].[page_count] * 8 ) / 1024.00 / 1024.00 AS NUMERIC(20, 2)) AS [size_in_GB],
             [ips].[record_count]
      FROM   [sys].[dm_db_index_physical_stats](DB_ID(), NULL, NULL, NULL, 'SAMPLED') AS [ips]
             INNER JOIN [sys].[objects] AS [obj]
                     ON [ips].[object_id] = [obj].[object_id]
             INNER JOIN [sys].[indexes] AS [ix]
                     ON [ix].[object_id] = [ips].[object_id]
                        AND [ips].[index_id] = [ix].[index_id]
      WHERE  [ips].[database_id] = DB_ID()
             AND [ix].[name] IS NOT NULL
             AND [ips].[avg_fragmentation_in_percent] > 0
             /*only tables bigger than ~400MB */
             AND [ips].[page_count] >= 52000
      ORDER  BY [ips].[avg_fragmentation_in_percent] DESC;
  END; 