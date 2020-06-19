# Prefix for each machine
$VmName = "testvm"

# Number of VM
$numberOfVM = 4

#Error path
$ErrorLog = "C:\ErrorLog.txt"

#Resource Group
$resourceGroup = "YourResourceGroup"

#Location
$location = "EastUS" 

#PublicKey
$sshPublicKey = "YourPublicKey"


if($numberOfVM -lt 5) { 

	Try {

        # Create a subnet configuration
        $subnetConfig = New-AzureRmVirtualNetworkSubnetConfig `
          -Name default `
          -AddressPrefix 10.0.1.0/24

        # Create a virtual network
        $vnet = New-AzureRmVirtualNetwork `
          -ResourceGroupName $resourceGroup `
          -Location $location `
          -Name "$($VmName)-vnet" `
          -AddressPrefix 10.0.0.0/16 `
          -Subnet $subnetConfig

         $subnetId=$vnet.Subnets[0].Id 

        # Create an inbound network security group rule for port 22
        $nsgRuleSSH = New-AzureRmNetworkSecurityRuleConfig `
          -Name "$($VmName)-SecurityGroupRuleSSH"  `
          -Protocol "Tcp" `
          -Direction "Inbound" `
          -Priority 1000 `
          -SourceAddressPrefix * `
          -SourcePortRange * `
          -DestinationAddressPrefix * `
          -DestinationPortRange 22 `
          -Access "Allow"

        # Create an inbound network security group rule for port 80
        $nsgRuleWeb = New-AzureRmNetworkSecurityRuleConfig `
          -Name "$($VmName)-SecurityGroupRuleHTTP"  `
          -Protocol "Tcp" `
          -Direction "Inbound" `
          -Priority 1001 `
          -SourceAddressPrefix * `
          -SourcePortRange * `
          -DestinationAddressPrefix * `
          -DestinationPortRange 80 `
          -Access "Allow"

        # Create a network security group
        $nsg = New-AzureRmNetworkSecurityGroup `
          -ResourceGroupName $resourceGroup `
          -Location $location `
          -Name "$($VmName)-SecurityGroup" `
          -SecurityRules $nsgRuleSSH,$nsgRuleWeb

        $nsgid=$nsg.Id

        function Provision-VM( [string]$VmName, [string]$i,  [string]$resourceGroup ,[string]$location, [string] $subnetId, [string] $nsgid, [string] $sshPublicKey, [int] $numberOfVM ) {
            Start-Job -ArgumentList $VmName, $i,  $resourceGroup, $location, $subnetId, $nsgid, $sshPublicKey, $numberOfVM {
                param($VmName, $i,  $resourceGroup, $location, $subnetId, $nsgid, $sshPublicKey, $numberOfVM)

              # Create a public IP address and specify a DNS name
              $pip = New-AzureRmPublicIpAddress `
              -ResourceGroupName $resourceGroup `
              -Location $location `
              -AllocationMethod Static `
              -IdleTimeoutInMinutes 4 `
              -Name "$($VmName)-$($i)-pip"

              # Create a virtual network card and associate with public IP address and NSG
              $nic = New-AzureRmNetworkInterface `
              -Name "$($VmName)-$($i)-Nic" `
              -ResourceGroupName $resourceGroup `
              -Location $location `
              -SubnetId $subnetId `
              -PublicIpAddressId $pip.Id `
              -NetworkSecurityGroupId $nsgid

              # Define a credential object
               $securePassword = ConvertTo-SecureString ' ' -AsPlainText -Force
               $cred = New-Object System.Management.Automation.PSCredential ("azureuser", $securePassword)

               # Create a virtual machine configuration
               $vmConfig = New-AzureRmVMConfig `
                  -VMName "$($VmName)-$($i)" `
                  -VMSize "Standard_D1" | `
                Set-AzureRmVMOperatingSystem `
                  -Linux `
                  -ComputerName "$($VmName)-$($i)"`
                  -Credential $cred `
                  -DisablePasswordAuthentication | `
                Set-AzureRmVMSourceImage `
                  -PublisherName "Canonical" `
                  -Offer "UbuntuServer" `
                  -Skus "16.04-LTS" `
                  -Version "latest" | `
                Add-AzureRmVMNetworkInterface `
                  -Id $nic.Id

                # Configure the SSH key
                Add-AzureRmVMSshPublicKey `
                  -VM $vmconfig `
                  -KeyData $sshPublicKey `
                  -Path "/home/azureuser/.ssh/authorized_keys"
    
               New-AzureRmVM `
                -ResourceGroupName $resourceGroup `
                -Location $location -VM $vmConfig

                
               if ($numberOfVM % 2 -eq 0){
                    if($i % 2 -eq 0){
                        #Shutdown tag
                        $tags = (Get-AzureRmResource -ResourceGroupName $resourceGroup -ResourceType Microsoft.Compute/virtualMachines -Name "$($VmName)-$($i)").Tags
                        $tags += @{Name="shutdown"}
                        Set-AzureRmResource -ResourceGroupName $resourceGroup ` -Name "$($VmName)-$($i)" -ResourceType "Microsoft.Compute/VirtualMachines" -Tag $tags -Force               
                    }
                }
                else{
                    #2 Disk
                    $storageType = 'Standard_LRS'
                    $dataDiskName = "$($vmName)-$($i)-DataDisk"

                    $diskConfig = New-AzureRmDiskConfig -SkuName $storageType -Location $location -CreateOption Empty -DiskSizeGB 4
                    $dataDisk = New-AzureRmDisk -DiskName $dataDiskName -Disk $diskConfig -ResourceGroupName $resourceGroup

                    $vm = Get-AzureRmVM -Name "$($vmName)-$($i)" -ResourceGroupName $resourceGroup
                    $vm = Add-AzureRmVMDataDisk -VM $vm -Name $dataDiskName -CreateOption Attach -ManagedDiskId $dataDisk.Id -Lun 1

                    Update-AzureRmVM -VM $vm -ResourceGroupName $resourceGroup
                }
            }
        }


        #VMs
        For ($i=1; $i -le $numberOfVM; $i++) {
            Provision-VM $VmName $i  $resourceGroup $location $subnetId $nsgid $sshPublicKey $numberOfVM
            
        }

        # Wait for all to complete
        While (Get-Job -State “Running”) {
            Get-Job -State “Completed” | Receive-Job
            Start-Sleep -Seconds 5

        }

        # Display output from all jobs
        Get-Job | Receive-Job


        echo “Provisioning Completed”

        #Outputs
        #IPs of VMs
        For ($i=1; $i -le $numberOfVM; $i++) {

            echo "Information of the machine: $($VmName)-$($i)"
            $name=Get-AzureRmVM -Name "$($VmName)-$($i)" -ResourceGroupName $resourceGroup  | Select-Object Name
            #Public IP
            $n = Get-AzureRmNetworkInterface -Name "$($VmName)-$($i)-Nic" -ResourceGroupName $resourceGroup
            $pii=$n.IpConfigurations.publicIpAddress.Id
            $pubIp = Get-AzureRmPublicIpAddress -ResourceGroupName $resourceGroup | Where-Object {$_.Id -eq $pii}

            echo "Public IP: $($pubIp.IpAddress)"
            echo "Name: $($name.Name)"
            
        }

    }
    Catch{
	"ERROR "+ $_.Exception.Message | Add-Content $ErrorLog
	}

}
else{
     echo "The number of VMs must be less than or equal to 4"
}

