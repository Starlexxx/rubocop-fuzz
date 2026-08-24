# frozen_string_literal: true

module RuboCopFuzz
  # Finds cross-cop config dependencies by scanning cop sources for
  # `config.for_cop`, `for_enabled_cop` and `cop_enabled?` references.
  # A cluster is the referencing cop plus every cop it reads config from.
  class DependencyMiner
    REFERENCE_RE = %r{(?:for_cop|for_enabled_cop|cop_enabled\?)\(\s*['"](?<cop>[A-Z][A-Za-z]*/[A-Z][A-Za-z]*)['"]}

    def initialize(rubocop_dir)
      @rubocop_dir = rubocop_dir
    end

    def clusters
      Dir.glob(File.join(@rubocop_dir, 'lib', 'rubocop', 'cop', '*', '*.rb')).sort.filter_map do |path|
        refs = File.read(path).scan(REFERENCE_RE).flatten.uniq
        next if refs.empty?

        source = cop_name_from_path(path)
        next unless source

        ([source] + refs).uniq
      end
    end

    private

    def cop_name_from_path(path)
      department, file = path.split('/').last(2)
      return if department == 'mixin'

      cop = File.basename(file, '.rb').split('_').map(&:capitalize).join
      "#{department.split('_').map(&:capitalize).join}/#{cop}"
    end
  end
end
