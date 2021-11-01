defmodule CarpinchoMq.MixProject do
  use Mix.Project

  def project do
    [
      app: :carpincho_mq,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {App, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      { :libcluster, "~> 3.0" },
      { :horde, "~> 0.8.5" }
    ]
  end
end
