<# 
   This is a script framework to Create an Active Directory User and Office365 user
   This is a work in progress, and is in active development
   Created by ses2045

   INSTRUCTIONS:
   Make sure that your powershell has the following installed:
   Import-Module ActiveDirectory
   Import-Module MSOnline

   Open Powershell as Admin (preferably on a Domain Controller)
   run "cd C:\Users\de-fixedit\Desktop"
   run .\"Filename" 
   Follow the Params 
#>

[cmdletbinding()]

param (

#This make the Parameter Mandatory and in the very first position in the line
#If the param is skipped it will ask for the next Param
[Parameter(mandatory=$true,Position=0)]
[ValidateNotNullOrEmpty()]
[string]$Firstname,

[Parameter(Mandatory=$true,Position=1)]
[ValidateNotNullOrEmpty()]
[string]$Lastname,

#The $Location Param is the "OU"
#This will give you trouble if your AD is deep and very complex with where users accounts are located
#This Exits the script if a Non OU is provided
[Parameter(Mandatory=$true,Position=2)]
[ValidateNotNullOrEmpty()]
[ValidateSet('Detroit', 'Ann Arbor', 'Lansing', 'Toledo', 'Cleveland', ignorecase=$false)]
$Location,

#This is their Job Position
[Parameter(Mandatory=$true,Position=3)]
[ValidateNotNullOrEmpty()]
[string]$Position,

#This Exits the script if a Non Correct License is choosen
#This uses Business Premium or Essentials licenses, but you can change this for whatever your org uses
[Parameter(Mandatory=$true,Position=4)]
[ValidateNotNullOrEmpty()]
[ValidateSet('Premium','Essentials')]
[string]$License,

[Parameter(Mandatory=$true,Position=5)]
[ValidateNotNullOrEmpty()]
[string]$Pass
)

#This function just outputs time: [mm/dd/yy hh:mm:ss]
function Get-TimeStamp {
    
    return "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)
    
}

#This is where any Errors are dumped
$ErrorLog = "C:\ScriptErrors\ScriptLogs.txt"

$Loc = $Location

$State
if($Location -eq ("Detroit" -or "Ann Arbor" -or "Lansing")) {$State = "MI"}
if($Location -eq ("Cleveland") -or ("Toledo")) {$State = "OH"}


#This takes the first letter and lastname and makes a username
#Richard Stallman would be RStallman
$Username = $Firstname[0] + $Lastname

$Fullname = $Firstname + " " + $Lastname

#This Takes the Location of the user and puts it into the full Organizational Unit
[string]$OU = "OU=$Loc,OU=Users,OU=MyBuisness,DC=ad,DC=mybuisness,DC=com"

#This takes the Prompted Password and turns it into a secure string
$Defpass = (ConvertTo-SecureString "$Pass" -AsPlainText -Force)


#This is where the License variables are
#You can find this with the Get-MsolAccountSku cmdlet when connected to O365
#With the Connect-MsolService cmdlet
$Arm = "mybuisness:RIGHTSMANAGEMENT"
$Prem = "mybuisness:O365_BUSINESS_PREMIUM" 
$Esse = "mybuisness:O365_BUSINESS_ESSENTIALS"

#This checks to see if the username is already taken, if it is null it will say "Username is free"
$Found = try { Get-ADUser $Username } catch { Write-Host "Username is Free"}

$Email = $Username + "@mybuisness.com" 

#This is where the User is created
#Any errors will be caught 
Try {
    if ($Found -eq $null)
    { New-ADUser -SamAccountName $Username -AccountPassword $Defpass -UserPrincipalName $Email -GivenName $Firstname -Surname $Lastname -Name $Fullname -DisplayName $Fullname -path $OU -Enabled $true -ChangePasswordAtLogon $true -Title $Position -City $Location -State $State }
    
    #This is used to make a user with their fullname if there is already a username taken, so if RStalman is taken it will create RandallStallman
    if ($Found -ne $null)
    { $Username = $Firstname + $Lastname
      $Email = $Username + "@mybuisness.com" 
      New-ADUser -SamAccountName $Username -AccountPassword $Defpass -UserPrincipalName $Email -GivenName $Firstname -Surname $Lastname -Name $Fullname -DisplayName $Fullname -path $OU -Enabled $true -ChangePasswordAtLogon $true -Title $Position -City $Location -State $State }
    
    Write-Host "User $Username Created!"
    Write-Host $Email

    #This starts the sync between your AD and your O365 
    Start-ADSyncSyncCycle -policytype delta
    Write-Host "Starting AD Sync...Waiting 60 Seconds"
    Start-Sleep -Seconds 60
}

Catch {
    Write-Output "$(Get-TimeStamp)" | Out-File $ErrorLog -Append
    $_ | Out-File $ErrorLog -Append
    Write-Warning "Something went Wrong, Check the Log file at $ErrorLog , Exiting"
    Start-Sleep -Seconds 15
    Exit
} 

#This connects to Azure 365, a popup will appear that looks much like your normal MS login, this is safe to log into
Connect-MsolService
Write-Host "Connecting to Office 365"
start-sleep -Seconds 10

#These 3 Will allow us to see the current Active and Consumed Licenses
$ArmTest = Get-MsolAccountSku | Where {$_.AccountSkuID -eq $Arm}
$PremTest = Get-MsolAccountSku | Where {$_.AccountSkuID -eq $Prem}
$EsseTest = Get-MsolAccountSku | Where {$_.AccountSkuID -eq $Esse}

#These 3 will give us the Total Remaining Licenses
$ArmRem = $ArmTest.ActiveUnits - $ArmTest.ConsumedUnits
$PremRem = $PremTest.ActiveUnits - $PremTest.ConsumedUnits
$EsseRem = $EsseTest.ActiveUnits - $EsseTest.ConsumedUnits

#This Gives a warning when any of the licenses are under 5 remaining
if ($ArmRem -le 5) { 
    Write-Warning "There are $ArmRem Azure Rights Management Licenses! ! !"
    Start-Sleep -Seconds 5 
}

if (($License -eq 'Premium') -and ($PremRem -le 5)) { 
    Write-Warning "There are $PremRem Business Premium Licenses! ! !" 
    Start-Sleep -Seconds 5 
}

if (($License -eq 'Essentials') -and ($EsseRem -le 5)) { 
    Write-warning "There are $EsseRem Essentials Licenses! ! !" 
    Start-Sleep -Seconds 5 
}

#These should tell you that there are no licenses and exit the script, usefull for when you dont want to accidently purchase more
#NOTE: The user will still be created
if ($ArmRem -eq '0') {
    Write-Host "There are no Azure Rights Managment Licenses! ! ! Please Check Office 365 Admin Center" -ForegroundColor Red
    Start-Sleep -Secconds 10
    Exit
}

if (($License -eq 'Premium') -and ($PremRem -eq '0')) {
    Write-Host "There are no Business Premium Licenses! ! ! Please Check Office 365 Admin Center!" -ForegroundColor Red 
    Start-Sleep -Seconds 10
    Exit
}

if (($License -eq 'Essentials') -and ($EsseRem -eq '0')) {
    Write-Host "There are no Business Essentials Licenses! ! ! Please Check Office 365 Admin Center" -ForegroundColor Red 
    Start-Sleep -Seconds 10
    Exit
}

#This is where the license is added to the MSOL account
Try{
    
    Get-MsolUser -UserPrincipalName $Email | Format-table -HideTableHeaders UserPrincipalName
    Set-MsolUser -UserPrincipalName $Email -UsageLocation "US"

    if ($License -eq 'Premium') {Set-MsolUserLicense -UserPrincipalName $Email -AddLicenses $Arm,$Prem }
    if ($License -eq 'Essentials') {Set-MsolUserLicense -UserPrincipalName $Email -AddLicenses $Arm,$Esse }

    Write-Host "License added! Please check Office365 to verify a Mailbox is being created!"
}

#This write out any errors to the "C:\ScriptErrors\ScriptLogs.txt" file 
Catch{

    Write-Output "$(Get-TimeStamp)" | Out-File $ErrorLog -Append
    $_ | Out-File $ErrorLog -Append
    Write-Warning "Something went Wrong, Check the Log file at $ErrorLog , Exiting"
    Start-Sleep -Seconds 15
    Exit
}
