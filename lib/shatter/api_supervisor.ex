defmodule Shatter.APISupervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts), do: Supervisor.start_link(__MODULE__, :ok, opts)

  @impl true
  def init(:ok) do
    children = [
      {Bandit, plug: Shatter.API.Router, port: Application.get_env(:shatter, :http_port, 4000)}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
