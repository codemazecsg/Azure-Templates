configuration CreateADPDC 
{ 
   param 
   ( 
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds,

        [String]$DnsForwarder="8.8.8.8",

        [Int]$RetryCount=20,
        [Int]$RetryIntervalSec=45
    ) 
    
    Import-DscResource -ModuleName xActiveDirectory, xStorage, xNetworking
    [System.Management.Automation.PSCredential ]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($Admincreds.UserName)", $Admincreds.Password)
    $Interface=Get-NetAdapter|Where Name -Like "Ethernet*"|Select-Object -First 1 
    $InterfaceAlias=$($Interface.Name) 


    Node localhost
    {
        LocalConfigurationManager
        {
            ActionAfterReboot = 'ContinueConfiguration'
            ConfigurationMode = 'ApplyOnly'
            RebootNodeIfNeeded = $true
        }
        WindowsFeature DNS 
        { 
            Ensure = "Present" 
            Name = "DNS"
        }
        xDnsServerAddress DnsServerAddress
        {
            Address        = '127.0.0.1'
            InterfaceAlias = $InterfaceAlias
            AddressFamily  = 'IPv4'
        }
        xWaitforDisk Disk2
        {
             DiskNumber = 2
             RetryIntervalSec =$RetryIntervalSec
             RetryCount = $RetryCount
        }
        xDisk ADDataDisk
        {
            DiskNumber = 2
            DriveLetter = "F"
            FSLabel = 'ADData'
        }
        WindowsFeature ADDSInstall
        {
            Ensure = "Present"
            Name = "AD-Domain-Services"
        }
        WindowsFeature ADDSTools
        {
            Ensure = "Present"
            Name = "RSAT-ADDS"
        }
        WindowsFeature DNSServerTools
        {             
            Ensure = "Present"
            Name = "RSAT-DNS-Server"
        }
        xADDomain FirstDS
        {
            DomainName = $DomainName
            DomainAdministratorCredential = $DomainCreds
            SafemodeAdministratorPassword = $DomainCreds
            DatabasePath = "F:\NTDS"
            LogPath = "F:\NTDS"
            SysvolPath = "F:\SYSVOL"
            DependsOn = "[WindowsFeature]ADDSInstall","[xDisk]ADDataDisk“
        }
        Script ConfigDNSForwarder
        {
            GetScript = {
                return @{Result = $true}
            }
            
            SetScript = Format-ConfigDnsForwarderScriptBlock -DnsFowarder $DnsForwarder -ScriptBlock {
                $dnsForwarder = @"
{DnsForwarderPlaceholder}
"@
                try
                {
                    $desiredFwdIPs = @()
                    if($null -ne (Get-DnsServerForwarder).IPAddress)
                    {
                        foreach($fwdIP in @((Get-DnsServerForwarder).IPAddress))
                        {
                            if(($fwdIP -eq "fec0:0:0:ffff::1") -or ($fwdIP -eq "fec0:0:0:ffff::2") -or ($fwdIP -eq "fec0:0:0:ffff::3"))
                            {
                                Write-Verbose -Message "Removing DNS forwarder: $fwdIP"
                                Remove-DnsServerForwarder -IPAddress $fwdIP -Force
                            }
                            else
                            {
                                $desiredFwdIPs += $fwdIP
                            }
                        }
                    }
                    if(-not [string]::IsNullOrEmpty($dnsForwarder))
                    {
                        $dnsForwarderIP = [IPAddress]$dnsForwarder
                        if($desiredFwdIPs -notcontains $dnsForwarderIP)
                        {
                            Write-Verbose -Message "Adding DNS forwarder: $dnsForwarderIP"
                            $desiredFwdIPs += $dnsForwarderIP
                            Set-DnsServerForwarder -IPAddress $desiredFwdIPs -Confirm:$false
                        }
                    }
                }
                catch
                {
                    Write-Error -Message ($_ | Out-String)
                }
            }
            
            TestScript = Format-ConfigDnsForwarderScriptBlock -DnsFowarder $DnsForwarder -ScriptBlock {
                $dnsForwarder = @"
{DnsForwarderPlaceholder}
"@
                try
                {                    
                    $fwdIPs = @()
                    if($null -ne (Get-DnsServerForwarder).IPAddress)
                    {
                        $fwdIPs = @((Get-DnsServerForwarder).IPAddress)
                        foreach($fwdIP in $fwdIPs)
                        {
                            if(($fwdIP -eq "fec0:0:0:ffff::1") -or ($fwdIP -eq "fec0:0:0:ffff::2") -or ($fwdIP -eq "fec0:0:0:ffff::3"))
                            {
                                return $false
                            }
                        }
                    }
                    if(-not [string]::IsNullOrEmpty($dnsForwarder))
                    {
                        $dnsForwarderIP = [IPAddress]$dnsForwarder
                        if($fwdIPs -notcontains $dnsForwarderIP)
                        {
                            return $false
                        }                        
                    }
                }
                catch
                {
                    Write-Warning -Message ($_ | Out-String)
                }

                return $true
            }

            DependsOn = "[xADDomain]FirstDS"
        }
   }
} 

function Format-ConfigDnsForwarderScriptBlock
{
    param(
        [parameter(Mandatory=$false)]
        [string] $DnsFowarder = "",

        [parameter(Mandatory=$true)]
        [System.Management.Automation.ScriptBlock] $ScriptBlock
    )

    $result = $ScriptBlock.ToString()
    $result = $result.Replace("{DnsForwarderPlaceholder}", $DnsFowarder)
    return $result
}