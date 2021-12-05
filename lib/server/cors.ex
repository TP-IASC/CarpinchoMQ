defmodule CORS do
  use Corsica.Router,
  origins: ["http://localhost:3333"],
  allow_credentials: true,
  max_age: 600

  resource "/public/*", origins: "*"
  resource "/*"
end
