#!/usr/bin/ruby
require 'csv'

## Configuragion

@FirstInterconnectVlan = 3999
@CountDown = true
@Devices = ['Router','Switch','Other']

@DeviceConfigs = ['','','']

CSV.open('input.csv', 'r', ';') do |row|
 p row
end