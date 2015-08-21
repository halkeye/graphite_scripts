require 'optparse'
require 'inifile'
require 'simple-graphite'

class Base
  attr_accessor :interval
  attr_accessor :config
  attr_accessor :debug
  attr_accessor :name
  attr_accessor :username

  def initialize(args)
    {
      :interval => 10,
      :config => File.dirname(__FILE__) + '/config.ini',
      :debug => false,
      :args => ARGV
    }.merge(args).each do |k,v|
      instance_variable_set("@#{k.to_s}", v) unless v.nil?
    end
  end

  def cli_options
    return OptionParser.new do |opts|
      opts.banner = "Usage: plex_graphite.rb [options] configkey"
      opts.on("-c", "--config FILE", "Filename of config file") do |config|
        self.config = config
      end
      opts.on("-i", "--interval INTERVAL", "sleep time") do |interval|
        self.interval = interval.to_i
      end
      opts.on("-d", "--[no-]debug", "Debug") do |d|
        self.debug = d
      end
    end
  end

  def ini
    @ini ||= IniFile.load(self.config)
  end

  def parse_cli(args)
    self.cli_options().parse!(args)
  end

  def get_graphite
    return Graphite.new({
      :host => ini['graphite']['host'],
      :port => ini['graphite']['port'].to_i,
      :type => :udp
    })
  end

  def get_config(key)
    return ini["social_media:#{self.name}:#{self.username}"][key] || ini["social_media:#{self.name}"][key]
  end
end
