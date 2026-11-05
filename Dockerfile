# syntax=docker/dockerfile:1
# check=error=true

# Production is the default target; --target test includes workflow test dependencies.
# Build and run a web-only instance (set SECRET_KEY_BASE in the host environment):
# docker build -t main .
# docker run --rm -p 3000:3000 --env SECRET_KEY_BASE --name main main ./bin/web

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
# Keep the base digest aligned with this version; the Renovate Ruby workflow updates both.
ARG RUBY_VERSION=4.0.9
FROM docker.io/library/ruby:$RUBY_VERSION-slim@sha256:22cfdec4c490b9e7e4913527a126ddc34bf30cf5432711f70eb1aa4b3ac388a5 AS base

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
    BUNDLE_VERSION="system" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Shared build stage for installing gems
FROM base AS build-base

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Copy dependency inputs before application source to preserve gem caches.
COPY vendor/ ./vendor/
COPY .ruby-version Gemfile Gemfile.lock ./

# Build production gems once for both output targets.
FROM build-base AS production-gems

ENV BUNDLE_WITHOUT="development:test"

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

FROM production-gems AS build

RUN bundle exec bootsnap precompile --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code cache for faster boot
RUN bundle exec bootsnap precompile app/ lib/

# Install test dependencies separately so they are ready in the published test image.
FROM production-gems AS test-build

ENV BUNDLE_WITHOUT="development:web"

RUN bundle install && \
    bundle clean --force && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

COPY . .

# Shared runtime user for production and workflow tests.
FROM base AS runtime

# Create the unprivileged runtime user; code and gems stay root-owned.
RUN groupadd --system --gid 1000 rails && \
    useradd -l rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

FROM runtime AS test

ENV RAILS_ENV="test" \
    BUNDLE_WITHOUT="development:web" \
    R3X_RUNTIME_PROFILE="workflow_cli" \
    R3X_SKIP_VAULT_ENV_LOAD="true"

COPY --from=test-build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=test-build /rails /rails

RUN chown -R rails:rails log storage tmp
USER 1000:1000

ARG GIT_CODE_VERSION=dev
ENV GIT_CODE_VERSION="${GIT_CODE_VERSION}"

# Pack-owned test scripts are supplied as arguments; no database preparation runs.
ENTRYPOINT ["bundle", "exec", "ruby"]
CMD ["--version"]

# Keep production last so an ordinary docker build still builds the app image.
FROM runtime AS production

ENV BUNDLE_WITHOUT="development:test"

# Copy built artifacts: gems, application
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

RUN chown -R rails:rails log storage tmp
USER 1000:1000

ARG GIT_CODE_VERSION=dev
ENV GIT_CODE_VERSION="${GIT_CODE_VERSION}"

# Entrypoint prepares the database for web/jobs runtime commands.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start the server by default
EXPOSE 3000
CMD ["./bin/rails", "server"]
