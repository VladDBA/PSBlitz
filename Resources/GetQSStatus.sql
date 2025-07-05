/*
	Part of PSBlitz - https://github.com/VladDBA/PSBlitz
	License - https://github.com/VladDBA/PSBlitz/blob/main/LICENSE
    Check Query Store status and flush QS data from memory to QS
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

DECLARE @NextStep BIT;
DECLARE @DatabaseName SYSNAME;
DECLARE @LineFeed NVARCHAR(5);
SET @LineFeed = CHAR(13) + CHAR(10);

;SET @DatabaseName = NULL;

IF ( (SELECT CAST(SERVERPROPERTY('Edition') AS NVARCHAR(128))) = N'SQL Azure' )
  BEGIN
      IF ( (SELECT SERVERPROPERTY ('EngineEdition')) NOT IN ( 5, 8 )
            OR (SELECT [compatibility_level]
                FROM   sys.[databases]
                WHERE  [name] = DB_NAME()) < 130 )
        BEGIN
            SELECT 'No' AS [EligibleForBlitzQueryStore];
        END;
      ELSE
        BEGIN
            SELECT 'Yes' AS [EligibleForBlitzQueryStore];

            BEGIN TRY
                EXEC sp_query_store_flush_db;
            END TRY
            BEGIN CATCH
                PRINT 'could not flush.';
            END CATCH;
        END;
  END; 
ELSE
  BEGIN /*Not SQL Azure*/
      IF ( (SELECT CAST(PARSENAME(CONVERT(NVARCHAR(128), SERVERPROPERTY ('ProductVersion')), 4) AS TINYINT)) < 13 )
        BEGIN
            SELECT 'No' AS [EligibleForBlitzQueryStore]
        END
      ELSE IF ( (SELECT CAST(PARSENAME(CONVERT(NVARCHAR(128), SERVERPROPERTY ('ProductVersion')), 4) AS TINYINT)) >= 13 )
        BEGIN
            IF(SELECT COUNT(*)
               FROM   sys.[databases] AS [d]
               WHERE  [d].[is_query_store_on] = 1
                      AND [d].[user_access_desc] = 'MULTI_USER'
                      AND [d].[state_desc] = 'ONLINE'
                      AND [d].name = @DatabaseName
                      AND [d].[is_distributor] = 0) > 0
              BEGIN
                  SELECT 'Yes' AS [EligibleForBlitzQueryStore];

                  SET @NextStep = 1;
              END
            ELSE
              BEGIN
                  SELECT 'No' AS [EligibleForBlitzQueryStore];

                  SET @NextStep = 0;
              END
        END;

      IF ( @NextStep = 1 )
        BEGIN
            DECLARE @sql NVARCHAR(400);

            SET @sql = N'USE [' + @DatabaseName + N']' + @LineFeed
                       + N' BEGIN TRY'
            SET @sql += @LineFeed
                        + N'EXEC sp_query_store_flush_db;'
                        + @LineFeed + N'END TRY '
            SET @sql += @LineFeed + N'BEGIN CATCH' + @LineFeed
                        + N'PRINT ''could not flush'''
            SET @sql += @LineFeed + N'END CATCH;'

            EXEC (@sql);
        END;
  END; 
