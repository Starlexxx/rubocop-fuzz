# frozen_string_literal: true

require_relative 'rubocop_fuzz/version'
require_relative 'rubocop_fuzz/corpus'
require_relative 'rubocop_fuzz/config_generator'
require_relative 'rubocop_fuzz/dependency_miner'
require_relative 'rubocop_fuzz/invoker'
require_relative 'rubocop_fuzz/detectors'
require_relative 'rubocop_fuzz/syntax_check'
require_relative 'rubocop_fuzz/pool'
require_relative 'rubocop_fuzz/scanner'
require_relative 'rubocop_fuzz/report'

module RuboCopFuzz
  class Error < StandardError; end
end
