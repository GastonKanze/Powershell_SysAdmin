$TagValue = "shutdown"

$vms = Get-AzureRmResource -TagName "Name" -ResourceType Microsoft.Compute/virtualMachines `
    | where { $_.Tags[‘Name’] -ieq $TagValue } | Select Name, ResourceGroupName
    
 Foreach ($vm in $vms){        
    Write-Output "Stopping $($vm.Name)";         
    Stop-AzureRmVm -Name $vm.Name -ResourceGroupName $vm.ResourceGroupName -Force;  
} 

