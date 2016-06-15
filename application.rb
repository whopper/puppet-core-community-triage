require 'sinatra'
require 'trello'
require 'json'

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
  @employees ||= ['whopper', 'HAIL9000', 'branan', 'Magisus', 'kylog', 'seangriff',
                  'Iristyle', 'er0ck', 'ferventcoder', 'johnduarte', 'thallgren',
                  'joshcooper', 'hlindberg', 'peterhuene', 'MikaelSmith',
                  'puppetcla']
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
  description = "#{data["pull_request"]["body"]}\n\n"\
                "Opened by: #{data["pull_request"]["user"]["login"]}\n"\
                "Link: #{data["pull_request"]["html_url"]}\n"\
                "Created: #{data["pull_request"]["created_at"]}"\

  existing = get_existing_trello_card(board, data["pull_request"]["html_url"])
  card = nil

  if !existing
    card = Trello::Card.create(
      name: data["pull_request"]["title"],
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

post '/payload' do
  data = JSON.parse(request.body.read)
  board = get_board
  populate_lists

  action = data["action"]
  if action == "opened" || action == "reopened"
    # New PR or reopened PR: add trello card to "open Pull Requests"
    if !pull_request_updated_by_employee?(data["pull_request"]["user"]["login"])
      create_trello_card(board, @open_pr_list, data)
    end
  elsif action == "created"
    # Comments: If written by non-employee, move card to "waiting on us"
    if !pull_request_updated_by_employee?(data["comment"]["user"]["login"])
      existing = get_existing_trello_card(board, get_pull_request_url(data))
      if existing
        move_trello_card(existing, @waiting_on_us_list) if (existing.list_id != @open_pr_list.id && existing.list_id != @waiting_on_deep_dive_list.id)
        add_comment_to_trello_card(existing, "Update: New comment from #{data["comment"]["user"]["login"]}: #{data["comment"]["html_url"]}")
      end
    end
  elsif action == "edited"
    # The PR was edited with a title change. Update its trello card.
    if !pull_request_updated_by_employee?(data["comment"]["user"]["login"])
      existing = get_existing_trello_card(board, get_pull_request_url(data))
      if existing
        # Note: due to a bug in ruby-trello (https://github.com/jeremytregunna/ruby-trello/issues/152), we can't
        # update the fields of a card. To work around this, we archive the old card and create a new one :(
        archive_trello_card(existing)
        new_card = create_trello_card(board, @waiting_on_us_list, data)
        add_comment_to_trello_card(new_card, "Update: Pull request title updated by #{data["pull_request"]["user"]["login"]}")
      end
    end
  elsif action == "labeled"
      existing = get_existing_trello_card(board, get_pull_request_url(data))
      if existing
        case data["label"]["name"]
        when 'Triaged', 'Merge After Unfreeze'
          move_trello_card(existing, @waiting_on_us_list)
        when 'Waiting on Contributor'
          move_trello_card(existing, @waiting_on_contributor_list)
        when 'Blocked'
          move_trello_card(existing, @waiting_on_deep_dive_list)
        end
      end
  elsif action == "synchronize"
    # The PR was force pushed to
      existing = get_existing_trello_card(board, get_pull_request_url(data))
      if existing
        move_trello_card(existing, @waiting_on_us_list) if (existing.list_id != @open_pr_list.id && existing.list_id != @waiting_on_deep_dive_list.id)
        add_comment_to_trello_card(existing, "Update: force push by #{data["pull_request"]["user"]["login"]}")
      end
  elsif action == "closed" # TODO: merged?
    # Closed PR. Archive trello card.
    existing = get_existing_trello_card(board, get_pull_request_url(data))
    if existing
      add_comment_to_trello_card(existing, "Pull request closed by #{data["pull_request"]["user"]["login"]}")
      archive_trello_card(existing)
    end
  end
end
