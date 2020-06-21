Import-Module SQLPS


$SQLPackageExtractLocation = '\\lwdelapp-003\Sites\dfs\BUILD\FeedExtract'
$LPDatabaseServer = 'lwdeldb-003'
$LPDatabaseName = 'DFS_master'
$LPDBUserName = 'dfsadmin'
$LPDBPassword = 'Password-1'

$releaseversionNumberT = '5.72.2.4'
$filedirectory = '\\lwdeldb-003\Backups\DFS\DFS_MASTER\' + $releaseversionNumberT




$DropscriptFile = $filedirectory + '\' +'1.LW ' +  $releaseversionNumberT+'_DropAllObjects.sql'
$IncrementalScriptFile = $filedirectory + '\' +'2.LW ' +  $releaseversionNumberT+'_IncrementalScripts.sql'
$CoreReleaseScriptFile = $filedirectory + '\' +'3.LW ' +  $releaseversionNumberT+'_Core.ReleaseScripts.sql'
$CoreConstraintScriptFile = $filedirectory + '\' +'4.LW ' +  $releaseversionNumberT+'_Core.Constraints.sql'
$ReleaseVersionScriptFile = $filedirectory + '\' +'5.LW ' +  $releaseversionNumberT+'_ReleaseVersion.sql'
$WorkFlowSetupScriptFile = $filedirectory + '\' +'5.LW ' +  $releaseversionNumberT+'_WorkFlowSetup.sql'






$ConsolidatedScriptsFolder=$SQLPackageExtractLocation+"\Lw.ReleaseScripts\Core.Project.ReleaseScripts"
$ScriptsFolder=$SQLPackageExtractLocation+"\Lw.ReleaseScripts\ReleaseScripts"


function DropAllObjectsScripts
{
    $sqlString+="EXEC DropAllObjects 1,0"+"`n"+"GO"+"`n"+"`n"
    $sqlString+="DECLARE @SQL NVARCHAR(MAX) = N'' SELECT @SQL += N'DROP SYNONYM ' + QUOTENAME(SCHEMA_NAME([schema_id])) + N'.' + QUOTENAME(name) + N';' + Char(13) + Char(10) FROM sys.synonyms WHERE SCHEMA_NAME([schema_id]) = N'dbo' EXEC sys.sp_executesql @SQL " +"`n"+"GO"+"`n"

    return $sqlString
}

function Workflowsetupscripts
{

    $WorkflowsetupsqlString = "Update GlobalParameters Set Value='True' where Name='MasterUpdateRequired' and Category='App'"+"`n"+"GO"
   
    return $WorkflowsetupsqlString
}

function ReleaseVersionScripts
{
 $sqlString = "IF NOT EXISTS(SELECT 1 FROM ReleaseVersions rv WHERE rv.VersionNumber = '"+ $releaseversionNumberT +"')" +"`n"
$sqlString += "BEGIN" +"`n"
$sqlString += "	INSERT INTO ReleaseVersions" +"`n"
$sqlString += "	(VersionNumber,ShippedDate,AppliedDate,AppliedBy,CreatedById,CreatedTime)" +"`n"
$sqlString += "	VALUES" +"`n"
$sqlString += "	('"+ $releaseversionNumberT +"',GETDATE(),GETDATE(),NULL,1,SYSDATETIMEOFFSET())" +"`n"
$sqlString += "END" +"`n"+"GO"+"`n"   
return $sqlString
}

function CleanUpReleaseVersion
{
$sqlString = "IF EXISTS(SELECT 1 FROM ReleaseVersions rv WHERE rv.VersionNumber = '"+ $releaseversionNumberT +"')" +"`n"
$sqlString += "BEGIN" +"`n"
$sqlString += "delete ReleaseVersions WHERE VersionNumber = '"+ $releaseversionNumberT  +"'`n"
$sqlString += "END" +"`n"+"Go"+"`n"   
Invoke-Sqlcmd -ErrorAction 'Stop' -querytimeout 0  -ServerInstance  $LPDatabaseServer -Database $LPDatabaseName -Username $LPDBUserName -Password $LPDBPassword -Query $sqlString
}

function global:GetGeneratedScripts
{
    Write-Host "getting core.Project.ReleaseScripts and core.Project.Constraints.."
    $CoreReleaseScripts=[System.IO.Directory]::GetFiles($ConsolidatedScriptsFolder)
    foreach($coreReleaseScriptFile in $CoreReleaseScripts)
    {

        $sqlString3+=[System.IO.File]::ReadAllText($coreReleaseScriptFile)+"`n"+"GO"+"`n"
    }

    return $sqlString3

}
function global:GetScriptNamesInDB($ExecInBaseDB)
{
  Write-Host "getting all script names in DB.."
  $GetDbScriptsQuery = "select ReleaseScriptName from ReleaseVersionDetails"


  $ScriptsInDB= Invoke-Sqlcmd -ErrorAction 'Stop' -querytimeout 0  -ServerInstance  $LPDatabaseServer -Database $LPDatabaseName -Username $LPDBUserName -Password $LPDBPassword -Query $GetDbScriptsQuery
  $ScriptNamesInDB = @($ScriptsInDB | select -ExpandProperty ReleaseScriptName)

  IF([string]::IsNullOrEmpty($ScriptNamesInDB)) 
  {            
      return $ScriptNamesInDB
  } 
  else 
  {            
      return $ScriptNamesInDB.Trim()
  }  
}



function global:GetScriptsToExecute($ExecInBaseDB)
{
  Write-Host "Finding out scripts to execute..."

  $ReleaseVersionId = GetLastReleaseVersionNumber $ExecInBaseDB 

  $GetDbScriptsQuery = "select ReleaseScriptName from ReleaseVersionDetails where ReleaseVersionId ="+ $ReleaseVersionId

  Write-Host $GetDbScriptsQuery

  $ScriptsInDB= Invoke-Sqlcmd -ErrorAction 'Stop' -querytimeout 0  -ServerInstance  $LPDatabaseServer -Database $LPDatabaseName -Username $LPDBUserName -Password $LPDBPassword -Query $GetDbScriptsQuery

  $ScriptNamesInDBToExecute = @($ScriptsInDB | select -ExpandProperty ReleaseScriptName)

  return $ScriptNamesInDBToExecute

}
function global:GetAllScriptsNameInPakage
{
Write-Host "getting all scripts from pakage.."
  
$ScriptFiles =Get-ChildItem $ScriptsFolder\*.sql | select -expand basename

$versionList = New-Object System.Collections.ArrayList($null)

foreach($ScriptFile in $ScriptFiles)
{               
[void]$versionList.Add($ScriptFile)            
}
  
Write-host "sorting the scripts..."

$versionList.sort()

return $versionList

}
function global:GetLastReleaseVersionNumber($ExecInBaseDB)
{
    $strSQL = "
    SELECT CASE WHEN EXISTS(SELECT * FROM ReleaseVersions) 
    THEN (SELECT TOP 1 Id FROM ReleaseVersions ORDER BY id DESC)
    ELSE NULL 
    END AS VersionNumber
    "
      
    $result = Invoke-Sqlcmd -ErrorAction 'Stop' -querytimeout 0  -ServerInstance  $LPDatabaseServer -Database $LPDatabaseName -Username $LPDBUserName -Password $LPDBPassword -Query $strSQL

    if($result -ne [System.DBNull]::Value)
    {
    return $result.VersionNumber 
    }
    else
    {
    return 1
    }
}

function global:InsertNewScriptsToDB($ExecInBaseDB)
{
    $AvailableScripts = GetAllScriptsNameInPakage

    $ScriptsInDb=GetScriptNamesInDB $ExecInBaseDB

    foreach ($AvailableScript in $AvailableScripts)
    {
    $AvailableScript=$AvailableScript.Trim()

    If(-not($ScriptsInDb -contains $AvailableScript))
    {


    $ReleaseVersionId = GetLastReleaseVersionNumber $ExecInBaseDB 

    $InsertQuery = "INSERT INTO [dbo].[ReleaseVersionDetails] ([ReleaseScriptName],[IsExecuted],[CreatedById],[CreatedTime],[UpdatedById],[UpdatedTime],[ReleaseVersionId]) VALUES ('"+$AvailableScript +"',0,1,GETDATE(),null,null,"+$ReleaseVersionId+")"


    $script=Invoke-Sqlcmd -ErrorAction 'Stop' -querytimeout 0  -ServerInstance  $LPDatabaseServer -Database $LPDatabaseName -Username $LPDBUserName -Password $LPDBPassword -Query $InsertQuery 
    }
    }
}
function global:PrepareIncrementalScript($ExecInBaseDB)
{
$ScriptsToExecute=GetScriptsToExecute $ExecInBaseDB

$DailySQLScripts =[System.IO.Directory]::GetFiles($ScriptsFolder)

Write-Host "Fetching incremental scripts"



if([System.IO.File]::Exists($IncrementalScriptFile))
{
$headertext = '/*-------------------------------------------------------' +'LW'+ $releaseversionNumberT+ '-------------------------------------------------------*/'
Set-Content -Path $IncrementalScriptFile -Value  $headertext  

    
}
else
{
    $headertext = '/*-------------------------------------------------------' +'LW'+ $releaseversionNumberT+ '-------------------------------------------------------*/'
    New-Item -Path $IncrementalScriptFile -ItemType File
    Set-Content -Path $IncrementalScriptFile -Value  $headertext  
}
foreach($ScriptToExecute in $ScriptsToExecute)
{      
$updateScript=""
$ScriptString=""

$fileToFetch = $ScriptsFolder + "\" + $ScriptToExecute.ToString() + ".sql"
$SelectedFile=$DailySQLScripts | Where { $_.contains($fileToFetch) } | select  
    
Write-Host "Fetching ",$ScriptToExecute  

$ScriptString=[System.IO.File]::ReadAllText($SelectedFile)+"`n"+"GO"+"`n"

Add-Content -Path $IncrementalScriptFile $ScriptString


}
}

function global:ExecuteIncrementalScript($ExecInBaseDB)
{

Write-Host 'Executing Incremental script'

$ScriptString=[System.IO.File]::ReadAllText($incrementalScriptFile)
if($ScriptString -ne [System.DBNull]::Value)
{
Invoke-Sqlcmd -ErrorAction 'Stop' -querytimeout 0  -ServerInstance  $LPDatabaseServer -Database $LPDatabaseName -Username $LPDBUserName -Password $LPDBPassword -Query $ScriptString
}

$ReleaseVersionId = GetLastReleaseVersionNumber $ExecInBaseDB

Write-Host 'updating release version details'

$updateScript = "UPDATE ReleaseVersionDetails SET IsExecuted = 1 where ReleaseVersionId ="+ $ReleaseVersionId+"`n" +"Go"
          
Invoke-Sqlcmd -ErrorAction 'Stop' -querytimeout 0  -ServerInstance  $LPDatabaseServer -Database $LPDatabaseName -Username $LPDBUserName -Password $LPDBPassword -Query $updateScript

Write-Host 'updating release version details - completed'
}
if(!(Test-Path -Path $filedirectory ))
{
New-Item -Path $filedirectory -ItemType Directory
}

CleanUpReleaseVersion
$DropScripts= DropAllObjectsScripts
Set-Content -Path $DropscriptFile -Value  $DropScripts  
$workflowsetupscript = Workflowsetupscripts
Set-Content -Path  $WorkFlowSetupScriptFile  -Value  $workflowsetupscript
$releaseversionscript = ReleaseVersionScripts
Set-Content -Path $ReleaseVersionScriptFile  -Value   $releaseversionscript
InsertNewScriptsToDB $false
PrepareIncrementalScript $false
$ReleaseScripts = "$ConsolidatedScriptsFolder" + "\Core.Project.ReleaseScripts.sql"
Copy-Item $ReleaseScripts -Destination $coreReleaseScriptFile
$ConstraintScripts = "$ConsolidatedScriptsFolder" + "\Core.Project.Constraints.sql"
Copy-Item $ConstraintScripts -Destination $CoreConstraintScriptFile

Try
{
    
$timeout = New-Object System.TimeSpan -ArgumentList @(15,0,0) # five hours
$options = [System.Transactions.TransactionScopeOption]::Required
$scope = New-Object -TypeName System.Transactions.TransactionScope -ArgumentList @($options,$timeout)

    


Write-Host "Running Drop Script..."

Invoke-Sqlcmd -ErrorAction 'Stop' -querytimeout 0  -ServerInstance  $LPDatabaseServer -Database $LPDatabaseName -Username $LPDBUserName -Password $LPDBPassword -Query $DropScripts 

Write-Host "Drop Script Executed Successfully"

ExecuteIncrementalScript $false

Write-Host "Running Release Scripts and constraints"
Invoke-Sqlcmd -ErrorAction 'Stop' -querytimeout 0  -ServerInstance  $LPDatabaseServer -Database $LPDatabaseName -Username $LPDBUserName -Password $LPDBPassword -InputFile $ReleaseScripts


Invoke-Sqlcmd -ErrorAction 'Stop' -querytimeout 0  -ServerInstance  $LPDatabaseServer -Database $LPDatabaseName -Username $LPDBUserName -Password $LPDBPassword -InputFile $ConstraintScripts

Write-Host "Running workflowsetupscript"
Invoke-Sqlcmd -ErrorAction 'Stop' -querytimeout 0  -ServerInstance  $LPDatabaseServer -Database $LPDatabaseName -Username $LPDBUserName -Password $LPDBPassword -Query $workflowsetupscript

Write-Host "Running releaseversionscript"
Invoke-Sqlcmd -ErrorAction 'Stop' -querytimeout 0  -ServerInstance  $LPDatabaseServer -Database $LPDatabaseName -Username $LPDBUserName -Password $LPDBPassword -Query $releaseversionscript



Write-Host "Script Execution completed"
$scope.Complete() 
Write-Host "Transaction committed"
}
catch
{
    Write-Host "Transaction RolledBack"
$_.exception.message
Exit 1

}
finally
{
$scope.Dispose() 
   
}