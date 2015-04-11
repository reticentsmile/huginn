module Agents
  class MemoryProfileAgent < Agent
    include FormConfigurable

    gem_dependency_check { RUBY_VERSION.split('.').map(&:to_i).tap { |o| o[0] >= 2 && o[1] >= 1 }.any? }

    description <<-MD
      It does emit the amount of allocated objects.

      When receiving an event it dump a JSON file of object allocations to a file in the directory configures as `object_dump_path`.

      __WARNING__: Running this agent will significantly slow down your background worker!
    MD

    def default_options
      {
        'object_dump_path' => File.join(Rails.root, 'tmp'),
      }
    end

    form_configurable :object_dump_path

    def validate_options
      errors.add(:base, "set object_dump_path to an existing direcotory") unless working?
    end

    def working?
      options[:object_dump_path] && Dir.exists?(options[:object_dump_path])
    end

    def check
      require_objspace
      ObjectSpace.trace_object_allocations_start
      create_event payload: ObjectSpace.count_objects
    end

    def receive(incoming_events)
      return unless working?
      require_objspace
      io = File.open(File.join(options[:object_dump_path], file_name), 'w')
      ObjectSpace.dump_all(output: io)
    ensure
      io.close if io
    end

    private
    def file_name
      "huginn-object-dump-#{Time.now.iso8601}.json"
    end

    def require_objspace
      require 'objspace' unless defined?(ObjectSpace.trace_object_allocations_start)
    end
  end
end
