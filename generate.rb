#!/usr/bin/ruby
require 'csv'
require 'erb'

## Configuragion

FirstInterconnectVLAN = 3999
FirstSubnet = "10.127.255.248"
CountDown = true
InterconnectVLANSize = 29

Devices = [
 {'Name' => 'Router02', 'Type' => 'Router', 'Interface' => 'GigabitEthernet0/1', 'Vendor' => 'Cisco'},
 {'Name' => 'Switch03', 'Type' => 'Switch', 'Vendor' => 'Cisco'},
 {'Name' => 'Firewall', 'Type' => 'Other'}
]

## End Configuragion

## Dont touch anything below this

@VRFs = []

CSV.open('input.csv', 'r', ',') do |row|
 unless row[0] == "Description"
  @VRF = { "Description" => row[0],"Name" => row[1],"VLAN" => row[2],"OSPF" => row[3],"Networks" => row[4].split(' ') }
  @VRFs.push @VRF
 end
end

@CurrentVLANID = FirstInterconnectVLAN
@CurrentSubnet = FirstSubnet.clone

@InterconnectVLANs = []

# Calculate all interconnects we need and add them to the VRF
@VRFs.each do |@VRF|
 @VRF['Interconnects'] = []
 @UnconnectedDevices = Devices.clone
 
 # Go through all the devices and connect them to all the other devices
 while @UnconnectedDevices.length > 0
  @Device = @UnconnectedDevices.last
  @UnconnectedDevices.pop
  @UnconnectedDevices.each do |@ConnectingDevice|
   @VLAN = {
    "Description" => "#{@VRF['Name']} #{@Device['Name']} to #{@ConnectingDevice['Name']} ",
    "Devices" => [@Device,@ConnectingDevice],
    "VLAN" => @CurrentVLANID,
    "Subnet" => @CurrentSubnet,
    "VRF" => @VRF['Name']
   }
   if CountDown
    # Reduce the VLAN by 1 and reduce the subnet as necessary
    @CurrentVLANID = @CurrentVLANID - 1
    @SubnetData = @CurrentSubnet.split('.')
    if (@SubnetData[3] == "0")
     @SubnetData[3] = 255 - (2**(32 - InterconnectVLANSize))
     @SubnetData[2] = @SubnetData[2].to_i - 1
    else
     @SubnetData[3] = @SubnetData[3].to_i - (2**(32 - InterconnectVLANSize))
    end
    @CurrentSubnet = @SubnetData.join('.')
   else
    @CurrentVLANID = @CurrentVLANID + 1
   end
   @VRF['Interconnects'].push @VLAN['Subnet']
   @InterconnectVLANs.push @VLAN
  end
 end
end

# Build the config for each device
Devices.each do |@Device|
 @DeviceConfig = ""
 if (File::exists?("#{@Device['Type'].downcase}_config.erb"))
  puts "\n*** Start of config for #{@Device['Name']} ***\n\n"
 else
  puts "\n*** I don't know how to generate a config for #{@Device['Name']} ***\n\n"
 end
 
 
 # Add all the interconnect VLANs
 @InterconnectVLANs.each do |@Interconnect|
  @interface_name = @Device['Interface']
  @vlan = @Interconnect['VLAN']
  @description = @Interconnect['Description']
  @vrf = @Interconnect['VRF']
  @octets = @Interconnect['Subnet'].split('.')

  # Use the index to decide which IP is the first
  @octets[3] = @octets[3].to_i + 1 + @Interconnect['Devices'].index(@Device).to_i
  @address = @octets.join('.')

  # Manual Subnet Mask
  case InterconnectVLANSize
   when 29
    @netmask = "255.255.255.248"
   when 30
    @netmask = "255.255.255.252"
  end
  
  # Spit out config
  if (@Interconnect['Devices'].index(@Device))
   if (File::exists?("#{@Device['Type'].downcase}_config.erb"))
    puts ERB.new(File.read("#{@Device['Type'].downcase}_config.erb")).result
	puts "\n"
   else
    puts "Need to manually configure #{@description}"
    puts "    VLAN: #{@vlan}"
    puts "     VRF: #{@vrf}"
    puts " ADDRESS: #{@address}/#{InterconnectVLANSize}"
    puts "\n"
   end
  end
 end
 
 # Add Client Interface
 
 @VRFs.each do |@VRF|
  puts "Need to create client interface for #{@VRF['Description']}"
 end
 
 # Create OSPF Process
 @VRFs.each do |@VRF|
  if (@Device['Vendor'] == 'Cisco')
   @client_id = @VRF['OSPF']
   @name = @VRF['Name']
   @client_interface = ""
   case @Device['Type']
    when 'Router'
	 @client_interface = "#{@Device['Interface']}.#{@VRF['VLAN']}"
	when 'Switch'
	 @client_interface = "Vlan#{@VRF['VLAN']}"
   end
   @networks = []
   @VRF['Interconnects'].each do |@Subnet|
    @network = {'address' => @Subnet}
	case InterconnectVLANSize
     when 29
      @netmask = "255.255.255.248"
     when 30
      @netmask = "255.255.255.252"
	end
	@network['netmask'] = @netmask
	@networks.push @network
   end
   @VRF['Networks'].each do |@Subnet|
    @network = {'address' => @Subnet.split('/')[0]}
	case @Subnet.split('/')[1]
     when 29
      @netmask = "255.255.255.248"
     when 30
      @netmask = "255.255.255.252"
	end
	@network['netmask'] = @netmask
	@networks.push @network
   end
   puts ERB.new(File.read("ospf.erb")).result
  else
   puts "Need to manually configure OSPF for VRF #{@VRF['Name']}\n\n"
  end
 end

end