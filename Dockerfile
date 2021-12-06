FROM bitwalker/alpine-elixir

RUN mkdir /app
WORKDIR /app

COPY . .
RUN mix do deps.get, deps.compile

CMD ["mix"]