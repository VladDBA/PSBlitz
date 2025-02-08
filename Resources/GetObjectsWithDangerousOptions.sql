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

USE [..PSBlitzReplace..];

SELECT DB_NAME()                       AS [database_name],
       QUOTENAME(SCHEMA_NAME([ob].[schema_id]))
       + N'.' + QUOTENAME([ob].[name]) AS [object_name],
       [ob].[type_desc]                AS [object_type],
       CASE
         WHEN [md].[uses_ansi_nulls] = 0 THEN 'OFF'
         ELSE 'ON'
       END                             AS [ANSI_NULLS],
       CASE
         WHEN [md].[uses_quoted_identifier] = 0 THEN 'OFF'
         ELSE 'ON'
       END                             AS [QUOTED_IDENTIFIER],
       [ob].[create_date],
       [ob].[modify_date]
FROM   sys.[sql_modules] AS [md]
       INNER JOIN sys.[objects] AS [ob]
               ON [md].[object_id] = [ob].[object_id]
WHERE  [ob].[is_ms_shipped] = 0
       AND
       ([md].[uses_ansi_nulls] = 0
          OR [md].[uses_quoted_identifier] = 0);