#!/usr/bin/env ruby
require './social_media.rb'
require 'oauth'
require 'json'

@cli = SocialMedia.new({
  :name     => "twitter",
  :interval => 60,
  :base_url => "https://api.twitter.com"
})
@cli.parse_cli ARGV

access_token = @cli.oauth_access_token

while true do
  response = access_token.get("/1.1/users/show.json?screen_name=#{@cli.username}")
  json_data = JSON.parse(response.body)

  data = {}
  ['followers_count', 'friends_count', 'listed_count', 'favourites_count', 'statuses_count'].each do |field|
    data[field.gsub(/_count$/, '')] = json_data[field].to_i
  end
  @cli.send_to_graphite(data)
  sleep @cli.interval
end
