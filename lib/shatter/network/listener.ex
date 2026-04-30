defmodule Shatter.Network.Listener do
  @moduledoc false

  use GenServer

  alias Shatter.DHCP.Packet
  alias Shatter.Network.{HandlerRegistry, HandlerSupervisor, RequestHandler}

  @default_port 67

  def start_link(opts) do
    {port, opts} = Keyword.pop(opts, :port, Application.get_env(:shatter, :dhcp_port, @default_port))
    {handler_sup, opts} = Keyword.pop(opts, :handler_supervisor, HandlerSupervisor)
    {handler_reg, opts} = Keyword.pop(opts, :handler_registry, HandlerRegistry)
    GenServer.start_link(__MODULE__, {port, handler_sup, handler_reg}, opts)
  end

  @spec port(GenServer.server()) :: :inet.port_number()
  def port(server), do: GenServer.call(server, :port)

  @impl true
  def init({port, handler_sup, handler_reg}) do
    {:ok, socket} = :gen_udp.open(port, [:binary, active: true, broadcast: true, reuseaddr: true])
    {:ok, %{socket: socket, port: port, handler_supervisor: handler_sup, handler_registry: handler_reg}}
  end

  @impl true
  def handle_call(:port, _from, state) do
    {:reply, state.port, state}
  end

  @impl true
  def handle_info({:udp, _sock, client_ip, client_port, data}, state) do
    case Packet.parse(data) do
      {:ok, packet} -> dispatch(packet, {client_ip, client_port}, state)
      {:error, _} -> :ok
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Private ────────────────────────────────────────────────────────────────

  defp dispatch(packet, client, state) do
    case message_type(packet) do
      1 ->
        DynamicSupervisor.start_child(
          state.handler_supervisor,
          {RequestHandler,
           [
             socket: state.socket,
             client: client,
             packet: packet,
             handler_registry: state.handler_registry
           ]}
        )

      3 ->
        case Registry.lookup(state.handler_registry, packet.xid) do
          [{pid, _}] -> GenServer.cast(pid, {:request, packet})
          [] -> :ok
        end

      _ ->
        :ok
    end
  end

  defp message_type(%{options: options}) do
    case List.keyfind(options, 53, 0) do
      {53, type} -> type
      nil -> nil
    end
  end
end
