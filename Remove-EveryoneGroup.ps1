<#PSScriptInfo

.VERSION 1.1.7

.GUID a88953e9-bba3-4eed-80a8-5bbd2597c97a

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
1.0.5 - Fixed issue with $endreport collection that caused improper output and memory usage.  
1.0.6 - Fixed error that caused $OutputPath parameter to be mandatory. 
1.0.7 - Converted all Arrays to ArrayLists for performance increase. 
1.0.8 - Automated and removed the -Full switch.
1.0.9 - Changed default behavior to hide progress. -ShowProgress will now display progress.
1.1.0 - Rewrite of entire script to improve performance and manageability. Changes to remove NTFSSecurity pending.
1.1.1 - Removed commented-out variables. Added logic to determine $UNCPath using regular expressions. 
1.1.3 - Added runspaces to improve performance.
1.1.5 - Added synchronized hash tables for progress tracking. 
1.1.6 - Updated max thread limits to vary per machine. 
#>

#Requires -Module NTFSSecurity

<# 

.DESCRIPTION 
 Removes the Everyone group from specified home directories. Removes inheritance and adds the Administrator group if required. 

#> 

Param(
    # Home directory folder. Example: $UNCName = "\\[ServerName]\[DirectoryPath]$\"
    [Parameter( Mandatory )]
    [String]
    $UNCName
)
<#

$adminCount      : Number of folders missing Administrators group.
$acl             : ACL Object of the current $folder in the loop. 
$changeCount     : Number of folders modified
$dir             : Each item in $UNCDirectories
$everyCount      : Number of folders with Everyone Group present.
$everyoneGroup   : Used to check and remove Everyone Group if present. Count = 0 if absent.
$folder          : Current $UNCChildren item in the loop.
$folderMod       : True if current folder ACL was changed.
$inherCount      : Number of folders with inheritance enabled.
$UNCChildren     : Folders contained within $UNCName.
$UNCDirectories  : Child items of ..\home\
$UNCName         : Directory to be checked.

#>
$threadCount = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
$SharedChanges = [HashTable]::Synchronized(@{})
$SharedChanges.ChangesMade = 0
$SharedChanges.FoldersComplete = 0


$RunspacePool = [runspacefactory]::CreateRunspacePool(1,$threadCount)
$RunspacePool.ApartmentState = "MTA"
$RunspacePool.Open()
[System.Collections.ArrayList]$RunspaceCollection = @()
$RunspaceBlock = {
    param($UNCChildren)
    $t = ($UNCChildren | Measure-Object).Count
    $i = 0
    foreach($folder in $UNCChildren){
        $Instance = [powershell]::Create().AddScript($ScriptBlock).AddArgument($folder).AddArgument($SharedChanges)
        $Instance.RunspacePool = $RunspacePool
        $RunspaceCollection.Add([PSCustomObject]@{
        Results  = $Instance.BeginInvoke()
        Instance = $Instance
        }) | Out-Null
    }
    do {
        $i = $SharedChanges.FoldersComplete
        Write-Progress -Activity "All folders loaded. Checking/Updating." -Status "$i/$t Folders Complete."
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
    param($folder,$SharedChanges)
    Import-Module NTFSSecurity
    # Check access to folder. Add admin if needed.
    try{
        $acl = $folder.GetAccessControl()
    }
    catch{
        Add-NTFSAccess $folder -Account BUILTIN\Administrators -AccessRights FullControl -AccessType Allow -InheritanceFlags ContainerInherit,ObjectInherit -PropagationFlags None
        $acl = $folder.GetAccessControl()                
    }
    # Disable inheritance.
    if($acl.access.IsInherited -eq $true){
        $acl.SetAccessRuleProtection($true,$true)
        $folder.SetAccessControl($acl)
    }
    # Check if Administrator Group was removed due to inheritance. Add if needed.
    try{
        $acl = $folder.GetAccessControl()
    }
    catch{
        Add-NTFSAccess $folder -Account BUILTIN\Administrators -AccessRights FullControl -AccessType Allow -InheritanceFlags ContainerInherit,ObjectInherit -PropagationFlags None
        $acl = $folder.GetAccessControl()
    }
    # Check if Everyone Group exists. Remove if needed.
    $everyoneGroup = $acl.Access.Where({ $_.IdentityReference -match 'Everyone' })
    if($everyoneGroup.count -ne 0){
        $everyoneGroup | ForEach-Object { $acl.RemoveAccessRule($_) } | Out-Null
        $folder.SetAccessControl($acl)
        $folderMod = $true
    }
    if($folderMod){
        $SharedChanges.ChangesMade++
        $SharedChanges.FolderNames += $folder.Name + "`n"
    }
    $SharedChanges.FoldersComplete++
}
if ($UNCName -match "^\\\\[^\\]+\\c\$\\home$") {
    # Get all subfolders under /home
    $UNCDirectories = Get-ChildItem $UNCName -Directory | Sort-Object
    foreach($dir in $UNCDirectories){
        Write-Host "Retrieving child folders of $dir."
        $UNCChildren = Get-ChildItem $dir.FullName -Directory | Sort-Object
        &$RunspaceBlock -UNCChildren $UNCChildren | Out-Null
        $SharedChanges.FolderNames
        Write-Host "Folders Requiring Everyone Group Removal in $dir : ",$SharedChanges.ChangesMade
        $SharedChanges.ChangesMade = 0
        $SharedChanges.FoldersComplete = 0
        $SharedChanges.Remove('FolderNames')
    }
} 
else{
    Write-Host "Retrieving child folders of $UNCName."
    $UNCChildren = Get-ChildItem $UNCName -Directory | Sort-Object
    &$RunspaceBlock -UNCChildren $UNCChildren | Out-Null
    $SharedChanges.FolderNames
    Write-Host "Folders Requiring Everyone Group Removal: ",$SharedChanges.ChangesMade
}


$RunspacePool.Close()
$RunspacePool.Dispose()