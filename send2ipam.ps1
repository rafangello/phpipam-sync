#==================================================
#
#....... Enviar Reservas para o IPAM ..............
#
#==================================================



#-------------------------------------------
# Server.DOMINIO / Ex.: DC.yourdomain.local

$Domain = "DHCP-DEV-APP"

#Scope(s) DHCP em decimal - Ex.: 192.168.200.0 = 3232286720 (Google: Convert ip to decimal)
$scopes = {3232286720,3232261376}

# Query to get all IPs
$Query = "SELECT `ipaddresses`.ip_addr, `ipaddresses`.mac, `ipaddresses`.description, subnets.subnet FROM `ipaddresses` INNER JOIN subnets ON `ipaddresses`.`subnetId` = subnets.id WHERE subnets.subnet IN (" + $scopes + ") "

#database and credentials
$MySQLAdminUserName = 'dhcpsync' 
$MySQLAdminPassword = '********' 
$MySQLDatabase = 'phpipam' 
$MySQLHost = '192.168.1.100' 

$ConnectionString = "server=" + $MySQLHost + ";port=3306;uid=" + $MySQLAdminUserName + ";pwd=" + $MySQLAdminPassword + ";database="+$MySQLDatabase 


#---------------------------------
#Binary to IP Address
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
#-----------
#Converte IP (String) para Decimal / SUbnet
#
function IpToDecSubnet($ip){ 
    
    [String[]] $ip_array = $ip.Split('.')

    $decimal = [Int64](([Int32])::Parse($ip_array[3])*[Math]::Pow(2,24)+
            ([Int32])::Parse($ip_array[2])*[Math]::Pow(2,16)+
            ([Int32])::Parse($ip_array[1])*[Math]::Pow(2,8)+
            ([Int32])::Parse($ip_array[0]))
    return $decimal
} 
#------------------------------------



#Check IP on DHCP
Write-Output "Check DHCP reservations.."
  
$checkReservations = 'Get-DhcpServerv4Scope -ComputerName ' + $Domain + ' | Get-DhcpServerv4Reservation -ComputerName '+ $Domain 
Write-Output $checkReservations
Invoke-Expression $checkReservations -OutVariable ondhcp

#Write-Output "Result:"
#Write-Output $ondhcp

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
  #Write-Output $Records


#++++++++++ Checking DHCP reservations  ++++++++++++++++
  Write-Output " "
  Write-Output " "
  Write-Output "Checking DHCP reservations:"
  foreach ($r_dhcp in $ondhcp){
    Write-Output " "
    $onipam = 0
    $ip1 = [Convert]::ToString($r_dhcp.IPAddress)
    
    foreach ($r_ipam in $Records ){
        $ip_addr = $r_ipam.ip_addr
        $subnet = $r_ipam.subnet
        $ip_addr= [Convert]::ToString($ip_addr,2)
        $subnet = [Convert]::ToString($subnet,2)
        $ip =  IpFromBin($ip_addr)
        $scope =  IpFromBin($subnet)
        $mac = $r_ipam.mac
        $mac = [Convert]::ToString($mac)
        $mac = $mac.Replace(':',"")           
        
        $ip2 = [Convert]::ToString($ip)
        
        if ($ip1.Equals($ip2)){
            Write-Output $ip1
             Write-Output "="
              Write-Output $ip2
            $onipam = 1
            break;
        }        
    }
    Write-Output "Scope:"
    Write-Output $scope     
    $subnet =  [IPAddress]::Parse($r_dhcp.ScopeId.Address.ToString())
    $subnetip = $subnet
    $subnet = $subnet.ToString()
    $subnet = IpToDecSubnet($subnet)
    
    $ip1dec = IpToDec($ip1)
    Write-Output $ip1dec
    
    if($onipam){
        Write-Output $ip1
        Write-Output "Found on IPAM"
        
    }else{
        $ip_addr = $ip1dec
        $mac = $r_dhcp.ClientId
        $description = $r_dhcp.Description
        $name = $r_dhcp.Name

        Write-Output $ip1
        Write-Output "Not found on IPAM"
        Try{
            $Query_subnet = "SELECT id FROM `subnets` WHERE subnets.subnet = " + $subnet + " "
           # Write-Output $Query_subnet
            Write-Output "Sending to IPAM..."
            $Command = New-Object MySql.Data.MySqlClient.MySqlCommand($Query_subnet, $Connection) 
            $DataAdapter = New-Object MySql.Data.MySqlClient.MySqlDataAdapter($Command) 
            $DataSet = New-Object System.Data.DataSet 
            $RecordCount = $dataAdapter.Fill($dataSet, "data") 
            $Records = $DataSet.Tables[0]
            $subnet = $Records[0].id
             
            $subnetcheck = $subnet.ToString()

            if(![string]::IsNullOrEmpty($subnetcheck)){
            # Write-Output $r_dhcp
                $Query_insert = "INSERT INTO `ipaddresses` (`subnetId`, `ip_addr`, `description`, `dns_name`, `mac`) VALUES("+ $subnet +", '"+ $ip_addr +"','"+ $description +"','"+ $name +"','"+ $mac +"')"
               # Write-Output $Query_insert
                $Command = New-Object MySql.Data.MySqlClient.MySqlCommand($Query_insert, $Connection) 
                $Command.ExecuteNonQuery()
                Write-Output "Saved!"               
             }
             else{
                Write-Output "Subnet:"
                Write-Output $subnetip
                #Write-Output $subnet
                Write-Output "Subnet do not exist on IPAM. Register the scope/subnet on IPAM before run this script!!"
            }
        }
        Catch{
           Write-Host "ERROR : $query `n$Error[0]"
        }
        
        #$rm =  'Remove-DhcpServerv4Reservation -ComputerName '+ $Domain + ' -IpAddress '+ $ip1 +''
        #Invoke-Expression $rm
        #Write-Output "Reservation REMOVED from DHCP."
    }
    Write-Output " "
  }


  
  Write-Output "Finish."
} 
Catch { 
    Write-Host "ERROR : $query `n$Error[0]" 
} 

Finally { 
  $Connection.Close() 
} 
