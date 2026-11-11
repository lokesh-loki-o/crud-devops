# Build stage: full official Ruby image compiles the gems (mysql2 needs build tools)
FROM ruby:3.3.10 AS build
WORKDIR /rails
ENV RAILS_ENV=production BUNDLE_WITHOUT=development:test
COPY Gemfile Gemfile.lock ./
RUN bundle install
COPY . .

# Runtime stage: slim official Ruby image, Puma running as a non-root user
FROM ruby:3.3.10-slim
WORKDIR /rails
ENV RAILS_ENV=production BUNDLE_WITHOUT=development:test
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends curl libmariadb3 && \
    rm -rf /var/lib/apt/lists/*
RUN useradd --create-home --uid 1000 rails
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build --chown=rails:rails /rails /rails
USER rails
EXPOSE 3000
ENTRYPOINT ["/rails/bin/docker-entrypoint"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
