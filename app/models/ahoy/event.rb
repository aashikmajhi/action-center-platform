module Ahoy
  class Event < ActiveRecord::Base
    self.table_name = "ahoy_events"

    belongs_to :visit
    belongs_to :user
    belongs_to :action_page

    scope :actions,    -> { where(name: "Action") }
    scope :views,      -> { where(name: "View") }
    scope :emails,     -> { where("properties ->> 'actionType' = 'email'") }
    scope :congress_messages, -> { where("properties ->> 'actionType' = 'congress_message'") }
    scope :calls,      -> { where("properties ->> 'actionType' = 'call'") }
    scope :signatures, -> { where("properties ->> 'actionType' = 'signature'") }
    scope :tweets,     -> { where("properties ->> 'actionType' = 'tweet'") }
    scope :on_page,    -> (id) { where(action_page_id: id) }
    scope :in_range, ->(start_date, end_date) {
      where(time: start_date..end_date.tomorrow)
    }

    before_save :user_opt_out
    before_save :anonymize_views
    after_create :record_civicrm

    TYPES = %i(views emails tweets calls signatures congress_messages).freeze

    def self.action_types(action_page = nil)
      TYPES.dup.tap do |t|
        if action_page.present?
          t.delete(:calls) if !action_page.enable_call
          t.delete(:congress_messages) if !action_page.enable_congress_message
          t.delete(:emails) if !action_page.enable_email
          t.delete(:signatures) if !action_page.enable_petition
          t.delete(:tweets) if !action_page.enable_tweet
        end
      end
    end

    # Returns data, grouped by name, for displaying a chart with both
    # actions and views at the same time
    def self.chart_data
      group(:name).group_by_date
    end

    # Reformats chart data for use in tables
    # Returns the following format:
    # {
    #   "June 1 2019": {
    #     action: 10,
    #     view: 20
    #   },
    #   ...
    # }
    def self.table_data
      {}.tap do |table|
        chart_data.each do |(type, date), count|
          table[date] ||= {}
          key = type.downcase.to_sym
          table[date][key] = count
        end
      end
    end

    # Returns events grouped by date. Can be used to chart event collections
    # with only one event type
    def self.group_by_date
      group_by_day(:time, format: "%b %-e %Y").count
    end

    def self.summary
      @view_count ||= views.count
      @action_count ||= actions.count
      { view: @view_count, action: @action_count }
    end

    def user_opt_out
      if user
         user_id = nil unless user.record_activity?
      end
    end

    def record_civicrm
      if name == "Action" && user && action_page_id
        user.add_civicrm_activity! action_page_id
      end
    end

    def anonymize_views
      self.user_id = nil if name == "View"
    end
  end
end
