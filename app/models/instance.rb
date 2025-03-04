# frozen_string_literal: true
# == Schema Information
#
# Table name: instances
#
#  domain         :string           primary key
#  accounts_count :bigint(8)
#

class Instance < ApplicationRecord
  self.primary_key = :domain

  attr_accessor :failure_days

  has_many :accounts, foreign_key: :domain, primary_key: :domain

  belongs_to :domain_block, foreign_key: :domain, primary_key: :domain
  belongs_to :domain_allow, foreign_key: :domain, primary_key: :domain
  belongs_to :unavailable_domain, foreign_key: :domain, primary_key: :domain # skipcq: RB-RL1031

  scope :matches_domain, ->(value) { where(arel_table[:domain].matches("%#{value}%")) }

  def self.refresh
    Scenic.database.refresh_materialized_view(table_name, concurrently: true, cascade: false)
  end

  def readonly?
    true
  end

  def delivery_failure_tracker
    @delivery_failure_tracker ||= DeliveryFailureTracker.new(domain)
  end

  def unavailable?
    unavailable_domain.present? || domain_block&.suspend?
  end

  def failing?
    failure_days.present? || unavailable?
  end

  def to_param
    domain
  end

  delegate :exhausted_deliveries_days, to: :delivery_failure_tracker

  def availability_over_days(num_days, end_date = Time.now.utc.to_date)
    failures_map    = exhausted_deliveries_days.index_with { true }
    period_end_at   = exhausted_deliveries_days.last || end_date
    period_start_at = period_end_at - num_days.days

    (period_start_at..period_end_at).map do |date|
      [date, failures_map[date]]
    end
  end
end
