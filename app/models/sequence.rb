class Sequence < ApplicationRecord
  validates :key, presence: true, uniqueness: true
  validates :value, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Thread-safe increment and return next value
  def self.next_value(key)
    transaction do
      sequence = lock.find_by!(key: key)
      sequence.increment!(:value)
      sequence.value
    end
  rescue ActiveRecord::RecordNotFound
    raise StandardError, "Sequence '#{key}' is not defined. Add it to the sequences table in a migration."
  end

  # Initialize a sequence if it doesn't exist
  def self.ensure_exists(key, starting_value = 0)
    find_or_create_by(key: key) do |seq|
      seq.value = starting_value
    end
  end

  # Reset a sequence to a specific value
  def self.reset_to(key, value)
    transaction do
      sequence = lock.find_by!(key: key)
      sequence.update!(value: value)
    end
  end

  def display_name
    "#{key}: #{value}"
  end
end
