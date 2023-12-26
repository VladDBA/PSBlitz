/*
	Part of PSBlitz - https://github.com/VladDBA/PSBlitz
	License - https://github.com/VladDBA/PSBlitz/blob/main/LICENSE
*/

SET NOCOUNT ON;
SET STATISTICS XML OFF;

/*Create supporting index*/
CREATE NONCLUSTERED INDEX [IX_AGG]
  ON [tempdb].[dbo].[BlitzWho_..BlitzWhoOut..] ([database_name], [start_time], [query_hash], [session_id], [elapsed_time] );

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @DatabaseName NVARCHAR(128);

SET @DatabaseName = N'';

/*Standard output*/
SELECT [CheckDate],
       [start_time],
       [elapsed_time],
       [session_id],
       [database_name],
       [query_text],
       [query_cost],
       [status],
       [cached_parameter_info],
       [wait_info],
       [top_session_waits],
       [blocking_session_id],
       [open_transaction_count],
       [is_implicit_transaction],
       [nt_domain],
       [host_name],
       [login_name],
       [nt_user_name],
       [program_name],
       [fix_parameter_sniffing],
       [client_interface_name],
       [login_time],
       [start_time],
       [request_time],
       [request_cpu_time],
       [request_logical_reads],
       [request_writes],
       [request_physical_reads],
       [session_cpu],
       [session_logical_reads],
       [session_physical_reads],
       [session_writes],
       [tempdb_allocations_mb],
       [memory_usage],
       [estimated_completion_time],
       [percent_complete],
       [deadlock_priority],
       [transaction_isolation_level],
       [degree_of_parallelism],
       [grant_time],
       [requested_memory_kb],
       [grant_memory_kb],
       [is_request_granted],
       [required_memory_kb],
       [query_memory_grant_used_memory_kb],
       [ideal_memory_kb],
       [is_small],
       [timeout_sec],
       [resource_semaphore_id],
       [wait_order],
       [wait_time_ms],
       [next_candidate_for_memory_grant],
       [target_memory_kb],
       [max_target_memory_kb],
       [total_memory_kb],
       [available_memory_kb],
       [granted_memory_kb],
       [query_resource_semaphore_used_memory_kb],
       [grantee_count],
       [waiter_count],
       [timeout_error_count],
       [forced_grant_count],
       [workload_group_name],
       [resource_pool_name],
	   [query_hash]
FROM   [tempdb].[dbo].[BlitzWho_..BlitzWhoOut..]
WHERE  [database_name] = CASE
                           WHEN @DatabaseName = N'' THEN [database_name]
                           ELSE @DatabaseName
                         END
AND [program_name] NOT LIKE N'PSBlitz%';

/*Aggregate output*/
;WITH agg ( ID, [session_id], [query_hash], start_time, [TotalExecTime])
     AS (SELECT MAX(ID),
                [session_id],
                [query_hash],
                [start_time],
                MAX([elapsed_time]) AS [TotalExecTime]
         FROM   [tempdb].[dbo].[BlitzWho_..BlitzWhoOut..]
         WHERE  [database_name] = CASE
                                    WHEN @DatabaseName = N'' THEN [database_name]
                                    ELSE @DatabaseName
                                  END
		AND [program_name] NOT LIKE N'PSBlitz%'
         GROUP  BY [session_id],
                   [query_hash],
                   [start_time])
SELECT [agg].[start_time],
       [who].[elapsed_time],
       [agg].[session_id],
       [who].[database_name],
       [who].[query_text],
       [who].[outer_command],
       [who].[query_plan],
       [who].[query_cost],
       [who].[status],
       [who].[cached_parameter_info],
       [who].[wait_info],
       [who].[top_session_waits],
       [who].[blocking_session_id],
       [who].[open_transaction_count],
       [who].[is_implicit_transaction],
       [who].[nt_domain],
       [who].[host_name],
       [who].[login_name],
       [who].[nt_user_name],
       [who].[program_name],
       [who].[fix_parameter_sniffing],
       [who].[client_interface_name],
       [who].[login_time],
       [who].[request_time],
       [who].[request_cpu_time],
       [who].[request_logical_reads],
       [who].[request_writes],
       [who].[request_physical_reads],
       [who].[session_cpu],
       [who].[session_logical_reads],
       [who].[session_physical_reads],
       [who].[session_writes],
       [who].[tempdb_allocations_mb],
       [who].[memory_usage],
       [who].[estimated_completion_time],
       [who].[percent_complete],
       [who].[deadlock_priority],
       [who].[transaction_isolation_level],
       [who].[degree_of_parallelism],
       [who].[grant_time],
       [who].[requested_memory_kb],
       [who].[grant_memory_kb],
       [who].[is_request_granted],
       [who].[required_memory_kb],
       [who].[query_memory_grant_used_memory_kb],
       [who].[ideal_memory_kb],
       [who].[is_small],
       [who].[timeout_sec],
       [who].[resource_semaphore_id],
       [who].[wait_order],
       [who].[wait_time_ms],
       [who].[next_candidate_for_memory_grant],
       [who].[target_memory_kb],
       [who].[max_target_memory_kb],
       [who].[total_memory_kb],
       [who].[available_memory_kb],
       [who].[granted_memory_kb],
       [who].[query_resource_semaphore_used_memory_kb],
       [who].[grantee_count],
       [who].[waiter_count],
       [who].[timeout_error_count],
       [who].[forced_grant_count],
       [who].[workload_group_name],
       [who].[resource_pool_name],
       [agg].[query_hash],
       [who].[query_plan_hash]
FROM   [tempdb].[dbo].[BlitzWho_..BlitzWhoOut..] [who]
       INNER JOIN [agg]
               ON [who].[ID] = [agg].ID
ORDER  BY [elapsed_time] DESC;

/*Cleanup*/
IF OBJECT_ID(N'tempdb.dbo.BlitzWho_..BlitzWhoOut..', N'U') IS NOT NULL
  BEGIN
      DROP TABLE [tempdb].[dbo].[BlitzWho_..BlitzWhoOut..];
  END;
IF OBJECT_ID(N'tempdb.dbo.BlitzWhoOutFlag_..BlitzWhoOut..', N'U') IS NOT NULL
  BEGIN
      DROP TABLE [tempdb].[dbo].[BlitzWhoOutFlag_..BlitzWhoOut..];
  END;