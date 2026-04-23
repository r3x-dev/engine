# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t main .
# docker run -d -p 80:80 -e SECRET_KEY_BASE=<random secret> --name main main
# docker build --target ci -t main-ci .

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=4.0.3
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y libjemalloc2 sqlite3 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Shared build stage for installing gems
FROM base AS build-base

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY vendor/ ./vendor/
COPY .ruby-version Gemfile Gemfile.lock ./

# Throw-away build stage to reduce size of final image
FROM build-base AS build

ENV BUNDLE_WITHOUT="development:test"

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    bundle exec bootsnap precompile -j 1 --gemfile

# Copy application code
COPY . .

# Precompile assets for Mission Control Jobs UI, then bootsnap for faster boot
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile && \
    bundle exec bootsnap precompile -j 1 app/ lib/

# CI image for containerized test/build checks.
# It intentionally excludes the `development` group and keeps the `test` group.
# Revisit this only if we start running development-only CI tooling inside the image:
# `debug`, `bundler-audit`, `brakeman`, `rubocop-rails-omakase`,
# `rubocop-minitest`, `rubocop-thread_safety`, `dotenv-rails`.
FROM build-base AS ci

ENV RAILS_ENV="test" \
    BUNDLE_WITHOUT="development"

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile

COPY . .

RUN bundle exec bootsnap precompile -j 1 app/ lib/

ARG GIT_CODE_VERSION=dev
ENV GIT_CODE_VERSION="${GIT_CODE_VERSION}"

# Final stage for app image
FROM base AS production

ENV BUNDLE_WITHOUT="development:test"

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
USER 1000:1000

# Copy built artifacts: gems, application
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

ARG GIT_CODE_VERSION=dev
ENV GIT_CODE_VERSION="${GIT_CODE_VERSION}"

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start the server by default
EXPOSE 3000
CMD ["./bin/rails", "server"]
