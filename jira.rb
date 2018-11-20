#!/usr/bin/env ruby

require 'rubygems'
require 'faraday'
require 'faraday_curl'
require 'logger'
require 'json'
require 'simple-graphite'

module Faraday
  class Connection
    def noproxy
      @proxy = nil
    end
  end
end

$config = JSON.parse(File.read(File.join(File.dirname(__FILE__), 'config.json')))
graphiteClient = Graphite.new({:host => $config["graphite"]["host"], :port => $config["graphite"]["port"].to_i, :type => :udp})
interval = 60*10; # 10 minutes

def doRedmineRequest(url)
  logger = Logger.new(STDOUT)

  conn = Faraday.new(:url => $config["redmine"]["url"]) do |f|
    f.noproxy
    f.request :url_encoded
    f.request :curl, logger, :warn
    f.adapter Faraday.default_adapter
  end

  response = conn.get do |req|
    req.url url
    req.headers['X-Redmine-API-Key'] = $config["redmine"]["key"]
  end

  return JSON.parse(response.body)
end

def doJiraRequest(url)
  logger = Logger.new(STDOUT)

  conn = Faraday.new(:url => $config["jira"]["url"]) do |f|
    f.noproxy
    f.basic_auth($config["jira"]["user"], $config["jira"]["pass"])
    f.request :url_encoded
    f.request :curl, logger, :warn
    f.adapter Faraday.default_adapter
  end

  response = conn.get do |req|
    req.url url
  end

  return JSON.parse(response.body)
end


while true do
  metrics = {}
  metrics.default = 0

  jira = {}
  jira[:rapidViewId] = 46
  jira[:activeSprintId] = doJiraRequest("rest/greenhopper/1.0/sprintquery/#{jira[:rapidViewId]}")['sprints'].select{ |sprint| sprint["state"] == "ACTIVE" }[0]["id"]
  metrics["jira.sprint.remainingdays"] = doJiraRequest("rest/greenhopper/1.0/gadgets/sprints/remainingdays?rapidViewId=#{jira[:rapidViewId]}&sprintId=#{jira[:activeSprintId]}")["days"]

#  doJiraRequest('rest/api/2/status').each do |status|
#      status_key = status["name"].gsub(/\W+/,'').downcase()
#      metrics["jira.sprint.#{status_key}_count"] = 0
#      metrics["jira.sprint.#{status_key}_points"] = 0
#  end

  startAt = 0
  while true do
    jiraIssues = doJiraRequest("rest/api/2/search?jql=type=story and sprint=#{jira[:activeSprintId]}&startAt=#{startAt}")
    jiraIssues["issues"].each do |issue|
      story_points = issue["fields"]["customfield_10002"].to_i
      status_key = issue["fields"]["status"]["name"].gsub(/\W+/,'').downcase()

      metrics["jira.sprint.#{status_key}_count"] += 1
      metrics["jira.sprint.#{status_key}_points"] += story_points
    end
    startAt += jiraIssues["maxResults"].to_i
    break if startAt.to_i > jiraIssues["total"].to_i
  end

  begin
    jiraIssues = doJiraRequest("rest/api/2/search?fields=aggregatetimespent&jql=summary%20~%20\"Support\"%20and%20summary%20!~%20\"PAT%20support\"%20and%20sprint%20in%20openSprints()%20and%20project=TEAMMANAGE")
    metrics["jira.sprint.support_time"] = 0
    jiraIssues["issues"].each do |issue|
      metrics["jira.sprint.support_time"] += issue["fields"]["aggregatetimespent"].to_i
    end
  end

  #jiraIssues = doJiraRequest("rest/greenhopper/1.0/rapid/charts/sprintreport?rapidViewId=#{jira[:rapidViewId]}&sprintId=#{jira[:activeSprintId]}")['contents']
  #['completed', 'incompleted', 'punted'].each do |field|
  #  metrics["jira.sprint.#{field}_count"] = jiraIssues["#{field}Issues"].length
  #  metrics["jira.sprint.#{field}_points"] = jiraIssues["#{field}IssuesEstimateSum"]["value"].to_f
  #end
  #metrics['jira.sprint.added_count'] = jiraIssues["issueKeysAddedDuringSprint"].length

  redmine_issue_maps = {}
  doRedmineRequest('issue_statuses.json')['issue_statuses'].each do |status|
    redmine_issue_maps[status['id']] = status['name']
  end

  redmine_issue_maps.keys.each do |status_id|
    key = redmine_issue_maps[status_id].gsub(/\W+/,'').downcase();
    count = doRedmineRequest("issues.json?limit=1&status_id=#{status_id}")['total_count'].inspect
    metrics["redmine.issues.#{key}_count"] = count
  end
  if ($config["graphite"]["enabled"]) then
    graphiteClient.send_metrics(metrics)
  else
    puts metrics.inspect
  end
  sleep(interval)
end
