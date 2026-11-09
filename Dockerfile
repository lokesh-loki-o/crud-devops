# syntax=docker/dockerfile:1
# check=error=true

# Production image for the Rails CRUD API.
#   build stage:   full official Ruby image (compilers and MySQL headers included)
#   runtime stage: slim official Ruby image, running Puma as a non-root user

# Must match the version in .ruby-version
ARG RUBY_VERSION=3.3.10

# ---- Build stage ------------------------------------------------------------
FROM docker.io/library/ruby:$RUBY_VERSION AS build

WORKDIR /rails

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test"

# Install gems first so this layer is cached until the Gemfile changes
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile

COPY . .

# Precompile bootsnap code for faster boot, and make sure runtime dirs exist
RUN bundle exec bootsnap precompile -j 1 app/ lib/ && \
    mkdir -p log tmp/pids storage

# ---- Runtime stage ----------------------------------------------------------
FROM docker.io/library/ruby:$RUBY_VERSION-slim

WORKDIR /rails

# curl: healthchecks. libmariadb3 + client: mysql2 at runtime. jemalloc: lower memory use.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl default-mysql-client libmariadb3 libjemalloc2 libvips && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so" \
    PORT="3000"

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

USER 1000:1000

# The entrypoint prepares the database, then hands over to Puma
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
