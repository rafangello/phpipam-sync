param(
[string]$ipAddr,
[string]$subnetId,
[string]$user
)

#==================================================
#
#.............. IPAM/DHCP SYNC ....................
#
#==================================================
$date = Get-Date
Write-Output "-----------------------------------------------------------------------------" >> C:\ipam\logdc01.txt
Write-Output "Starting..." >> C:\ipam\logdc01.txt
Write-Output $user >> C:\ipam\logdc01.txt
Write-Output $date >> C:\ipam\logdc01.txt


#-------------------------------------------
# Server.DOMINIO / Ex.: DC.yourdomain.local

$Domain = "DHCP-DEV-APP"



#Converte IP (String) para Decimal
#
function IpToDec($ip){ 
    
    [String[]] $ip_array = $ip.Split('.')

    $decimal = [Int64](([Int32])::Parse($ip_array[0])*[Math]::Pow(2,24)+
            ([Int32])::Parse($ip_array[1])*[Math]::Pow(2,16)+
            ([Int32])::Parse($ip_array[2])*[Math]::Pow(2,8)+
            ([Int32])::Parse($ip_array[3]))
    return $decimal
}



$ipAddrDec = IpToDec($ipAddr)

# Query to get IPs from IPAM database
$Query = "SELECT `ipaddresses`.ip_addr, `ipaddresses`.mac, `ipaddresses`.description, `subnets`.subnet FROM `ipaddresses` INNER JOIN `subnets` ON `ipaddresses`.subnetId = `subnets`.id WHERE `ipaddresses`.subnetId = "+ $subnetId+" AND  `ipaddresses`.ip_addr= "+ $ipAddrDec+" "

#database and credentials
$MySQLAdminUserName = 'dhcpsync' 
$MySQLAdminPassword = '********' 
$MySQLDatabase = 'phpipam' 
$MySQLHost = '192.168.1.100' 
$ConnectionString = "server=" + $MySQLHost + ";port=3306;uid=" + $MySQLAdminUserName + ";pwd=" + $MySQLAdminPassword + ";database="+$MySQLDatabase 



#---------------------------------
#Converte Binario para EndereCo IP
#
function IpFromBin($addressInBin){ 
   [string[]]$addressInInt32 = @()
   $addressInBin = $addressInBin.ToCharArray()
   for ($i = 0;$i -lt $addressInBin.length;$i++) { 
       $partAddressInBin += $addressInBin[$i]  
       if(($i+1)%8 -eq 0){ 
         $partAddressInBin = $partAddressInBin -join "" 
         $addressInInt32 += [Convert]::ToInt32($partAddressInBin -join "",2)
         $partAddressInBin = "" 
            } 
     }
    $addressInInt32 = $addressInInt32 -join "." 
    return $addressInInt32
} 
#------------------------------------

#++++++++++++++++++++++++++++++++++++
# ExecuCao da query e atualizaCao das reservas no DHCP
#------------------------------------
Try { 
 [void][System.Reflection.Assembly]::LoadWithPartialName("MySql.Data") 
  $Connection = New-Object MySql.Data.MySqlClient.MySqlConnection 
  $Connection.ConnectionString = $ConnectionString 
  $Connection.Open() 
  Write-Output "Running query..."
  $Command = New-Object MySql.Data.MySqlClient.MySqlCommand($Query, $Connection) 
  $DataAdapter = New-Object MySql.Data.MySqlClient.MySqlDataAdapter($Command) 
  $DataSet = New-Object System.Data.DataSet 
  $RecordCount = $dataAdapter.Fill($dataSet, "data") 
  $Records = $DataSet.Tables[0]
  $Records.Keys | ForEach-Object {$Records.$_}
  Write-Output $Records

  foreach ($reservation in $Records ){
    
    Write-Output "Start check..."
    
    #Setting Values
    $ip_addr = $reservation.ip_addr
    $subnet = $reservation.subnet
  
    $ip_addr= [Convert]::ToString($ip_addr,2)
    $subnet = [Convert]::ToString($subnet,2)

    $ip =  IpFromBin($ip_addr)
    $scope =  IpFromBin($subnet)

    Write-Output $scope >> C:\ipam\log.txt
    $mac = $reservation.mac
    
    $mac = [Convert]::ToString($mac)
    $mac = $mac.Replace(':',"")
    $mac = $mac.Replace('-',"")
    $description = $reservation.description

    #Check IP on DHCP
    Write-Output "Check DHCP reservations.." >> C:\ipam\log.txt
  
    $checkReservations = 'Get-DhcpServerv4Reservation -ComputerName '+ $Domain + ' -IpAddress ' + $ip 
    #Write-Output $checkReservations
    $found = Invoke-Expression $checkReservations
  
    if(-not $found){
        Write-Output "New reservation to load..." >> C:\ipam\log.txt
        Write-Output "Loading dhcp Reservation"
        Write-Output $ip >> C:\ipam\log.txt
        $add =  'Add-DhcpServerv4Reservation -ScopeId '+ $scope+ ' -IpAddress '+ $ip +' -ClientId "'+ $mac +'" -Description "'+$description+'" '
        Invoke-Expression $add | Tee-Object C:\ipam\log.txt
    }  
    
    if($found){
        Write-Output "Updating DHCP Reservation" >> C:\ipam\log.txt
        Write-Output $ip >> C:\ipam\log.txt
        $rm =  'Remove-DhcpServerv4Reservation -ComputerName '+ $Domain + ' -IpAddress '+ $ip +''
        Invoke-Expression $rm | Tee-Object C:\ipam\log.txt
        $add =  'Add-DhcpServerv4Reservation -ScopeId '+ $scope+ ' -IpAddress '+ $ip +' -ClientId "'+ $mac +'" -Description "'+$description+'" '
        Invoke-Expression $add | Tee-Object C:\ipam\log.txt
    }
  }

  Write-Output " . " >> C:\ipam\log.txt

    
  Write-Output "Finish." >> C:\ipam\log.txt

} 
Catch { 
    
    Write-Host "ERROR : $query `n$Error[0]" >> C:\ipam\log.txt
} 

Finally { 
  $Connection.Close() 
}