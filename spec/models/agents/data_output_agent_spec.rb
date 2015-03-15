# encoding: utf-8

require 'spec_helper'

describe Agents::DataOutputAgent do
  let(:agent) do
    _agent = Agents::DataOutputAgent.new(name: 'My Data Output Agent')
    _agent.options = _agent.default_options.merge('secrets' => %w(secret1 secret2), 'events_to_show' => 3)
    _agent.options['template']['item']['pubDate'] = "{{date}}"
    _agent.user = users(:bob)
    _agent.sources << agents(:bob_website_agent)
    _agent.save!
    _agent
  end

  describe "#working?" do
    it "checks if events have been received within expected receive period" do
      expect(agent).not_to be_working
      Agents::DataOutputAgent.async_receive agent.id, [events(:bob_website_agent_event).id]
      expect(agent.reload).to be_working
      two_days_from_now = 2.days.from_now
      stub(Time).now { two_days_from_now }
      expect(agent.reload).not_to be_working
    end
  end

  describe "validation" do
    before do
      expect(agent).to be_valid
    end

    it "should validate presence and length of secrets" do
      agent.options[:secrets] = ""
      expect(agent).not_to be_valid
      agent.options[:secrets] = "foo"
      expect(agent).not_to be_valid
      agent.options[:secrets] = []
      expect(agent).not_to be_valid
      agent.options[:secrets] = ["hello"]
      expect(agent).to be_valid
      agent.options[:secrets] = %w(hello world)
      expect(agent).to be_valid
    end

    it "should validate presence of expected_receive_period_in_days" do
      agent.options[:expected_receive_period_in_days] = ""
      expect(agent).not_to be_valid
      agent.options[:expected_receive_period_in_days] = 0
      expect(agent).not_to be_valid
      agent.options[:expected_receive_period_in_days] = -1
      expect(agent).not_to be_valid
    end

    it "should validate presence of template and template.item" do
      agent.options[:template] = ""
      expect(agent).not_to be_valid
      agent.options[:template] = {}
      expect(agent).not_to be_valid
      agent.options[:template] = { 'item' => 'foo' }
      expect(agent).not_to be_valid
      agent.options[:template] = { 'item' => { 'title' => 'hi' } }
      expect(agent).to be_valid
    end
  end

  describe "#receive_web_request" do
    before do
      current_time = Time.now
      stub(Time).now { current_time }
      agents(:bob_website_agent).events.destroy_all
    end

    it "requires a valid secret" do
      content, status, content_type = agent.receive_web_request({ 'secret' => 'fake' }, 'get', 'text/xml')
      expect(status).to eq(401)
      expect(content).to eq("Not Authorized")

      content, status, content_type = agent.receive_web_request({ 'secret' => 'fake' }, 'get', 'application/json')
      expect(status).to eq(401)
      expect(content).to eq(error: "Not Authorized")

      content, status, content_type = agent.receive_web_request({ 'secret' => 'secret1' }, 'get', 'application/json')
      expect(status).to eq(200)
    end

    describe "returning events as RSS and JSON" do
      let!(:event1) do
        agents(:bob_website_agent).create_event payload: {
          "url" => "http://imgs.xkcd.com/comics/evolving.png",
          "title" => "Evolving",
          "hovertext" => "Biologists play reverse Pokemon, trying to avoid putting any one team member on the front lines long enough for the experience to cause evolution."
        }
      end

      let!(:event2) do
        agents(:bob_website_agent).create_event payload: {
          "url" => "http://imgs.xkcd.com/comics/evolving2.png",
          "title" => "Evolving again",
          "date" => '',
          "hovertext" => "Something else"
        }
      end

      let!(:event3) do
        agents(:bob_website_agent).create_event payload: {
          "url" => "http://imgs.xkcd.com/comics/evolving0.png",
          "title" => "Evolving yet again with a past date",
          "date" => '2014/05/05',
          "hovertext" => "Something else"
        }
      end

      it "can output RSS" do
        stub(agent).feed_link { "https://yoursite.com" }
        content, status, content_type = agent.receive_web_request({ 'secret' => 'secret1' }, 'get', 'text/xml')
        expect(status).to eq(200)
        expect(content_type).to eq('text/xml')
        expect(content.gsub(/\s+/, '')).to eq Utils.unindent(<<-XML).gsub(/\s+/, '')
          <?xml version="1.0" encoding="UTF-8" ?>
          <rss version="2.0">
          <channel>
           <title>XKCD comics as a feed</title>
           <description>This is a feed of recent XKCD comics, generated by Huginn</description>
           <link>https://yoursite.com</link>
           <lastBuildDate>#{Time.now.rfc2822}</lastBuildDate>
           <pubDate>#{Time.now.rfc2822}</pubDate>
           <ttl>60</ttl>

           <item>
            <title>Evolving yet again with a past date</title>
            <description>Secret hovertext: Something else</description>
            <link>http://imgs.xkcd.com/comics/evolving0.png</link>
            <pubDate>#{Time.zone.parse(event3.payload['date']).rfc2822}</pubDate>
            <guid>#{event3.id}</guid>
           </item>

           <item>
            <title>Evolving again</title>
            <description>Secret hovertext: Something else</description>
            <link>http://imgs.xkcd.com/comics/evolving2.png</link>
            <pubDate>#{event2.created_at.rfc2822}</pubDate>
            <guid>#{event2.id}</guid>
           </item>

           <item>
            <title>Evolving</title>
            <description>Secret hovertext: Biologists play reverse Pokemon, trying to avoid putting any one team member on the front lines long enough for the experience to cause evolution.</description>
            <link>http://imgs.xkcd.com/comics/evolving.png</link>
            <pubDate>#{event1.created_at.rfc2822}</pubDate>
            <guid>#{event1.id}</guid>
           </item>

          </channel>
          </rss>
        XML
      end

      it "can output JSON" do
        agent.options['template']['item']['foo'] = "hi"

        content, status, content_type = agent.receive_web_request({ 'secret' => 'secret2' }, 'get', 'application/json')
        expect(status).to eq(200)

        expect(content).to eq('title' => 'XKCD comics as a feed',
                              'description' => 'This is a feed of recent XKCD comics, generated by Huginn',
                              'pubDate' => Time.now,
                              'items' => [
                                {
                                  'title' => 'Evolving yet again with a past date',
                                  'description' => 'Secret hovertext: Something else',
                                  'link' => 'http://imgs.xkcd.com/comics/evolving0.png',
                                  'guid' => event3.id,
                                  'pubDate' => Time.zone.parse(event3.payload['date']).rfc2822,
                                  'foo' => 'hi'
                                },
                                {
                                  'title' => 'Evolving again',
                                  'description' => 'Secret hovertext: Something else',
                                  'link' => 'http://imgs.xkcd.com/comics/evolving2.png',
                                  'guid' => event2.id,
                                  'pubDate' => event2.created_at.rfc2822,
                                  'foo' => 'hi'
                                },
                                {
                                  'title' => 'Evolving',
                                  'description' => 'Secret hovertext: Biologists play reverse Pokemon, trying to avoid putting any one team member on the front lines long enough for the experience to cause evolution.',
                                  'link' => 'http://imgs.xkcd.com/comics/evolving.png',
                                  'guid' => event1.id,
                                  'pubDate' => event1.created_at.rfc2822,
                                  'foo' => 'hi'
                                }
                              ])
      end
    end
  end
end
