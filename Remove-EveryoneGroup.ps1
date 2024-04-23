<#PSScriptInfo

.VERSION 1.1.0

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
#>

#Requires -Module NTFSSecurity

<# 

.DESCRIPTION 
 Removes the Everyone group from specified home directories. Removes inheritance and adds the Administrator group if required. 

#> 

Param(
    # Home directory folder. Example: $UNCName = "\\nawespscfs101v\c$\home\USER01\"
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

if ($UNCName -match "^\\\\[^\\]+\\c\$\\home$") {
    # Get all subfolders under /home
    $UNCDirectories = Get-ChildItem $UNCName -Directory
    foreach($dir in $UNCDirectories){
        [int]$adminCount = 0
        [int]$inherCount = 0
        [int]$everyCount = 0
        [int]$changeCount = 0
        Write-Host ("{0,-25} {1,-35}" -f "Directory", $dir.Name) -ForegroundColor Cyan
        $UNCChildren = Get-ChildItem $dir
        foreach($folder in $UNCChildren){
            # Check access to folder. Add admin if needed.
            try{
                $acl = $folder.GetAccessControl()
            }
            catch{
                Add-NTFSAccess $folder -Account BUILTIN\Administrators -AccessRights FullControl -AccessType Allow -InheritanceFlags ContainerInherit,ObjectInherit -PropagationFlags None
                $acl = $folder.GetAccessControl()
                $adminCount += 1
                $folderMod = $true
                Write-Host ("{0,-25} {1,-35}" -f $folder.Name, "Admin Added") -ForegroundColor Red
            }
            # Disable inheritance.
            if($acl.access.IsInherited -eq $true){
                $acl.SetAccessRuleProtection($true,$true)
                $folder.SetAccessControl($acl)
                $inherCount += 1
                $folderMod = $true
                Write-Host ("{0,-25} {1,-35}" -f $folder.Name, "Inheritance Removed") -ForegroundColor Red
            }
    
            # Check if Administrator Group was removed due to inheritance. Add if needed.
            try{
                $acl = $folder.GetAccessControl()
            }
            catch{
                Add-NTFSAccess $folder -Account BUILTIN\Administrators -AccessRights FullControl -AccessType Allow -InheritanceFlags ContainerInherit,ObjectInherit -PropagationFlags None
                $acl = $folder.GetAccessControl()
                $adminCount += 1
                $folderMod = $true
                Write-Host ("{0,-25} {1,-35}" -f $folder.Name, "Admin Added") -ForegroundColor Red
            }
    
            # Check if Everyone Group exists. Remove if needed.
            $everyoneGroup = $acl.Access.Where({ $_.IdentityReference -match 'Everyone' })
            if($everyoneGroup.count -ne 0){
                $everyoneGroup | ForEach-Object { $acl.RemoveAccessRule($_) } | Out-Null
                $folder.SetAccessControl($acl)
                $everyCount += 1
                $folderMod = $true
                Write-Host ("{0,-25} {1,-35}" -f $folder.Name, "Everyone Removed") -ForegroundColor Red
            }
    
            if($folderMod){
                $changeCount += 1
                Remove-Variable folderMod
            }
            Else{
                Write-Host ("{0,-25} {1,-35}" -f $folder.Name, "Good") -ForegroundColor Green
            }
        }
        Write-Host ("{0,-25} {1,-35}" -f "Folders modified:", $changeCount)
        Write-Host ("{0,-25} {1,-35}" -f "Admin Groups Added:", $adminCount)
        Write-Host ("{0,-25} {1,-35}" -f "Inheritance Removed:", $inherCount)
        Write-Host ("{0,-25} {1,-35}" -f "Everyone Removed:", $everyCount)

    }
} 
elseif ($UNCName -match "^\\\\[^\\]+\\c\$\\home\\[^\\]+$" -or $UNCName -match "^\\\\[^\\]+\\[^\\]+\$") {
    $UNCChildren = Get-ChildItem $UNCName | Sort-Object
    [int]$adminCount = 0
    [int]$inherCount = 0
    [int]$everyCount = 0
    [int]$changeCount = 0
    foreach($folder in $UNCChildren){
        # Check access to folder. Add admin if needed.
        try{
            $acl = $folder.GetAccessControl()
        }
        catch{
            Add-NTFSAccess $folder -Account BUILTIN\Administrators -AccessRights FullControl -AccessType Allow -InheritanceFlags ContainerInherit,ObjectInherit -PropagationFlags None
            $acl = $folder.GetAccessControl()
            $adminCount += 1
            $folderMod = $true
            Write-Host ("{0,-25} {1,-35}" -f $folder.Name, "Admin Added") -ForegroundColor Red
        }
        # Disable inheritance.
        if($acl.access.IsInherited -eq $true){
            $acl.SetAccessRuleProtection($true,$true)
            $folder.SetAccessControl($acl)
            $inherCount += 1
            $folderMod = $true
            Write-Host ("{0,-25} {1,-35}" -f $folder.Name, "Inheritance Removed") -ForegroundColor Red
        }

        # Check if Administrator Group was removed due to inheritance. Add if needed.
        try{
            $acl = $folder.GetAccessControl()
        }
        catch{
            Add-NTFSAccess $folder -Account BUILTIN\Administrators -AccessRights FullControl -AccessType Allow -InheritanceFlags ContainerInherit,ObjectInherit -PropagationFlags None
            $acl = $folder.GetAccessControl()
            $adminCount += 1
            $folderMod = $true
            Write-Host ("{0,-25} {1,-35}" -f $folder.Name, "Admin Added") -ForegroundColor Red
        }

        # Check if Everyone Group exists. Remove if needed.
        $everyoneGroup = $acl.Access.Where({ $_.IdentityReference -match 'Everyone' })
        if($everyoneGroup.count -ne 0){
            $everyoneGroup | ForEach-Object { $acl.RemoveAccessRule($_) } | Out-Null
            $folder.SetAccessControl($acl)
            $everyCount += 1
            $folderMod = $true
            Write-Host ("{0,-25} {1,-35}" -f $folder.Name, "Everyone Removed") -ForegroundColor Red
        }

        if($folderMod){
            $changeCount += 1
            Remove-Variable folderMod
        }
        Else{
            Write-Host ("{0,-25} {1,-35}" -f $folder.Name, "Good") -ForegroundColor Green
        }
    }
    Write-Host ("{0,-25} {1,-35}" -f "Folders modified:", $changeCount)
    Write-Host ("{0,-25} {1,-35}" -f "Admin Groups Added:", $adminCount)
    Write-Host ("{0,-25} {1,-35}" -f "Inheritance Removed:", $inherCount)
    Write-Host ("{0,-25} {1,-35}" -f "Everyone Removed:", $everyCount)
}