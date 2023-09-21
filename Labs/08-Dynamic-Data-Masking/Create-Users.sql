USE MASTER;

DROP LOGIN atingupta  
DROP USER atingupta  

-- Creates the login
CREATE LOGIN atingupta
    WITH PASSWORD = '340$Uuxwp7Mcxo7Khy';  
GO  

-- Creates a database user for the login created above.  
CREATE USER atingupta FOR LOGIN atingupta;  
GO  


GRANT SELECT ON SCHEMA :: dbo TO atingupta;

