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
### Checks-Test.ps1
###
### Written by Carol Wapshere
###
### This is a sample file showing how different types of checks and fixes may be defined.
###
### UNDERSTANDING THE CHECKS HASHTABLE:
###   o The Checks hashtable is a consistent way to define how invalid objects are identified and repaired. 
###   o When defining checks it is very important to think about the size of the XPath query - never run a query like "/Person". We need to define small
###   queries that find only the invalid objects.
###   o Because of the way XPath works we often need to specify exact values - so it is expensive to query for "all people who belong to any group" but
###   not so bad to query for "all people who belong to group X".
###   o These checks should start with an XPath query that exports a selection of reference objects. We then loop through each object constructing a
###   targeted query just for that object. 
###   o Each Check must have a unique Key value. They will be run in numerical order.
###
###   The Checks hashtable has the following entries:
###     TargetAttribute    - The string attribute to update on the target
###     MultiValue         - True or False depending on whether the Target Attribute is multivalued
###     RefObjFilter       - Used to export all possible reference objects for this check
###     RefObjFile         - For efficiency, some lists of Reference Objects can be saved to a file so we're not re-querying the FIM Service each time. 
###                          The file will be regenerated after the number of hours specified in $RefreshInterval.
###     SourceValue        - The attribute on the Referenced object which is copied to the Target
###     RefObjAttribs      - A list of attributes we need to pick off the referenced object to use in constructing the search filters
###     ErrorFilter        - Finds objects which have an error of some type. May contain multiple filters.
###                          If the filter is likely to cause a timed out search, break it down by including "starts-with(DisplayName,'<A-Z>')" in the criteria. 
###                          This will cause the script to loop through each letter. (Use an attribute other than DisplayName if more appropriate)
###     ErrorFix           - How to fix objects found by the matching filter in ErrorFilter. May contain:
###                               * SourceValue - add the SourceValue to the TargetAttribute
###                               * DeleteValue - remove the SourceValue from the TargetAttribute
###                               * Expire - set ExpirationTime to today
###                               * ReTransition - Force a set retransition when the Reference Object is a criteria set
###                               * Other constant value - add the constant value to TargetAttribute


$Checks = @{}


## String value on referenced object matches string value on referring object
## Example: Check string attribute OfficeLocation matches the name of the linked Location object
$Checks.Add(1,@{})
# The attribute to update on an invalid object is OfficeLocation
$Checks.Item(1).Add("TargetAttribute","OfficeLocation")
# The OfficeLocation attribute is single valued
$Checks.Item(1).Add("MultiValue","False")
# Start by exporting all Location objects - these are the reference objects
$Checks.Item(1).Add("RefObjFilter","/Location")
# To reduce load on the FIM Service save the exported Locations to a file which can be used for the next runs of these Checks up to a maximum file age
$Checks.Item(1).Add("RefObjFile","E:\Scripts\DataQuality\data\locations.xml")
# The value from the reference object that will be copied to the target
$Checks.Item(1).Add("SourceValue","DisplayName")
# The script will loop through each exported Location object. Save the following attributes to use in the targeted XPath filters that look for invalid objects
$Checks.Item(1).Add("RefObjAttribs",@{"0" = "ObjectID";"1" = "DisplayName"})
# Start the ErrorFilter hashtable
$Checks.Item(1).Add("ErrorFilter",@{})
# Test 1: For each Location, find people who have the Location linked but do not have the correct OfficeLocation value
$Checks.Item(1).ErrorFilter.Add("1","/Person[Location='{0}' and not(OfficeLocation=""{1}"")]")
# Test 2: For each Location, find people who have no Location linked but do have a value in OfficeLocation
$Checks.Item(1).ErrorFilter.Add("2","/Person[not(Location='{0}') and OfficeLocation=""{1}""]")
# Start the ErrorFix hashtable
$Checks.Item(1).Add("ErrorFix",@{})
# Fix for objects found by Test 1: Update target's OfficeLocation with the SourceValue from the referenced Location
$Checks.Item(1).ErrorFix.Add("1","SourceValue")
# Fix for objects found by Test 2: Clear the OfficeLocation value on the target
$Checks.Item(1).ErrorFix.Add("2","DeleteValue")


## Boolean flag set correctly
## Example: People in the "People with AD Account" set should have IsInAD = True
$Checks.Add(2,@{})
$Checks.Item(2).Add("TargetAttribute","IsInAD")
$Checks.Item(2).Add("MultiValue","False")
# The only reference object we will export is the Set
$Checks.Item(2).Add("RefObjFilter","/Set[DisplayName = 'People with AD Account']")
# Get the ObjectID off the Set object to use in the ErrorFilters
$Checks.Item(2).Add("RefObjAttribs",@{"0" = "ObjectID"})
$Checks.Item(2).Add("ErrorFilter",@{})
# Test 1: Person is not in the set but has IsInAD = True
$Checks.Item(2).ErrorFilter.Add("1","/Person[ (ObjectID = /Set[ObjectID = '{0}']/ComputedMember) and not(IsInAD = 'True')]")
# Test 2: Person is in set but does not have IsInAD = True
$Checks.Item(2).ErrorFilter.Add("2","/Person[ not(ObjectID = /Set[ObjectID = '{0}']/ComputedMember) and (IsInAD = 'True')]")
$Checks.Item(2).Add("ErrorFix",@{})
# Fix for objects found by Test 1: Set IsInAD to True
$Checks.Item(2).ErrorFix.Add("1","True")
# Fix for objects found by Test 2: Set IsInAD to False
$Checks.Item(2).ErrorFix.Add("2","False")


## Dependency between two attributes on the same object
## Example: An empty PreferredFirstName should be populated with the FirstName
$Checks.Add(3,@{})
$Checks.Item(3).Add("TargetAttribute","PreferredFirstName")
$Checks.Item(3).Add("MultiValue","False")
# The Reference Objects filter here directly exports the problem objects
$Checks.Item(3).Add("RefObjFilter","/Person[not(starts-with(PreferredFirstName,'%')) and starts-with(FirstName,'%')]")
$Checks.Item(3).Add("SourceValue","FirstName")
$Checks.Item(3).Add("RefObjAttribs",@{"0" = "ObjectID"})
$Checks.Item(3).Add("ErrorFilter",@{})
# This ErrorFilter just selects each object in turn that was exported by the RefObjFilter
$Checks.Item(3).ErrorFilter.Add("1","/Person[ObjectID='{0}']")
$Checks.Item(3).Add("ErrorFix",@{})
# Fix any found objects by copying FirstName to PreferredFirstName
$Checks.Item(3).ErrorFix.Add("1","SourceValue")


## Date-dependant string value is correct
## Example: Set blank EmployeeStatus value based on Start and End dates
$Checks.Add(4,@{})
$Checks.Item(4).Add("TargetAttribute","EmployeeStatus")
$Checks.Item(4).Add("MultiValue","False")
# Get all Person objects with no EmployeeStatus
$Checks.Item(4).Add("RefObjFilter","/Person[not(starts-with(EmployeeStatus,'%'))]")
$Checks.Item(4).Add("RefObjAttribs",@{"0" = "ObjectID"})
$Checks.Item(4).Add("ErrorFilter",@{})
# Test 1: EmployeeStartDate in the future
$Checks.Item(4).ErrorFilter.Add("1","/Person[ObjectID='{0}' and (EmployeeStartDate > op:add-dayTimeDuration-to-dateTime(fn:current-dateTime(), xs:dayTimeDuration('P1D')))]")
# Test 2: Between EmployeeStartDate and EmployeeEndDate
$Checks.Item(4).ErrorFilter.Add("2","/Person[ObjectID='{0}' and (EmployeeStartDate < op:add-dayTimeDuration-to-dateTime(fn:current-dateTime(), xs:dayTimeDuration('P1D'))) and (EmployeeEndDate > fn:current-dateTime()) ]")
# Test 3: Past EmployeeEndDaye
$Checks.Item(4).ErrorFilter.Add("3","/Person[ObjectID='{0}' and (EmployeeEndDate < op:subtract-dayTimeDuration-from-dateTime(fn:current-dateTime(), xs:dayTimeDuration('P1D'))) ]")
$Checks.Item(4).Add("ErrorFix",@{})
# Fix for objects found by Test 1: Set EmployeeStats to Inactive
$Checks.Item(4).ErrorFix.Add("1","Inactive")
# Fix for objects found by Test 2: Set EmployeeStats to Active
$Checks.Item(4).ErrorFix.Add("2","Active")
# Fix for objects found by Test 3: Set EmployeeStats to Inactive
$Checks.Item(4).ErrorFix.Add("3","Inactive")


## Check comprising three objects
## Example: A Person's linked Roles match their active Entitlements, where the Entitlement has a reference both to the Person and the Role
$Checks.Add(5,@{})
# In this example 'Applications' is a multivalued reference attribute on the Person object that should link all Application Roles the person has Entitlements for
$Checks.Item(5).Add("TargetAttribute","Applications")
$Checks.Item(5).Add("MultiValue","True")
# Reference objects to loop through - all 'Application' type Role objects
$Checks.Item(5).Add("RefObjFilter","/Role[RoleType='Application']")
$Checks.Item(5).Add("RefObjFile","E:\Scripts\DataQuality\data\approles.xml")
$Checks.Item(5).Add("SourceValue","ObjectID")
$Checks.Item(5).Add("RefObjAttribs",@{"0" = "ObjectID"})
$Checks.Item(5).Add("ErrorFilter",@{})
# Test 1: For each Role, find people who have an active Entitlement with that Role, but do not have a direct link to the Role
$Checks.Item(5).ErrorFilter.Add("1","/Person[ (ObjectID = /Entitlement[Status = 'Active' and RoleLink = '{0}']/PersonLink) and not (Applications = '{0}') ]")
# Test 2: For each Role, find people who have a direct link to the Role, but do not have an active Entitlement
$Checks.Item(5).ErrorFilter.Add("2","/Person[ not(ObjectID = /Entitlement[Status = 'Active' and RoleLink = '{0}']/PersonLink) and (Applications = '{0}') ]")
$Checks.Item(5).Add("ErrorFix",@{})
# Fix for objects found by Test 1: Add the Role
$Checks.Item(5).ErrorFix.Add("1","SourceValue")
# Fix for objects found by Test 2: Remove the Role
$Checks.Item(5).ErrorFix.Add("2","DeleteValue")


## Members of a Set have something that all Set members get.
## Find all Sets that grant automatic entitlements and check members have the entitlement.
$Checks.Add(6,@{})
# Get all Sets that are related to default entitlement assignment
$Checks.Item(6).Add("RefObjFilter","/Set[contains(DisplayName,'Entitlement Default Users') and ServiceLink=/Service and ServiceRoleLink=/ServiceRole]")
# These Sets have been created with a reference link to the Service and ServiceRole they relate to - extract them to use in the error filters
$Checks.Item(6).Add("RefObjAttribs",@{"0" = "ObjectID";"1" = "ServiceRoleLink";"2" = "ServiceLink"})
$Checks.Item(6).Add("ErrorFilter",@{})
# Test 1: People who belong to the Set but don't have an entitlement for that Service
$Checks.Item(6).ErrorFilter.Add("1","/Person[ (ObjectID = /Set[ObjectID = '{0}']/ComputedMember) and not(ObjectID = /Entitlement[ServiceLink = '{2}']/PersonLink)]")
# Test 2: People not in the Set who have a "Default" entitlement - e they got it from being in the Set initially
$Checks.Item(6).ErrorFilter.Add("2","/Entitlement[Status='Active' and IsDefault = 'True' and RoleLink = '{1}' and not(PersonLink = /Set[ObjectID = '{0}']/ComputedMember)]")
$Checks.Item(6).Add("ErrorFix",@{})
# Fix 1: Force Set retransition - entitlement should be created by associated workflow
$Checks.Item(6).ErrorFix.Add("1","ReTransition")
# Fix 2: Expire the entitlement for person who no longer belongs to the Set
$Checks.Item(6).ErrorFix.Add("2","Expire")
