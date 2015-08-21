#!/usr/bin/env ruby
require 'optparse'
require 'inifile'
require 'simple-graphite'
require 'oauth'
require 'json'

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

$username = ARGV[0]
$ini = IniFile.load(options[:config])

def get_graphite
  return Graphite.new({
    :host => $ini['graphite']['host'],
    :port => $ini['graphite']['port'].to_i,
    :type => :udp
  })
end
def get_config(key)
  return $ini["social_media:twitter:#{$username}"][key] || $ini["social_media:twitter"][key]
end

client = OAuth::Consumer.new(
  get_config('client_id'),
  get_config('client_secret'),
  {
    :site => "https://api.twitter.com",
    :scheme => :header,
    :verbose => true
  }
)

if (!get_config('oauth_token'))
  request_token = c.get_request_token
  $stderr.puts "\nPlease goto #{request_token.authorize_url} to register this app\n"
  $stderr.puts
  $stderr.puts "Enter PIN: "

  puts "[social_media:twitter]"
  puts "client_id=#{get_config('client_id')}"
  puts "client_secret=#{get_config('client_secret')}"
  puts "oauth_token=#{at.params[:oauth_token]}"
  puts "oauth_token_secret=#{at.params[:oauth_token_secret]}"
  exit
end

access_token = OAuth::AccessToken.new(client, get_config('oauth_token'), get_config('oauth_token_secret'))

g = get_graphite
while true do
  response = access_token.get("/1.1/users/show.json?screen_name=#{$username}")
  json_data = JSON.parse(response.body)

  data = {}
  ['followers_count', 'friends_count', 'listed_count', 'favourites_count', 'statuses_count'].each do |field|
    data["social.twitter.#{$username}.#{field.gsub(/_count$/, '')}"] = json_data[field].to_i
  end
  g.send_metrics(data)
  sleep options[:interval]
end
