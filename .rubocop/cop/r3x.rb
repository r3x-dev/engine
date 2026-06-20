# frozen_string_literal: true

Dir.glob(File.expand_path("r3x/**/*.rb", __dir__)).each do |file|
  require file
end
