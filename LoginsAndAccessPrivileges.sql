
-- Create TempTable to Store Info
IF OBJECT_ID('tempdb.dbo.##AuditResults', 'U') IS NOT NULL
  DROP TABLE ##AuditResults;
  GO

CREATE TABLE ##AuditResults (
       [ServerName] [nvarchar](128) NULL
       ,[DBName] [nvarchar](128) NULL
       ,[UserName] [nvarchar](128) NULL
       ,[UserType] [nvarchar](60) NULL
       ,[DatabaseUserName] [nvarchar](128) NULL
       ,[Role] [nvarchar](128) NULL
       ,[PermissionType] [nvarchar](128) NULL
       ,[PermissionState] [nvarchar](60) NULL
       ,[ObjectType] [nvarchar](60) NULL
       ,[ObjectName] [nvarchar](128) NULL
       ,[ColumnName] [nvarchar](128) NULL
	   ,[ExecutionDate] [datetime] NOT NULL
	   ,[Performer] [varchar](1000) NULL
	   
       ) ON [PRIMARY]
GO

-- Add Server and Database Name
DECLARE @AuditId INT = 12312;
DECLARE @AuditQuery VARCHAR(MAX);

SELECT @AuditQuery = 
       '
USE [?]
INSERT INTO ##AuditResults
(
       [ServerName],
       [DBName],
       [UserName],
       [UserType],
       [DatabaseUserName] ,
       [Role],
       [PermissionType],
       [PermissionState] ,
       [ObjectType],
       [ObjectName],
       [ColumnName],
	   [ExecutionDate], 
	   [Performer]
)
SELECT 
@@SERVERNAME COLLATE SQL_Latin1_General_CP1_CI_AS as ServerName , 
db_name() COLLATE SQL_Latin1_General_CP1_CI_AS as DBName, a.*
FROM (

SELECT  
    [UserName] = CASE princ.[type] 
                    WHEN ''S'' THEN princ.[name] COLLATE SQL_Latin1_General_CP1_CI_AS
                    WHEN ''U'' THEN ulogin.[name] COLLATE SQL_Latin1_General_CP1_CI_AS
                 END,
    [UserType] = CASE princ.[type]
                    WHEN ''S'' THEN ''SQL User''
                    WHEN ''U'' THEN ''Windows User''
                 END,  
    [DatabaseUserName] = princ.[name] COLLATE SQL_Latin1_General_CP1_CI_AS,       
    [Role] = null,      
    [PermissionType] = perm.[permission_name] COLLATE SQL_Latin1_General_CP1_CI_AS,       
    [PermissionState] = perm.[state_desc] COLLATE SQL_Latin1_General_CP1_CI_AS,       
    [ObjectType] = obj.type_desc,--perm.[class_desc],       
    [ObjectName] = OBJECT_NAME(perm.major_id) COLLATE SQL_Latin1_General_CP1_CI_AS,
    [ColumnName] = col.[name] COLLATE SQL_Latin1_General_CP1_CI_AS,
	[ExecutionDate] = GETdate(), 
	[Performer]= SYSTEM_USER

FROM    
    --database user
    sys.database_principals princ  
LEFT JOIN
    --Login accounts
    sys.login_token ulogin on princ.[sid] = ulogin.[sid]
LEFT JOIN        
    --Permissions
    sys.database_permissions perm ON perm.[grantee_principal_id] = princ.[principal_id]
LEFT JOIN
    --Table columns
    sys.columns col ON col.[object_id] = perm.major_id 
                    AND col.[column_id] = perm.[minor_id]
LEFT JOIN
    sys.objects obj ON perm.[major_id] = obj.[object_id]
WHERE 
    princ.[type] in (''S'',''U'')
UNION
--List all access provisioned to a sql user or windows user/group through a database or application role
SELECT  
    [UserName] = CASE memberprinc.[type] 
                    WHEN ''S'' THEN memberprinc.[name] COLLATE SQL_Latin1_General_CP1_CI_AS
                    WHEN ''U'' THEN ulogin.[name] COLLATE SQL_Latin1_General_CP1_CI_AS
                 END,
    [UserType] = CASE memberprinc.[type]
                    WHEN ''S'' THEN ''SQL User''
                    WHEN ''U'' THEN ''Windows User''
                 END, 
    [DatabaseUserName] = memberprinc.[name] COLLATE SQL_Latin1_General_CP1_CI_AS,   
    [Role] = roleprinc.[name] COLLATE SQL_Latin1_General_CP1_CI_AS,      
    [PermissionType] = perm.[permission_name]COLLATE SQL_Latin1_General_CP1_CI_AS,       
    [PermissionState] = perm.[state_desc] COLLATE SQL_Latin1_General_CP1_CI_AS,       
    [ObjectType] = obj.type_desc COLLATE SQL_Latin1_General_CP1_CI_AS,--perm.[class_desc],   
    [ObjectName] = OBJECT_NAME(perm.major_id)COLLATE SQL_Latin1_General_CP1_CI_AS,
    [ColumnName] = col.[name] COLLATE SQL_Latin1_General_CP1_CI_AS,
	[ExecutionDate] = GETdate(), 
	[Performer]= SYSTEM_USER
FROM    
    --Role/member associations
    sys.database_role_members members
JOIN
    --Roles
    sys.database_principals roleprinc ON roleprinc.[principal_id] = members.[role_principal_id]
JOIN
    --Role members (database users)
    sys.database_principals memberprinc ON memberprinc.[principal_id] = members.[member_principal_id]
LEFT JOIN
    --Login accounts
    sys.login_token ulogin on memberprinc.[sid] = ulogin.[sid]
LEFT JOIN        
    --Permissions
    sys.database_permissions perm ON perm.[grantee_principal_id] = roleprinc.[principal_id]
LEFT JOIN
    --Table columns
    sys.columns col on col.[object_id] = perm.major_id 
                    AND col.[column_id] = perm.[minor_id]
LEFT JOIN
    sys.objects obj ON perm.[major_id] = obj.[object_id]
UNION
--List all access provisioned to the public role, which everyone gets by default
SELECT  
    [UserName] = ''{All Users}'',
    [UserType] = ''{All Users}'', 
    [DatabaseUserName] = ''{All Users}'',       
    [Role] = roleprinc.[name] COLLATE SQL_Latin1_General_CP1_CI_AS,      
    [PermissionType] = perm.[permission_name] COLLATE SQL_Latin1_General_CP1_CI_AS,       
    [PermissionState] = perm.[state_desc] COLLATE SQL_Latin1_General_CP1_CI_AS,       
    [ObjectType] = obj.type_desc COLLATE SQL_Latin1_General_CP1_CI_AS,--perm.[class_desc],  
    [ObjectName] = OBJECT_NAME(perm.major_id) COLLATE SQL_Latin1_General_CP1_CI_AS,
    [ColumnName] = col.[name] COLLATE SQL_Latin1_General_CP1_CI_AS,
	[ExecutionDate] = GETdate(), 
	[Performer]= SYSTEM_USER
FROM    
    --Roles
    sys.database_principals roleprinc
LEFT JOIN        
    --Role permissions
    sys.database_permissions perm ON perm.[grantee_principal_id] = roleprinc.[principal_id]
LEFT JOIN
    --Table columns
    sys.columns col on col.[object_id] = perm.major_id 
                    AND col.[column_id] = perm.[minor_id]                   
JOIN 
    --All objects   
    sys.objects obj ON obj.[object_id] = perm.[major_id]
WHERE
    --Only roles
    roleprinc.[type] = ''R'' AND
    --Only public role
    roleprinc.[name] = ''public'' AND
    --Only objects of ours, not the MS objects
    obj.is_ms_shipped = 0

UNION 
SELECT member.name COLLATE SQL_Latin1_General_CP1_CI_AS AS UserName, 
       role.type_desc COLLATE SQL_Latin1_General_CP1_CI_AS as UserType, 
       null as DatabaseUserName, role.name as Role, 
   [PermissionType] = null,
    [PermissionState] = null,
    [ObjectType] = null,
    [ObjectName] = null,
    [ColumnName] = null,
	[ExecutionDate] = GETdate(), 
	[Performer]= SYSTEM_USER
	
FROM sys.server_role_members  
JOIN sys.server_principals AS role  
    ON sys.server_role_members.role_principal_id = role.principal_id  
JOIN sys.server_principals AS member  
    ON sys.server_role_members.member_principal_id = member.principal_id
) a
'

SET NOCOUNT ON;

DECLARE @database_name VARCHAR(300) -- Stores database name for use in the cursor
DECLARE @sql_command_to_execute NVARCHAR(MAX) -- Will store the TSQL after the database name has been inserted
       -- Stores our final list of databases to iterate through, after filters have been applied
DECLARE @database_names TABLE (database_name VARCHAR(100))
DECLARE @SQL VARCHAR(MAX) -- Will store TSQL used to determine database list

SET @SQL = '      SELECT
                     SD.name AS database_name
              FROM sys.databases SD
			  where SD.state = 0
			  AND replica_id IS NULL
       '

-- If Database is Mirrored it will be excluded from the check 
-- Prepare database name list
INSERT INTO @database_names (database_name)
EXEC (@SQL)

DECLARE db_cursor CURSOR
FOR
SELECT database_name
FROM @database_names

OPEN db_cursor

FETCH NEXT
FROM db_cursor
INTO @database_name

WHILE @@FETCH_STATUS = 0
BEGIN
       SET @sql_command_to_execute = REPLACE(@AuditQuery, '?', @database_name) -- Replace "?" with the database name

       EXEC sp_executesql @sql_command_to_execute

       FETCH NEXT
       FROM db_cursor
       INTO @database_name
END

CLOSE db_cursor;

DEALLOCATE db_cursor;

SELECT *
FROM ##AuditResults

DROP TABLE ##AuditResults
