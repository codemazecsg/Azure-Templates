<#
.Synopsis
    Configure the SQL Server node.

.DESCRIPTION
    This script configures the SQL Server for the HPC Grid Cluster.

.NOTES
    This cmdlet requires:
    1. The current computer is a virtual machine created from the Azure SQL Image.
    2. The current computer is domain joined.

#>
param
(
	[Parameter(Mandatory=$true)]
	[String] $AdminUserName,
	
	[Parameter(Mandatory=$true)]
	[String] $AdminPassword,
	
    [Parameter(Mandatory=$true)]
    [String] $DomainAdminUserName,
	
    [Parameter(Mandatory=$true)]
    [String] $DomainNetBiosName	
)
	
$LogPath = "c:\Config"
$LogFile = "config.log"

function WriteLog
{
	param 
	(
    [Parameter(Mandatory=$false)]
    [String] $entry = "---"	
	)

	(Get-Date -format "MM/dd/yyyy hh:mm:ss") + " :: " + $entry | out-file $LogPath\$LogFile -append
}

if ((test-path -path $LogPath) -ne $true)
{
	New-Item $LogPath -type Directory
}

WriteLog("AdminuserName: " + $AdminUserName)
WriteLog("DomainAdminUserName: " + $DomainAdminUserName)
WriteLog("DomainNetBIOSName: " + $DomainNetBiosName)

try {
	
	$execPassword = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($AdminPassword))
	WriteLog("AdminPassword: " + $execPassword.SubString(0, 3).PadRight($execPassword.Length, "*"))
	$execUserCred = New-Object -TypeName System.Management.Automation.PSCredential `
                -ArgumentList @("$env:COMPUTERNAME\$AdminUserName", (ConvertTo-SecureString -String $execPassword -AsPlainText -Force))
	WriteLog("Credentials have been created.")
	
	Invoke-Command -ComputerName localhost -Credential $execUserCred -ScriptBlock {
		param($DomainAdminUserName, $DomainNetBiosName, $LogPath, $LogFile)
		
		function WriteLog
		{
			param 
			(
			[Parameter(Mandatory=$false)]
			[String] $entry = ""	
			)

			(Get-Date -format "MM/dd/yyyy hh:mm:ss") + " :: " + $entry | out-file $LogPath\$LogFile -append
		}
	
		try {

			Import-Module "sqlps" -DisableNameChecking -Force
			
			# Verify SQL has started and service in a "Running" state
			$loopCount = 0
			while (((Get-Service -Name MSSQLSERVER).Status -ne "Running") -and ($loopCount -lt 60))
			{
				WriteLog("Service Status: [" + $loopCount + "] " + (Get-Service -Name MSSQLSERVER).Status)
				Start-Sleep 3
				$loopCount++
			}
			
			# Verify locla admin has been provisioned
			$loginSuccess = 0
			$accessCheckLoopCnt = 0
			while (($loginSuccess -eq 0) -and ($accessCheckLoopCnt -lt 60))
			{
				try {
					Invoke-Sqlcmd -ServerInstance '.' -Database 'master' -Query "select @@version"
					$loginSuccess = 1
				}
				catch {
					WriteLog("Warning: Unable to access SQL Server")
					$accessCheckLoopCnt++
					Start-Sleep 3
				}
			}
		
			# Add domain admin as sysadmin in SQL Server
			Invoke-Sqlcmd -ServerInstance '.' -Database 'master' -Query "create login [$DomainNetBiosName\$DomainAdminUserName] from Windows"
			Invoke-Sqlcmd -ServerInstance '.' -Database 'master' -Query "sp_addsrvrolemember '$DomainNetBiosName\$DomainAdminUserName', 'sysadmin'"
			WriteLog("Domain user sysadmin access to SQL configured.")
			
			# Disable Windows Firewall
			Import-Module "NetSecurity"
			Get-NetFirewallProfile -All | Set-NetFirewallProfile -Enabled False
			WriteLog("Firewall disabled.")
			
		}
		catch {
		
			WriteLog("Warning: Error encountered!!!")
			WriteLog($error[0])
		}

		} -ArgumentList $DomainAdminUserName, $DomainNetBiosName, $LogPath, $LogFile
	}
	catch {
	
			WriteLog("Warning: Error encountered!!!")
			WriteLog($error[0])
		
	}