SET NOCOUNT ON;
SET STATISTICS XML OFF;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @DatabaseName NVARCHAR(256);

SET @DatabaseName = N'';

SELECT GETDATE()                                                 AS [time_of_check],
       DB_NAME([es].[database_id])                               AS [database_name],
       [s].[session_id],
       [re].[blocking_session_id],
       [re].[wait_type],
       ([re].[wait_time] / 1000.00)                              AS [wait_time_seconds],
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
       [sqltext_rec].[text]                                      AS [most_recent_sql]
FROM   sys.dm_tran_session_transactions AS [s]
       INNER JOIN sys.dm_tran_active_transactions AS [t]
               ON [s].[transaction_id] = [t].[transaction_id]
       LEFT JOIN sys.dm_exec_sessions AS [es]
              ON [es].[session_id] = [s].[session_id]
       LEFT JOIN sys.dm_exec_connections AS [conn]
              ON [conn].[session_id] = [s].[session_id]
       LEFT JOIN sys.dm_exec_requests AS [re]
              ON [s].[session_id] = [re].[session_id]
       OUTER apply sys.dm_exec_sql_text([re].[sql_handle]) AS [sqltext]
       OUTER APPLY sys.dm_exec_sql_text([conn].[most_recent_sql_handle]) AS [sqltext_rec]
WHERE  [es].[database_id] = CASE
                              WHEN @DatabaseName <> N'' THEN DB_ID(@DatabaseName)
                              ELSE [es].[database_id]
                            END;