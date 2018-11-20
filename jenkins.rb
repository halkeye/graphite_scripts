#!/usr/bin/env ruby

require 'rubygems'
require 'faraday'
require 'faraday_curl'
require 'logger'
require 'json'
require 'simple-graphite'
require 'active_support/time'
require 'pp'

module Faraday
  class Connection
    def noproxy
      @proxy = nil
    end
  end
end

$config = JSON.parse(File.read(File.join(File.dirname(__FILE__), 'config.json')))
graphiteClient = Graphite.new({:host => $config["graphite"]["host"], :port => $config["graphite"]["port"].to_i, :type => :udp})

interval = 10; # 10 seconds

def doJenkinsRequest(url)
  logger = Logger.new(STDOUT)

  conn = Faraday.new(:url => $config["jenkins"]["url"]) do |f|
    f.noproxy
    f.basic_auth($config["jenkins"]["user"], $config["jenkins"]["pass"])
    f.request :url_encoded
    f.request :curl, logger, :warn
    f.adapter Faraday.default_adapter
  end

  response = conn.get do |req|
    req.url url
  end

  return JSON.parse(response.body)
end

jenkinsColorMap = {
  "blue" => "ok",
  "red" => "fail",
  "aborted" => "aborted",
  "yellow" => "warn",
  "disabled" => "disabled",
  "notbuilt" => "notbuilt"
}
jenkinsColorMap.keys.each do |status|
  jenkinsColorMap["#{status}_anime"] = "running"
end


while true do
  metrics = {}
  metrics.default = 0

  executorInfo = doJenkinsRequest("computer/api/json")
  queueInfo = doJenkinsRequest("queue/api/json")
  buildInfoMin = doJenkinsRequest("view/All/timeline/data?min=#{1.minute.ago.to_i*1000}&max=#{0.minute.ago.to_i*1000}")
  buildInfoHour = doJenkinsRequest("view/All/timeline/data?min=#{1.hour.ago.to_i*1000}&max=#{0.minute.ago.to_i*1000}")
  jobsInfo = doJenkinsRequest("api/json?tree=jobs[name,color,status,url]")

  metrics["jenkins.queue.size"] = queueInfo["items"].length
  metrics["jenkins.builds.started_builds_last_minute"] = buildInfoMin["events"].length
  metrics["jenkins.builds.started_builds_last_hour"] = buildInfoHour["events"].length

  metrics["jenkins.executors.total"] = executorInfo["totalExecutors"] || 0
  metrics["jenkins.executors.busy"] = executorInfo["busyExecutors"] || 0
  metrics["jenkins.executors.free"] = (executorInfo["totalExecutors"] || 0) - (executorInfo["busyExecutors"] || 0)


  nodesTotal = executorInfo["computer"] || []
  metrics["jenkins.nodes.offline"] = nodesTotal.map{ |node| node["offline"] ? 1 : 0 }.reduce(:+)
  metrics["jenkins.nodes.online"] = nodesTotal.length - metrics["jenkins.nodes.offline"]

  jobsInfo["jobs"].each do |job|
    key = jenkinsColorMap[job["color"]] || job["color"]
    jobName = job["url"].split("/").last
    metrics["jenkins.jobs.status.#{key}"] += 1
    testInfo = doJenkinsRequest("job/#{jobName}/lastBuild/api/json?tree=actions[failCount,skipCount,totalCount,urlName]")
    testInfo["actions"].each do |action|
      ["fail", "skip", "total"].each do |field|
        next unless action.has_key? "#{field}Count"
        metrics["jenkins.jobs.#{jobName}.#{field}_count"] += action["#{field}Count"].to_i
      end
    end
  end

  pp(metrics)
  if ($config["graphite"]["enabled"]) then
    graphiteClient.send_metrics(metrics)
  else
    puts metrics.inspect
  end
  sleep(interval)
end
