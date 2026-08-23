# frozen_string_literal: true

module RuboCopFuzz
  # Collects Ruby files from installed gems (latest version of each)
  # and slices them into shards.
  class Corpus
    Shard = Struct.new(:name, :root, :files, keyword_init: true) do
      def relative_files
        files.map { |f| f.delete_prefix("#{root}/") }
      end
    end

    MAX_FILE_BYTES = 512 * 1024

    def initialize(gems_dir, max_files_per_shard: 50)
      @gems_dir = gems_dir
      @max_files_per_shard = max_files_per_shard
    end

    def shards
      latest_gem_dirs.flat_map { |name, dir| shards_for_gem(name, dir) }
    end

    private

    def latest_gem_dirs
      by_name = {}
      Dir.children(@gems_dir).sort.each do |entry|
        path = File.join(@gems_dir, entry)
        next unless File.directory?(path)

        name, version = split_name_version(entry)
        next unless version

        current = by_name[name]
        by_name[name] = [version, path] if current.nil? || current[0] < version
      end
      by_name.transform_values { |(_v, path)| path }
    end

    def split_name_version(entry)
      # "actionpack-8.1.2" -> ["actionpack", Gem::Version("8.1.2")]
      m = entry.match(/\A(.+)-(\d[\w.]*)\z/)
      return [entry, nil] unless m

      [m[1], Gem::Version.new(m[2])]
    rescue ArgumentError
      [entry, nil]
    end

    def shards_for_gem(name, dir)
      files = ruby_files(dir)
      return [] if files.empty?

      slices = files.each_slice(@max_files_per_shard).to_a
      slices.each_with_index.map do |slice, i|
        shard_name = slices.size == 1 ? name : "#{name}.#{i}"
        Shard.new(name: shard_name, root: dir, files: slice)
      end
    end

    def ruby_files(dir)
      Dir.glob(File.join(dir, '**', '*.rb')).sort.select do |f|
        File.file?(f) && File.size(f).between?(1, MAX_FILE_BYTES)
      end
    end
  end
end
