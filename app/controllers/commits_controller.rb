class CommitsController < ApplicationController
  TOKEN = Rails.root.join(".github-hook-token").read.chomp

  skip_forgery_protection
  before_action :validate_token

  def receive
    payload = JSON.parse(params[:payload])

    post_message build_message(payload) unless payload['commits'].empty?

    head 201
  rescue JSON::ParserError, ActiveRecord::RecordInvalid
    head 422
  end

  private

  def validate_token
    unless ActiveSupport::SecurityUtils.secure_compare params[:token], TOKEN
      redirect_to root_path
    end
  end

  def build_message payload
    branch = payload['ref'].gsub "refs/heads/", ""
    repository = payload['repository']['name']
    repository_url = payload['repository']['url']
    message_lines = []
    message_lines << "New push to **#{branch}** at [#{repository.capitalize}](#{repository_url})" << ""

    payload['commits'].reverse.each do |commit|
      first_line, *commit_lines = commit['message'].strip.split("\n")

      message_lines << "* [Commit](#{commit['url']}): #{first_line} by *#{commit['author']['name']}*"
      message_lines.concat commit_lines.map {|line| "  #{line}" }
    end

    message_lines << ""
    message_lines << "##{repository}_push ##{repository}_#{branch.gsub("/", "_")}_push"

    convert_issue_links message_lines.join("\n")
  end

  def convert_issue_links message
    message.gsub(/#(\d+)/) do |match|
      "[#{$1}](https://github.com/diaspora/diaspora/issues/#{$1})"
    end
  end

  def post_message message
    user = User.where(id: 43).first
    post = user.build_post(:status_message,
      public: true,
      text: message,
      aspect_ids: user.aspect_ids
    )
    post.save!
    user.add_to_streams(post, user.aspects)
    user.dispatch_post(post, url: short_post_url(post.guid))
  end
end
