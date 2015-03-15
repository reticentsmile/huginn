module InheritanceTracking
  extend ActiveSupport::Concern

  module ClassMethods
    def inherited(subclass)
      @subclasses ||= []
      @subclasses << subclass
      @subclasses.uniq!
      super
    end

    attr_reader :subclasses

    def with_subclasses(*subclasses)
      original_subclasses = @subclasses
      @subclasses = subclasses.flatten
      yield
    ensure
      @subclasses = original_subclasses
    end
  end
end
