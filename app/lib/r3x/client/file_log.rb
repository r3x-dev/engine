module R3x
  module Client
    class FileLog
      DEFAULT_LIMIT = 100
      RUN_ACTIVE_JOB_TAG_PATTERN = /r3x\.run_active_job_id=[^"\s|]+/

      def initialize(path: nil)
        @path = R3x::WorkflowLog.path_for(path:)
      end

      def query(query:, start_at: nil, end_at: nil, limit: DEFAULT_LIMIT)
        run_active_job_tag = extract_run_active_job_tag(query)
        matches = []
        limit = normalized_limit(limit)

        each_log_path do |log_path|
          File.foreach(log_path) do |line|
            entry = build_entry(line, run_active_job_tag:, start_at:, end_at:)
            next if entry.nil?

            matches << entry
            matches.shift if matches.size > limit
          end
        end

        matches
      end

      private
        attr_reader :path

        def each_log_path
          paths = log_paths
          raise Errno::ENOENT, path.to_s if paths.empty?

          paths.each do |log_path|
            yield log_path
          end
        end

        def log_paths
          archive_paths + existing_active_path
        end

        def archive_paths
          return [] unless path.dirname.exist?

          path.dirname.children.filter_map do |candidate|
            archive_index = candidate.basename.to_s.delete_prefix("#{path.basename}.")
            next unless candidate.file?
            next unless candidate.basename.to_s.match?(/\A#{Regexp.escape(path.basename.to_s)}\.\d+\z/)

            [ Integer(archive_index), candidate ]
          end.sort_by { |index, _candidate| -index }
            .map(&:last)
        end

        def existing_active_path
          path.exist? ? [ path ] : []
        end

        def build_entry(line, run_active_job_tag:, start_at:, end_at:)
          stripped_line = line.strip
          return if stripped_line.blank?

          payload = MultiJson.load(stripped_line)
          return unless payload.is_a?(Hash)

          time = parse_time(payload["time"] || payload["_time"])
          return if time.nil?
          return unless includes_run?(payload, run_active_job_tag)
          return if start_at.present? && time < start_at
          return if end_at.present? && time > end_at

          {
            "_time" => time.utc.iso8601(6),
            "_msg" => stripped_line
          }
        rescue MultiJson::ParseError
          nil
        end

        def extract_run_active_job_tag(query)
          tag = query.to_s.match(RUN_ACTIVE_JOB_TAG_PATTERN)&.[](0)
          return tag if tag.present?

          raise ArgumentError, "Unsupported file log query: #{query.inspect}"
        end

        def includes_run?(payload, run_active_job_tag)
          Array(payload["tags"]).map(&:to_s).include?(run_active_job_tag) || payload["message"].to_s.include?(run_active_job_tag)
        end

        def normalized_limit(limit)
          limit.to_i.positive? ? limit.to_i : DEFAULT_LIMIT
        end

        def parse_time(value)
          return if value.blank?

          Time.zone.parse(value)
        rescue ArgumentError
          nil
        end
    end
  end
end
