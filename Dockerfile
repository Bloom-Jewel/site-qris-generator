FROM ruby:2.7-alpine

ENV RUBY__BLOOM_SITE=/usr/local/lib/ruby/site/lib
VOLUME [${RUBY__BLOOM_SITE}]

EXPOSE 8694

RUN \
  addgroup mihono && \
  adduser -D -G mihono bourbon && \
  apk add --no-cache \
    git \
    imagemagick && \
  mkdir /app && chown bourbon:mihono /app

USER bourbon

RUN \
  git clone https://github.com/Bloom-Jewel/site-qris-generator /app && \
  cd /app && \
  bundle install

WORKDIR /app
COPY --chown=1000:1000 config.yml .

# Apply RUBYOPT after.
ENV RUBYOPT="-I${RUBY__BLOOM_SITE} -rbloom-jewel/site"

CMD bundle exec ruby boot.rb

