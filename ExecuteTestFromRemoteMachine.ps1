#----------varaible declarations --------------------------------------------
#path variables
$OdessaTestServerNetworkPath = "\\lwdelapp-003\Sites\DFS\BUILD\OT\OdessaTestExecutionWorkspace"
$OdessaTestServerLocalPath = "E:\Sites\DFS\BUILD\OT\OdessaTestExecutionWorkspace"
#creds
$remoteSessionUser = "db_job"
$remoteSessionPwd = "password-1"
$TestServer = "lwdelapp-003"
#configs
$OTBinaryPath = "$OdessaTestServerLocalPath\OdessaTestClient\Binaries\OdessaTest.exe"
$OTlogPath = $OdessaTestServerNetworkPath #provide network path 
$OTWorkSpace = "$OdessaTestServerLocalPath\TestSuites\Projects\SmokeSuite"
$OTScenarioCollection = "NightlyBuild"
$LPurl= "http://dfsqa.del3.odessadev.local/"
$APIGetURL= "http://dfsqa.api.del3.odessadev.local/api/Entity/User/Id=1?select=FirstName,LastName"
$APIPostURL = "http://dfsqa.api.del3.odessadev.local//api/Entity/BankBranch/Create"
$global:RunName = $null
#-------------------------------------------------------------------------
$startTime = get-date -Format dd_MM_hhmmss
$projectName = "SmokeSuite" + $startTime

$global:MailBody = "Team,<br>"

Write-Host "$projectName"

function global:GetCredForPSS {

$pw = convertto-securestring -AsPlainText -Force -String $remoteSessionPwd
$global:cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $remoteSessionUser,$pw

}

function global:ExecuteOTtest{
$s = New-PSSession -ComputerName $TestServer -credential $global:cred
Invoke-Command -Session $s -Script  {

        Write-Host "Executing Odessa Test Scenarios"

        $userName = "system.user"

        $workingDirectory = $Using:OTWorkSpace 

        &$Using:OTBinaryPath -Operation Execute -DeploymentPath $Using:LPurl -WorkingDirectory $workingDirectory -Scenarios $Using:OTScenarioCollection -Collection true -RunName $Using:projectName -LogsFolder $Using:OTlogPath
        Start-Sleep -Seconds 30

        Write-Host "Test Execution Completed"

                                    }
}

function global:ExecutedScenarioDetails{

$SqlQuery = "SELECT sh.ScenarioName,sh.ScenarioRunStatus,sh.ModuleName FROM dbo.ScenarioHeader sh JOIN dbo.RunHeader rh ON sh.RunHeaderID = rh.RunHeaderID WHERE rh.RunName ='"+ $projectName +"'"
$SQLConnection = New-Object System.Data.SqlClient.SqlConnection
$SqlConnection.ConnectionString = "Server = 'lwdeldb-003'; Database = 'TestAutomation'; uid = 'development'; pwd = 'jk'"

$SqlCmd = New-Object System.Data.SqlClient.SqlCommand
$SqlCmd.CommandText = $SqlQuery
$SqlCmd.Connection = $SqlConnection

$SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
$SqlAdapter.SelectCommand = $SqlCmd

$DataSet = New-Object System.Data.DataSet
$SqlAdapter.Fill($DataSet)
$SqlConnection.Close()

# This code outputs the retrieved data
$table = $DataSet.Tables[0]

$global:MailBody += "<style> table, th, td { border: 1px solid black;}.Error { border: 1.5px solid red; color: red; }.Success { border: 1.5px solid green; color: green; }</style> "

$global:MailBody += "<br><table><tr><th>ScenarioName</th><th>Status</th><th>Module</th></tr>"
foreach ($row in $table.Rows)
{
    if($row[1] -ne "Completed With Errors"){
        $global:MailBody += "<tr><td class='Success'>" + $row[0] + "</td><td>" + $row[1] + "</td><td>" + $row[2] + "</td></tr>" 
    }
    else{
        $global:MailBody += "<tr><td  class='Error'>" + $row[0] + "</td><td class='Error'>" + $row[1] + "</td><td class='Error'>" + $row[2] + "</td></tr>"
    }
}
$global:MailBody += "</table><br>"
} 

function global:CheckRunStatus {
         $logfile = $OTlogPath+"\"+$projectName+"_Execute.txt"

         $val = 0
         $global:success = 0
         $retryGetResult = 1

         Write-Host "Validating Test Execution"
         
         while($val -ne 1)
            {
                Start-Sleep -Seconds 300
                
                if([System.IO.File]::Exists($logfile))
                    {
                        $SEL = Get-Content $logfile | Select -Index 2
                        
                        if ($SEL -eq 'Status: Passed')
                            {
                                $global:success = 0
                                $val = 1
                                $global:MailBody += "<br>&emsp;<font color=black>Please find the execution results below.</font><br>" 
global:ExecutedScenarioDetails
                            }
                        else
                            {
                                $val = 1
                                $global:MailBody += "&emsp;<b><font color=red>OT Validation Failed please check the logs</b></font><br>" 
                            }
                    }
                else
                    {
                    $retryGetResult++
                    Write-Host "Retrying Validating Execution"
                    }
                
                if ($retryGetResult -eq 20)
                    {
                    $global:MailBody += "&emsp;<b><font color=red>OT Validation Failed please check the logs</b></font><br>" 
                    $val = 1
                    Exit 1
                    }
            }


         
}

function global:TestAPI{

    $Headers = @{
        Authorization = "Basic dXNlci4xOlBhc3N3b3JkLTE="
    }


    $getresponse = Invoke-WebRequest -Uri $APIGetURL -Headers $Headers -UseBasicParsing

    $getcond = $getresponse | Select-String -Pattern '"FirstName": "System",'   

    $success = 0

    if ($getcond -ne $null) {$success = 1} else {$success = 0}


    $data = @{
                "Name" = "AutoAPITest_$startTime";
                "BankName"= "BB_AutoAPITest";
                "ACHRoutingNumber"= "768345234";
                "ABARoutingNumber"= "123234345";
   
            }

    $body = $data | ConvertTo-Json

    

    $postresponse = Invoke-WebRequest -Uri $APIPostURL -Headers $Headers -Method POST -Body $body -ContentType "application/json" -UseBasicParsing

    $postcond = $postresponse | Select-String -Pattern '"Success": true,'   

    if ($getcond -ne $null) {$success = 1} else {$success = 0}

    if ($success -eq 1){$global:MailBody += "&emsp;<b><font color=green>API validation successfull</b></font><br>&emsp;<b><font color=black>Successfully executed 2 scenarios.</b></font><br>" }
    else {$global:MailBody += "&emsp;<b><font color=red>API Validation Failed please check the logs</b></font><br>" }
}

function Send-Email(){
    param(
        [Parameter(Mandatory=$true)][string]$smtpServer = "YOUREMAILSERVER.COM",
        [string]$ComputerName = $env:ComputerName,
        [string]$from = "from@yourdomain.com",
        [string]$to = "you@yourdomain.com",
        [string]$subject = "Default Send-Email Subject.",
        [string]$body = "Default Send-Email Body"
    )
    
    try { 

        #Creating a Mail object
        $msg = new-object Net.Mail.MailMessage

        #Creating SMTP server object
        $smtp = new-object Net.Mail.SmtpClient($smtpServer,25) 
        #$smtp.EnableSsl = $true 
        $smtp.Credentials = New-Object System.Net.NetworkCredential("no-reply@odessatech.in", "password-1"); 

        #Email structure 
        $msg.From = $from
        $msg.ReplyTo = "noreply@yourdomain.com"
        $msg.To.Add($to)

        $msg.subject = "Nightly Build : Test Results"
        write-host $global:MailBody

        $msg.body = $global:MailBody 
        $msg.IsBodyHtml = 1

      

        #Sending email 
        $smtp.Send($msg)
  } catch {
        Write-Warning $_
  }
}



GetCredForPSS 
ExecuteOTtest 
CheckRunStatus
TestAPI
Send-Email -smtpServer mail.odessatech.in -from 'LWOctopusDeployment@odessainc.com'  -to 'Dell-Blr@odessainc.com';


