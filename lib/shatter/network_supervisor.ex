defmodule Shatter.NetworkSupervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts), do: Supervisor.start_link(__MODULE__, :ok, opts)

  @impl true
  def init(:ok) do
    port = Application.get_env(:shatter, :dhcp_port, 67)

    children = [
      Shatter.Network.HandlerRegistry,
      {Shatter.Network.HandlerSupervisor, [name: Shatter.Network.HandlerSupervisor]},
      {Shatter.Network.Listener, port: port}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
