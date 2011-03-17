#!/usr/bin/ruby
require 'csv'
require 'erb'
require 'rubygems'
require 'netaddr'

## Configuragion

FirstCoreInterconnectVLAN = 3999
CoreInterconnectSubnet = "10.127.0.0/16"
InterconnectVLANSize = 29
CountDown = true

CoreDevices = [
  { 'Name' => 'Router02', 'Type' => 'Router', 'Interface' => 'GigabitEthernet0/0', 'Vendor' => 'Cisco' } ,
  { 'Name' => 'Switch03', 'Type' => 'Switch', 'Vendor' => 'Cisco' } ,
  { 'Name' => 'Firewall', 'Type' => 'Firewall', 'Vendor' => 'McAfee' }
]

## End Configuragion

## Dont touch anything below this

@VRFs = []

CSV.open('input.csv', 'r', ?,, ?\r) do |row|
  unless row[0] == "Description"
    @VRF = {"Description" => row[0],"Name" => row[1],"VLAN" => row[2],"OSPF" => row[3],"Networks" => row[4].split(' ') }
    @VRFs.push @VRF
  end
end

@CoreSubnets = NetAddr::CIDR.create(CoreInterconnectSubnet).subnet(:Bits => InterconnectVLANSize, :Objectify => true)

@InterconnectVLANs = []
@CurrentVLANID = FirstCoreInterconnectVLAN

# Calculate all interconnects we need and add them to the VRF
@VRFs.each do |@VRF|
  if CountDown
    @index = FirstCoreInterconnectVLAN - @CurrentVLANID
  else
    @index = @CurrentVLANID - FirstCoreInterconnectVLAN
  end
  @VRF['Interconnects'] = []
  @UnconnectedCoreDevices = CoreDevices.clone

  # Go through all the CoreDevices and connect them to all the other CoreDevices
  while @UnconnectedCoreDevices.length > 0
    @Device = @UnconnectedCoreDevices.last
    @UnconnectedCoreDevices.pop
    @UnconnectedCoreDevices.each do |@ConnectingDevice|
      @VLAN = {
       "Description" =>"#{ @VRF['Name'] } #{ @Device['Name'] } to #{ @ConnectingDevice['Name'] }",
       "CoreDevices" => [@Device,@ConnectingDevice],
       "VLAN" => @CurrentVLANID,
       "Subnet" => @CoreSubnets[@CoreSubnets.length - @index - 1],
       "VRF" => @VRF['Name']
      }
      if CountDown
        @CurrentVLANID = @CurrentVLANID - 1
        @index = FirstCoreInterconnectVLAN - @CurrentVLANID
      else
        @CurrentVLANID = @CurrentVLANID + 1
        @index = @CurrentVLANID - FirstCoreInterconnectVLAN
      end
        
      @VRF['Interconnects'].push @VLAN['Subnet']
      @InterconnectVLANs.push @VLAN
    end
  end
end

# Build the config for each device
CoreDevices.each do |@Device|
  @DeviceConfig = ""
  if (File::exists?("#{@Device['Vendor'].downcase }_#{ @Device['Type'].downcase }_config.erb"))
    puts "\n*** Start of config for #{ @Device['Name'] } ***\n\n"
  else
    puts "\n*** I don't know how to generate a config for #{@Device['Name']} ***\n"
    puts "\n*** (No #{@Device['Type'].downcase }_config.erb) ***\n\n"
  end

  # Add VRFs or Zones
  @VRFs.each do |@VRF|
    case @Device['Vendor']
    when 'Cisco'
      puts "ip vrf #{ @VRF['Name'] }\n\n"
    when 'McAfee'
      puts "cf zone add name=#{ @VRF['Name'] } modes=14\n\n"
    end
  end

  # Add all the interconnect VLANs
  @InterconnectVLANs.each do |@Interconnect|
    @interface_name = @Device['Interface']
    @vlan = @Interconnect['VLAN']
    @description = @Interconnect['Description']
    @vrf = @Interconnect['VRF']
    
    
    # Spit out config
    if (@Interconnect['CoreDevices'].index(@Device))
      device_index = @Interconnect['CoreDevices'].index(@Device).to_i + 1
      subnet = @Interconnect['Subnet']
      ip_address = NetAddr::CIDR.create(subnet.enumerate[device_index])
      @address = ip_address.ip
      @netmask = subnet.wildcard_mask

      if (File::exists?("#{@Device['Vendor'].downcase }_#{ @Device['Type'].downcase }_config.erb"))
        puts ERB.new(File.read("#{ @Device['Vendor'].downcase }_#{ @Device['Type'].downcase }_config.erb")).result
        puts "\n"
      else
        puts "! DEBUG: No file #{ @Device['Vendor'].downcase }_#{ @Device['Type'].downcase }_config.erb"
        puts "! Need to manually configure #{ @description }"
        puts "! VLAN: #{ @vlan }"
        puts "! VRF: #{ @vrf }"
        puts "! ADDRESS: #{ @address } /#{ InterconnectVLANSize }"
        puts "\n"
      end
    end
  end

  # Add Client Interface

  @VRFs.each do |@VRF|
    puts "! Need to create client interface for #{ @VRF['Description'] }\n\n"
  end

  # Create OSPF Process
  @VRFs.each do |@VRF|
    @client_id = @VRF['OSPF']
    @name = @VRF['Name']
    @client_interface = ""
    if (@Device['Vendor'] == 'Cisco')
      case @Device['Type']
      when 'Router'
        @client_interface = "#{ @Device['Interface'] }.#{ @VRF['VLAN'] }"
      when 'Switch'
        @client_interface = "Vlan#{ @VRF['VLAN'] }"
      end
      @networks = []
      @VRF['Interconnects'].each do |@Subnet|
        @network = { :address => @Subnet.ip, :netmask => @Subnet.wildcard_mask }
        @networks.push @network
      end
      @VRF['Networks'].each do |@Subnet|
        cidr = NetAddr::CIDR.create(@Subnet)
        @network = { :address => cidr.ip, :netmask => cidr.wildcard_mask }
        @networks.push @network
      end
      puts ERB.new(File.read("ospf.erb")).result

    elsif (@Device['Vendor'] == 'McAfee')
      puts "! Need to manually configure OSPF for VRF #{ @VRF['Name'] }\n\n"
    else
      puts "! Need to manually configure OSPF for VRF #{ @VRF['Name'] }\n\n"
    end
  end
end

puts "\n***The following VLANs need to be set up on the switches:\n\n"
@InterconnectVLANs.each do |@VLAN|
  puts "VLAN #{ @VLAN['VLAN'] } between #{ @VLAN['CoreDevices'][0]['Name'] } and #{ @VLAN['CoreDevices'][1]['Name'] }"
end