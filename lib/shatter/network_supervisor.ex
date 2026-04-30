defmodule Shatter.NetworkSupervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts), do: Supervisor.start_link(__MODULE__, :ok, opts)

  @impl true
  def init(:ok) do
    children = [
      {Shatter.Network.Listener, []},
      {Shatter.Network.HandlerSupervisor, []}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
