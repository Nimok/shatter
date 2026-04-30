defmodule Shatter.Network.RequestHandler do
  @moduledoc false

  use GenServer, restart: :temporary

  @default_timeout 30_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    socket = Keyword.fetch!(opts, :socket)
    client = Keyword.fetch!(opts, :client)
    packet = Keyword.fetch!(opts, :packet)
    handler_registry = Keyword.get(opts, :handler_registry, Shatter.Network.HandlerRegistry)
    timeout = Keyword.get(opts, :timeout, Application.get_env(:shatter, :dhcp_handler_timeout, @default_timeout))

    case Registry.register(handler_registry, packet.xid, :handler) do
      {:ok, _} ->
        {:ok, %{socket: socket, client: client, packet: packet, lease: nil, timeout: timeout},
         {:continue, :send_offer}}

      {:error, {:already_registered, _}} ->
        {:stop, :normal}
    end
  end

  @impl true
  def handle_continue(:send_offer, state) do
    case Shatter.Store.find_pool_for_giaddr(state.packet.giaddr) do
      {:ok, pool} ->
        case Shatter.Allocator.allocate(trim_chaddr(state.packet), pool) do
          {:ok, lease} ->
            offer = build_offer(state.packet, lease, pool)
            {client_ip, client_port} = state.client
            send_packet(state.socket, client_ip, client_port, state.packet.giaddr, Shatter.DHCP.Packet.serialize(offer))
            {:noreply, %{state | lease: lease}, state.timeout}

          {:error, reason} ->
            {:stop, reason, state}
        end

      {:error, reason} ->
        {:stop, reason, state}
    end
  end

  @impl true
  def handle_cast({:request, _packet}, %{lease: nil} = state) do
    {:noreply, state, state.timeout}
  end

  def handle_cast({:request, _request_packet}, state) do
    %{socket: socket, packet: discover, lease: lease} = state

    case Shatter.Store.find_pool_for_giaddr(discover.giaddr) do
      {:ok, pool} ->
        bound = %{lease | state: :bound}
        :ok = Shatter.Store.update_lease(bound)
        ack = build_ack(discover, bound, pool)
        {client_ip, client_port} = state.client
        send_packet(socket, client_ip, client_port, discover.giaddr, Shatter.DHCP.Packet.serialize(ack))
        {:stop, :normal, state}

      _ ->
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_info(:timeout, state) do
    {:stop, :normal, state}
  end

  # ── Private ────────────────────────────────────────────────────────────────

  defp send_packet(socket, {127, _, _, _} = client_ip, client_port, _giaddr, data),
    do: :gen_udp.send(socket, client_ip, client_port, data)

  defp send_packet(socket, _client_ip, _client_port, {0, 0, 0, 0}, data),
    do: :gen_udp.send(socket, {255, 255, 255, 255}, 68, data)

  defp send_packet(socket, _client_ip, _client_port, giaddr, data),
    do: :gen_udp.send(socket, giaddr, 67, data)

  defp trim_chaddr(%{chaddr: chaddr, hlen: hlen}), do: binary_part(chaddr, 0, hlen)

  defp build_offer(discover, lease, pool) do
    %{
      op: 2,
      htype: discover.htype,
      hlen: discover.hlen,
      hops: 0,
      xid: discover.xid,
      secs: 0,
      flags: discover.flags,
      ciaddr: {0, 0, 0, 0},
      yiaddr: lease.ip,
      siaddr: {0, 0, 0, 0},
      giaddr: discover.giaddr,
      chaddr: discover.chaddr,
      sname: "",
      file: "",
      options: [
        {53, 2},
        {1, pool.subnet_mask},
        {3, [pool.gateway]},
        {51, pool.lease_duration_seconds},
        {54, server_ip()}
      ]
    }
  end

  defp build_ack(discover, lease, pool) do
    offer = build_offer(discover, lease, pool)
    %{offer | options: List.keyreplace(offer.options, 53, 0, {53, 5})}
  end

  defp server_ip do
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
  end
end
