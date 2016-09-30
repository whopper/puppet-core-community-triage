require 'openssl'

module Triager
  class GitHub
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
  end
end
