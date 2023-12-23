/*
	Part of PSBlitz - https://github.com/VladDBA/PSBlitz
	License - https://github.com/VladDBA/PSBlitz/blob/main/LICENSE
*/
SET NOCOUNT ON;
SET STATISTICS XML OFF;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
DECLARE @DatabaseName NVARCHAR(128),
@DBName  NVARCHAR(128),
        @ExecSQL NVARCHAR(MAX);

SET @DatabaseName = N'';

/*Make sure temp table doesn't exist*/
IF OBJECT_ID(N'tempdb.dbo.#FSFiles', N'U') IS NOT NULL
    DROP TABLE #FSFiles;
/*Create temp table*/
CREATE TABLE #FSFiles
  (  [DatabaseID]    [SMALLINT] NULL,
     [FSFilesCount]  [INT] NULL,
     [FSFilesSizeGB] [NUMERIC](23, 3) NULL);

/*Cursor to get FILESTREAM files and their sizes for databases that use FS*/


DECLARE DBsWithFS CURSOR LOCAL STATIC READ_ONLY FORWARD_ONLY FOR
SELECT DISTINCT DB_NAME(mf.database_id)
FROM   sys.master_files AS mf
INNER JOIN sys.databases AS d ON mf.database_id = d.database_id
WHERE  mf.[type] = 2
AND d.[state] = 0
AND  mf.database_id = CASE WHEN @DatabaseName <> N'' 
                        THEN DB_ID(@DatabaseName)
						ELSE mf.database_id
						END;

OPEN DBsWithFS; 

FETCH NEXT FROM DBsWithFS INTO @DBName;

WHILE @@FETCH_STATUS = 0
  BEGIN
      SET @ExecSQL = N'USE ['+@DBName+N'];
	  INSERT INTO #FSFiles ([DatabaseID],[FSFilesCount],[FSFilesSizeGB])
	  SELECT DB_ID(),
       COUNT([type]),
       CAST(SUM(CAST([size] AS BIGINT) * 8 / 1024.00 / 1024.00) AS NUMERIC(23, 3)) 
       FROM sys.database_files
	   WHERE  [type] = 2
	   GROUP  BY [type];';
      EXEC (@ExecSQL);
      FETCH NEXT FROM DBsWithFS INTO @DBName;
  END;

CLOSE DBsWithFS;
DEALLOCATE DBsWithFS;

/*Return database files and size info*/
SELECT d.[name]                          AS [Database],
d.[create_date] AS [Created],
       d.[state_desc]                    AS [DatabaseState],
       SUM(CASE
             WHEN f.[type] = 0 THEN 1
             ELSE 0
           END)                          AS [DataFiles],
       CAST(SUM(CASE
                  WHEN f.[type] = 0 THEN ( CAST(f.size AS BIGINT) * 8 / 1024.00 / 1024.00 )
                  ELSE 0.00
                END) AS NUMERIC(23, 3))  AS [DataFilesSizeGB],
       SUM(CASE
             WHEN f.[type] = 1 THEN 1
             ELSE 0
           END)                          AS [LogFiles],
       CAST(SUM(CASE
                  WHEN f.[type] = 1 THEN ( CAST(f.size AS BIGINT) * 8 / 1024.00 / 1024.00 )
                  ELSE 0.00
                END) AS NUMERIC(23, 3))  AS [LogFilesSizeGB],
       l.[VirtualLogFiles],
       ISNULL(fs.FSFilesCount, 0)        AS [FILESTREAMContainers],
       ISNULL(fs.FSFilesSizeGB, 0.000)   AS [FSContainersSizeGB],
       CAST(SUM(CAST(f.size AS BIGINT) * 8 / 1024.00 / 1024.00) AS NUMERIC(23, 3))
       + ISNULL(fs.FSFilesSizeGB, 0.000) AS [DatabaseSizeGB],
	   [d].[log_reuse_wait_desc]         AS [CurrentLogReuseWait],
	   d.[compatibility_level]           AS [CompatibilityLevel],
	   [d].[page_verify_option_desc]     AS [PageVerifyOption],
       [d].[containment_desc]            AS [Containment],
       d.[collation_name]                AS [Collation],
	   d.[snapshot_isolation_state_desc] AS [SnapshotIsolationState],
       CASE WHEN d.[is_read_committed_snapshot_on] = 1 THEN 'Yes' ELSE 'No'
	   END                               AS [ReadCommittedSnapshotOn],
       d.recovery_model_desc             AS [RecoveryModel],
	   CASE WHEN d.[is_auto_close_on] = 1 THEN 'Yes' ELSE 'No'
	   END                               AS [AutoCloseOn],
	   CASE WHEN d.[is_auto_shrink_on] = 1 THEN 'Yes' ELSE 'No'
	   END                               AS [AutoShrinkOn],
	   CASE WHEN d.[is_query_store_on] = 1 THEN 'Yes' ELSE 'No'
	   END                               AS [QueryStoreOn],
	   CASE WHEN d.[is_trustworthy_on] = 1 THEN 'Yes' ELSE 'No'
	   END                               AS [TrustworthyOn]
FROM   sys.master_files AS f
       INNER JOIN sys.databases AS d
               ON f.database_id = d.database_id
       LEFT JOIN #FSFiles AS fs
              ON f.database_id = fs.DatabaseID
       CROSS APPLY (SELECT [file_id],
                           COUNT(*) AS [VirtualLogFiles]
                    FROM   sys.dm_db_log_info (d.database_id)
                    GROUP  BY [file_id]) AS l
WHERE d.[database_id] = CASE WHEN @DatabaseName <> N'' 
                        THEN DB_ID(@DatabaseName)
						ELSE d.[database_id]
						END
GROUP  BY d.[name],
          fs.FSFilesCount,
          fs.FSFilesSizeGB,
		  d.[compatibility_level],
		  d.[state_desc],
		  d.[create_date],
		  d.[collation_name],
		  [d].[log_reuse_wait_desc],
		  d.[snapshot_isolation_state_desc],
		  d.[is_read_committed_snapshot_on],
		  d.recovery_model_desc,
		  d.[is_auto_close_on],
		  d.[is_auto_shrink_on],
		  [d].[containment_desc],
          [d].[page_verify_option_desc],
		  d.[is_query_store_on],
		  d.[is_trustworthy_on],
		  l.[VirtualLogFiles]
ORDER BY [DatabaseSizeGB] DESC
OPTION (RECOMPILE);
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
WHERE  [state] = 0; 

OPEN AvailableSpace; 

FETCH NEXT FROM AvailableSpace INTO @DBName;

WHILE @@FETCH_STATUS = 0
  BEGIN
      SET @ExecSQL = N'USE ['+@DBName+N'];
	  INSERT INTO #AvailableSpace ([DatabaseID],[FileID],[AvailableSpaceGB]) 
	  SELECT DB_ID() AS [database_id], 
       [f].[file_id], 
       CAST(( ( CAST([f].[size] AS BIGINT) - CAST(FILEPROPERTY([f].[name], ''SpaceUsed'') AS BIGINT) ) * 8 / 1024.00 / 1024.00 ) AS NUMERIC(23, 3)) AS [Available SpaceGB]
       FROM   sys.[database_files] AS [f]
	   WHERE [f].[type] <> 2;';
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
WHERE [database_id] = CASE WHEN @DatabaseName <> N'' 
                        THEN DB_ID(@DatabaseName)
						ELSE [database_id]
						END
ORDER  BY [database_id] ASC,
          [file_id] ASC
OPTION(RECOMPILE);
/*cleanup*/
IF OBJECT_ID(N'tempdb.dbo.#AvailableSpace', N'U') IS NOT NULL
    DROP TABLE #AvailableSpace;