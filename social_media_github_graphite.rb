#!/usr/bin/env ruby
require './social_media.rb'
require "net/http"
require 'json'

@cli = SocialMedia.new({
  :name => "github",
  :interval => 60,
})
@cli.parse_cli ARGV

uri = URI.parse("https://api.github.com/users/#{@cli.username}")
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

while true do
  metrics = {}
  headers = {
    "Authorization" => "token #{@cli.config('token')}",
    "User-Agent" => 'halkeye/graphite_scripts'
  }
  request = Net::HTTP::Get.new(uri.request_uri, headers)
  response = JSON.parse(http.request(request).body)
  ['public_repos', 'public_gists', 'following', 'followers'].each do |field|
    metrics[field] = response[field].to_i
  end
  @cli.send_to_graphite(metrics)
  sleep @cli.interval
end
