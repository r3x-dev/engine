# Auto-load environment variables from .env file in development/test
# Skip silently if dotenv is not installed (production uses explicit env vars)
begin
  require "dotenv"
  Dotenv.load
rescue LoadError
  # dotenv not installed - assuming environment variables are set explicitly
end
