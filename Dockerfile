FROM ruby:2.7-alpine

ENV RUBY__BLOOM_SITE=/usr/local/lib/ruby/site/lib
VOLUME [${RUBY__BLOOM_SITE}]

EXPOSE 8694

RUN \
  addgroup mihono && \
  adduser -D -G mihono bourbon && \
  apk update && apk upgrade && \
  apk add git

USER bourbon

RUN \
  cd $HOME && \
  git clone https://github.com/Bloom-Jewel/site-qris-generator web && \
  cd web && \
  bundle install

COPY --chown=1000:1000 config.yml web/
WORKDIR /home/bourbon/web

# Apply RUBYOPT after.
ENV RUBYOPT="-I${RUBY__BLOOM_SITE} -rbloom-jewel/site"

CMD bundle exec ruby boot.rb

