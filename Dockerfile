# syntax=docker/dockerfile:1
# check=error=true

# Production is the default target; --target test includes workflow test dependencies.
# Build and run a web-only instance (set SECRET_KEY_BASE in the host environment):
# docker build -t main .
# docker run --rm -p 3000:3000 --env SECRET_KEY_BASE --name main main ./bin/web

# Keep both base digests aligned with this version; the Renovate Ruby workflow updates them.
# renovate: datasource=docker depName=docker.io/library/ruby versioning=docker
ARG RUBY_VERSION=4.0.9
# Shared build stage for installing gems
FROM dhi.io/ruby:$RUBY_VERSION-debian13-dev@sha256:4ddf6c1b849c4e78a8e3728243b8b00ca06c2956d312b04ae75dfc7be5bf5558 AS build-base

# Rails app lives here
WORKDIR /rails

# Install packages needed to build gems
# DHI dev supplies build tools and headers; pkg-config is needed by native gems.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y pkg-config

# Set production environment variables.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_VERSION="system"

# dprint belongs only to the local development/CI toolchain.
FROM build-base AS dev-tools
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y ca-certificates curl unzip

# Renovate updates the version; checksums come from the matching release.
# renovate: datasource=github-releases depName=dprint/dprint
ARG DPRINT_VERSION=0.64.3
ARG TARGETARCH
RUN case "$TARGETARCH" in \
      amd64) dprint_arch=x86_64 ;; \
      arm64) dprint_arch=aarch64 ;; \
      *) echo "Unsupported dprint architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac && \
    release_url="https://github.com/dprint/dprint/releases/download/${DPRINT_VERSION}" && \
    cd /tmp && \
    curl -fsSL "$release_url/SHASUMS256.txt" -o SHASUMS256.txt && \
    for arch in x86_64 aarch64; do \
      archive="dprint-${arch}-unknown-linux-gnu.zip"; \
      curl -fsSL "$release_url/$archive" -o "$archive" && \
      awk -v name="$archive" '$2 == name' SHASUMS256.txt | sha256sum -c - || exit 1; \
    done && \
    unzip -q "dprint-${dprint_arch}-unknown-linux-gnu.zip" -d /usr/local/bin && \
    rm dprint-*-unknown-linux-gnu.zip SHASUMS256.txt

FROM build-base AS dev
COPY --from=dev-tools /usr/local/bin/dprint /usr/local/bin/dprint
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y git

# Local commands use the host bundle bind and ignore checkout-local Bundler configuration.
ENV RAILS_ENV="development" \
    BUNDLE_DEPLOYMENT="false" \
    BUNDLE_AUTO_INSTALL="true" \
    BUNDLE_IGNORE_CONFIG="true" \
    BUNDLE_PATH="/bundle" \
    HOME="/tmp"
WORKDIR /
USER 1000:1000

# Build production gems once for both output targets.
FROM build-base AS production-gems

# Keep dependency inputs out of the shared dev-tools and dev image layers.
# Copy dependency inputs before application source to preserve gem caches.
COPY vendor/ ./vendor/
COPY Gemfile Gemfile.lock ./

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
FROM dhi.io/ruby:$RUBY_VERSION-debian13@sha256:d5919cd983e663c6cc4f40582bf097ff3fb2cde90d7e6baafaa919c2319251e8 AS runtime

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
    BUNDLE_AUTO_INSTALL="false" \
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
