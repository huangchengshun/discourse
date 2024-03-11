# frozen_string_literal: true

class AdminNoticeSerializer < ApplicationSerializer
  attributes :message, :priority, :identifier
end
