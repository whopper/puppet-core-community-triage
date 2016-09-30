require 'trello'

module Triager
  class Trelloer
    def initialize(github)
      Trello.configure do |config|
        config.developer_public_key = ENV['PUBLIC_KEY']
        config.member_token = ENV['MEMBER_TOKEN']
      end

      raise 'No github instance provided' unless github
      @gh = github
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
      raise 'Invalid board configuration. Are there at least 4 lists on the board?' unless board.lists.length >= 4
      @open_pr_list ||= board.lists[0]
      @waiting_on_us_list ||= board.lists[1]
      @waiting_on_contributor_list ||= board.lists[2]
      @waiting_on_deep_dive_list ||= board.lists[3]
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
      description = "#{@gh.get_pull_request_body(data)}\n\n"\
                    "Opened by: #{@gh.get_user_login(data)}\n"\
                    "Link: #{@gh.get_pull_request_url(data)}\n"\
                    "Created: #{@gh.get_pull_request_created(data)}"\

      existing = get_existing_trello_card(board, @gh.get_pull_request_url(data))
      card = nil
      if !existing
        card = Trello::Card.create(
          name: @gh.get_pull_request_title(data),
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

    def parse_open_pr(data)
      create_trello_card(@board, @open_pr_list, data)
    end

    def parse_created_pr(data)
      user = @gh.get_user_login(data)
      card = get_existing_trello_card(@board, @gh.get_pull_request_url(data))
      if card
        move_trello_card(card, @waiting_on_us_list) if (card.list_id != @open_pr_list.id && card.list_id != @waiting_on_deep_dive_list.id)
      else
        card = create_trello_card(board, @waiting_on_us_list, data)
      end

      add_comment_to_trello_card(card, "Update: New comment from #{user}: #{data["comment"]["html_url"]}")
    end

    def parse_edited_pr(data)
      user = @gh.get_user_login(data)
      existing = get_existing_trello_card(@board, @gh.get_pull_request_url(data))
      if existing
        # Note: due to a bug in ruby-trello (https://github.com/jeremytregunna/ruby-trello/issues/152), we can't
        # update the fields of a card. To work around this, we archive the old card and create a new one :(
        archive_trello_card(existing)
      end

      new_card = create_trello_card(@board, @waiting_on_us_list, data)
      add_comment_to_trello_card(new_card, "Update: Pull request title updated by #{user}")
    end

    def parse_labeled_pr(data)
      existing = get_existing_trello_card(@board, @gh.get_pull_request_url(data))
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
        create_trello_card(@board, list, data)
      end
    end

    def parse_synchronize_pr(data)
      user = @gh.get_user_login(data)

      # The PR was force pushed to
      card = get_existing_trello_card(@board, @gh.get_pull_request_url(data))
      if card
        move_trello_card(card, @waiting_on_us_list) if (card.list_id != @open_pr_list.id && card.list_id != @waiting_on_deep_dive_list.id)
      else
        card = create_trello_card(@board, @waiting_on_us_list, data)
      end

      add_comment_to_trello_card(card, "Update: force push by #{user}")
    end

    def parse_closed_pr(data)
      user = @gh.get_user_login(data)

      # Closed PR. Archive trello card.
      existing = get_existing_trello_card(@board, @gh.get_pull_request_url(data))
      if existing
        add_comment_to_trello_card(existing, "Pull request closed by #{user}")
        archive_trello_card(existing)
      end
    end
  end
end
