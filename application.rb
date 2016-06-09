require 'sinatra'
require 'trello'
require 'json'

Trello.configure do |config|
  config.developer_public_key = ENV['PUBLIC_KEY']
  config.member_token = ENV['MEMBER_TOKEN']
end

def get_board
  @me ||= Trello::Member.find(ENV['TRELLO_USER'])
  @board ||= Trello::Board.find("5759a368ea02d5f1ca319977")
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
  @employees ||= ['herp', 'derp']
end

def get_existing_card(title, board)
  board = get_board
  existing = board.cards.detect do |card|
    card.attributes[:name] == title
  end

  existing
end

get '/' do
  "hello world, GET"
end

post '/' do
  "hello world, POST"
end

post '/payload' do
  data = JSON.parse(request.body.read)
  board = get_board
  populate_lists

  if data["action"] == "opened" || data["action"] == "reopened"
    # new PR or reopened PR: add trello card to "open Pull Requests"
    description = "#{data["pull_request"]["body"]}\n\nOpened by: #{data["pull_request"]["user"]["login"]}\nCreated: #{data["pull_request"]["created_at"]}"

    existing = get_existing_card(data["pull_request"]["title"], board)

    if !existing
      card = Trello::Card.create(
        name: data["pull_request"]["title"],
        desc: description,
        list_id: @open_pr_list.attributes[:id],
      )
    end

  elsif data["action"] == "created"
    # If non-employee commented, move card to "waiting on us"
    populate_employee_logins
    user = data["comment"]["user"]["login"]
    if data["pull_request"]
      title = data["pull_request"]["title"]
    else
      title = data["issue"]["title"]
    end

    if !@employees.include?(user)
      existing = get_existing_card(title, board)

      if existing
        existing.move_to_list(@waiting_on_us_list.attributes[:id])
      end
    end
  elsif data["action"] == "closed" # TODO: merged?
    # Closed PR. Archive trello card.
    existing = get_existing_card(data["pull_request"]["title"], board)
    existing.close! if existing
  end
end
