defmodule Shatter.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Shatter.Cluster,
      {Shatter.Store, name: Shatter.Store},
      {Shatter.NetworkSupervisor, name: Shatter.NetworkSupervisor},
      {Shatter.LeaseSupervisor, name: Shatter.LeaseSupervisor},
      {Shatter.APISupervisor, name: Shatter.APISupervisor}
    ]

    opts = [strategy: :one_for_one, name: Shatter.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
