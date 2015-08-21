require 'optparse'
require 'inifile'
require 'simple-graphite'

class SocialMedia
  attr_accessor :interval
  attr_accessor :config_file
  attr_accessor :debug
  attr_accessor :name
  attr_accessor :username
  attr_accessor :base_url

  def initialize(args)
    {
      :interval => 10,
      :config_file => File.dirname(__FILE__) + '/config.ini',
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
        self.config_file = config
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
    @ini ||= IniFile.load(self.config_file)
  end

  def parse_cli(args)
    self.cli_options().parse!(args)
    self.username = ARGV[0]
  end

  def graphite
    @graphite ||= Graphite.new({
      :host => ini['graphite']['host'],
      :port => ini['graphite']['port'].to_i,
      :type => :udp
    })
  end

  def config(key)
    return ini["social_media:#{self.name}:#{self.username}"][key] || ini["social_media:#{self.name}"][key]
  end

  def oauth_access_token
    client = OAuth::Consumer.new(
      self.config('client_id'),
      self.config('client_secret'),
      {
        :site => self.base_url,
        :scheme => :header,
        :verbose => true
      }
    )

    if (!config('oauth_token'))
      request_token = client.get_request_token
      $stderr.puts "\nPlease goto #{request_token.authorize_url} to register this app\n"
      $stderr.puts
      $stderr.puts "Enter PIN: "

      puts "[" + ["social_media", self.name, self.username].reject(&:nil?).join(":") + "]";
      puts "client_id=#{self.config('client_id')}"
      puts "client_secret=#{self.config('client_secret')}"
      puts "oauth_token=#{at.params[:oauth_token]}"
      puts "oauth_token_secret=#{at.params[:oauth_token_secret]}"
      exit
    end

    return OAuth::AccessToken.new(client, self.config('oauth_token'), self.config('oauth_token_secret'))
  end

  def send_to_graphite(data)
    metrics = {}
    graphite_key = ["social", self.name, self.username].reject(&:nil?).join(".")
    data.each_pair do |key, value|
      metrics["#{graphite_key}.#{key}"] = value
    end
    puts metrics.inspect if self.debug
    graphite.send_metrics(metrics)
  end

  alias_method :get_graphite, :graphite
  alias_method :get_config, :config

end
