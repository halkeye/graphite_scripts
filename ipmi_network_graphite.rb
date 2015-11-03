#!/usr/bin/env ruby
require 'snmp'
require 'optparse'
require 'inifile'
require 'simple-graphite'

options = {
  :interval => 10,
  :config => File.dirname(__FILE__) + '/config.ini',
  :debug => false
}
OptionParser.new do |opts|
  opts.banner = "Usage: plex_graphite.rb [options] configkey"
  opts.on("-c", "--config FILE", "Filename of config file") do |config|
    options[:config] = config
  end
  opts.on("-i", "--interval INTERVAL", "sleep time") do |interval|
    options[:interval] = interval.to_i
  end
  opts.on("-d", "--[no-]debug", "Debug") do |d|
    options[:debug] = d
  end
end.parse!

ini = IniFile.load(options[:config])
config = ini["ipmi_network_graphite.rb:#{ARGV[0]}"]

g = Graphite.new({:host => ini['graphite']['host'], :port =>  ini['graphite']['port'].to_i, :type => :udp})

ifTable_columns = ["ifDescr", "ifInOctets", "ifInErrors", "ifOutOctets", "ifOutErrors"]

SNMP::Manager.open(:community => config['community'], :host => config['host']) do |manager|
  g.push_to_graphite do |graphite|
    while true do
      manager.walk(ifTable_columns) do |row|
        ifName = row[0].value
        row.each_with_index do |col, idx|
          next if idx == 0;
          str = "#{config['name']||host}.network.#{ifName}.#{ifTable_columns[idx]} #{col.value} #{g.time_now}"
          puts str if options[:debug]
          graphite.puts str
        end
      end
      sleep options[:interval]
    end
  end
end
