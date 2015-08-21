#!/usr/bin/env ruby
require './social_media.rb'
require "net/http"
require 'json'

@cli = SocialMedia.new({
  :name => "github",
  :interval => 60,
})
@cli.parse_cli ARGV

username = ARGV[0]

uri = URI.parse("https://api.github.com/users/#{username}")
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

g = @cli.get_graphite
while true do
  metrics = {}
  headers = {
    "Authorization" => "token #{@cli.get_config('token')}",
    "User-Agent" => 'halkeye/graphite_scripts'
  }
  request = Net::HTTP::Get.new(uri.request_uri, headers)
  response = JSON.parse(http.request(request).body)
  ['public_repos', 'public_gists', 'following', 'followers'].each do |field|
    metrics["social.github.#{username}.#{field}"] = response[field].to_i
  end
  g.send_metrics(metrics)
  puts metrics.inspect if @cli.debug
  sleep @cli.interval
end
