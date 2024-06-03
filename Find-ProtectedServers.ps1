
<#PSScriptInfo

.VERSION 1.0.3

.GUID abaa749f-9a32-4c17-8835-cc0ea82b8d6f

.AUTHOR Colin Hearn

.COMPANYNAME Leidos

.COPYRIGHT

.TAGS

.LICENSEURI

.PROJECTURI

.ICONURI

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES


.PRIVATEDATA

#>

<# 

.DESCRIPTION 
 Finds servers in each domain that are being backed up to SnapCenter or SnapManager. 

#> 
Param()
$allServers = @{
    "East" = @{
        "Domain" = 
            "nadsusea.nads.navy.mil"
        "Locality" = 
            "East Coast"
        "ServerLocators" = 
            "NAEACHRLSQ*",                
            "NAEACRANSQ*",
            "NAEAJAXSSQ*",
            "NAEAMECHSQ*",
            "NAEANRFKSQ*",
            "NAEAPAXRSQ*",
            "NAEAWNYDSQ*", 
            "NAEACHRLX*",                
            "NAEACRANX*",
            "NAEAJAXSX*",
            "NAEAMECHX*",
            "NAEANRFKX*",
            "NAEAPAXRX*",
            "NAEAWNYDX*"
    }
    "West" = @{
        "Domain" = 
            "nadsuswe.nads.navy.mil"
        "Locality" = 
            "West Coast"
        "ServerLocators" =
            "NAWEBREMSQ*",
            "NAWECHLKSQ*",
            "NAWESDNISQ*",
            "NAWESPSCSQ*",
            "NAWEPRLHSQ*",
            "NAWEBREMX*",
            "NAWECHLKX*",
            "NAWESDNIX*",
            "NAWESPSCX*",
            "NAWEPRLHX*"
    }
    "PACOM" = @{
        "Domain" = 
            "pads.pacom.mil"
        "Locality" = 
            "Pads"
        "ServerLocators" = 
            "PADSSPRLHSQ*",
            "PADSPRLHX*"
    }
    "NMCI" = @{
        "Domain" = 
            "nmci-isf.com"
        "Locality" = 
            "NMCI"
        "ServerLocators" = 
            "NMCI*SQ*",
            "NMCI*X*"
    } 
}

$threadCount = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
$FoundServers = [HashTable]::Synchronized(@{})
$FoundServers.Complete = 0

$RunspacePool = [runspacefactory]::CreateRunspacePool(1,$threadCount)
$RunspacePool.ApartmentState = "MTA"
$RunspacePool.Open()
[System.Collections.ArrayList]$RunspaceCollection = @()

$RunspaceBlock = {
    param($Domain, $Locality, $ServerLocators,$FoundServers)
    $dc = Get-ADDomainController -DomainName $Domain -Discover -NextClosestSite
    $i = 0
    foreach($ServerLocator in $ServerLocators){
        $Instance = [powershell]::Create().AddScript($ScriptBlock).AddArgument($ServerLocator).AddArgument($dc).AddArgument($Locality).AddArgument($FoundServers)
        $Instance.RunspacePool = $RunspacePool
        $RunspaceCollection.Add([PSCustomObject]@{
        Results  = $Instance.BeginInvoke()
        Instance = $Instance
        }) | Out-Null
    }
    do {
        $i = $FoundServers.Complete
        Write-Progress -Activity "All servers loaded for $Locality." -Status "$i Servers Complete."
        Start-Sleep -Seconds 1
    }
    while ($RunspaceCollection.Results.IsCompleted -contains $false)
    foreach ($Runspace in $RunspaceCollection){
        if ($Runspace.Results.IsCompleted){
            $Runspace.Instance.EndInvoke($Runspace.Results)
            $Runspace.Instance.Dispose()
        }
    }
}
$ScriptBlock = {
    param($ServerLocator, $dc,$Locality, $FoundServers)
    # SnapDrive SQ = SnapManagerService
    # SnapCenter SQ = SCWPluginService + SCSQLPluginService
    # Exchange = SCWPluginService
    $sdSvc = (Get-Service -ComputerName $foundServer -ServiceName SnapManagerService -ErrorAction SilentlyContinue).StartType
    $scSvc = (Get-Service -ComputerName $foundServer -ServiceName SCSQLPluginService -ErrorAction SilentlyContinue).StartType
    $exSvc = (Get-Service -ComputerName $foundServer -ServiceName SCWPluginService -ErrorAction SilentlyContinue).StartType
    
    $serverList = (Get-ADComputer -Filter 'Name -like $ServerLocator' -Server $dc.HostName[0]).DNSHostName
    foreach($foundServer in $serverList){
        if($sdSvc -eq 'Automatic'){
            $ProtectionType = "SnapDrive SQL"
            $SvcAccount = (Get-WmiObject win32_service -ComputerName $foundServer -Filter "Name='SnapManagerService'").StartName
        }
        elseif($scSvc -eq 'Automatic'){
            $ProtectionType = "SnapCenter SQL"
            $SvcAccount = (Get-WmiObject win32_service -ComputerName $foundServer -Filter "Name='SCSQLPluginService'").StartName
        }
        elseif($exSvc -eq 'Automatic'){
            $ProtectionType = "SnapCenter Exchange"
            $SvcAccount = (Get-WmiObject win32_service -ComputerName $foundServer -Filter "Name='SCWPluginService'").StartName
        }
        else{Continue}
        $FoundServers.$Locality.$foundServer += @{
            "Protection Type" = $ProtectionType
            "Service Account" = $SvcAccount
            "Domain" = $dc.Domain
            "Site" = $dc.Site
        }
        $FoundServers.Complete++
    }

}
Foreach($region in $AllServers.GetEnumerator()){
    $h = ($region.Value)
    &$RunspaceBlock -Domain $h.Domain -ServerLocators $h.ServerLocators -Locality $h.Locality -FoundServers $FoundServers
}

$FoundServers | Export-Csv -Path .\Users\colin.hearn\Documents\Powershell\ServerTest.csv
$RunspacePool.Close()
$RunspacePool.Dispose()