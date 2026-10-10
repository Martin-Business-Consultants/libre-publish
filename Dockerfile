# syntax=docker/dockerfile:1
# check=error=true

# The CMS's production image, for Kamal (config/deploy.yml) or by hand:
#   docker build -t cms .
#   docker build --secret id=CMS_PLUGINS,env=CMS_PLUGINS -t cms .   # with the install's plugins
#   docker build --secret id=CMS_THEME,env=CMS_THEME -t cms .       # with the site's theme
#   docker run -d -p 80:80 -e SECRET_KEY_BASE=… -v cms_storage:/rails/storage --name cms cms

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version. The Debian
# release is pinned with the base (CMS_BASE): the Ruby each release carries is
# built on it, so an install updating in place keeps a system it runs on.
ARG RUBY_VERSION=4.0.6
FROM docker.io/library/ruby:$RUBY_VERSION-slim-trixie AS base

# Rails app lives here
WORKDIR /rails

# Install base packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips sqlite3 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
# CMS_BASE counts changes to this stage (Ruby aside, which travels with each
# release): bump it when a release needs other system packages or a newer
# Debian, so an install updating in place (Upgrade::InPlace) redeploys instead.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so" \
    CMS_RUNTIME="docker" \
    CMS_BASE="1"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems (no Node: the admin's JavaScript is
# served through importmap with no build step)
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./
# Plugins are gems the Gemfile globs, so they're needed before bundling.
COPY engines ./engines
COPY plugins ./plugins
COPY themes ./themes

# The install's own plugins, from the CMS_PLUGINS builder secret (bin/fetch-plugins).
COPY bin/fetch-plugins ./bin/
COPY config/default_plugins.yml ./config/
RUN --mount=type=secret,id=CMS_PLUGINS,required=false bin/fetch-plugins

# The site's theme, from the CMS_THEME builder secret (bin/fetch-theme); none, and it's headless.
COPY bin/fetch-theme ./bin/
RUN --mount=type=secret,id=CMS_THEME,required=false bin/fetch-theme

# A plugin's gems aren't in the repository's Gemfile.lock, so with any
# installed the lock is resolved here (the core's gems stay at their locked
# versions) and kept aside for `COPY . .`, which would put the original back.
RUN if ls plugins/*/*.gemspec themes/*/*.gemspec 2> /dev/null | grep -q .; then BUNDLE_DEPLOYMENT=0 BUNDLE_FROZEN=0 bundle lock; fi && \
    cp Gemfile.lock /tmp/Gemfile.lock && \
    bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    bundle exec bootsnap precompile -j 1 --gemfile

# Copy application code
COPY . .
RUN cp /tmp/Gemfile.lock Gemfile.lock

# Precompile bootsnap code for faster boot times.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Precompiling assets (Propshaft digests; nothing is compiled) without
# requiring the install's secrets
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile


# The release bundle an install updates itself with (Upgrade::InPlace): the
# app as built, the default plugins included, with its gems in bundle/ and the
# Ruby they were built for in ruby/ (config/bundled_ruby.rb switches to it),
# so a new Ruby updates in place too. The release workflow exports it for
# each architecture and checks it boots on another Ruby (bin/check-bundle).
FROM scratch AS bundle
COPY --from=build /rails /
COPY --from=build /usr/local/bundle /bundle
COPY --from=build /usr/local/bin /ruby/bin
COPY --from=build /usr/local/lib /ruby/lib

# Final stage for app image
FROM base

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
USER 1000:1000

# Copy built artifacts: gems, application
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
