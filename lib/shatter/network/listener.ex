defmodule Shatter.Network.Listener do
  @moduledoc false

  use GenServer

  require Logger

  alias Shatter.DHCP.Packet
  alias Shatter.Network.{HandlerRegistry, HandlerSupervisor, RequestHandler}

  @default_port 67

  def start_link(opts) do
    {port, opts} = Keyword.pop(opts, :port, Application.get_env(:shatter, :dhcp_port, @default_port))
    {handler_sup, opts} = Keyword.pop(opts, :handler_supervisor, HandlerSupervisor)
    {handler_reg, opts} = Keyword.pop(opts, :handler_registry, HandlerRegistry)
    {handler_timeout, opts} = Keyword.pop(opts, :handler_timeout, nil)
    GenServer.start_link(__MODULE__, {port, handler_sup, handler_reg, handler_timeout}, opts)
  end

  @spec port(GenServer.server()) :: :inet.port_number()
  def port(server), do: GenServer.call(server, :port)

  @impl true
  def init({port, handler_sup, handler_reg, handler_timeout}) do
    case :gen_udp.open(port, [:binary, active: :once, broadcast: true, reuseaddr: true]) do
      {:ok, socket} ->
        {:ok, actual_port} = :inet.port(socket)
        {:ok, %{socket: socket, port: actual_port, handler_supervisor: handler_sup, handler_registry: handler_reg, handler_timeout: handler_timeout, server_ip: compute_server_ip()}}

      {:error, :eacces} ->
        Logger.error("DHCP listener: permission denied on port #{port} — run as root or set config :shatter, :dhcp_port to a port > 1024")
        {:stop, :eacces}

      {:error, :eaddrinuse} ->
        Logger.error("DHCP listener: port #{port} is already in use")
        {:stop, :eaddrinuse}

      {:error, reason} ->
        Logger.error("DHCP listener: failed to open UDP socket on port #{port}: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:port, _from, state) do
    {:reply, state.port, state}
  end

  @impl true
  def handle_info({:udp, sock, client_ip, client_port, data}, state) do
    :inet.setopts(sock, active: :once)

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
        handler_opts =
          [socket: state.socket, client: client, packet: packet,
           handler_registry: state.handler_registry, server_ip: state.server_ip] ++
            if state.handler_timeout, do: [timeout: state.handler_timeout], else: []

        case DynamicSupervisor.start_child(state.handler_supervisor, {RequestHandler, handler_opts}) do
          {:ok, _} -> :ok
          {:error, reason} -> Logger.warning("DHCP listener: failed to start handler for xid #{packet.xid}: #{inspect(reason)}")
        end

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

  defp compute_server_ip do
    case Application.get_env(:shatter, :dhcp_server_ip) do
      nil -> detect_server_ip()
      ip -> ip
    end
  end

  defp detect_server_ip do
    ip =
      case :inet.getifaddrs() do
        {:ok, addrs} ->
          addrs
          |> Enum.flat_map(fn {_name, opts} -> Keyword.get_values(opts, :addr) end)
          |> Enum.find({0, 0, 0, 0}, fn
            {127, _, _, _} -> false
            {a, b, c, d} when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) -> true
            _ -> false
          end)

        _ ->
          {0, 0, 0, 0}
      end

    if ip == {0, 0, 0, 0} do
      Logger.warning(
        "DHCP server: could not determine a non-loopback server IP for option 54. " <>
          "Set config :shatter, :dhcp_server_ip to a valid IPv4 address."
      )
    end

    ip
  end
end
