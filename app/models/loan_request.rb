class LoanRequest < ActiveRecord::Base
  validates :title, :description, :amount,
    :requested_by_date, :repayment_begin_date,
    :repayment_rate, :contributed, presence: true
  has_many :orders
  has_many :loan_requests_contributors
  has_many :users, through: :loan_requests_contributors
  has_many :loan_requests_categories
  has_many :categories, through: :loan_requests_categories
  belongs_to :user
  enum status: %w(active funded)
  enum repayment_rate: %w(monthly weekly)
  before_create :assign_default_image

  def assign_default_image
    self.image_url = Rails.cache.fetch("image_url--#{id}") {DefaultImages.random}
    # self.image_url ||= DefaultImages.random
    # self.image_url = DefaultImages.random if self.image_url.to_s.empty?
  end

  def owner
    Rails.cache.fetch("username--id") {self.user.name}
  end

  def requested_by
    Rails.cache.fetch("requested--#{id}") {self.requested_by_date.strftime("%B %d, %Y")}
  end

  def updated_formatted
    Rails.cache.fetch("updated--#{id}") {self.updated_at.strftime("%B %d, %Y")}
  end

  def repayment_begin
    Rails.cache.fetch("repayment_begin--#{id}") {self.repayment_begin_date.strftime("%B %d, %Y")}
  end

  def funding_remaining
    Rails.cache.fetch("funding_remaining--#{id}") {amount - contributed}
  end

  def self.projects_with_contributions
    Rails.cache.fetch("projects_with_contributions--#{id}") {where("contributed > ?", 0)}
  end

  def list_project_contributors
    Rails.cache.fetch("list_project_contributors--#{id}") {project_contributors.map(&:name).to_sentence}
  end

  def progress_percentage
    Rails.cache.fetch("progress_percentage--#{id}") {((1.00 - (funding_remaining.to_f / amount.to_f)) * 100).to_i}
  end

  def minimum_payment
    Rails.cache.fetch("minimum_payment--#{id}") do
      if repayment_rate == "weekly"
        (contributed - repayed) / 12
      else
        (contributed - repayed) / 3
      end
    end
  end

  def repayment_due_date
    Rails.cache.fetch("repayment_due_date--#{id}") {(repayment_begin_date + 12.weeks).strftime("%B %d, %Y")}
  end

  def pay!(amount, borrower)
    repayment_percentage = (amount / contributed.to_f)
    project_contributors.each do |lender|
      repayment = lender.contributed_to(self).first.contribution * repayment_percentage
      lender.increment!(:purse, repayment)
      borrower.decrement!(:purse, repayment)
      self.increment!(:repayed, repayment)
    end
  end

  def remaining_payments
    Rails.cache.fetch("remaining_payments--#{id}") {(contributed - repayed) / minimum_payment}
  end

  def project_contributors
    Rails.cache.fetch("project_contributors--#{id}") do
      LoanRequestsContributor.where(loan_request_id: self.id).pluck(:user_id).map do |user_id|
        User.find(user_id)
      end
    end
  end

  def related_projects
    category_ids = self.categories.pluck(:id)
    LoanRequest.joins(:categories).where(categories: {id: category_ids}).where.not(id: self.id).limit(4).order("RANDOM()")
    # (categories.flat_map(&:loan_requests) - [self]).shuffle.take(4)
  end
end
