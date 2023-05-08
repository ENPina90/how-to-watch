class List < ApplicationRecord
  belongs_to :user
  has_many :entries, dependent: :destroy
end
