Import-Module SQLPS

$LPDatabaseServer = 'lwdeldb-003'
$LPDatabaseName = 'DFS_STAGING'
$LPDBUserName = 'dfsadmin'
$LPDBPassword = 'Password-1'
$DbPath = "\\lwdeldb-003\Backups\DFS\DFS_MASTER\"
$sourceDB = "dfs_master"
$releaseversionNumber = '5.72.2.4'

$backupFile = $DbPath + $sourceDB + "_" +$releaseversionNumber+ ".bak"

$sql = @"
use master
go
alter database [$LPDatabaseName] 
set single_user with rollback immediate
go
RESTORE DATABASE [$LPDatabaseName] 
FROM disk =  '$backupFile'
WITH replace
go
use [$LPDatabaseName] 
EXEC   sp_adduser 'development'  , 'development' , 'db_owner'
GO
"@


$Messages = %{ $Rows = Invoke-Sqlcmd  -ServerInstance  $LPDatabaseServer -Database 'Master' -Username $LPDBUserName -Password $LPDBPassword -Query $sql -verbose} 4>&1
