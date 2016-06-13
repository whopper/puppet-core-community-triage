require 'sinatra'
require 'trello'
require 'json'

Trello.configure do |config|
  config.developer_public_key = ENV['PUBLIC_KEY']
  config.member_token = ENV['MEMBER_TOKEN']
end

def get_board
  @me ||= Trello::Member.find(ENV['TRELLO_USER'])
  @board ||= Trello::Board.find(ENV['TRELLO_BOARD_ID'])
  @board
end

def populate_lists
  board = get_board
  @open_pr_list ||= board.lists[0]
  @waiting_on_us_list ||= board.lists[1]
  @waiting_on_contributor_list ||= board.lists[2]
  @waiting_on_deep_dive_list ||= board.lists[3]
end

def populate_employee_logins
  @employees ||= ['whopper', 'HAIL9000', 'branan', 'Magisus', 'kylog', 'seangriff',
                  'Iristyle', 'er0ck', 'ferventcoder', 'johnduarte', 'thallgren',
                  'joshcooper', 'hlindberg', 'peterhuene', 'MikaelSmith']
end

def get_existing_trello_card(board, pull_request_url)
  board = get_board
  existing = board.cards.detect do |card|
    card.attributes[:desc] =~ /#{pull_request_url}/
  end

  existing
end

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

def move_trello_card(card, list)
  card.move_to_list(list.attributes[:id])
end

def archive_trello_card(card)
  card.close!
end

def add_comment_to_trello_card(card, comment)
  card.add_comment(comment)
end

def pull_request_updated_by_employee?(user)
  populate_employee_logins
  @employees.include?(user) ? true : false
end

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
      move_trello_card(existing, @waiting_on_us_list) if existing
      add_comment_to_trello_card(existing, "Update: New comment from #{data["comment"]["user"]["login"]}: #{data["comment"]["html_url"]}")
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
        move_trello_card(existing, @waiting_on_us_list)
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
