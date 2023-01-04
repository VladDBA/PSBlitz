USE [..PSBlitzReplace..];

SET NOCOUNT ON;
DECLARE @SQL NVARCHAR(MAX);
DECLARE @LineFeed NVARCHAR(5);
SET @LineFeed = CHAR(13) + CHAR(10);

SELECT @SQL = 
N'SELECT DB_NAME() AS [database],'
+ @LineFeed + N'SCHEMA_NAME([obj].[schema_id]) + ''.'''
+ @LineFeed + N'+ [obj].[name] AS [object_name],'
+ @LineFeed + N'[obj].[type_desc] AS [object_type],'
+ @LineFeed + N'[stat].[name] AS [stats_name],'
+ @LineFeed + N'CASE WHEN [stat].[auto_created] = 1 THEN ''Auto-Created'''
+ @LineFeed + N'WHEN [stat].[auto_created] = 1 THEN ''User-Created'''
+ @LineFeed + N'  ELSE ''Index'' END AS [origin],'
+ @LineFeed + N'[stat].[filter_definition],'
+ @LineFeed + N'[sp].[last_updated],'
+ @LineFeed + N'ISNULL([sp].[rows],0) AS [rows],'
+ @LineFeed + N'ISNULL([sp].[unfiltered_rows],0) AS [unfiltered_rows],'
+ @LineFeed + N'ISNULL([sp].[rows_sampled],0) AS [rows_sampled],'
+ @LineFeed + N'CASE WHEN [sp].[rows] IS NULL THEN 0 ' 
+ @LineFeed + N'ELSE (CAST(CAST([sp].[rows_sampled] AS FLOAT)' 
+ @LineFeed + N'/ CAST([sp].[rows] AS FLOAT)' 
+ @LineFeed + N'* 100.00 AS DECIMAL(5,2))) END AS [sample_percent],'
+ @LineFeed + N'ISNULL([sp].[modification_counter],0) AS [modification_counter],'
+ @LineFeed + N'CASE WHEN [sp].[modification_counter] IS NULL THEN 0 ' 
+ @LineFeed + N'ELSE (CAST(CAST([sp].[modification_counter] AS FLOAT)' 
+ @LineFeed + N'/ CAST([sp].[rows] AS FLOAT)' 
+ @LineFeed + N'* 100.00 AS DECIMAL(38,2))) END AS [modified_percent],'
+ @LineFeed + N'ISNULL([sp].[steps],0) AS [steps],'
+ @LineFeed + N'''No'' AS [partitioned], 1 AS [partition_number]' 
+ @LineFeed + N'FROM   [sys].[stats] AS [stat]'
+ @LineFeed + N'CROSS APPLY [sys].[dm_db_stats_properties]([stat].[object_id],'
+ @LineFeed + N'[stat].[stats_id]) AS [sp]'
+ @LineFeed + N'INNER JOIN [sys].[objects] AS [obj]'
+ @LineFeed + N'ON [stat].[object_id] = [obj].[object_id]'
+ @LineFeed + N'WHERE'
+ @LineFeed + N'[obj].[type] IN ( ''U'', ''V'' )'		/*limit objects to tables and potentially indexed views*/
+ @LineFeed + CASE WHEN CAST(SERVERPROPERTY('ProductMajorVersion') AS TINYINT) > 11
				THEN N'AND [stat].[is_incremental] = 0'
				ELSE N'' END /*limit to non-incremental stats only */
+ @LineFeed + N'AND [sp].[rows] >= 1000'			/*only get tables with 1k rows or more*/
+ CASE WHEN CAST(SERVERPROPERTY('ProductMajorVersion') AS TINYINT) > 11
				THEN + @LineFeed + N'UNION'
+ @LineFeed + N'SELECT DB_NAME() AS [database],'
+ @LineFeed + N'SCHEMA_NAME([obj].[schema_id]) + ''.'''
+ @LineFeed + N'+ [obj].[name] AS [object_name],'
+ @LineFeed + N'[obj].[type_desc] AS [object_type],'
+ @LineFeed + N'[stat].[name] AS [stats_name],'
+ @LineFeed + N'CASE WHEN [stat].[auto_created] = 1 THEN ''Auto-Created'''
+ @LineFeed + N'WHEN [stat].[auto_created] = 1 THEN ''User-Created'''
+ @LineFeed + N'ELSE ''Index'' END AS [origin],'
+ @LineFeed + N'[stat].[filter_definition],'
+ @LineFeed + N'[sip].[last_updated],'
+ @LineFeed + N'ISNULL([sip].[rows],0) AS [rows],'
+ @LineFeed + N'ISNULL([sip].[unfiltered_rows],0) AS [unfiltered_rows],'
+ @LineFeed + N'ISNULL([sip].[rows_sampled],0) AS [rows_sampled],'
+ @LineFeed + N'CASE WHEN [sip].[rows] IS NULL THEN 0 ' 
+ @LineFeed + N'ELSE (CAST(CAST([sip].[rows_sampled] AS FLOAT)' 
+ @LineFeed + N'/ CAST([sip].[rows] AS FLOAT)' 
+ @LineFeed + N'* 100.00 AS DECIMAL(5,2)))' 
+ @LineFeed + N'END AS [sample_percent],'
+ @LineFeed + N'ISNULL([sip].[modification_counter],0)	AS [modification_counter],'
+ @LineFeed + N'CASE WHEN [sip].[modification_counter] IS NULL THEN 0 '
+ @LineFeed + N'ELSE (CAST(CAST([sip].[modification_counter] AS FLOAT)'
+ @LineFeed + N'/ CAST([sip].[rows] AS FLOAT)'
+ @LineFeed + N'* 100.00 AS DECIMAL(5,2)))'
+ @LineFeed + N'END AS [modified_percent],'
+ @LineFeed + N'ISNULL([sip].[steps],0) AS [steps],'
+ @LineFeed + N'''Yes'' AS [partitioned],'
+ @LineFeed + N'[sip].[partition_number]'
+ @LineFeed + N'FROM [sys].[stats] AS [stat]'
+ @LineFeed + N'CROSS APPLY [sys].[dm_db_incremental_stats_properties]([stat].[object_id],'
+ @LineFeed + N'[stat].[stats_id]) AS [sip]'
+ @LineFeed + N'INNER JOIN [sys].[objects] AS [obj]'
+ @LineFeed + N'ON [stat].[object_id] = [obj].[object_id]'
+ @LineFeed + N'WHERE'
+ @LineFeed + N'[obj].[type] IN ( ''U'', ''V'' )'		/*limit objects to tables and potentially indexed views*/
+ @LineFeed + N'AND [stat].[is_incremental] = 1'	/*limit to incremental stats only */
+ @LineFeed + N'AND [sip].[rows] >= 1000'			/*only get tables with 1k rows or more*/
+ @LineFeed + N'ORDER BY [modified_percent] DESC;'
ELSE ';'
END
BEGIN
	EXEC(@SQL);
END

/*Index Fragmentation Info*/

SELECT DB_NAME()											AS [database],
       SCHEMA_NAME([obj].[schema_id]) + '.' + [obj].[name]	AS [object_name],
       [obj].[type_desc]									AS [object_type],
       [ix].[name]											AS [index_name],
	   [ips].[index_type_desc]								AS [index_type],
       CAST([ips].[avg_fragmentation_in_percent] AS 
		DECIMAL(5,2))										AS [avg_frag_percent],
       [ips].[page_count],
	   [ips].[record_count]
FROM   [sys].[dm_db_index_physical_stats](DB_ID(),
                                      NULL,
                                      NULL,
                                      NULL,
                                      'SAMPLED') AS [ips]
       INNER JOIN [sys].[objects] AS [obj]
               ON [ips].[object_id] = [obj].[object_id]
       INNER JOIN [sys].[indexes] AS [ix]
               ON [ix].[object_id] = [ips].[object_id]
                  AND [ips].[index_id] = [ix].[index_id]
WHERE
  [ips].[database_id] = DB_ID()
  AND [ix].[name] IS NOT NULL
  AND [ips].[avg_fragmentation_in_percent] > 0
ORDER  BY
  [ips].[avg_fragmentation_in_percent] DESC;