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
Param(
    [Parameter()]
    [String]
    $CsvPath = "C:\test\ProtectedServers.csv"
)
$allServers = @{
    "East" = @{
        "Domain" = 
            "nadsusea.nads.navy.mil"
        "Locality" = 
            "East Coast"
        "ServerLocators" = @(
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
            )
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
        "ServerLocators" = @(
            "PADSSPRLHSQ*",
            "PADSPRLHX*"
            )
    }
    "NMCI" = @{
        "Domain" = 
            "nmci-isf.com"
        "Locality" = 
            "NMCI"
        "ServerLocators" = @(
            "NMCI*SQ*",
            "NMCI*X*"
            )
    } 
}

$threadCount = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
$FoundServers = [HashTable]::Synchronized(@{})
$FoundServers.Complete = 0

$RunspacePool = [runspacefactory]::CreateRunspacePool(1,$threadCount)
$RunspacePool.ApartmentState = "MTA"
$RunspacePool.Open()
[System.Collections.ArrayList]$RunspaceCollection = @()
$ScriptBlock = {
    param(
        [string]$ServerLocator,
        [Microsoft.ActiveDirectory.Management.ADDomainController]$dc,
        [string]$Locality, 
        [hashtable]$FoundServers
        )
    Write-Verbose "Searching for servers with locator $ServerLocator in domain $($dc.Domain)."
    # SnapDrive SQ = SnapManagerService
    # SnapCenter SQ = SCWPluginService + SCSQLPluginService
    # Exchange = SCWPluginService
    Import-Module ActiveDirectory
    $serverList = (Get-ADComputer -Filter "Name -like $ServerLocator" -Server $dc.HostName[0]).DNSHostName
    if(-not $serverList){
        Write-Verbose "No servers found for locator $ServerLocator ."
    }
    foreach($foundServer in $serverList){
        Write-Verbose "Processing server $foundServer"
        $sdSvc = (Get-Service -ComputerName $foundServer -ServiceName SnapManagerService -ErrorAction SilentlyContinue).StartType
        $scSvc = (Get-Service -ComputerName $foundServer -ServiceName SCSQLPluginService -ErrorAction SilentlyContinue).StartType
        $exSvc = (Get-Service -ComputerName $foundServer -ServiceName SCWPluginService -ErrorAction SilentlyContinue).StartType
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
        else{
            Continue
        }
        Write-Verbose "Adding server $foundServer to the list with protection type $ProtectionType"
        $FoundServers[$Locality][$foundServer] += @{
            "Protection Type" = $ProtectionType
            "Service Account" = $SvcAccount
            "Domain" = $dc.Domain
            "Site" = $dc.Site
        }
        $FoundServers.Complete++
    }
}
$RunspaceBlock = {
    param(
        [string]$Domain, 
        [string]$Locality, 
        [array]$ServerLocators, 
        [hashtable]$FoundServers
        )
    Write-Verbose "Discovering domain controller for domain $Domain"
    $dc = Get-ADDomainController -DomainName $Domain -Discover -NextClosestSite
    foreach($ServerLocator in $ServerLocators){
        $Instance = [powershell]::Create().AddScript($ScriptBlock).AddArgument($ServerLocator).AddArgument($dc).AddArgument($Locality).AddArgument($FoundServers)
        $Instance.RunspacePool = $RunspacePool
        $RunspaceCollection.Add([PSCustomObject]@{
        Results  = $Instance.BeginInvoke()
        Instance = $Instance
        }) | Out-Null
    }
    do {
        Write-Progress -Activity "All servers loaded for $Locality." -Status "$($FoundServers.Complete) Servers Complete."
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

Foreach($region in $AllServers.Keys){
    $h = ($AllServers.$region.Value)
    &$RunspaceBlock -Domain $h.Domain -ServerLocators $h.ServerLocators -Locality $h.Locality -FoundServers $FoundServers
}

$FoundServers | Export-Csv -Path $CsvPath
$RunspacePool.Close()
$RunspacePool.Dispose()
