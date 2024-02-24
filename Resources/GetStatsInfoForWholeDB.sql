/*
	Part of PSBlitz - https://github.com/VladDBA/PSBlitz
	License - https://github.com/VladDBA/PSBlitz/blob/main/LICENSE
*/
/*Stats Info*/
USE [..PSBlitzReplace..];

SET NOCOUNT ON;
SET STATISTICS XML OFF;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @SQL NVARCHAR(MAX);
DECLARE @LineFeed NVARCHAR(5);
DECLARE @MinRecords INT;
SET @LineFeed = CHAR(13) + CHAR(10);

SET @MinRecords = 10000;

SELECT @SQL = 
N'SELECT DB_NAME() AS [database],'
+ @LineFeed + N'SCHEMA_NAME([obj].[schema_id]) + ''.'''
+ @LineFeed + N'+ [obj].[name] AS [object_name],'
+ @LineFeed + N'[obj].[type_desc] AS [object_type],'
+ @LineFeed + N'[stat].[name] AS [stats_name],'
+ @LineFeed + N'CASE WHEN [stat].[auto_created] = 1 '
+ N'AND [stat].[user_created] = 0 THEN ''Auto-Created'''
+ @LineFeed + N'WHEN [stat].[user_created] = 1 '
+ N'AND [stat].[auto_created] = 0 THEN ''User-Created'''
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
+ @LineFeed + N'CASE WHEN [stat].[is_incremental] = 1 THEN ''Yes'''
+ @LineFeed + N'ELSE ''No'' END AS [incremental],'
+ @LineFeed + N'CASE WHEN [stat].[is_temporary] = 1 THEN ''Yes'''
+ @LineFeed + N'ELSE ''No'' END AS [temporary],'
+ @LineFeed + N'CASE WHEN [stat].[no_recompute] = 1 THEN ''Yes'''
+ @LineFeed + N'ELSE ''No'' END AS [no_recompute],'
+ CASE WHEN CAST(ISNULL(SERVERPROPERTY('ProductMajorVersion'),0) AS TINYINT) >= 15
OR CAST(SERVERPROPERTY('Edition') AS NVARCHAR(50)) = 'SQL Azure'
  THEN @LineFeed + N'CASE WHEN [stat].[has_persisted_sample]  = 1 THEN ''Yes'''
  + @LineFeed + N'ELSE ''No'' END AS [persisted_sample],'
  ELSE @LineFeed + N'''only available for 2019 and above'' AS [persisted_sample],'
END
+ CASE WHEN CAST(ISNULL(SERVERPROPERTY('ProductMajorVersion'),0) AS TINYINT) >= 13 
OR CAST(SERVERPROPERTY('Edition') AS NVARCHAR(50)) = 'SQL Azure'
THEN  @LineFeed + N'[sp].[persisted_sample_percent],'
  ELSE @LineFeed + N'0 AS [persisted_sample_percent],'
END
+ @LineFeed + N'ISNULL([sp].[steps],0) AS [steps],'
+ @LineFeed + N'''No'' AS [partitioned], 1 AS [partition_number]' 
+ @LineFeed + N',''DBCC SHOW_STATISTICS ("''+SCHEMA_NAME([obj].[schema_id])+N''.'''
+'+[obj].[name]+N''", ''+[stat].[name]+N'');'' AS [get_details]'
+ @LineFeed + N'FROM   [sys].[stats] AS [stat]'
+ @LineFeed + N'CROSS APPLY [sys].[dm_db_stats_properties]([stat].[object_id],'
+ @LineFeed + N'[stat].[stats_id]) AS [sp]'
+ @LineFeed + N'INNER JOIN [sys].[objects] AS [obj]'
+ @LineFeed + N'ON [stat].[object_id] = [obj].[object_id]'
+ @LineFeed + N'WHERE'
+ @LineFeed + N'[obj].[type] IN ( ''U'', ''V'' )'	/*limit objects to tables and potentially indexed views*/
+ @LineFeed + CASE WHEN CAST(ISNULL(SERVERPROPERTY('ProductMajorVersion'),0) AS TINYINT) > 11
				THEN N'AND [stat].[is_incremental] = 0'
				ELSE N'' END						/*limit to non-incremental stats only */
+ @LineFeed + N'AND [sp].[rows] >= ' + CAST(@MinRecords AS NVARCHAR(10))
+ CASE WHEN CAST(ISNULL(SERVERPROPERTY('ProductMajorVersion'),0) AS TINYINT) > 11
				THEN + @LineFeed + N'UNION'
+ @LineFeed + N'SELECT DB_NAME() AS [database],'
+ @LineFeed + N'SCHEMA_NAME([obj].[schema_id]) + ''.'''
+ @LineFeed + N'+ [obj].[name] AS [object_name],'
+ @LineFeed + N'[obj].[type_desc] AS [object_type],'
+ @LineFeed + N'[stat].[name] AS [stats_name],'
+ @LineFeed + N'CASE WHEN [stat].[auto_created] = 1 '
+ N'AND [stat].[user_created] = 0 THEN ''Auto-Created'''
+ @LineFeed + N'WHEN [stat].[user_created] = 1 '
+ N'AND [stat].[auto_created] = 0 THEN ''User-Created'''
+ @LineFeed + N'  ELSE ''Index'' END AS [origin],'
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
+ @LineFeed + N'CASE WHEN [stat].[is_incremental] = 1 THEN ''Yes'' '
+ @LineFeed + N'ELSE ''No'' END AS [incremental],'
+ @LineFeed + N'CASE WHEN [stat].[is_temporary] = 1 THEN ''Yes'' '
+ @LineFeed + N'ELSE ''No'' END AS [temporary],'
+ @LineFeed + N'CASE WHEN [stat].[no_recompute] = 1 THEN ''Yes'''
+ @LineFeed + N'ELSE ''No'' END AS [no_recompute],'
+ CASE WHEN CAST(ISNULL(SERVERPROPERTY('ProductMajorVersion'),0) AS TINYINT) >= 15
OR CAST(SERVERPROPERTY('Edition') AS NVARCHAR(50)) = 'SQL Azure'
  THEN @LineFeed + N'CASE WHEN [stat].[has_persisted_sample]  = 1 THEN ''Yes'''
  + @LineFeed + N'ELSE ''No'' END AS [persisted_sample],'
  ELSE @LineFeed + N'''only available for 2019 and above'' AS [persisted_sample],'
END
+ @LineFeed + N'0 AS [persisted_sample_percent],'
+ @LineFeed + N'ISNULL([sip].[steps],0) AS [steps],'
+ @LineFeed + N'''Yes'' AS [partitioned],'
+ @LineFeed + N'[sip].[partition_number]'
+ @LineFeed + N',''DBCC SHOW_STATISTICS ("''+SCHEMA_NAME([obj].[schema_id])+N''.'''
+'+[obj].[name]+N''", ''+[stat].[name]+N'');'' AS [get_details]'
+ @LineFeed + N'FROM [sys].[stats] AS [stat]'
+ @LineFeed + N'CROSS APPLY [sys].[dm_db_incremental_stats_properties]([stat].[object_id],'
+ @LineFeed + N'[stat].[stats_id]) AS [sip]'
+ @LineFeed + N'INNER JOIN [sys].[objects] AS [obj]'
+ @LineFeed + N'ON [stat].[object_id] = [obj].[object_id]'
+ @LineFeed + N'WHERE'
+ @LineFeed + N'[obj].[type] IN ( ''U'', ''V'' )'	/*limit objects to tables and potentially indexed views*/
+ @LineFeed + N'AND [stat].[is_incremental] = 1'	/*limit to incremental stats only */
+ @LineFeed + N'AND [sip].[rows] >= ' + CAST(@MinRecords AS NVARCHAR(10))
+ @LineFeed + N'ORDER BY [modified_percent] DESC OPTION(RECOMPILE);'
				ELSE 
				+ @LineFeed + N'ORDER BY [modified_percent] DESC OPTION(RECOMPILE);'
END;
BEGIN
	EXEC(@SQL);
END;