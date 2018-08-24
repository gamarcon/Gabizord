########################################################################################################################################
#This is script is not 100% mine - I got it from [https://community.spiceworks.com/people/martin9700] and adapted to my environment needs
#Connects to SQL Sevrer instances and verify available space and send report by Email
#I scheduled it to run daily on SQL Agent and the list of server must be saved on a directory where SQL Server instance has access  
#Comments and Improvements are Welcome
########################################################################################################################################

[CmdletBinding()]
Param (
    [string[]]$To = @("login@domain.com"), #Person/Group who should receive the report
    [Parameter(ValueFromPipeline,ValueFromPipelineByPropertyName)]
    [Alias("ServerList")]
    [string[]]$Name = (Get-Content "C:\TEST\Instance_Test.txt"), #List of SQL Server Instances; If your server name has special special characters, please put them between ""
    [int]$Threshold = 1,
    [string]$ReportPath
)

#Environment
$SMTPSplat = @{
    To         = $To
    From       = "SQL Report SQL-Admin@domain.com" #Report Sender Name
    Subject    = "SQL Server Daily Report - $(Get-Date)" #Subject
    SMTPServer = "SMTP.domain.com"  #SMTP Server
}

#
#
Write-Verbose "$(Get-Date): New-SQLBackupReport starting..."

#region Functions
Function Invoke-SQLQuery {   
    
    [CmdletBinding(DefaultParameterSetName="query")]
    Param (
        [string[]]$Instance = $env:COMPUTERNAME,
        
        [Parameter(ParameterSetName="query",Mandatory)]
        [string]$Database,
        
        [Management.Automation.PSCredential]$Credential,
        [switch]$MultiSubnetFailover,
        
        [Parameter(ParameterSetName="query",ValueFromPipeline)]
        [string]$Query,

        [Parameter(ParameterSetName="query")]
        [switch]$NoInstance,
        
        [Parameter(ParameterSetName="list")]
        [switch]$ListDatabases
    )
    Begin {
        If ($ListDatabases)
        {   $Database = "Master"
            $Query = "Select Name,state_desc as [State],recovery_model_desc as [Recovery Model] From Sys.Databases"
        }        
        
        If (-not $Query)
        {   $Path = Join-Path -Path $env:TEMP -ChildPath "Invoke-SQLQuery-Query.txt"
            Start-Process Notepad.exe -ArgumentList #$Path -Wait
           $Query = Get-Content $Path
        }
    }

   End 
   {
        If ($Input)
        {   $Query = $Input -join "`n"
        }

        If ($Credential)
         {   $Security = "uid=$($Credential.UserName);pwd=$($Credential.GetNetworkCredential().Password)"
         }
         Else
         {   $Security = "Integrated Security=True;"
        }
        
        If ($MultiSubnetFailover)
        {   $MSF = "MultiSubnetFailover=yes;"
            If ($ErrorActionPreference -ne "SilentlyContinue")
            {
                Write-Verbose "MultiSubnetFailover has been set to on.  You must have the SQL 2012 Native Client installed for this to work."
            }
        }
        
        ForEach ($SQLServer in $Instance)
        {   $ConnectionString = "data source=$SQLServer,1433;Initial catalog=$Database;$Security;$MSF"
        
            $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
            $SqlConnection.ConnectionString = $ConnectionString
            $SqlCommand = $SqlConnection.CreateCommand()
            $SqlCommand.CommandText = $Query
            $DataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $SqlCommand
            $DataSet = New-Object System.Data.Dataset
            Try {
                $Records = $DataAdapter.Fill($DataSet)
                If ($DataSet.Tables[0])
                {   If (-not $NoInstance)
                    {
                        $DataSet.Tables[0] | Add-Member -MemberType NoteProperty -Name Instance -Value $SQLServer
                    }
                    Write-Output $DataSet.Tables[0]
                }
                Else
                {   
                    If ($ErrorActionPreference -ne "SilentlyContinue")
                    {
                        Write-Warning "Query did not return any records"
                    }
                }
            }
            Catch {
                If ($ErrorActionPreference -ne "SilentlyContinue")
                {
                    Write-Warning "$($SQLServer): $($_.Exception.Message)"
                }
            }
            $SqlConnection.Close()
        }
    }
}

Function Set-GroupRowColorsByColumn {
    
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory,ValueFromPipeline)]
        [string[]]$InputObject,
        [Parameter(Mandatory)]
        [string]$ColumnName,
        [string]$CSSEvenClass = "TREven",
        [string]$CSSOddClass = "TROdd"
    )

    BEGIN {
        Write-Verbose "$(Get-Date): Set-ColorHTMLRowsByColumn begins"
    }

    PROCESS {
        ForEach ($Line in $InputObject)
        {
            #Header Column
            If ($Line -like "*<th>*")
            {
                If ($Line -notlike "*$ColumnName*")
                {
                    Write-Error "Unable to locate a column named $ColumnName"
                    Exit 999
                }
                $Search = $Line | Select-String -Pattern "<th>.*?</th>" -AllMatches
                $Index = 0
                ForEach ($Column in $Search.Matches)
                {
                    If (($Column.Groups.Value -replace "<th>|</th>","") -eq $ColumnName)
                    {
                        Write-Verbose "$(Get-Date): $ColumnName located at column $($Index + 1)"
                        Break
                    }
                    $Index ++
                }
            }
            If ($Line -like "*<td>*")
            {
                #Check the column for a value change, and if so swap the designated class
                $Search = $Line | Select-String -Pattern "<td>.*?</td>" -AllMatches
                If ($LastColumn -ne $Search.Matches[$Index].Value)
                {
                    If ($Class -eq $CSSEvenClass)
                    {
                        $Class = $CSSOddClass
                    }
                    Else
                    {
                        $Class = $CSSEvenClass
                    }
                }
                $LastColumn = $Search.Matches[$Index].Value
                $Line = $Line.Replace("<tr>","<tr class=""$Class"">")
            }
            Write-Output $Line
        }
    }

    END {
        Write-Verbose "$(Get-Date): Set-ColorHTMLRowsByColumn finished"
    }
}

Function Get-Size {
    Param (
        [float]$Size
    )

    If ($Size -ge 1000000000)
    {
        Write-Output ("{0:N2} GB" -f ($Size / 1gb))
    }
    ElseIf ($Size -gt 0)
    {
        Write-Output ("{0:N2} MB" -f ($Size / 1mb))
    }
    Else
    {
        Write-Output $null
    }
}



If ($Name.Count -eq 0)
{
    Write-Error "$(Get-Date): No servers specified, aborting script"
    Exit 999
}
If (-not $ReportPath)
{
    $ReportPath = Join-Path (Split-Path $MyInvocation.MyCommand.Path) -ChildPath "Reports"
    If (-not (Test-Path $ReportPath))
    {
        New-Item -Path $ReportPath -ItemType Directory | Out-Null
    }
}
Else
{
    If (-not (Test-Path $ReportPath))
    {
        Write-Error "$(Get-Date): The report path ""$ReportPath"" does not exist, aborting script"
        Exit 999
    }
}

$BackupSets = ForEach ($db in $Name)
{
    Write-Verbose "$(Get-Date): Working on $db..."
    If (-not (Test-Connection $db -Quiet -Count 2))
    {
        Write-Warning "$(Get-Date): Unable to ping $db, skipping server"
        Continue
    }
    $BaseName = $db.Split(".")[0]  
    $Version = ([version](Invoke-Sqlquery -Instance $db -Database Master -Query "SELECT SERVERPROPERTY('productversion') AS [Version]").Version).Major
    $Databases = Invoke-SQLQuery -Instance $db -Database Master -Query "SELECT name,recovery_model_desc AS RecoveryModel, create_date as DBCreation, state_desc as DBStatus FROM sys.databases WHERE name != 'tempdb'"
    $DataSpace = Invoke-SQLQuery -Instance $db -Database Master -Query "exec sp_msforeachdb 'use [?]; select DB_NAME() AS DbName, sum(size)/128.0 AS File_Size_MB, sum(CAST(FILEPROPERTY(name, ''SpaceUsed'') AS INT))/128.0 as Space_Used_MB, SUM( size)/128.0 - sum(CAST(FILEPROPERTY(name,''SpaceUsed'') AS INT))/128.0 AS Free_Space_MB  from sys.database_files  where type=0 group by type'"
    $MirrorInfo = Invoke-SQLQuery -Instance $db -Database Master -Query "SELECT sys.name AS Name FROM sys.databases AS sys JOIN sys.database_mirroring AS mir ON sys.database_id = mir.database_id WHERE mir.mirroring_role = 2" | Select -ExpandProperty Name
    $Backup = Invoke-SQLQuery -Instance $db -Database Master -Query $BKQuery
   

  
    ForEach ($Database in $Databases)
    {
                       
        [PSCustomObject]@{


            Server                   = $db
            Database                 = If ($Database.Name.Length -gt 50) { $Database.Name.SubString(0,50) } Else { $Database.Name }  #Cutting the name length down to make the report look better
            "Database Creation"      = $Database.DBCreation
            "Database Status"        = $Database.DBStatus
            "Recovery Model"         = $Database.RecoveryModel
            "Database Size (MB) "    = $DataSpace.File_Size_MB
            "Available Space (MB)"   = $DataSpace.Free_Space_MB
            "% Space Used"           =(($DataSpace.Space_Used_MB/1024)/$DataSpace.File_Size_MB)*100

              
        }
    }
}



$BackupSetsNC = ForEach ($db in $Name)
{
    Write-Verbose "$(Get-Date): Working on $db..."
    If (Test-Connection $db -Quiet -Count 2)
    {
        Write-Warning "$(Get-Date): Checking $db - No action required, please continue"
        Continue
    }
            
        [PSCustomObject]@{


            Server                   = $db
            "Message"      = "$(Get-Date): Unable to connet to $db - please contact SQL-Admin@domain.com" #In case you need to notfify users
           
        }
}




Write-Verbose "$(Get-Date): Generating report..."
$HTMLHeader = @"
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"  "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<style>
TABLE {border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse; }
TR:Hover TD {Background-Color: #C1D5F8;}
TH {border-width: 1px;padding: 3px;border-style: solid;border-color: black;background-color: #00008B; color:white; }
TD {border-width: 1px;padding: 3px;border-style: solid;border-color: black;width: 5%; font-size:.8em; }
.odd { background-color: white; }
.even { background-color: #dddddd; }
span { font-size:.6em; }
</style>
<title>SQL Backup Report</title>
</head>
<body>
<h1 style="text-align:center;">SQL Database Space Report</h1><br/>  
"@

$BackupSets = $BackupSets | Sort Server,Database
$BackupSetsNC = $BackupSetsNC | Sort Server
$Successful = $BackupSets | Where "Database Status" -eq "ONLINE"
$NoConnection = $BackupSetsNC 

$TableHTML = $Successful | ConvertTo-Html -Fragment | Set-GroupRowColorsByColumn -ColumnName Server -CSSEvenClass even -CSSOddClass odd

$TableHTMLNC = $NoConnection | ConvertTo-Html -Fragment | Set-GroupRowColorsByColumn -ColumnName Server -CSSEvenClass even -CSSOddClass odd


$HTML = @"
$HTMLHeader
$TableHTML
<br/>
<div style='background-color: black;color: white;font-size: 120%;text-align: center;font-weight: bold;'>Could not Connect to</div>`n
$TableHTMLNC
<br/>
<span>Created by Gabi Marcondes; Report on: $(Get-Date)</span>
"@


Write-Verbose "$(Get-Date): Sending email to $($To -join ", ")..."
Send-MailMessage @SMTPSplat -Body ($HTML | Out-String) -BodyAsHtml

Write-Verbose "$(Get-Date): Saving report..."

#Cleanup old reports
Get-ChildItem "$ReportPath\*.html" | Where { $_.LastWriteTime -lt (Get-Date).AddDays(-365) } | Remove-Item -Force

#Save New Report
$OutputFile = Join-Path -Path $ReportPath -ChildPath "SQLBackup-$(Get-Date -Format 'MM-dd-yyyy').html"
$HTML | Out-File $OutputFile -Encoding ascii

Write-Verbose "$(Get-Date): New-SQLBackupReport complete"
