# spec/app_spec.rb
require 'spec_helper.rb'

describe "PR Triager Sinatra App Endpoints" do
  before(:each) do
    stub_env({
      'TRELLO_USER' => 'clippy6',
      # If you need to update the VCR cassettes, add the token back in here.
      'MEMBER_TOKEN' => ENV['MEMBER_TOKEN'] || 'MEMBER_TOKEN',
      'PUBLIC_KEY' => 'd370f9906b4243eed0ed979b6ddb065f',
      'TRELLO_BOARD_ID' => '57ed940eec8df927ab3ca130',
    })
  end

  it "should return OK on GET for healthchecks" do
    get '/'
    # Rspec 2.x
    expect(last_response).to be_ok
  end

  context "posting with no payload" do
    let(:params) { {}.to_json }
    before do
      post '/payload', params
    end

    it "should be a bad request" do
      expect(last_response).to be_bad_request
    end
  end

  context "posting with github secret enabled" do
    before(:each) do
      stub_env('GITHUB_HOOK_SECRET', 'notsecret')
    end

    context "no github secret in payload" do
      let(:params) { {}.to_json }
      before do
        post '/payload', params
      end

      it "should be unauthorized" do
        expect(last_response).to be_unauthorized
      end
    end

    context "invalid github secret in payload" do
      let(:rack_env) { {'HTTP_X_HUB_SIGNATURE' => 'md5=notadigest'} }
      let(:params) { {}.to_json }
      before do
        post '/payload', params, rack_env
      end

      it "should be unauthorized" do
        expect(last_response).to be_unauthorized
      end
    end

    context "valid github secret in payload" do
      let(:rack_env) { {'HTTP_X_HUB_SIGNATURE' => 'md5=52f6cd3e5bd10a00ff5e06c7598538a0'} }
      let(:params) { {}.to_json }
      before do
        post '/payload', params, rack_env
      end

      it "should be a bad request" do
        expect(last_response).to be_bad_request
      end
    end
  end

  # https://developer.github.com/v3/activity/events/types/#pullrequestevent
  context "post valid opened payload", vcr: { cassette_name: 'trello/opened' } do
    before do
      json = File.read("fixtures/payloads/pr_opened.json")
      post '/payload', json, 'CONTENT_TYPE' => 'application/json'
    end

    it "should be ok" do
      expect(last_response).to be_ok
    end
  end

  # https://developer.github.com/v3/activity/events/types/#pullrequestreviewcommentevent
  context "post valid created payload", vcr: { cassette_name: 'trello/created' } do
    before do
      json = File.read("fixtures/payloads/pr_created.json")
      post '/payload', json, 'CONTENT_TYPE' => 'application/json'
    end

    it "should be ok" do
      expect(last_response).to be_ok
    end
  end

  # https://developer.github.com/v3/activity/events/types/#pullrequestevent
  context "post valid edited payload", vcr: { cassette_name: 'trello/edited' } do
    before do
      json = File.read("fixtures/payloads/pr_edited.json")
      post '/payload', json, 'CONTENT_TYPE' => 'application/json'
    end

    it "should be ok" do
      expect(last_response).to be_ok
    end
  end

  # https://developer.github.com/v3/activity/events/types/#pullrequestevent
  context "post valid labeled payload", vcr: { cassette_name: 'trello/labeled' } do
    before do
      json = File.read("fixtures/payloads/pr_labeled.json")
      post '/payload', json, 'CONTENT_TYPE' => 'application/json'
    end

    it "should be ok" do
      expect(last_response).to be_ok
    end
  end

  # https://developer.github.com/v3/activity/events/types/#pullrequestevent
  context "post valid synchronize payload", vcr: { cassette_name: 'trello/synchronize' } do
    before do
      json = File.read("fixtures/payloads/pr_synchronize.json")
      post '/payload', json, 'CONTENT_TYPE' => 'application/json'
    end

    it "should be ok" do
      expect(last_response).to be_ok
    end
  end

  # https://developer.github.com/v3/activity/events/types/#pullrequestevent
  context "post valid closed payload", vcr: { cassette_name: 'trello/closed' } do
    before do
      json = File.read("fixtures/payloads/pr_closed.json")
      post '/payload', json, 'CONTENT_TYPE' => 'application/json'
    end

    it "should be ok" do
      expect(last_response).to be_ok
    end
  end
end
