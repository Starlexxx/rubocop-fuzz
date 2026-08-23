# frozen_string_literal: true

require_relative 'lib/rubocop_fuzz/version'

Gem::Specification.new do |spec|
  spec.name = 'rubocop-fuzz'
  spec.version = RuboCopFuzz::VERSION
  spec.authors = ['Starlexxx']
  spec.summary = 'Config-fuzzing regression harness for RuboCop'
  spec.description = 'Finds cop crashes, infinite correction loops and broken ' \
                     'autocorrects in RuboCop by running it over a real-world ' \
                     'corpus with generated config variants.'
  spec.homepage = 'https://github.com/Starlexxx/rubocop-fuzz'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1'

  spec.files = Dir['lib/**/*.rb', 'exe/*', 'README.md', 'LICENSE.txt']
  spec.bindir = 'exe'
  spec.executables = ['rubocop-fuzz']
  spec.require_paths = ['lib']

  spec.metadata['rubygems_mfa_required'] = 'true'
end
