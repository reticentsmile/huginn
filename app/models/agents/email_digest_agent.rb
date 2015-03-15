module Agents
  class EmailDigestAgent < Agent
    include EmailConcern

    default_schedule "5am"

    cannot_create_events!

    description <<-MD
      The EmailDigestAgent collects any Events sent to it and sends them all via email when scheduled.

      By default, the will have a `subject` and an optional `headline` before listing the Events.  If the Events'
      payloads contain a `message`, that will be highlighted, otherwise everything in
      their payloads will be shown.

      You can specify one or more `recipients` for the email, or skip the option in order to send the email to your
      account's default email address.

      Set `expected_receive_period_in_days` to the maximum amount of time that you'd expect to pass between Events being received by this Agent.
    MD

    def default_options
      {
        'subject' => "You have some notifications!",
        'headline' => "Your notifications:",
        'expected_receive_period_in_days' => "2"
      }
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        memory['queue'] ||= []
        memory['queue'] << event.payload
        memory['events'] ||= []
        memory['events'] << event.id
      end
    end

    def check
      if memory['queue'] && memory['queue'].length > 0
        ids = memory['events'].join(",")
        groups = memory['queue'].map { |payload| present(payload) }
        log "Sending digest mail to #{user.email} with events [#{ids}]"
        recipients.each do |recipient|
          SystemMailer.delay.send_message(to: recipient, subject: interpolated['subject'], headline: interpolated['headline'], groups: groups)
        end
        memory['queue'] = []
        memory['events'] = []
      end
    end
  end
end
