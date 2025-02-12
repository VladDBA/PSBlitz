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

DECLARE @IsAzureSQLDB BIT;
SET @IsAzureSQLDB = 0;
IF OBJECT_ID('tempdb..##PSBlitzDangerousOptions') IS NOT NULL
BEGIN
    DROP TABLE ##PSBlitzDangerousOptions;
END;
IF OBJECT_ID('tempdb..##PSBlitzDBs') IS NOT NULL
BEGIN
    DROP TABLE ##PSBlitzDBs;
END;
CREATE TABLE ##PSBlitzDangerousOptions
(
    [database]         NVARCHAR(128),
    [object_name]      NVARCHAR(261),
    [type]             NVARCHAR(60),
    [ANSI_NULLS]       NVARCHAR(3),
    [QUOTED_IDENTIFIER] NVARCHAR(3),
    [created]          DATETIME,
    [modified]         DATETIME
);
CREATE TABLE ##PSBlitzDBs
(
    [database] NVARCHAR(128)
);
IF(@IsAzureSQLDB = 1)
BEGIN
INSERT INTO ##PSBlitzDBs ([database]) SELECT DB_NAME();
END
ELSE
BEGIN
INSERT INTO ##PSBlitzDBs ([database])
VALUES 
('PSBlitzReplace');
END

IF (SELECT COUNT(*) FROM ##PSBlitzDBs) >0
BEGIN
    DECLARE @DB NVARCHAR(128);
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE DBs CURSOR
    FOR
        SELECT [database]
        FROM ##PSBlitzDBs
        ORDER BY [database];
    OPEN DBs;
    FETCH NEXT FROM DBs INTO @DB;
    WHILE @@FETCH_STATUS = 0
    BEGIN
    IF (@DB <> N'PSBlitzReplace')
    BEGIN
        SET @SQL = N'
        INSERT INTO ##PSBlitzDangerousOptions
        SELECT '''+@DB+N'''                      AS [database],
               QUOTENAME(SCHEMA_NAME([ob].[schema_id]))
               + N''.'' + QUOTENAME([ob].[name]) AS [object_name],
               [ob].[type_desc]                AS [type],
               CASE
                 WHEN [md].[uses_ansi_nulls] = 0 THEN ''OFF''
                 ELSE ''ON''
               END                             AS [ANSI_NULLS],
               CASE
                 WHEN [md].[uses_quoted_identifier] = 0 THEN ''OFF''
                 ELSE ''ON''
               END                             AS [QUOTED_IDENTIFIER],
               [ob].[create_date] AS [created],
               [ob].[modify_date] AS [modified]
        FROM   '+CASE WHEN @IsAzureSQLDB = 1 THEN N'' 
                      ELSE QUOTENAME(@DB) +N'.' END +N'sys.[sql_modules] AS [md]
               INNER JOIN '+CASE WHEN @IsAzureSQLDB = 1 THEN N'' 
                      ELSE QUOTENAME(@DB) +N'.' END +N'sys.[objects] AS [ob]
                       ON [md].[object_id] = [ob].[object_id]
        WHERE  [ob].[is_ms_shipped] = 0
               AND
               ([md].[uses_ansi_nulls] = 0
                  OR [md].[uses_quoted_identifier] = 0);';
       EXEC sp_executesql @SQL;
        END;
        FETCH NEXT FROM DBs INTO @DB;
    END;
    CLOSE DBs;
    DEALLOCATE DBs;
END;

SELECT [database],
       [object_name],
       [type],
       [ANSI_NULLS],
       [QUOTED_IDENTIFIER],
       [created],
       [modified] 
FROM   ##PSBlitzDangerousOptions;