/*
	Part of PSBlitz - https://github.com/VladDBA/PSBlitz
	License - https://github.com/VladDBA/PSBlitz/blob/main/LICENSE
*/
SET NOCOUNT ON;
SET STATISTICS XML OFF;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @DatabaseName NVARCHAR(128),
        @DBName       NVARCHAR(128),
        @ExecSQL      NVARCHAR(MAX),
		@ParamDef     NVARCHAR(200),
		@SkipThis     BIT,
        @LineFeed     NVARCHAR(5); 


SET @LineFeed = CHAR(13) + CHAR(10);

SET @DatabaseName = N'';

SELECT @SkipThis = CASE
                     WHEN /*If running on SQL Server 2016 SP1 or lower skip some things*/
                   (
                     CAST(SERVERPROPERTY('ProductMajorVersion') AS TINYINT) = 13
                     AND CAST(SERVERPROPERTY('ProductLevel') AS NVARCHAR(128)) IN ( N'RTM', N'SP1' )
                    )
                    OR CAST(ISNULL(SERVERPROPERTY('ProductMajorVersion'), 0) AS TINYINT) < 13 THEN 1
                     ELSE 0
                   END;

/*Make sure temp tables don't exist*/
IF OBJECT_ID(N'tempdb.dbo.#FSFiles', N'U') IS NOT NULL
    DROP TABLE #FSFiles;
IF OBJECT_ID(N'tempdb.dbo.#BufferPoolInfo', N'U') IS NOT NULL
    DROP TABLE #BufferPoolInfo;
/*Create temp tables*/
CREATE TABLE #FSFiles
  (  [DatabaseID]    [SMALLINT] NULL,
     [FSFilesCount]  [INT] NULL,
     [FSFilesSizeGB] [NUMERIC](23, 3) NULL);

CREATE TABLE #BufferPoolInfo(
	[database_id] [int] NULL,
	[CachedSizeMB] [numeric](23, 3) NULL,
	[BufferPool%] [decimal](5, 2) NULL);

/*Cursor to get FILESTREAM files and their sizes for databases that use FS*/
DECLARE DBsWithFS CURSOR LOCAL STATIC READ_ONLY FORWARD_ONLY FOR
SELECT DISTINCT DB_NAME([mf].[database_id])
FROM   sys.[master_files] AS [mf]
       INNER JOIN sys.[databases] AS [d]
               ON [mf].[database_id] = [d].[database_id]
WHERE  [mf].[type] = 2
       AND [d].[state] = 0
       AND [d].[user_access] = 0
       AND
       ([mf].[database_id] IN ( 1, 2, 3, 4 )
          OR [mf].[database_id] = CASE
                                WHEN @DatabaseName <> N'' THEN DB_ID(@DatabaseName)
                                ELSE [mf].[database_id]
                              END);

OPEN DBsWithFS; 

FETCH NEXT FROM DBsWithFS INTO @DBName;

WHILE @@FETCH_STATUS = 0
  BEGIN
      SET @ExecSQL = N'USE ' + QUOTENAME(@DBName) + N';' + @LineFeed
                     + N'INSERT INTO #FSFiles ([DatabaseID],[FSFilesCount],[FSFilesSizeGB])'
                     + @LineFeed
                     + N'SELECT DB_ID(), COUNT([type]),'
                     + @LineFeed
                     + N'CAST(SUM(CAST([size] AS BIGINT) * 8 / 1024.00 / 1024.00) AS NUMERIC(23, 3))'
                     + @LineFeed
                     + N'FROM sys.database_files WHERE  [type] = 2 GROUP  BY [type];';
      EXEC (@ExecSQL);
      FETCH NEXT FROM DBsWithFS INTO @DBName;
  END; 


CLOSE DBsWithFS;
DEALLOCATE DBsWithFS;

/*Populate BufferPoolInfo table
I'm not filtering by database name here*/
WITH AggBPInfo
AS
(SELECT [database_id],
CAST(COUNT(*) * 8/1024.0 AS NUMERIC(23, 3))  AS [CachedSizeMB]
FROM sys.dm_os_buffer_descriptors
WHERE [database_id] <> 32767 
GROUP BY [database_id])
INSERT INTO #BufferPoolInfo([database_id],[CachedSizeMB],[BufferPool%])
SELECT 
        [database_id], 
        [CachedSizeMB],
        CAST([CachedSizeMB] / SUM([CachedSizeMB]) OVER() * 100.0 AS DECIMAL(5,2)) AS [BufferPool%]
FROM AggBPInfo

/*Return database files and size info*/
SELECT @ExecSQL = CAST(N'SELECT d.[name] AS [Database],CONVERT(VARCHAR(25),d.[create_date],120) AS [Created],' AS NVARCHAR(MAX))
                  + @LineFeed
                  + N'd.[state_desc] AS [DatabaseState],'
                  + @LineFeed
                  + N'd.[user_access_desc] AS [UserAccess],'
                  + @LineFeed
                  + N'SUM(CASE WHEN f.[type] = 0 THEN 1 ELSE 0'
                  + @LineFeed
                  + N' END) AS [DataFiles], CAST(SUM(CASE'
                  + @LineFeed
                  + N' WHEN f.[type] = 0 THEN ( CAST(f.size AS BIGINT) * 8 / 1024.00 / 1024.00 )'
                  + @LineFeed
                  + N' ELSE 0.00 END) AS NUMERIC(23, 3))  AS [DataFilesSizeGB],'
                  + @LineFeed
                  + N'SUM(CASE WHEN f.[type] = 1 THEN 1 ELSE 0 END) AS [LogFiles],'
                  + @LineFeed
                  + N'CAST(SUM(CASE WHEN f.[type] = 1 THEN ( CAST(f.size AS BIGINT) * 8 / 1024.00 / 1024.00 )'
                  + @LineFeed
                  + N'ELSE 0.00 END) AS NUMERIC(23, 3))  AS [LogFilesSizeGB],'
                  + @LineFeed
                  + CASE
                      WHEN @SkipThis = 1 THEN N' ''n/a'' AS '
                      ELSE N'l.'
                    END
                  + '[VirtualLogFiles], ISNULL(fs.FSFilesCount, 0)        AS [FILESTREAMContainers],'
                  + @LineFeed
                  + N'ISNULL(fs.FSFilesSizeGB, 0.000)   AS [FSContainersSizeGB],'
                  + @LineFeed
                  + N'CAST(SUM(CAST(f.size AS BIGINT) * 8 / 1024.00 / 1024.00) AS NUMERIC(23, 3))'
                  + @LineFeed
                  + N'+ ISNULL(fs.FSFilesSizeGB, 0.000) AS [DatabaseSizeGB],'
				  + @LineFeed
				  + N'bpi.[CachedSizeMB],bpi.[BufferPool%],'
                  + @LineFeed
                  + N'd.[log_reuse_wait_desc] AS [CurrentLogReuseWait],'
                  + @LineFeed
                  + N'd.[compatibility_level] AS [CompatibilityLevel],'
                  + @LineFeed
                  + N'd.[page_verify_option_desc] AS [PageVerifyOption],'
                  + @LineFeed
                  + N'd.[containment_desc] AS [Containment],'
                  + @LineFeed
                  + N'd.[collation_name] AS [Collation],'
                  + @LineFeed
                  + N'd.[snapshot_isolation_state_desc] AS [SnapshotIsolationState],'
                  + @LineFeed
                  + N'CASE WHEN d.[is_read_committed_snapshot_on] = 1 THEN ''Yes'' ELSE ''No'''
                  + @LineFeed
                  + N'END AS [ReadCommittedSnapshotOn], d.recovery_model_desc AS [RecoveryModel],'
                  + @LineFeed
                  + N'CASE WHEN d.[is_auto_close_on] = 1 THEN ''Yes'' ELSE ''No'' END AS [AutoCloseOn],'
                  + @LineFeed
                  + N'CASE WHEN d.[is_auto_shrink_on] = 1 THEN ''Yes'' ELSE ''No'' END AS [AutoShrinkOn],'
                  + @LineFeed
                  + N'CASE WHEN d.[is_query_store_on] = 1 THEN ''Yes'' ELSE ''No'' END AS [QueryStoreOn],'
                  + @LineFeed
                  + N'CASE WHEN d.[is_trustworthy_on] = 1 THEN ''Yes'' ELSE ''No'' END AS [TrustworthyOn],'
				  + @LineFeed
				  + N'CASE WHEN d.[is_encrypted] = 1 THEN ''Yes'' ELSE ''No'' END AS [IsEncrypted]'
				  + @LineFeed
                  + CASE
                      WHEN @SkipThis = 1 THEN ' ''n/a'' AS [EncryptionState]'
					  ELSE N', CASE WHEN ek.[encryption_state] = 0 OR ek.[encryption_state] IS NULL THEN ''No Encryption'''
					  + @LineFeed + N'WHEN ek.[encryption_state] = 1 THEN ''Unencrypted'''
					  + @LineFeed + N'WHEN ek.[encryption_state] = 2 THEN ''Encryption in progress'''
					  + @LineFeed + N'WHEN ek.[encryption_state] = 3 THEN ''Encrypted'''
					  + @LineFeed + N'WHEN ek.[encryption_state] = 4 THEN ''Key change in progress'''
					  + @LineFeed + N'WHEN ek.[encryption_state] = 5 THEN ''Decryption in progress'''
					  + @LineFeed + N'WHEN ek.[encryption_state] = 6 THEN ''Protection change in progress'''
					  + @LineFeed + N'END AS [EncryptionState]'
					  END
                  + @LineFeed + N'FROM   sys.master_files AS f'
                  + @LineFeed
                  + N'INNER JOIN sys.databases AS d  ON f.database_id = d.database_id'
                  + @LineFeed
                  + N'LEFT JOIN #FSFiles AS fs ON f.database_id = fs.DatabaseID'
                  + @LineFeed
				  + N'LEFT JOIN #BufferPoolInfo AS bpi ON d.database_id = bpi.database_id'
				  + @LineFeed
                  + CASE
                      WHEN @SkipThis = 1 THEN ''
                      ELSE 'CROSS APPLY (SELECT [file_id],'
                           + @LineFeed
                           + N'COUNT(*) AS [VirtualLogFiles] FROM   sys.dm_db_log_info (d.database_id)'
                           + @LineFeed + N'GROUP  BY [file_id]) AS l'
						   + @LineFeed + N'LEFT JOIN sys.dm_database_encryption_keys AS ek'
						   + @LineFeed + N'ON d.[database_id] = ek.[database_id]'
                    END
                  + @LineFeed + N'WHERE d.[database_id] IN (1,2,3,4) OR d.[database_id] = '
                  + CASE
                      WHEN @DatabaseName <> N'' THEN CAST(DB_ID(@DatabaseName) AS NVARCHAR(10))
                      ELSE N'd.[database_id]'
                    END
                  + @LineFeed
                  + N'GROUP  BY d.[name], [fs].FSFilesCount, [fs].FSFilesSizeGB,  [d].[compatibility_level],'
                  + @LineFeed
                  + N'[d].[state_desc], d.[user_access_desc], [d].[create_date], [d].[collation_name],'
                  + @LineFeed
                  + N'[d].[log_reuse_wait_desc], [d].[snapshot_isolation_state_desc], [d].[is_read_committed_snapshot_on],'
                  + @LineFeed
                  + N'[d].recovery_model_desc, [d].[is_auto_close_on], [d].[is_auto_shrink_on],'
                  + @LineFeed
                  + N'[d].[containment_desc],[d].[page_verify_option_desc],[d].[is_query_store_on], [d].[is_trustworthy_on], d.[is_trustworthy_on],d.[is_encrypted]'
                  + @LineFeed
				  + N',bpi.[CachedSizeMB],bpi.[BufferPool%]'
                  + CASE
                      WHEN @SkipThis = 1 THEN ''
                      ELSE ',[l].[VirtualLogFiles], ek.[encryption_state]'
                    END
                  + @LineFeed
                  + N'ORDER BY [DatabaseSizeGB] DESC'
                  + @LineFeed + N'OPTION (RECOMPILE);'

EXEC(@ExecSQL); 

/*Drop temp table*/
IF OBJECT_ID(N'tempdb.dbo.#FSFiles', N'U') IS NOT NULL
    DROP TABLE #FSFiles;

	/*Get file info*/
/*Make sure temp table doesn't exist*/
IF OBJECT_ID(N'tempdb.dbo.#AvailableSpace', N'U') IS NOT NULL
    DROP TABLE #AvailableSpace;
/*Create temp table*/
CREATE TABLE #AvailableSpace
  (  [DatabaseID]    [SMALLINT] NULL,
     [FileID]  [INT] NULL,
     [AvailableSpaceGB] [NUMERIC](23, 3) NULL);
/*Cursor to get available space for each database file*/
DECLARE AvailableSpace CURSOR LOCAL STATIC READ_ONLY FORWARD_ONLY FOR
SELECT [name]
FROM   sys.[databases]
WHERE  [state] = 0
AND [user_access] = 0; 

OPEN AvailableSpace; 

FETCH NEXT FROM AvailableSpace INTO @DBName;

WHILE @@FETCH_STATUS = 0
  BEGIN
      SET @ExecSQL = N'USE ' + QUOTENAME(@DBName) + N';' + @LineFeed
                     + N'INSERT INTO #AvailableSpace ([DatabaseID],[FileID],[AvailableSpaceGB])'
                     + @LineFeed
                     + N'SELECT DB_ID() AS [database_id], [f].[file_id],'
                     + @LineFeed
                     + N'CAST(( ( CAST([f].[size] AS BIGINT) - CAST(FILEPROPERTY([f].[name], ''SpaceUsed'') '
                     + N'AS BIGINT) ) * 8 / 1024.00 / 1024.00 ) AS NUMERIC(23, 3)) AS [Available SpaceGB]'
                     + @LineFeed
                     + N'FROM   sys.[database_files] AS [f] WHERE [f].[type] <> 2'
					 + @LineFeed + N'OPTION (RECOMPILE);';
      EXEC (@ExecSQL);
      FETCH NEXT FROM AvailableSpace INTO @DBName;
  END; 

CLOSE AvailableSpace;
DEALLOCATE AvailableSpace;

SELECT DB_NAME(f.database_id)                                     AS [Database],
       f.[file_id]                                                AS [FileID],
       f.[name]                                                   AS [FileLogicalName],
       f.[physical_name]                                          AS [FilePhysicalName],
       f.[type_desc]                                              AS [FileType],
       state_desc                                                 AS [State],
       CAST(( CAST(f.size AS BIGINT) * 8 / 1024.00 / 1024.00 ) AS NUMERIC(23, 3)) AS [SizeGB],
	   [as].[AvailableSpaceGB],
       CASE
         WHEN [max_size] = 0
               OR [growth] = 0 THEN 'File autogrowth is disabled'
         WHEN [max_size] = -1
              AND [growth] > 0 THEN 'Unlimited'
         WHEN [max_size] > 0 THEN CAST(CAST (CAST([max_size] AS BIGINT) * 8 / 1024.00 / 1024.00 AS NUMERIC(23, 3)) AS VARCHAR(20))
       END                                                        AS [MaxFileSizeGB],
       CASE
         WHEN [is_percent_growth] = 1 THEN CAST([growth] AS NVARCHAR(2)) + N' %'
         WHEN [is_percent_growth] = 0 THEN CAST(CAST(CAST([growth] AS BIGINT)*8/1024.00/1024.00 AS NUMERIC(23, 3)) AS VARCHAR(20))
                                           + ' GB'
       END                                                        AS [GrowthIncrement]
FROM   sys.master_files AS f
LEFT JOIN #AvailableSpace AS [as] ON f.[database_id] = [as].[DatabaseID] AND f.[file_id] = [as].[FileID]
WHERE [database_id] IN (1,2,3,4) 
  OR [database_id] = CASE WHEN @DatabaseName <> N'' 
                        THEN DB_ID(@DatabaseName)
						ELSE [database_id]
						END
ORDER  BY [database_id] ASC,
          [file_id] ASC
OPTION(RECOMPILE);
/*cleanup*/
IF OBJECT_ID(N'tempdb.dbo.#AvailableSpace', N'U') IS NOT NULL
    DROP TABLE #AvailableSpace;

/*Get database scoped configuration on instances running 2016 and above*/
IF ( @DatabaseName <> N'' AND CAST(ISNULL(SERVERPROPERTY('ProductMajorVersion'),0) AS TINYINT)>= 13)
  BEGIN
      SELECT @ExecSQL = N'SELECT N'''+@DatabaseName +N''' AS [Database], [name] AS [Config Name],'
                        + @LineFeed
                        + N'CASE WHEN [value] = 0 AND [name] <> N''MAXDOP'' THEN ''Off'''
						+ @LineFeed + N'WHEN [value] = 1 AND [name] <> N''MAXDOP'' THEN ''On'''
                        + @LineFeed
                        + N'WHEN CAST([value] AS VARCHAR(3)) IN (''OFF'', ''ON'')'
                        + @LineFeed
                        + N'THEN REPLACE(REPLACE(CAST([value] AS VARCHAR(3)),''FF'',''ff''),''N'',''n'')'
                        + @LineFeed + N'ELSE [value] END AS [Value],'
                        + @LineFeed
                        + CASE /*this column was introduced in SQL Server 2017*/
						WHEN CAST(ISNULL(SERVERPROPERTY('ProductMajorVersion'),0) AS TINYINT)>= 14 
						THEN N'CASE WHEN [is_value_default] = 1 THEN ''Yes'' ELSE ''No'''
                        + @LineFeed + N'END ' 
						ELSE '''n/a''' END 
						+N' AS [IsDefault] FROM '
						+QUOTENAME(@DatabaseName)
						+N'.sys.[database_scoped_configurations]'
						+ @LineFeed + N'OPTION (RECOMPILE);';
      EXEC(@ExecSQL);
  END;