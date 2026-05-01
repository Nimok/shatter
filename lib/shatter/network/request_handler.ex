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
    server_ip = Keyword.get(opts, :server_ip, {0, 0, 0, 0})

    case Registry.register(handler_registry, packet.xid, :handler) do
      {:ok, _} ->
        {:ok,
         %{socket: socket, client: client, packet: packet, lease: nil, timeout: timeout, server_ip: server_ip},
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
            offer = build_offer(state.packet, lease, pool, state.server_ip)
            {client_ip, client_port} = state.client
            send_packet(state.socket, client_ip, client_port, state.packet.giaddr, Shatter.DHCP.Packet.serialize(offer))
            {:noreply, %{state | lease: lease}, state.timeout}

          {:error, reason} ->
            {:stop, reason, state}
        end

      {:error, _} ->
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_cast({:request, _packet}, %{lease: nil} = state) do
    {:noreply, state, state.timeout}
  end

  def handle_cast({:request, request}, state) do
    %{socket: socket, packet: discover, lease: lease} = state

    with :ok <- validate_request(request, discover, lease),
         {:ok, pool} <- Shatter.Store.find_pool_for_giaddr(discover.giaddr) do
      bound = %{lease | state: :bound}
      :ok = Shatter.Store.update_lease(bound)
      ack = build_ack(discover, bound, pool, state.server_ip)
      {client_ip, client_port} = state.client
      send_packet(socket, client_ip, client_port, discover.giaddr, Shatter.DHCP.Packet.serialize(ack))
      {:stop, :normal, state}
    else
      _ -> {:noreply, state, state.timeout}
    end
  end

  @impl true
  def handle_info(:timeout, state) do
    {:stop, :normal, state}
  end

  # ── Private ────────────────────────────────────────────────────────────────

  defp validate_request(request, discover, lease) do
    requested_ip = request.options |> List.keyfind(50, 0) |> then(fn
      {50, ip} -> ip
      nil -> request.yiaddr
    end)

    cond do
      request.chaddr != discover.chaddr -> {:error, :chaddr_mismatch}
      requested_ip != lease.ip -> {:error, :ip_mismatch}
      true -> :ok
    end
  end

  defp send_packet(socket, {127, _, _, _} = client_ip, client_port, _giaddr, data),
    do: :gen_udp.send(socket, client_ip, client_port, data)

  defp send_packet(socket, _client_ip, _client_port, {0, 0, 0, 0}, data),
    do: :gen_udp.send(socket, {255, 255, 255, 255}, 68, data)

  defp send_packet(socket, _client_ip, _client_port, giaddr, data),
    do: :gen_udp.send(socket, giaddr, 67, data)

  defp trim_chaddr(%{chaddr: chaddr, hlen: hlen}), do: binary_part(chaddr, 0, hlen)

  defp build_offer(discover, lease, pool, server_ip) do
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
        {6, pool.dns_servers},
        {51, pool.lease_duration_seconds},
        {54, server_ip}
      ]
    }
  end

  defp build_ack(discover, lease, pool, server_ip) do
    offer = build_offer(discover, lease, pool, server_ip)
    %{offer | options: List.keyreplace(offer.options, 53, 0, {53, 5})}
  end

end
