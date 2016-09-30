require 'sinatra'
require "sinatra/config_file"
require_relative 'lib/triagertrello'
require_relative 'lib/triagergithub'
require 'json'

CONFIG_PATH = ENV['CONFIG_PATH'] || 'config.yml'
config_file(CONFIG_PATH)

##
# Method: populate_employee_logins
# @params: None
# @returns: none
# Populates and caches current core developer GitHub usernames in the @employees list
def populate_employee_logins
  if settings.employees
    @employees ||= settings.employees
  else
    @employees ||= []
  end
end

# Method: pull_request_updated_by_employee?
# @params: user [String] the GitHub username to check
# @returns: [Bool] true if the specified user is in the employee list, false otherwise
# Checks if the specified user is considered an employee.
def pull_request_updated_by_employee?(user)
  populate_employee_logins
  @employees.include?(user) ? true : false
end

post '/payload' do
  gh = Triager::GitHub.new
  unless gh.is_valid_payload?(request)
    halt(401, 'Invalid payload')
  end

  data = JSON.parse(request.body.read)
  unless data.length > 0
    halt(400, 'Malformed payload')
  end

  trello = Triager::Trelloer.new(gh)
  trello.populate_lists

  action = data["action"]
  user = gh.get_user_login(data)

  if action == "opened" || action == "reopened"
    # New PR or reopened PR: add trello card to "open Pull Requests"
    if !pull_request_updated_by_employee?(user)
      trello.parse_open_pr(data)
    end
  elsif action == "created"
    # Comments: If written by non-employee, move card to "waiting on us"
    if !pull_request_updated_by_employee?(user)
      trello.parse_created_pr(data)
    end
  elsif action == "edited"
    # The PR was edited with a title change. Update its trello card.
    if !pull_request_updated_by_employee?(user)
      trello.parse_edited_pr(data)
    end
  elsif action == "labeled"
    trello.parse_labeled_pr(data)
  elsif action == "synchronize"
    trello.parse_synchronize_pr(data)
  elsif action == "closed" # TODO: merged?
    trello.parse_closed_pr(data)
  end
end

get '/' do
  "OK"
end
