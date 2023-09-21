# Monitor Synapse Studio
- Open Monitor TAB in Synapse Workspace
- Inspect all the tabs available in monitor
- Inspect the last execution of Copy data in pipeline runs
- Refer SQL Request tab:
	- Open Request ID for details
- Refer SQL pools
	- Open each SQL pool and notice the DWU usage
- Refer Apache Spark Pool


## Monitor connections
- All logins to your data warehouse are logged to sys.dm_pdw_exec_sessions. This DMV contains the last 10,000 logins. - The session_id is the primary key and is assigned sequentially for each new login.

```
-- Other Active Connections
SELECT * FROM sys.dm_pdw_exec_sessions where status <> 'Closed' and session_id <> session_id();
```

## Monitor query execution
- All queries executed on SQL pool are logged to sys.dm_pdw_exec_requests. 
### Step 1: Identify the query you wish to investigate
```
-- Monitor active queries
SELECT *
FROM sys.dm_pdw_exec_requests
WHERE status not in ('Completed','Failed','Cancelled')
  AND session_id <> session_id()
ORDER BY submit_time DESC;

-- Find top 10 queries longest running queries
SELECT TOP 10 *
FROM sys.dm_pdw_exec_requests
ORDER BY total_elapsed_time DESC;
```

- From the preceding query results, note the Request ID of the query that you would like to investigate.
- Queries in the Suspended state can be queued due to a large number of active running queries
- These queries also appear in the sys.dm_pdw_waits.

- To simplify the lookup of a query in the sys.dm_pdw_exec_requests table, use LABEL to assign a comment to your query, which can be looked up in the sys.dm_pdw_exec_requests view.
```
-- Query with Label
SELECT *
FROM sys.tables
OPTION (LABEL = 'My Query')
;

-- Find a query with the Label 'My Query'
-- Use brackets when querying the label column, as it it a key word
SELECT  *
FROM    sys.dm_pdw_exec_requests
WHERE   [label] = 'My Query';
```

### Step 2: Investigate the query plan
- Use the Request ID to retrieve the query's distributed SQL (DSQL) plan from sys.dm_pdw_request_steps

```
-- Find the distributed query plan steps for a specific query.
-- Replace request_id with value from Step 1.

SELECT * FROM sys.dm_pdw_request_steps
WHERE request_id = 'QID####'
ORDER BY step_index;
```

### Step 3: Investigate SQL on the distributed databases
- Use the Request ID and the Step Index to retrieve details from sys.dm_pdw_sql_requests, which contains execution information of the query step on all of the distributed databases.
```
-- Find the distribution run times for a SQL step.
-- Replace request_id and step_index with values from Step 1 and 3.

SELECT * FROM sys.dm_pdw_sql_requests
WHERE request_id = 'QID####' AND step_index = 2;
```

- When the query step is running, DBCC PDW_SHOWEXECUTIONPLAN can be used to retrieve the SQL Server estimated plan from the SQL Server plan cache for the step running on a particular distribution.

```
-- Find the SQL Server execution plan for a query running on a specific SQL pool or control node.
-- Replace distribution_id and spid with values from previous query.

DBCC PDW_SHOWEXECUTIONPLAN(1, 78);
```


### Step 4: Investigate data movement on the distributed databases
- Use the Request ID and the Step Index to retrieve information about a data movement step running on each distribution from sys.dm_pdw_dms_workers.

```
-- Find information about all the workers completing a Data Movement Step.
-- Replace request_id and step_index with values from Step 1 and 3.

SELECT * FROM sys.dm_pdw_dms_workers
WHERE request_id = 'QID####' AND step_index = 2;
```

- Check the total_elapsed_time column to see if a particular distribution is taking significantly longer than others for data movement.
- For the long-running distribution, check the rows_processed column to see if the number of rows being moved from that distribution is significantly larger than others. If so, this finding might indicate skew of your underlying data. One cause for data skew is distributing on a column with many NULL values (whose rows will all land in the same distribution). Prevent slow queries by avoiding distribution on these types of columns or filtering your query to eliminate NULLs when possible.

- If the query is running, you can use DBCC PDW_SHOWEXECUTIONPLAN to retrieve the SQL Server estimated plan from the SQL Server plan cache for the currently running SQL Step within a particular distribution.

```
-- Find the SQL Server estimated plan for a query running on a specific SQL pool Compute or control node.
-- Replace distribution_id and spid with values from previous query.

DBCC PDW_SHOWEXECUTIONPLAN(55, 238);
```


### Monitor waiting queries
- If you discover that your query is not making progress because it is waiting for a resource, here is a query that shows all the resources a query is waiting for.
```
-- Find queries
-- Replace request_id with value from Step 1.

SELECT waits.session_id,
      waits.request_id,
      requests.command,
      requests.status,
      requests.start_time,
      waits.type,
      waits.state,
      waits.object_type,
      waits.object_name
FROM   sys.dm_pdw_waits waits
   JOIN  sys.dm_pdw_exec_requests requests
   ON waits.request_id=requests.request_id
WHERE waits.request_id = 'QID####'
ORDER BY waits.object_name, waits.object_type, waits.state;
```

- If the query is actively waiting on resources from another query, then the state will be AcquireResources. If the query has all the required resources, then the state will be Granted.

### Monitor tempdb
- The tempdb database is used to hold intermediate results during query execution. High utilization of the tempdb database can lead to slow query performance. For every DW100c configured, 399 GB of tempdb space is allocated (DW1000c would have 3.99 TB of total tempdb space). Below are tips for monitoring tempdb usage and for decreasing tempdb usage in your queries.

### Monitor tempdb with views
- To monitor tempdb usage, first install the microsoft.vw_sql_requests view from the Microsoft Toolkit for SQL pool. You can then execute the following query to see the tempdb usage per node for all executed queries:

```
-- Monitor tempdb
SELECT
    sr.request_id,
    ssu.session_id,
    ssu.pdw_node_id,
    sr.command,
    sr.total_elapsed_time,
    exs.login_name AS 'LoginName',
    DB_NAME(ssu.database_id) AS 'DatabaseName',
    (es.memory_usage * 8) AS 'MemoryUsage (in KB)',
    (ssu.user_objects_alloc_page_count * 8) AS 'Space Allocated For User Objects (in KB)',
    (ssu.user_objects_dealloc_page_count * 8) AS 'Space Deallocated For User Objects (in KB)',
    (ssu.internal_objects_alloc_page_count * 8) AS 'Space Allocated For Internal Objects (in KB)',
    (ssu.internal_objects_dealloc_page_count * 8) AS 'Space Deallocated For Internal Objects (in KB)',
    CASE es.is_user_process
    WHEN 1 THEN 'User Session'
    WHEN 0 THEN 'System Session'
    END AS 'SessionType',
    es.row_count AS 'RowCount'
FROM sys.dm_pdw_nodes_db_session_space_usage AS ssu
    INNER JOIN sys.dm_pdw_nodes_exec_sessions AS es ON ssu.session_id = es.session_id AND ssu.pdw_node_id = es.pdw_node_id
    INNER JOIN sys.dm_pdw_nodes_exec_connections AS er ON ssu.session_id = er.session_id AND ssu.pdw_node_id = er.pdw_node_id
    INNER JOIN microsoft.vw_sql_requests AS sr ON ssu.session_id = sr.spid AND ssu.pdw_node_id = sr.pdw_node_id
    LEFT JOIN sys.dm_pdw_exec_requests exr on exr.request_id = sr.request_id
    LEFT JOIN sys.dm_pdw_exec_sessions exs on exr.session_id = exs.session_id
WHERE DB_NAME(ssu.database_id) = 'tempdb'
    AND es.session_id <> @@SPID
    AND es.login_name <> 'sa'
ORDER BY sr.request_id;
```

### Monitor memory
- Memory can be the root cause for slow performance and out of memory issues. Consider scaling your data warehouse if you find SQL Server memory usage reaching its limits during query execution.

- The following query returns SQL Server memory usage and memory pressure per node:


```
-- Memory consumption
SELECT
  pc1.cntr_value as Curr_Mem_KB,
  pc1.cntr_value/1024.0 as Curr_Mem_MB,
  (pc1.cntr_value/1048576.0) as Curr_Mem_GB,
  pc2.cntr_value as Max_Mem_KB,
  pc2.cntr_value/1024.0 as Max_Mem_MB,
  (pc2.cntr_value/1048576.0) as Max_Mem_GB,
  pc1.cntr_value * 100.0/pc2.cntr_value AS Memory_Utilization_Percentage,
  pc1.pdw_node_id
FROM
-- pc1: current memory
sys.dm_pdw_nodes_os_performance_counters AS pc1
-- pc2: total memory allowed for this SQL instance
JOIN sys.dm_pdw_nodes_os_performance_counters AS pc2
ON pc1.object_name = pc2.object_name AND pc1.pdw_node_id = pc2.pdw_node_id
WHERE
pc1.counter_name = 'Total Server Memory (KB)'
AND pc2.counter_name = 'Target Server Memory (KB)'
```

### Monitor transaction log size
- The following query returns the transaction log size on each distribution. If one of the log files is reaching 160 GB, you should consider scaling up your instance or limiting your transaction size.

```
-- Transaction log size
SELECT
  instance_name as distribution_db,
  cntr_value*1.0/1048576 as log_file_size_used_GB,
  pdw_node_id
FROM sys.dm_pdw_nodes_os_performance_counters
WHERE
instance_name like 'Distribution_%'
AND counter_name = 'Log File(s) Used Size (KB)'
```


### Monitor transaction log rollback
- If your queries are failing or taking a long time to proceed, you can check and monitor if you have any transactions rolling back.

```
-- Monitor rollback
SELECT
    SUM(CASE WHEN t.database_transaction_next_undo_lsn IS NOT NULL THEN 1 ELSE 0 END),
    t.pdw_node_id,
    nod.[type]
FROM sys.dm_pdw_nodes_tran_database_transactions t
JOIN sys.dm_pdw_nodes nod ON t.pdw_node_id = nod.pdw_node_id
GROUP BY t.pdw_node_id, nod.[type]
```


### Monitor PolyBase load
- The following query provides an approximate estimate of the progress of your load. The query only shows files currently being processed.

```
-- To track bytes and files
SELECT
    r.command,
    s.request_id,
    r.status,
    count(distinct input_name) as nbr_files,
    sum(s.bytes_processed)/1024/1024/1024 as gb_processed
FROM
    sys.dm_pdw_exec_requests r
    inner join sys.dm_pdw_dms_external_work s
        on r.request_id = s.request_id
GROUP BY
    r.command,
    s.request_id,
    r.status
ORDER BY
    nbr_files desc,
    gb_processed desc;
```

### Monitor query blockings
- The following query provides the top 500 blocked queries in the environment.

```
--Collect the top blocking
SELECT
    TOP 500 waiting.request_id AS WaitingRequestId,
    waiting.object_type AS LockRequestType,
    waiting.object_name AS ObjectLockRequestName,
    waiting.request_time AS ObjectLockRequestTime,
    blocking.session_id AS BlockingSessionId,
    blocking.request_id AS BlockingRequestId
FROM
    sys.dm_pdw_waits waiting
    INNER JOIN sys.dm_pdw_waits blocking
    ON waiting.object_type = blocking.object_type
    AND waiting.object_name = blocking.object_name
WHERE
    waiting.state = 'Queued'
    AND blocking.state = 'Granted'
ORDER BY
    ObjectLockRequestTime ASC;
```

### Retrieve query text from waiting and blocking queries
- The following query provides the query text and identifier for the waiting and blocking queries to easily troubleshoot.

```
-- To retrieve query text from waiting and blocking queries

SELECT waiting.session_id AS WaitingSessionId,
       waiting.request_id AS WaitingRequestId,
       COALESCE(waiting_exec_request.command,waiting_exec_request.command2) AS WaitingExecRequestText,
       blocking.session_id AS BlockingSessionId,
       blocking.request_id AS BlockingRequestId,
       COALESCE(blocking_exec_request.command,blocking_exec_request.command2) AS BlockingExecRequestText,
       waiting.object_name AS Blocking_Object_Name,
       waiting.object_type AS Blocking_Object_Type,
       waiting.type AS Lock_Type,
       waiting.request_time AS Lock_Request_Time,
       datediff(ms, waiting.request_time, getdate())/1000.0 AS Blocking_Time_sec
FROM sys.dm_pdw_waits waiting
       INNER JOIN sys.dm_pdw_waits blocking
       ON waiting.object_type = blocking.object_type
       AND waiting.object_name = blocking.object_name
       INNER JOIN sys.dm_pdw_exec_requests blocking_exec_request
       ON blocking.request_id = blocking_exec_request.request_id
       INNER JOIN sys.dm_pdw_exec_requests waiting_exec_request
       ON waiting.request_id = waiting_exec_request.request_id
WHERE waiting.state = 'Queued'
       AND blocking.state = 'Granted'
ORDER BY Lock_Request_Time DESC;
```
