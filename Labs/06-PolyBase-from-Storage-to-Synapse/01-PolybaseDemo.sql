/*

PolyBase 6 steps Process

1. CREATE MASTER KEY
2. CREATE DATABASE SCOPED CREDENTIAL
3. CREATE EXTERNAL DATA SOURCE
4. CREATE EXTERNAL FILE FORMAT 
5. CREATE EXTERNAL TABLE
6. CREATE TABLE AS 
*/

-- Connect to SQL Pool
-- Drop existing resources if exists

DROP TABLE [prod].[FactTransactionHistory_atin] 
DROP SCHEMA [prod]
DROP EXTERNAL TABLE [stage].FactTransactionHistory_atin
DROP SCHEMA stage
DROP EXTERNAL FILE FORMAT CSVFileFormat_atin
DROP EXTERNAL DATA SOURCE AzureBlobStorage_atin
DROP DATABASE SCOPED CREDENTIAL BlobStorageCredential_atin
DROP MASTER KEY

/*
1. Create a Database Master Key. Only necessary if one does not already exist.
   Required to encrypt the credential secret in the next step.
   To access your Data Lake Storage account, you will need to create a Database Master Key to encrypt your credential secret. 
   You then create a Database Scoped Credential to store your secret. 
   When authenticating using service principals (Azure Directory Application user), 
   the Database Scoped Credential stores the service principal credentials set up in AAD. 
   You can also use the Database Scoped Credential to store the storage account key for Blob storage.
*/

-- DROP MASTER KEY
CREATE MASTER KEY;
GO

/*
  2.(for blob storage key authentication): Create a database scoped credential
    IDENTITY: Provide any string, it is not used for authentication to Azure storage.
    SECRET: Provide your Azure storage account key.
*/

--DROP DATABASE SCOPED CREDENTIAL BlobStorageCredential
CREATE DATABASE SCOPED CREDENTIAL BlobStorageCredential_atin
WITH
    IDENTITY = 'blobuser',
	SECRET = 'wE5yOuIk/H7+LuE9erRoEZIPe7ZLpcsewtf7WTZxgGP9tz+SuVqno6TYHbDgZ+NS0xFxbmwz8mLq+AStsgMq4w=='
;
GO

/*
	 3 (for blob): Create an external data source
	 TYPE: HADOOP - PolyBase uses Hadoop APIs to access data in Azure Data Lake Storage.
	 LOCATION: Provide Data Lake Storage blob account name and URI
	 CREDENTIAL: Provide the credential created in the previous step.
*/

--DROP EXTERNAL DATA SOURCE AzureBlobStorage
CREATE EXTERNAL DATA SOURCE AzureBlobStorage_atin
WITH (
    TYPE = HADOOP,
    LOCATION = 'wasbs://fthdata@sasharestudymtrl61222.blob.core.windows.net',
    CREDENTIAL = BlobStorageCredential_atin
);
GO

/*
	 4: Create an external file format
	 FIELD_TERMINATOR: Marks the end of each field (column) in a delimited text file
	 STRING_DELIMITER: Specifies the field terminator for data of type string in the text-delimited file.
	 DATE_FORMAT: Specifies a custom format for all date and time data that might appear in a delimited text file.
	 Use_Type_Default: Store missing values as default for datatype.
*/

--DROP EXTERNAL FILE FORMAT CSVFileFormat 
CREATE EXTERNAL FILE FORMAT CSVFileFormat_atin
WITH 
(   FORMAT_TYPE = DELIMITEDTEXT
,   FORMAT_OPTIONS  (   FIELD_TERMINATOR = ','
                    ,   STRING_DELIMITER = ''
                    ,   DATE_FORMAT      = 'yyyy-MM-dd HH:mm:ss'
                    ,   USE_TYPE_DEFAULT = FALSE 
                    )
);
GO

/*
	 5: Create an External Table
	 LOCATION: Folder under the Data Lake Storage root folder.
	 DATA_SOURCE: Specifies which Data Source Object to use.
	 FILE_FORMAT: Specifies which File Format Object to use
	 REJECT_TYPE: Specifies how you want to deal with rejected rows. Either Value or percentage of the total
	 REJECT_VALUE: Sets the Reject value based on the reject type.
*/

/* IMP NOTE
External Tables are strongly typed. 
This means that each row of the data being ingested must satisfy the table schema definition. 
If a row does not match the schema definition, the row is rejected from the load.
*/

--DROP EXTERNAL TABLE [stage].FactTransactionHistory 
--DROP SCHEMA stage

CREATE SCHEMA [stage];
GO

CREATE EXTERNAL TABLE [stage].FactTransactionHistory_atin
(
    [TransactionID] [int] NOT NULL,
	[ProductKey] [int] NOT NULL,
	[OrderDate] [datetime] NULL,
	[Quantity] [int] NULL,
	[ActualCost] [money] NULL
)
WITH
(
    LOCATION='/' 
,   DATA_SOURCE = AzureBlobStorage_atin
,   FILE_FORMAT = CSVFileFormat_atin
,   REJECT_TYPE = VALUE
,   REJECT_VALUE = 0
)
GO


SELECT TOP (1000) [TransactionID]
      ,[ProductKey]
      ,[OrderDate]
      ,[Quantity]
      ,[ActualCost]
FROM [stage].[FactTransactionHistory_atin]

SELECT count(*), [ProductKey]
FROM [stage].[FactTransactionHistory_atin]


/* 6 CREATE TABLE AS  - CTAS
	CTAS creates a new table and populates it with the results of a select statement. 
	CTAS defines the new table to have the same columns and data types as the results of the select statement. 
	If you select all the columns from an external table, the new table is a replica of the columns and data types in the external table.
*/

-- DROP SCHEMA [prod]
CREATE SCHEMA [prod];
GO

--DROP TABLE [prod].[FactTransactionHistory] 
CREATE TABLE [prod].[FactTransactionHistory_atin]       
WITH (DISTRIBUTION = HASH([ProductKey]  ) ) 
AS 
SELECT * FROM [stage].[FactTransactionHistory_atin]        
OPTION (LABEL = 'Load [prod].[FactTransactionHistory_atin]');



-- Verify number of rows
SELECT count(1) FROM [prod].[FactTransactionHistory_atin]

/*
By default, tables are defined as a clustered columnstore index. 
After a load completes, some of the data rows might not be compressed into the columnstore. 
To optimize query performance and columnstore compression after a load, rebuild the table to force the columnstore index to compress all the rows.
*/
ALTER INDEX ALL ON [prod].[FactTransactionHistory_atin] REBUILD;


-- verify the data was loaded into the 60 distributions
-- Find data skew for a distributed table
DBCC PDW_SHOWSPACEUSED('prod.FactTransactionHistory_atin');
