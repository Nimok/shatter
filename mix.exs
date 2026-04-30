defmodule Shatter.MixProject do
  use Mix.Project

  def project do
    [
      app: :shatter,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      config_path: "config/config.exs"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :mnesia],
      mod: {Shatter.Application, []}
    ]
  end

  defp deps do
    [
      {:libcluster, "~> 3.3"},
      {:bandit, "~> 1.0"},
      {:plug, "~> 1.16"},
      {:telemetry, "~> 1.0"}
    ]
  end
end
