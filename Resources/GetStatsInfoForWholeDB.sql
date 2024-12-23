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
DECLARE @Comment NVARCHAR(3);
SET @LineFeed = CHAR(13) + CHAR(10);
SET @Comment = N';--';

SET @MinRecords = 10000;
/*Make sure temp table doesn't exist*/
IF OBJECT_ID('tempdb.dbo.##PSBlitzStatsInfo', 'U') IS NOT NULL
    DROP TABLE ##PSBlitzStatsInfo;
/*Create temp table */
CREATE TABLE ##PSBlitzStatsInfo
  (
     [id]                       INT IDENTITY(1, 1) NOT NULL PRIMARY KEY CLUSTERED,
     [database]                 NVARCHAR(128) NULL,
	 [object_schema] NVARCHAR(128) NULL,
     [object_name]              NVARCHAR(257) NULL,
     [object_type]              NVARCHAR(60) NULL,
     [stats_name]               NVARCHAR(128) NULL,
	 [stat_id] INT NULL,
     [origin]                   NVARCHAR(12) NOT NULL,
     [filter_definition]        NVARCHAR(MAX) NULL,
     [last_updated]             DATETIME2(7) NULL,
     [rows]                     BIGINT NOT NULL,
     [unfiltered_rows]          BIGINT NOT NULL,
     [rows_sampled]             BIGINT NOT NULL,
     [sample_percent]           DECIMAL(5, 2) NULL,
     [modification_counter]     BIGINT NOT NULL,
     [modified_percent]         DECIMAL(38, 2) NULL,
     [incremental]              NVARCHAR(3) NOT NULL,
     [temporary]                NVARCHAR(3) NOT NULL,
     [no_recompute]             NVARCHAR(3) NOT NULL,
     [persisted_sample]         NVARCHAR(3) NOT NULL,
     [persisted_sample_percent] FLOAT NULL,
     [steps]                    INT NOT NULL,
     [partitioned]              NVARCHAR(40) NOT NULL,
     [partition_number]         INT NULL,
     [get_details]              NVARCHAR(1000) NULL,
     [update_table_stats]       NVARCHAR(1000) NULL,
     [update_individual_stats]  NVARCHAR(1000) NULL,
     [update_partition_stats]   NVARCHAR(1000) NULL
  );
 /*Load stats data into temp table*/ 

SELECT @SQL = CAST(N'INSERT INTO ##PSBlitzStatsInfo ([database], [object_schema], [object_name], ' AS NVARCHAR(MAX))
+ @LineFeed + N'[object_type], [stats_name], [stat_id], [origin], [filter_definition], [last_updated], '
+ @LineFeed + N'[rows], [unfiltered_rows], [rows_sampled], [sample_percent], [modification_counter],'
+ @LineFeed + N'[modified_percent], [incremental], [temporary], [no_recompute], '
+ @LineFeed + N'[persisted_sample], [persisted_sample_percent], [steps], '
+ @LineFeed + N'[partitioned], [partition_number], [get_details])'
+ @LineFeed + N'SELECT DB_NAME() AS [database],'
+ @LineFeed + N'SCHEMA_NAME([obj].[schema_id]) AS [object_schema],'
+ @LineFeed + N'[obj].[name] AS [object_name],'
+ @LineFeed + N'[obj].[type_desc] AS [object_type],'
+ @LineFeed + N'[stat].[name] AS [stats_name],'
+ @LineFeed + N'[stat].[stats_id],'
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
+ @LineFeed + N',N''DBCC SHOW_STATISTICS ("''+SCHEMA_NAME([obj].[schema_id])+N''.'''
+ N'+[obj].[name]+N''", ''+[stat].[name]+N'');'' AS [get_details]'
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
+ @LineFeed + N'SCHEMA_NAME([obj].[schema_id]) AS [object_schema],'
+ @LineFeed + N'[obj].[name] AS [object_name],'
+ @LineFeed + N'[obj].[type_desc] AS [object_type],'
+ @LineFeed + N'[stat].[name] AS [stats_name],'
+ @LineFeed + N'[stat].[stats_id],'
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
+ @LineFeed + N'* 100.00 AS DECIMAL(38,2)))'
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
+ @LineFeed + N',N''DBCC SHOW_STATISTICS ("''+SCHEMA_NAME([obj].[schema_id])+N''.'''
+ N'+[obj].[name]+N''", ''+[stat].[name]+N'');'' AS [get_details]'
+ @LineFeed + N'FROM [sys].[stats] AS [stat]'
+ @LineFeed + N'CROSS APPLY [sys].[dm_db_incremental_stats_properties]([stat].[object_id],'
+ @LineFeed + N'[stat].[stats_id]) AS [sip]'
+ @LineFeed + N'INNER JOIN [sys].[objects] AS [obj]'
+ @LineFeed + N'ON [stat].[object_id] = [obj].[object_id]'
+ @LineFeed + N'WHERE'
+ @LineFeed + N'[obj].[type] IN ( ''U'', ''V'' )'	/*limit objects to tables and potentially indexed views*/
+ @LineFeed + N'AND [stat].[is_incremental] = 1'	/*limit to incremental stats only */
+ @LineFeed + N'AND [sip].[rows] >= ' + CAST(@MinRecords AS NVARCHAR(10))
		ELSE N''
END
+ @LineFeed + N'ORDER BY [modified_percent] DESC, [stat].[stats_id] ASC OPTION(RECOMPILE);';
BEGIN
	EXEC(@SQL)
END;

UPDATE ##PSBlitzStatsInfo
SET    [update_table_stats] = CASE
                                WHEN [modified_percent] >= 30.00 OR [sample_percent] < 5.00 THEN N'UPDATE STATISTICS '
                                                                      + QUOTENAME([database]) + N'.'
                                                                      + QUOTENAME([object_schema]) + N'.'
                                                                      + QUOTENAME([object_name])
                                                                      + CASE WHEN [persisted_sample_percent] = 0 THEN
                                                                          CASE WHEN [rows] <= 20000000 THEN @Comment + N' WITH FULLSCAN;'
                                                                          WHEN [rows] > 20000000 AND [rows] <= 30000000 AND [sample_percent] < 90 THEN @Comment + N' WITH SAMPLE 90 PERCENT;'
																		  WHEN [rows] > 30000000 AND [rows] <= 40000000 AND [sample_percent] < 80 THEN @Comment + N' WITH SAMPLE 80 PERCENT;'
																		  WHEN [rows] > 40000000 AND [rows] <= 50000000 AND [sample_percent] < 70 THEN @Comment + N' WITH SAMPLE 70 PERCENT;'
																		  WHEN [rows] > 50000000 AND [rows] <= 60000000 AND [sample_percent] < 60 THEN @Comment + N' WITH SAMPLE 60 PERCENT;'
																		  WHEN [rows] > 60000000 AND [rows] <= 70000000 AND [sample_percent] < 50 THEN @Comment + N' WITH SAMPLE 50 PERCENT;'
																		  WHEN [rows] > 70000000 AND [rows] <= 80000000 AND [sample_percent] < 40 THEN @Comment + N' WITH SAMPLE 40 PERCENT;'
																		  WHEN [rows] > 80000000 AND [rows] <= 90000000 AND [sample_percent] < 30 THEN @Comment + N' WITH SAMPLE 30 PERCENT;'
																		  WHEN [rows] > 90000000 AND [rows] <= 100000000 AND [sample_percent] < 20 THEN @Comment + N' WITH SAMPLE 20 PERCENT;'
																		  WHEN [rows] > 100000000 AND [rows] <= 500000000 AND [sample_percent] < 10 THEN @Comment + N' WITH SAMPLE 10 PERCENT;'
																		  WHEN [rows] > 500000000 AND [sample_percent] < 5 THEN @Comment + N' WITH SAMPLE 5 PERCENT;'
                                                                          ELSE N';'
                                                                        END
																		ELSE N';'
																		END 
                                ELSE NULL
                              END

WHERE  [id] IN(SELECT MIN([id])
             FROM   ##PSBlitzStatsInfo
             GROUP  BY [object_name]);
UPDATE ##PSBlitzStatsInfo SET [update_individual_stats] = CASE
                                WHEN [modified_percent] >= 30.00 OR [sample_percent] < 5.00 THEN N'UPDATE STATISTICS '
								                                      + QUOTENAME([database]) + N'.'
                                                                      + QUOTENAME([object_schema]) + N'.'
                                                                      + QUOTENAME([object_name]) + N'('+QUOTENAME([stats_name])+N')'
																	  + CASE WHEN [persisted_sample_percent] = 0 THEN
                                                                          CASE WHEN [rows] <= 20000000 THEN @Comment + N' WITH FULLSCAN;'
                                                                          WHEN [rows] > 20000000 AND [rows] <= 30000000 AND [sample_percent] < 90 THEN @Comment + N' WITH SAMPLE 90 PERCENT;'
																		  WHEN [rows] > 30000000 AND [rows] <= 40000000 AND [sample_percent] < 80 THEN @Comment + N' WITH SAMPLE 80 PERCENT;'
																		  WHEN [rows] > 40000000 AND [rows] <= 50000000 AND [sample_percent] < 70 THEN @Comment + N' WITH SAMPLE 70 PERCENT;'
																		  WHEN [rows] > 50000000 AND [rows] <= 60000000 AND [sample_percent] < 60 THEN @Comment + N' WITH SAMPLE 60 PERCENT;'
																		  WHEN [rows] > 60000000 AND [rows] <= 70000000 AND [sample_percent] < 50 THEN @Comment + N' WITH SAMPLE 50 PERCENT;'
																		  WHEN [rows] > 70000000 AND [rows] <= 80000000 AND [sample_percent] < 40 THEN @Comment + N' WITH SAMPLE 40 PERCENT;'
																		  WHEN [rows] > 80000000 AND [rows] <= 90000000 AND [sample_percent] < 30 THEN @Comment + N' WITH SAMPLE 30 PERCENT;'
																		  WHEN [rows] > 90000000 AND [rows] <= 100000000 AND [sample_percent] < 20 THEN @Comment + N' WITH SAMPLE 20 PERCENT;'
																		  WHEN [rows] > 100000000 AND [rows] <= 500000000 AND [sample_percent] < 10 THEN @Comment + N' WITH SAMPLE 10 PERCENT;'
																		  WHEN [rows] > 500000000 AND [sample_percent] < 5 THEN @Comment + N' WITH SAMPLE 5 PERCENT;'
                                                                          ELSE N';'
                                                                        END
																		ELSE N';'
																		END 
                                ELSE NULL
                              END;
UPDATE ##PSBlitzStatsInfo SET [update_partition_stats] = CASE
                                WHEN [modified_percent] >= 30.00 OR [sample_percent] < 5.00 THEN N'UPDATE STATISTICS '
								                                      + QUOTENAME([database]) + N'.'
                                                                      + QUOTENAME([object_schema]) + N'.'
                                                                      + QUOTENAME([object_name])
																	  + N' WITH RESAMPLE ON PARTITIONS ('+CAST([partition_number] AS NVARCHAR(20)) +N');'
                                ELSE NULL
                              END
WHERE incremental = N'Yes';

SELECT TOP(10000) /*[id], */
       [database], [object_schema]+N'.'+[object_name] AS [object_name], [object_type],
       [stats_name], [origin], [filter_definition],
       CONVERT(VARCHAR(25),[last_updated],120) AS [last_updated], [rows], [unfiltered_rows],
       [rows_sampled], [sample_percent],
       [modification_counter], [modified_percent],
       [incremental], [temporary], [no_recompute],
       [persisted_sample], [persisted_sample_percent],
       [steps], [partitioned], [partition_number],
       [get_details], [update_table_stats],
       [update_individual_stats], [update_partition_stats]
FROM   ##PSBlitzStatsInfo
ORDER BY [modified_percent] DESC, [object_name] ASC;

SELECT COUNT(1) AS RecordCount FROM ##PSBlitzStatsInfo;

IF OBJECT_ID('tempdb.dbo.##PSBlitzStatsInfo', 'U') IS NOT NULL
    DROP TABLE ##PSBlitzStatsInfo;