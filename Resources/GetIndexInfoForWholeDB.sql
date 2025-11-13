/*
	Part of PSBlitz - https://github.com/VladDBA/PSBlitz
	License - https://github.com/VladDBA/PSBlitz/blob/main/LICENSE
*/
/*Index Fragmentation Info*/
USE [..PSBlitzReplace..];

SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
SET STATISTICS XML OFF;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @SkipCheck BIT = 0;

SELECT @SkipCheck = CASE WHEN (SELECT CAST(SUM(CAST([size] AS BIGINT) * 8 / 1024. / 1024.) AS NUMERIC(23, 3))
         FROM   sys.[database_files] WHERE [type]= 0)> 500 THEN 1
         WHEN (SELECT COUNT(1) FROM sys.[partitions] WHERE [partition_number] > 1) >100 THEN 1
         WHEN (SELECT COUNT(1) FROM sys.[indexes] i INNER JOIN sys.[tables] t ON i.[object_id] = t.[object_id])>1000
         THEN 1 ELSE 0 END;
IF @SkipCheck = 1
  BEGIN
  SELECT 'Check skipped due to database size' AS Skipped;
  RETURN;
  END;
  ELSE
  BEGIN
IF OBJECT_ID('tempdb.dbo.#PSBlitzIXFrag', 'U') IS NOT NULL
    DROP TABLE #PSBlitzIXFrag;
SELECT [l].[resource_associated_entity_id]
INTO   #PSBlitzIXFrag
FROM   sys.[dm_tran_locks] [l]
WHERE  [l].[request_mode] = N'X'
       AND [l].[request_type] = N'LOCK'
       AND [l].[resource_type] = N'OBJECT'
       AND [l].[resource_database_id] = DB_ID()
GROUP  BY [l].[resource_database_id],
          [l].[resource_associated_entity_id]; 


SELECT TOP(20000) DB_NAME()                                                                   AS [database],
       SCHEMA_NAME([obj].[schema_id]) + '.'
       + [obj].[name]                                                                         AS [object_name],
	   [obj].[object_id],
       [obj].[type_desc]                                                                      AS [object_type],
       ISNULL([ix].[name], '')                                                                AS [index_name],
	   [ix].[index_id],
       [ips].[index_type_desc]                                                                AS [index_type],
       [ips].[partition_number],
       CAST([ips].[avg_fragmentation_in_percent] AS DECIMAL(5, 2))                            AS [avg_frag_percent],
       [ips].[page_count]                                                                     AS [page_count],
       CAST(( CAST([ips].[page_count] AS BIGINT) * 8 ) / 1024.00 / 1024.00 AS NUMERIC(20, 2)) AS [size_in_GB],
       SUM(CASE
             WHEN [ips].[alloc_unit_type_desc] = N'IN_ROW_DATA' THEN CAST([ips].[record_count] AS BIGINT)
             ELSE 0
           END)                                                                               AS [record_count],
       [ips].[forwarded_record_count]                                                         AS [forwarded_record_count]
FROM   [sys].[indexes] AS [ix]
       INNER JOIN [sys].[objects] AS [obj]
               ON [ix].[object_id] = [obj].[object_id]
       CROSS APPLY [sys].[dm_db_index_physical_stats](DB_ID(), [obj].[object_id], [ix].[index_id], NULL, 'SAMPLED') AS [ips]
WHERE  [ix].[type] IN( 0, 1, 2, 3,
                       4, 5, 6, 7 )
       AND [ix].[is_disabled] = 0
       AND [obj].[name] <> N'BlitzWho_AzureSQLDBReplace'
       AND [obj].[type] IN ( 'U', 'V' )
       /*AND [ips].[avg_fragmentation_in_percent] > 0*/
       /*only tables larger than ~400MB */
       AND [ips].[page_count] >= 52000
       AND [obj].[object_id] NOT IN (SELECT [resource_associated_entity_id]
                                 FROM   #PSBlitzIXFrag)
GROUP  BY SCHEMA_NAME([obj].[schema_id]) + '.'
          + [obj].[name],
		  [obj].[object_id],
          [obj].[type_desc],
          [ix].[name],
		  [ix].[index_id],
          [ips].[index_type_desc],
          [ips].[partition_number],
          [ips].[avg_fragmentation_in_percent],
          [ips].[page_count],
          [ips].[forwarded_record_count]
ORDER  BY [ips].[avg_fragmentation_in_percent] DESC, [size_in_GB] DESC;

SELECT 'Exclusive Lock'                           AS [xlocked],
       OBJECT_NAME([resource_associated_entity_id]) AS [object_name]
FROM   #PSBlitzIXFrag;

IF OBJECT_ID('tempdb.dbo.#test', 'U') IS NOT NULL
    DROP TABLE #PSBlitzIXFrag;
END;