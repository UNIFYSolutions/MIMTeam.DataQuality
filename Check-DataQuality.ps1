PARAM(
    $ChecksFile="E:\Scripts\DataQuality\Checks-Test.ps1",
    $VerboseLogFile = "E:\Scripts\DataQuality\Check-Test.log",
    $RepairsLogFolder="E:\Logs\FIMDataQuality"
    )

#Copyright (c) 2014, Unify Solutions Pty Ltd
#All rights reserved.
#
#Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
#* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
#* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
#
#THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. 
#IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; 
#OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

### 
### Check-DataQuality.ps1
###
### Written by Carol Wapshere
###
### Runs checks on data quality on FIM Portal objects and repairs where possible. Example checks are:
###  - A string value matches one on a referenced object
###  - A boolean value is set correctly
###  - The correct value is set on an object based on the state of a referring object
###  - A value is correct based on the object being a member of a Set
### 
### When checks find an invalid object they may be fixed by:
###  - Copying a nominated attribute from a referenced object to the invalid object
###  - Deleting a particular attribute value
###  - Setting an attribute to a specified value
###  - Expiring an object
###  - Forcing a Set re-transition (criteria sets only)
###
### The Checks are defined in the $Checks hashtable which is contained in a seperate script - see Checks-Test.ps1 for examples and explanation. 
### To allow different scheduling options this hashtable is defined in a seperate file and then passed in as a parameter, alowing
### different Checks files to be run on different schedules, depending on their load and importance.
###
### BEFORE USING: 
###   1. You must have FIMPowerShell.ps1 from http://technet.microsoft.com/en-us/library/ff720152(v=ws.10).aspx
###   2. Define your Checks. See explanation in the sample Checks-Test.ps1 file.
###   3. Modify the default settings for script parameters and the location of the FIMPowerShell.ps1 script (below) to match your environment. 
###
### SCRIPT PARAMETERS:
###   -ChecksFile        (Required) The full path to the script containing the $Checks hashtable.
###   -RepairsLogFolder  (Required) The folder to use in creating a log of any repairs done.
###   -VerboseLogFile    (Optional) Logs errors and information about the script run. This is different to repair logs and should be used if troubleshooting this script.
###
###


### CONSTANTS
$RefreshInterval = 24 #In hours - how often to refresh the exported data\xml files used for quick enumeration of reference objects
$alphabet = @('A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z')

$ErrorActionPreference = "Stop"

# FIMPowerShell.ps1 from http://technet.microsoft.com/en-us/library/ff720152(v=ws.10).aspx
# TODO: Correct the path below to the location of your copy.
. E:\FIM\scripts\FIMPowerShell.ps1

# The ChecksFile should have been enetered on the command line
if (-not $ChecksFile -or -not (Test-Path $ChecksFile)) {Write-Error 'The ChecksFile parameter must be specified with the path to the PS1 script that defines the $Checks hashtable.'}
. $ChecksFile

$ErrorActionPreference = "Continue"


### If a Verbose logfile is specified, delete the existing logfile.
if ($VerboseLogFile)
{   
    if (test-path $VerboseLogFile) {Remove-Item $VerboseLogFile}
}



### FUNCTION - Logging ###
# Logs any repairs done to a timestamped CSV file. 
Function LogChange
{
    PARAM($ImportObject,$Comment,$RepairType)
    END
    {
    
        $LogTime = get-date -format "yyyyMMddHHmmss"

        if ($ImportObject.Changes)
        {
            foreach ($change in $ImportObject.Changes)
            {
                $Comment = $Comment + " " + $change.AttributeName + "=" + $change.AttributeValue
            }
        
            switch ($RepairType)
            {
                "SourceValue" {$RepairType="Add Value"}
                "DeleteValue" {$RepairType="Delete Value"}
                "ReTransition" {$RepairType="Set ReTransition"}
                default {$RepairType="Add Value"}
            }
            
            $values = @((get-date -format "MM/dd/yyyy HH:mm:ss").ToString(),
                        ($ImportObject.TargetObjectIdentifier).Replace("urn:uuid:",""),
                        $ImportObject.ObjectType,
                        $Comment,
                        $RepairType)
                        
            if ($VerboseLogFile) {$values -join ";" | add-content $VerboseLogFile}                   
            
            $RepairsLogFile = $RepairsLogFolder + "\" + ($ImportObject.TargetObjectIdentifier).Replace("urn:uuid:","") + "." + $LogTime + ".csv"
            "Timestamp;Target;ObjectType;Repair;RepairType" | out-file $RepairsLogFile -encoding "Default"
            ($values -join ";") | add-content $RepairsLogFile
        }
    }
}

### FUNCTION RemoveThenReAdd. ###
# Explicitly block an object from a set and then remove the block, allowing TransitionIn WF to fire.

Function RemoveThenReAdd
{
    PARAM($Set,$MemberID)
    END
    {
        # Update the filter to block the specific $MemberID
        $SetFilter = ($Set.ResourceManagementObject.ResourceManagementAttributes | where {$_.AttributeName -eq "Filter"}).Value
        $NewCondition = " and not(ObjectID = '{0}')]</Filter>" -f $MemberID
        $NewSetFilter = $RefObjFilter -replace ("]</Filter>",$NewCondition)
        
        $ImportObject = ModifyImportObject -TargetIdentifier $Set.ResourceManagementObject.ObjectIdentifier -ObjectType "Set"
        SetSingleValue -ImportObject $ImportObject -AttributeName "Filter" -NewAttributeValue $NewSetFilter
        $error.clear()
        Try { 
            $ImportObject | Import-FIMConfig
        } Catch {
            ##Write-Error $Error[0]
            if ($VerboseLogFile) {$Error[0] | add-content $VerboseLogFile} 
        }
        
        
        # Put the filter back as it was causing $MemberID to transition back in
        $ImportObject = ModifyImportObject -TargetIdentifier $Set.ResourceManagementObject.ObjectIdentifier -ObjectType "Set"
        SetSingleValue -ImportObject $ImportObject -AttributeName "Filter" -NewAttributeValue $SetFilter
        $error.clear()
        Try { 
            $ImportObject | Import-FIMConfig
        } Catch {
            ## Retry the change
            $ImportObject = ModifyImportObject -TargetIdentifier $Set.ResourceManagementObject.ObjectIdentifier -ObjectType "Set"
            SetSingleValue -ImportObject $ImportObject -AttributeName "Filter" -NewAttributeValue $SetFilter
            $error.clear()
            Try { 
                $ImportObject | Import-FIMConfig
            } Catch {
                if ($VerboseLogFile) {$Error[0] | add-content $VerboseLogFile} 
            }
        }
    }
}


### MAIN ###


foreach ($Check in $Checks.Keys | sort)
{
    if ($VerboseLogFile) {"Check number " + $Check | add-content $VerboseLogFile}   
    $TargetAttr = $Checks.($Check).TargetAttribute

    # Get the list of Reference Objects - from the file if specified and fresh enough; otherwise query
    if ($Checks.($Check).ContainsKey("RefObjFile"))
    {
        if  (Test-Path $Checks.($Check).RefObjFile)
        {
            $file = Get-Item $Checks.($Check).RefObjFile
            if ($VerboseLogFile) {"Lookup file " + $file | add-content $VerboseLogFile} 
              
            $DaysOld = (new-timespan $file.LastWriteTime $(get-date)).Days
            $HoursOld = ($DaysOld * 24) + (new-timespan $file.LastWriteTime $(get-date)).Hours
            if ($HoursOld -lt $RefreshInterval)
            {
                if ($VerboseLogFile) {"Using lookup file which has age in hours of " + $HoursOld | add-content $VerboseLogFile} 
                $RefObjects = ConvertTo-FIMResource -file $Checks.($Check).RefObjFile
            }
            else 
            {
                if ($VerboseLogFile) {"Refreshing lookup file which has age in hours of " + $HoursOld | add-content $VerboseLogFile} 
                if ($VerboseLogFile) {"Exporting using filter " + $Checks.($Check).RefObjFilter | add-content $VerboseLogFile} 
                $RefObjects = Export-FIMConfig -OnlyBaseResources -CustomConfig $Checks.($Check).RefObjFilter
                $RefObjects | ConvertFrom-FIMResource -file $Checks.($Check).RefObjFile
            }
        }
        else 
        {
            if ($VerboseLogFile) {"Exporting using filter " + $Checks.($Check).RefObjFilter | add-content $VerboseLogFile} 
            $RefObjects = Export-FIMConfig -OnlyBaseResources -CustomConfig $Checks.($Check).RefObjFilter
            $RefObjects | ConvertFrom-FIMResource -file $Checks.($Check).RefObjFile
        }
    }
    else 
    { 
        if ($VerboseLogFile) {"Exporting using filter " + $Checks.($Check).RefObjFilter | add-content $VerboseLogFile} 
        $RefObjects = Export-FIMConfig -OnlyBaseResources -CustomConfig $Checks.($Check).RefObjFilter 
    }
    
    
    # Run the checks against each Reference Object
    if ($RefObjects) {foreach ($RefObj in $RefObjects)
    {
        $RefObjName = ($RefObj.ResourceManagementObject.ResourceManagementAttributes | where {$_.AttributeName -eq "DisplayName"}).Value
        if ($VerboseLogFile) {"Running check against " + $RefObjName | add-content $VerboseLogFile} 
        
        # Get all attributes off the reference object that we need for the filters
        $AttribValues = @()
        if ($Checks.($Check).ContainsKey("RefObjAttribs")) 
        {foreach ($item in $Checks.($Check).Item("RefObjAttribs").Keys | sort)
        {
            $Attr = $RefObj.ResourceManagementObject.ResourceManagementAttributes | where {$_.AttributeName -eq $Checks.($Check).Item("RefObjAttribs").($item)}
            if ($Attr.IsMultiValue -eq 'True') {$value = ($Attr.Values)[0]}
            else {$value = $Attr.Value}   
            if ($value) {$AttribValues += $value.Replace("urn:uuid:","")} else {$AttribValues += $null}
        }}
        if ($VerboseLogFile) {"Values to use in filter: " + ($AttribValues -join ",") | add-content $VerboseLogFile} 
        
        # Get the source value from the referenced object if specified
        if ($Checks.($Check).ContainsKey("SourceValue"))
        {
            $Attr = $RefObj.ResourceManagementObject.ResourceManagementAttributes | where {$_.AttributeName -eq $Checks.($Check).SourceValue}
            if ($Attr.IsMultiValue -eq 'True') {$SourceValue = ($Attr.Values)[0]}
            else {$SourceValue = $Attr.Value}
        }
        if ($VerboseLogFile) {"Source value to compare against: " + $SourceValue | add-content $VerboseLogFile} 

        
        # Run each ErrorFilter and make any Fixes
        foreach ($item in $Checks.($Check).ErrorFilter.Keys)
        {
            $ErrorFilter = $Checks.($Check).ErrorFilter.($item) -f $AttribValues
            if ($ErrorFilter.contains("=''") -or $ErrorFilter.contains("="""""))
            { # Skip check because it has blank values in the filter where {n} did not get replaced by a valid string
            }
            else
            {
                if ($ErrorFilter.Contains("<A-Z>"))# Filter will result in a large query so we will break it down
                {
                    $loopArray = $alphabet
                }
                else
                {
                    $loopArray = @('A') # This dummy array is intended to make the foreach traverse once. Ther letter A is not used for anything.
                }
                
                foreach ($chr in $loopArray)
                {
                    $ErrorFilter = $Checks.($Check).ErrorFilter.($item) -f $AttribValues
                    if ($ErrorFilter.Contains("<A-Z>")) {$ErrorFilter = $ErrorFilter.Replace("<A-Z>",$chr)}
                    $ErrorFilter
                    
                    if ($VerboseLogFile) {"Looking for invalid objects using filter " + $ErrorFilter | add-content $VerboseLogFile}
                    $ErrorObjs = $null
                    $error.clear()
                    ## The following Try may mask errors that prevent objects being exported
                    Try { 
                        $ErrorObjs = Export-FIMConfig -OnlyBaseResources -CustomConfig $ErrorFilter 
                    } Catch {
                        ##Write-Error $Error[0]
                        if ($VerboseLogFile) {$Error[0] | add-content $VerboseLogFile} 
                    }
                    
                    if ($ErrorObjs)
                    {
                        $ErrorObjs.count
                        if ($VerboseLogFile -and $ErrorObjs.count) {"Found " + $ErrorObjs.count | add-content $VerboseLogFile}
                        elseif ($VerboseLogFile) {"Found 1" | add-content $VerboseLogFile}
                        
                        foreach ($obj in $ErrorObjs)
                        {
                            $ObjectType = ($obj.ResourceManagementObject.ResourceManagementAttributes | where {$_.AttributeName -eq 'ObjectType'}).Value
                            $ImportObject = ModifyImportObject -TargetIdentifier $obj.ResourceManagementObject.ObjectIdentifier -ObjectType $ObjectType
                            
                            if ($Checks.($Check).ErrorFix.($item) -eq "SourceValue")
                            {
                                if ($SourceValue -ne $null -and $SourceValue -ne "")
                                {
                                    if ($Checks.($Check).Item("MultiValue") -eq "False")
                                    {
                                        SetSingleValue -ImportObject $ImportObject -AttributeName $TargetAttr -NewAttributeValue $SourceValue
                                    } else {
                                        AddMultiValue -ImportObject $ImportObject -AttributeName $TargetAttr -NewAttributeValue $SourceValue
                                    }
                                    $LogDescription = "Add"
                                }
                            }
                            elseif ($Checks.($Check).ErrorFix.($item) -eq "DeleteValue")
                            {
                                if ($Checks.($Check).Item("MultiValue") -eq "False")
                                {
                                    SetSingleValue -ImportObject $ImportObject -AttributeName $TargetAttr -NewAttributeValue " "
                                } else {
                                    RemoveMultiValue -ImportObject $ImportObject -AttributeName $TargetAttr -NewAttributeValue $SourceValue
                                }
                                $LogDescription = "Remove"
                            }
                            elseif ($Checks.($Check).ErrorFix.($item) -eq "ReTransition")
                            {
                                RemoveThenReAdd -Set $RefObj -MemberID ($obj.ResourceManagementObject.ObjectIdentifier).replace("urn:uuid:","")
                                $LogDescription = "Re-transitioned {0} into set {1}." -f ($obj.ResourceManagementObject.ObjectIdentifier).replace("urn:uuid:",""),($RefObj.ResourceManagementObject.ObjectIdentifier).replace("urn:uuid:","")

                                # Sleep to space out set changes
                                Start-Sleep -s 30         
                            }
                            elseif ($Checks.($Check).ErrorFix.($item) -eq "Expire")
                            {
                                $DT = Get-Date (Get-Date -format 'd/M/yyyy')
                                $UTCDate = $DT.ToUniversalTime()
                                $Today = (Get-Date $UTCDate -Format "s") + ".000"
                                $ImportObject = ModifyImportObject -TargetIdentifier $obj.ResourceManagementObject.ObjectIdentifier -ObjectType $ObjectType
                                SetSingleValue -ImportObject $ImportObject -AttributeName "ExpirationTime" -NewAttributeValue $Today -FullyResolved 0
                                $error.clear()
                                Try { 
                                    $ImportObject | Import-FIMConfig
                                } Catch {
                                    ## Write-Error $Error[0]
                                    if ($VerboseLogFile) {$Error[0] | add-content $VerboseLogFile} 
                                }                            
                                $LogDescription = "Expired"
                            }
                            else # Use value specified on the check hashtable
                            {
                                if ($Checks.($Check).Item("MultiValue") -eq "False")
                                {
                                     SetSingleValue -ImportObject $ImportObject -AttributeName $TargetAttr -NewAttributeValue $Checks.($Check).ErrorFix.($item)
                                } else {
                                    AddMultiValue -ImportObject $ImportObject -AttributeName $TargetAttr -NewAttributeValue $Checks.($Check).ErrorFix.($item)
                                }
                                $LogDescription = "Add"
                            }

                            $ImportObject.Changes
                            $error.clear()
                            Try { 
                                $ImportObject | Import-FIMConfig
                            } Catch {
                                ## Write-Error $Error[0]
                                if ($VerboseLogFile) {$Error[0] | add-content $VerboseLogFile} 
                            }
                            
                            ## Log change to Repair table
                            LogChange -ImportObject $ImportObject -Comment $LogDescription -RepairType $Checks.($Check).ErrorFix.($item)
                        }
                    }
                }
            }
        }
    }}

    if ($VerboseLogFile) {"Check number " + $Check + " completed`n" | add-content $VerboseLogFile}   
    
}



