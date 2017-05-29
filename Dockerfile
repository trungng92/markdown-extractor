# To rebuild and push to docker registry:

FROM ruby:2.3

RUN  apt-get -qq update \
  && apt-get install -y git

RUN gem install kramdown

RUN mkdir /tmp/docs

CMD ["./run.sh"]