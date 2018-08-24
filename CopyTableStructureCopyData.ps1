########################################################################################################################################
#This is script is not 100% mine - I got it from [https://stackoverflow.com/users/6947281/vivek-kumar-singh] and adapted to my environment needs
#Connects to SQL Sevrer instance, verify the tables in the database and create the structure on the destination instance
#I scheduled it to run daily on SQL Agent and the list of server must be saved on a directory where SQL Server instance has access  
#Comments and Improvements are Welcome
########################################################################################################################################

$so = New-Object Microsoft.SqlServer.Management.Smo.ScriptingOptions; 
$so.DriAllConstraints = $true; 
$so.DriAllKeys = $true;
$so.DriClustered = $true; 
$so.DriDefaults = $true; 
$so.DriIndexes = $true; 
$so.DriNonClustered = $true; 
$so.DriPrimaryKey = $true; 
$so.DriUniqueKeys = $true; 
$so.AnsiFile = $true; 
$so.ClusteredIndexes  = $true; 
$so.IncludeHeaders = $true; 
$so.Indexes = $true; 
$so.SchemaQualify = $true; 
$so.Triggers = $true; 
$so.XmlIndexes = $true; 

#Hard-Coding the Server and database info
$SourceServer = "Server01"
$SourceDatabase = "DB01"
$TargetServer = "Server02"
$TargetDatabase = "DB02"


#Creating folders for storing Create_Database text files if they don't exist
If(!(Test-Path C:\TEST)) 
{
    New-Item -ItemType Directory -Force -Path C:\TEST
}

#Creating the database connection object for Source server
$Srcsrv = new-Object Microsoft.SqlServer.Management.Smo.Server($Sourceserver);
$Srcdb = New-Object Microsoft.SqlServer.Management.Smo.Database;
$Srcdb = $Srcsrv.Databases.Item($SourceDatabase);

#Creating the database connection object for Destination server
$Destsrv = new-Object Microsoft.SqlServer.Management.Smo.Server($TargetServer);
$Destdb = New-Object Microsoft.SqlServer.Management.Smo.Database;
$Destdb = $Destsrv.Databases.Item($TargetDatabase);

foreach ($table in $Srcdb.Tables)
{
    $table.Script($so) | Out-File -FilePath C:\TEST\$($table.Name).txt
    $CreatedbQuery = Get-Content C:\TEST\$($table.Name).txt | Out-String
    Invoke-sqlcmd -Query $CreatedbQuery -Database $TargetDatabase -server $TargetServer
}


#Using DBA Tools (https://dbatools.io/) to copy data from one instance to the oher. 
#I am copying only one table, but the Module can copy all tables as long as they exist in the destination instance.
#Truncating the destination table before importing data
Copy-DbaTableData -SqlInstance "Server01" -Destination "Server02" -Database DB01 -Table "Table01" -DestinationDatabase DB02 -DestinationTable "Table02" -KeepIdentity -Truncate

