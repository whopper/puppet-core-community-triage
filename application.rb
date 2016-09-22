require 'openssl'
require 'sinatra'
require "sinatra/config_file"
require 'trello'
require 'json'

CONFIG_PATH = ENV['CONFIG_PATH'] || 'config.yml'
config_file(CONFIG_PATH)

Trello.configure do |config|
  config.developer_public_key = ENV['PUBLIC_KEY']
  config.member_token = ENV['MEMBER_TOKEN']
end

##
# Method: get_board
# @params: None
# @returns: board, an instance of Trello::Board representing the community PR board
# Populates and cached the Trello board in the @board instance variable, and returns it
def get_board
  @me ||= Trello::Member.find(ENV['TRELLO_USER'])
  @board ||= Trello::Board.find(ENV['TRELLO_BOARD_ID'])
  @board
end

##
# Method: populate_lists
# @params: None
# @returns: None
# Populates and caches Trello lists acquired from the board
def populate_lists
  board = get_board
  @open_pr_list ||= board.lists[0]
  @waiting_on_us_list ||= board.lists[1]
  @waiting_on_contributor_list ||= board.lists[2]
  @waiting_on_deep_dive_list ||= board.lists[3]
end

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

##
# Method: get_existing_trello_card
# @params: board [Trello::Board] the board instance to use
#          pull_request_url [String] the URL of the pull request to search for on the board
# Searches a board for a specific pull request by checking for its URL in the card description
def get_existing_trello_card(board, pull_request_url)
  board = get_board
  existing = board.cards.detect do |card|
    card.attributes[:desc] =~ /#{pull_request_url}/
  end

  existing
end

##
# Method: create_trell_card
# @params: board [Trello::Board] the board instance to use
#          list [Trello::List] the list instance that the card should be placed into
#          data [Hash] the JSON blob acquired from the GitHub webhook payload
# @returns: card [Trello:Card] an object representing the Trello card which was created
# Creates a new Trello card in the specified list using the standard format
def create_trello_card(board, list, data)
  description = "#{get_pull_request_body(data)}\n\n"\
                "Opened by: #{get_user_login(data)}\n"\
                "Link: #{get_pull_request_url(data)}\n"\
                "Created: #{get_pull_request_created(data)}"\

  existing = get_existing_trello_card(board, get_pull_request_url(data))
  card = nil

  if !existing
    card = Trello::Card.create(
      name: get_pull_request_title(data),
      desc: description,
      list_id: list.attributes[:id],
    )
  end

  card
end

##
# Method: move_trello_card
# @params: card [Trello::Card] the card to be moved
#          list [Trello::List] the list which the card should be moved into
# @returns: None
# Moves the specified trello card into the specified list using the ruby_trello API
def move_trello_card(card, list)
  card.move_to_list(list.attributes[:id])
end

##
# Method: archive_trello_card
# @params: card [Trello::Card] the card to be archived
# @returns: None
# Archives the specified Trello card
def archive_trello_card(card)
  card.close!
end

##
# Method: add_comment_to_trello_card
# @params: card [Trello::Card] the card to add a comment to
#          comment [String] the text of the comment
# @returns: None
# Adds a new comment to the specified card containing the specified text
def add_comment_to_trello_card(card, comment)
  card.add_comment(comment)
end

# Method: pull_request_updated_by_employee?
# @params: user [String] the GitHub username to check
# @returns: [Bool] true if the specified user is in the employee list, false otherwise
# Checks if the specified user is considered an employee.
def pull_request_updated_by_employee?(user)
  populate_employee_logins
  @employees.include?(user) ? true : false
end

##
# Method: get_pull_request_url
# @params: data [Hash] The JSON blob acquired via the GitHub webhook payload
# @returns: URL [String] the URL of the pull request which was edited
# Gets the HTML URL of the pull request which was edited or changed in some way
def get_pull_request_url(data)
  if data["pull_request"]
    data["pull_request"]["html_url"]
  else
    data["issue"]["html_url"]
  end
end

##
# Method: get_user_login
# @params: data [Hash] The JSON blob acquired via the GitHub webhook payload
# @returns: login [String] the login of the user who send the payload
# Gets the user who sent the payload
def get_user_login(data)
  if data["sender"]["login"]
    data["sender"]["login"]
  elsif data["comment"]["user"]["login"]
    data["comment"]["user"]["login"]
  elsif data["pull_request"]
    data["pull_request"]["user"]["login"]
  else
    'Unknown User'
  end
end

def is_valid_payload?(request)
  hook_secret = ENV['GITHUB_HOOK_SECRET']
  hub_signature = request.env['HTTP_X_HUB_SIGNATURE']
  body = request.body.read
  request.body.rewind

  if hook_secret
    if hub_signature
      header_sum_type, header_hmac = hub_signature.split('=')
      digest = OpenSSL::Digest.new(header_sum_type)
      hmac = OpenSSL::HMAC.hexdigest(digest, hook_secret, body)
      hmac == header_hmac
    else
      false
    end
  else
    true
  end
end

##
# Method: get_pull_request_body
# @params: data [Hash] The JSON blob acquired via the GitHub webhook payload
# @returns: body [String] the body of the pull request which was edited
# Gets the body of the pull request which was edited or changed in some way
def get_pull_request_body(data)
  if data["pull_request"]
    data["pull_request"]["body"]
  elsif data["issue"]
    data["issue"]["body"]
  else
    'Unknown PR Contents'
  end
end

##
# Method: get_pull_request_created
# @params: data [Hash] The JSON blob acquired via the GitHub webhook payload
# @returns: time [String] the time when the pull request was created
# Gets the time when the pull request was created
def get_pull_request_created(data)
  if data["pull_request"]
    data["pull_request"]["created"]
  elsif data["issue"]
    data["issue"]["created_at"]
  else
    'Unknown Created Time'
  end
end

##
# Method: get_pull_request_created
# @params: data [Hash] The JSON blob acquired via the GitHub webhook payload
# @returns: title [String] the title of the pull request which was edited
# Gets the title of the pull request which was edited or changed in some way
def get_pull_request_title(data)
  if data["pull_request"]
    data["pull_request"]["title"]
  elsif data["issue"]
    data["issue"]["title"]
  else
    'Unknown Title'
  end
end

post '/payload' do
  unless is_valid_payload?(request)
    halt(401, 'Invalid payload')
  end

  data = JSON.parse(request.body.read)
  board = get_board
  populate_lists

  action = data["action"]
  user = get_user_login(data)

  if action == "opened" || action == "reopened"
    # New PR or reopened PR: add trello card to "open Pull Requests"
    if !pull_request_updated_by_employee?(user)
      create_trello_card(board, @open_pr_list, data)
    end
  elsif action == "created"
    # Comments: If written by non-employee, move card to "waiting on us"
    if !pull_request_updated_by_employee?(user)
      card = get_existing_trello_card(board, get_pull_request_url(data))
      if card
        move_trello_card(card, @waiting_on_us_list) if (existing.list_id != @open_pr_list.id && existing.list_id != @waiting_on_deep_dive_list.id)
      else
        card = create_trello_card(board, @waiting_on_us_list, data)
      end

      add_comment_to_trello_card(card, "Update: New comment from #{user}: #{data["comment"]["html_url"]}")
    end
  elsif action == "edited"
    # The PR was edited with a title change. Update its trello card.
    if !pull_request_updated_by_employee?(user)
      existing = get_existing_trello_card(board, get_pull_request_url(data))
      if existing
        # Note: due to a bug in ruby-trello (https://github.com/jeremytregunna/ruby-trello/issues/152), we can't
        # update the fields of a card. To work around this, we archive the old card and create a new one :(
        archive_trello_card(existing)
      end

      new_card = create_trello_card(board, @waiting_on_us_list, data)
      add_comment_to_trello_card(new_card, "Update: Pull request title updated by #{user}")
    end
  elsif action == "labeled"
      existing = get_existing_trello_card(board, get_pull_request_url(data))
      case data["label"]["name"]
      when 'Triaged', 'Merge After Unfreeze'
        list = @waiting_on_us_list
      when 'Waiting on Contributor'
        list = @waiting_on_contributor_list
      when 'Blocked'
        list = @waiting_on_deep_dive_list
      else
        list = @open_pr_list
      end

      if existing
        move_trello_card(existing, list)
      else
        create_trello_card(board, list, data)
      end
  elsif action == "synchronize"
    # The PR was force pushed to
      card = get_existing_trello_card(board, get_pull_request_url(data))
      if card
        move_trello_card(existing, @waiting_on_us_list) if (existing.list_id != @open_pr_list.id && existing.list_id != @waiting_on_deep_dive_list.id)
      else
        card = create_trello_card(board, @waiting_on_us_list, data)
      end

      add_comment_to_trello_card(card, "Update: force push by #{user}")
  elsif action == "closed" # TODO: merged?
    # Closed PR. Archive trello card.
    existing = get_existing_trello_card(board, get_pull_request_url(data))
    if existing
      add_comment_to_trello_card(existing, "Pull request closed by #{user}")
      archive_trello_card(existing)
    end
  end
end

get '/' do
  "OK"
end
