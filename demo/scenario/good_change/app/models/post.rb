# frozen_string_literal: true

class Post < ApplicationRecord
  has_many :comments

  scope :published, -> { where(published: true) }

  def label
    "post"
  end
end
