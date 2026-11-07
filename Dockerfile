# syntax=docker/dockerfile:1
# check=error=true

# Production is the default target; --target test includes workflow test dependencies.
# Build and run a web-only instance (set SECRET_KEY_BASE in the host environment):
# docker build -t main .
# docker run --rm -p 3000:3000 --env SECRET_KEY_BASE --name main main ./bin/web

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
# Keep the base digest aligned with this version; the Renovate Ruby workflow updates both.
ARG RUBY_VERSION=4.0.9
# Shared build stage for installing gems
FROM dhi.io/ruby:$RUBY_VERSION-debian13-dev@sha256:5f43427dc01e1064969cf84678e9d07b5baacd716e53472c37f5210559ffaebc AS build-base

# Rails app lives here
WORKDIR /rails

# Install packages needed to build gems
# DHI dev supplies build tools and headers; pkg-config is needed by native gems.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment variables.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_VERSION="system"

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
RUN bundle exec bootsnap precompile app/ lib/ && \
    chown -R 1000:1000 log storage tmp

# Install test dependencies separately so they are ready in the published test image.
FROM production-gems AS test-build

ENV BUNDLE_WITHOUT="development:web"

RUN bundle install && \
    bundle clean --force && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

COPY . .
RUN chown -R 1000:1000 log storage tmp

# Shared runtime for production and workflow tests.
# Runtime already includes jemalloc, which Ruby uses without LD_PRELOAD.
FROM dhi.io/ruby:$RUBY_VERSION-debian13@sha256:751ff0691c1f59798f280ff66886231672dea886939dab73651141787ed269b6 AS runtime

# The runtime includes Bundler's library but not its executable.
COPY --from=build-base /usr/bin/bundle /usr/bin/bundle
# Ruby entrypoints use /usr/bin/env in their shebangs.
COPY --from=build-base /usr/bin/env /usr/bin/env
COPY --from=build-base /usr/share/zoneinfo /usr/share/zoneinfo
WORKDIR /rails
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_VERSION="system" \
    HOME="/tmp"

FROM runtime AS test

ENV RAILS_ENV="test" \
    BUNDLE_WITHOUT="development:web" \
    R3X_RUNTIME_PROFILE="workflow_cli" \
    R3X_SKIP_VAULT_ENV_LOAD="true"

COPY --from=test-build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=test-build /rails /rails

# Run unprivileged; code and gems stay root-owned.
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

USER 1000:1000

ARG GIT_CODE_VERSION=dev
ENV GIT_CODE_VERSION="${GIT_CODE_VERSION}"

# Entrypoint prepares the database for web/jobs runtime commands.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start the server by default
EXPOSE 3000
CMD ["./bin/rails", "server"]
