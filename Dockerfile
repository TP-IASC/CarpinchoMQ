FROM bitwalker/alpine-elixir:latest

RUN mkdir /app
WORKDIR /app

COPY . .
RUN mix do deps.get, deps.compile

CMD ["mix"]