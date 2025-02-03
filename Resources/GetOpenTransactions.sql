/*
	Part of PSBlitz - https://github.com/VladDBA/PSBlitz
	License - https://github.com/VladDBA/PSBlitz/blob/main/LICENSE
*/
SET NOCOUNT ON;
SET STATISTICS XML OFF;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @DatabaseName NVARCHAR(256),
        @CheckPass VARCHAR(5);

SET @DatabaseName = N'';
/*This is here to avoid overwriting sqlplan files 
if they originate from the same SPID*/
SET @CheckPass = '';

/*
		This CTE is a fix for an edge case that causes the same record(s) to show up multiple times
		- can't do SELECT DISTINCT when XML data is involved, so I'll split this up using a CTE
*/
WITH qcte
     AS (SELECT DISTINCT CONVERT(VARCHAR(25),GETDATE(),120)                        AS [time_of_check],
                         DB_NAME([es].[database_id])                               AS [database_name],
                         [s].[session_id],
                         [re].[blocking_session_id],
                         [re].[wait_type],
                         ( [re].[wait_time] / 1000.00 )                            AS [wait_time_seconds],
                         [re].[wait_resource],
                         [re].[command],
                         [es].[status]                                             AS [session_status],
                         [re].[status]                                             AS [current_reuqest_status],
                         [t].[name]                                                AS [transaction_name],
                         [s].[open_transaction_count],
                         [t].[transaction_begin_time],
                         CASE
                           WHEN [t].[transaction_type] = 1 THEN 'Read/write transaction'
                           WHEN [t].[transaction_type] = 2 THEN 'Read-only transaction'
                           WHEN [t].[transaction_type] = 3 THEN 'System transaction'
                           WHEN [t].[transaction_type] = 4 THEN 'Distributed transaction'
                         END                                                       AS [transaction_type],
                         CASE
                           WHEN [t].[transaction_state] = 0 THEN 'The transaction has not been completely initialized yet'
                           WHEN [t].[transaction_state] = 1 THEN 'The transaction has been initialized but has not started'
                           WHEN [t].[transaction_state] = 2 THEN 'The transaction is active'
                           WHEN [t].[transaction_state] = 3 THEN 'The transaction has ended. This is used for read-only transactions'
                           WHEN [t].[transaction_state] = 4 THEN 'The commit process has been initiated on the distributed transaction.'
                                                                 + ' The distributed transaction is still active but further processing cannot take place.'
                           WHEN [t].[transaction_state] = 5 THEN 'The transaction is in a prepared state and waiting resolution'
                           WHEN [t].[transaction_state] = 6 THEN 'The transaction has been committed'
                           WHEN [t].[transaction_state] = 7 THEN 'The transaction is being rolled back'
                           WHEN [t].[transaction_state] = 8 THEN 'The transaction has been rolled back'
                         END                                                       AS [transaction_state],
                         ISNULL([re].[start_time], [es].[last_request_start_time]) AS [request_start_time],
                         CASE
                           WHEN [re].[start_time] IS NOT NULL THEN NULL
                           ELSE [es].[last_request_end_time]
                         END                                                       AS [request_end_time],
                         CASE
                           WHEN [re].[start_time] IS NOT NULL THEN DATEDIFF(second, [re].[start_time], GETDATE())
                           ELSE NULL
                         END                                                       AS [active_request_elapsed_seconds],
                         [es].[host_name],
                         [es].[login_name],
                         [es].[program_name],
                         [es].[client_interface_name],
                         [sqltext].[text]                                          AS [current_sql],
                         [current_qs].[plan_handle]                                AS [current_plan_handle],
						 /*
						 Because [most_recent_sql_handle] = [sql_handle] for running sessions, 
						 there's no need to show the same info twice (as current and most recent sql & plan)
						 */
                         CASE
                           WHEN [es].[status] = N'running'
                                AND [conn].[most_recent_sql_handle] = [re].[sql_handle] THEN NULL
                           ELSE [sqltext_rec].[text]
                         END                                                       AS [most_recent_sql],
                         CASE
                           WHEN [es].[status] = N'running'
                                AND [conn].[most_recent_sql_handle] = [re].[sql_handle] THEN NULL
                           ELSE [recent_qs].[plan_handle]
                         END                                                       AS [most_recent_plan_handle],
                         [conn].[most_recent_sql_handle],
                         [re].[sql_handle]
         FROM   sys.[dm_tran_session_transactions] AS [s]
                INNER JOIN sys.[dm_tran_active_transactions] AS [t]
                        ON [s].[transaction_id] = [t].[transaction_id]
                LEFT JOIN sys.[dm_exec_sessions] AS [es]
                       ON [es].[session_id] = [s].[session_id]
                LEFT JOIN sys.[dm_exec_connections] AS [conn]
                       ON [conn].[session_id] = [s].[session_id]
                LEFT JOIN sys.[dm_exec_requests] AS [re]
                       ON [s].[session_id] = [re].[session_id]
                LEFT JOIN sys.[dm_exec_query_stats] AS [recent_qs]
                       ON [conn].[most_recent_sql_handle] = [recent_qs].[sql_handle]
                LEFT JOIN sys.[dm_exec_query_stats] AS [current_qs]
                       ON [re].[sql_handle] = [current_qs].[sql_handle]
                OUTER APPLY sys.dm_exec_sql_text([re].[sql_handle]) AS [sqltext]
                OUTER APPLY sys.dm_exec_sql_text([conn].[most_recent_sql_handle]) AS [sqltext_rec]
         WHERE  [es].[database_id] = CASE
                                       WHEN @DatabaseName <> N'' THEN DB_ID(@DatabaseName)
                                       ELSE [es].[database_id]
                                     END)
SELECT CONVERT(VARCHAR(25),[qcte].[time_of_check],120) AS [time_of_check],
       [qcte].[database_name],
       [qcte].[session_id],
       [qcte].[blocking_session_id],
	   CASE
         WHEN [qcte].[current_sql] IS NOT NULL THEN 'Current_'
                                                    + CAST([qcte].[session_id] AS VARCHAR(10))
                                                    + '.query'
         ELSE ''
       END                         AS [current_query],
	   [qcte].[current_sql],
	   CASE
         WHEN [sqlplan_curr].[query_plan] IS NOT NULL THEN 'OpenTranCurrent'+@CheckPass+'_'
                                                           + CAST([qcte].[session_id] AS VARCHAR(10))
                                                           + '.sqlplan'
         ELSE '-- N/A --'
       END                         AS [current_plan_file],
	   CASE
         WHEN [qcte].[most_recent_sql] IS NOT NULL THEN 'MostRecent_'
                                                        + CAST([qcte].[session_id] AS VARCHAR(10))
                                                        + '.query'
         ELSE ''
       END                         AS [most_recent_query],
	   [qcte].[most_recent_sql],
	   CASE
         WHEN [sqlplan_rec].[query_plan] IS NOT NULL THEN 'OpenTranRecent'+@CheckPass+'_'
                                                          + CAST([qcte].[session_id] AS VARCHAR(10))
                                                          + '.sqlplan'
         ELSE '-- N/A --'
       END                         AS [most_recent_plan_file],
       [qcte].[wait_type],
       [qcte].[wait_time_seconds],
       [qcte].[wait_resource],
       [qcte].[command],
       [qcte].[session_status],
       [qcte].[current_reuqest_status],
       [qcte].[transaction_name],
       [qcte].[open_transaction_count],
       CONVERT(VARCHAR(25),[qcte].[transaction_begin_time],120) AS [transaction_begin_time],
       [qcte].[transaction_type],
       [qcte].[transaction_state],
       CONVERT(VARCHAR(25),[qcte].[request_start_time],120) AS [request_start_time],
       CONVERT(VARCHAR(25),[qcte].[request_end_time],120) AS [request_end_time],
       [qcte].[active_request_elapsed_seconds],
	   CASE 
	     WHEN [qcte].[request_end_time] IS NOT NULL 
		 THEN DATEDIFF(SECOND, [qcte].[request_end_time],[qcte].[time_of_check] ) 
		 ELSE NULL 
	   END AS [seconds_since_request_ended],
       [qcte].[host_name],
       [qcte].[login_name],
       [qcte].[program_name],
       [qcte].[client_interface_name],
       [sqlplan_curr].[query_plan] AS [current_plan],
       [sqlplan_rec].[query_plan]  AS [most_recent_plan]
FROM   [qcte]
       OUTER APPLY sys.dm_exec_query_plan([qcte].[current_plan_handle]) AS [sqlplan_curr]
       OUTER APPLY sys.dm_exec_query_plan([qcte].[most_recent_plan_handle]) AS [sqlplan_rec]
	   OPTION(RECOMPILE);