# MIMTeam.DataQuality
MIM Data Quality Script

# Author
Carol Wapshere

# Check-DataQuality.ps1
Runs checks on data quality on FIM Portal objects and repairs where possible. Example checks are:

* A string value matches one on a referenced object,
* A boolean value is set correctly,
* The correct value is set on an object based on the state of a referring object,
* A value is correct based on the object being a member of a Set.

When checks find an invalid object they may be fixed by:

* Copying a nominated attribute from a referenced object to the invalid object,
* Deleting a particular attribute value,
* Setting an attribute to a specified value,
* Expiring an object,
* Forcing a Set re-transition (criteria sets only).

The Checks are defined in the $Checks hashtable which is contained in a separate script - see Checks-Test.ps1 for examples and explanation. To allow different scheduling options this hashtable is defined in a separate file and then passed in as a parameter, allowing different Checks files to be run on different schedules, depending on their load and importance.

# BEFORE USING
1. You must have FIMPowerShell.ps1 from http://technet.microsoft.com/en-us/library/ff720152(v=ws.10).aspx
1. Define your Checks. See explanation in the sample Checks-Test.ps1 file.
1. Modify the default settings for script parameters and the location of the FIMPowerShell.ps1 script (below) to match your environment. 

# SCRIPT PARAMETERS
* ChecksFile (Required) The full path to the script containing the $Checks hashtable.
* RepairsLogFolder (Required) The folder to use in creating a log of any repairs done.
* VerboseLogFile (Optional) Logs errors and information about the script run. This is different to repair logs and should be used if troubleshooting this script.