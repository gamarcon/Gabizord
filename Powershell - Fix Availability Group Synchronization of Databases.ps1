# Created by Gabi Marcondes
#
########################################
# INSTRUCTION
#########################################
#
# Purpose - Fix Synchronization of Databases on AG in case the automatic synchronizartion fails
# IMPORTANT: For Availability Gourp Names: If the instance name is MSSQLSERVER (Local Instance) add it as [INSTANCE\DEFAULT], for example: SERVER01\DEFAULT
# How to Deploy it:
#           E:\Scripts\Automated_Script\AgFixSynch.ps1 -Primary "Primary InstanceName" -Secondary "Secondary InstanceName" -database "Database Name" -AG "Availability Group Name" -BKpLocation "\\Backup Location"
# Where [E:\Scripts\Automated_Script\] stands for the location where I saved the Powershell script
#   
#########################################


#Variables Input by the User

param
([string]$Primary
,[string]$Secondary
,[string]$database
,[string[]]$BKpLocation
,[string]$AG
) 

#Get the Data 

$date = get-date -format g

#Clean old Backup files om Folder 

Remove-Item $BKpLocation\*.* -Force
 
#Remove Database from AG

try

        {

            Remove-SqlAvailabilityDatabase -Path "SQLSERVER:\Sql\$Primary\AvailabilityGroups\$AG\AvailabilityDatabases\$database"  

           }

        catch

        {

            $ErrorMessage = $_.Exception.Message

            Continue

        }

 try

        {

            $DatabaseBackupFile = $BKpLocation + "\" + $database + "_FULL.bak"
            $LogBackupFile = $BKpLocation + "\" + $database +"_LOG.trn"
            $AGPrimaryPath = "SQLSERVER:\SQL\$Primary\AvailabilityGroups\$AG"
            $AGSecondaryPath = "SQLSERVER:\SQL\$Secondary\AvailabilityGroups\$AG"
            Backup-SqlDatabase -Database $database -BackupFile $DatabaseBackupFile -ServerInstance $Primary
            Backup-SqlDatabase -Database $database -BackupFile $LogBackupFile -ServerInstance $Primary -BackupAction Log
            Restore-SqlDatabase -Database $database -BackupFile $DatabaseBackupFile -ServerInstance $Secondary -NoRecovery
            Restore-SqlDatabase -Database $database -BackupFile $LogBackupFile -ServerInstance $Secondary -RestoreAction Log -NoRecovery
            Add-SqlAvailabilityDatabase -Path $AGPrimaryPath -Database $database
            Add-SqlAvailabilityDatabase -Path $AGSecondaryPath -Database $database  

         }

        catch

        {

            $ErrorMessage = $_.Exception.Message

            Continue

        }   

 

 
