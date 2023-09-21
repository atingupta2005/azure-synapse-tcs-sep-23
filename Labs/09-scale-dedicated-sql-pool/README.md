# Scale Dedicated SQL Pool
## Connect to the server as server admin
- Use SQL Server Management Studio (SSMS) to establish a connection to your Azure SQL server.

## View service objective
- The service objective setting contains the number of data warehouse units for the dedicated SQL pool
- To view the current data warehouse units for your dedicated SQL pool 
  - Right-click on the master system database and select New Query
```
SELECT
    db.name AS [Database]
,    ds.edition AS [Edition]
,    ds.service_objective AS [Service Objective]
FROM
     sys.database_service_objectives ds
JOIN
    sys.databases db ON ds.database_id = db.database_id
WHERE
    db.name = 'mySampleDataWarehouse';
```

## Scale compute
- In dedicated SQL pool (formerly SQL DW), you can increase or decrease compute resources by adjusting data warehouse units.
```
ALTER DATABASE mySampleDataWarehouse
MODIFY (SERVICE_OBJECTIVE = 'DW300c');
```

## Monitor scale change request
- To see the progress of the previous change request, you can use the WAITFORDELAY T-SQL syntax to poll the sys.dm_operation_status dynamic management view (DMV).
```
WHILE
(
    SELECT TOP 1 state_desc
    FROM sys.dm_operation_status
    WHERE
        1=1
        AND resource_type_desc = 'Database'
        AND major_resource_id = 'mySampleDataWarehouse'
        AND operation = 'ALTER DATABASE'
    ORDER BY
        start_time DESC
) = 'IN_PROGRESS'
BEGIN
    RAISERROR('Scale operation in progress',0,0) WITH NOWAIT;
    WAITFOR DELAY '00:00:05';
END
PRINT 'Complete';
```

## Check dedicated SQL pool state
- When a dedicated SQL pool (formerly SQL DW) is paused, you can't connect to it with T-SQL
- To see the current state of the dedicated SQL pool (formerly SQL DW), you can use a PowerShell cmdlet
```
$database | Select-Object DatabaseName, Status
```

## Check operation status
- To return information about various management operations on your dedicated SQL pool (formerly SQL DW), run the following query
```
SELECT *
FROM
    sys.dm_operation_status
WHERE
    resource_type_desc = 'Database'
AND
    major_resource_id = 'mySampleDataWarehouse';
```

