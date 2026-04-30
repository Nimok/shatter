defmodule Shatter.Network.IntegrationTest do
  use ExUnit.Case, async: false

  alias Shatter.Network.{HandlerSupervisor, Listener}
  alias Shatter.{DHCP.Packet, Pool, Store}

  @pool %Pool{
    id: :integration_pool,
    range_start: {10, 0, 0, 100},
    range_end: {10, 0, 0, 110},
    subnet_mask: {255, 255, 255, 0},
    gateway: {10, 0, 0, 1},
    dns_servers: [{1, 1, 1, 1}, {8, 8, 8, 8}],
    lease_duration_seconds: 86_400,
    local: true
  }

  @mac_a <<0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0x01>>
  @mac_b <<0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0x02>>

  setup do
    {:atomic, :ok} = :mnesia.clear_table(:leases)
    {:atomic, :ok} = :mnesia.clear_table(:pools)
    :ok = Store.insert_pool(@pool)

    n = System.unique_integer([:positive])
    sup_name = :"handler_sup_#{n}"
    reg_name = :"handler_reg_#{n}"

    start_supervised!({Registry, keys: :unique, name: reg_name})
    start_supervised!({HandlerSupervisor, [name: sup_name]})

    listener_pid =
      start_supervised!({Listener, port: 0, handler_supervisor: sup_name, handler_registry: reg_name})

    port = Listener.port(listener_pid)

    {:ok, sup: sup_name, reg: reg_name, port: port}
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp open_client, do: :gen_udp.open(0, [:binary, active: true]) |> elem(1)

  defp padded_chaddr(mac), do: mac <> :binary.copy(<<0>>, 16 - byte_size(mac))

  defp send_discover(client, mac, port, xid \\ nil) do
    xid = xid || :rand.uniform(0xFFFFFFFF)

    pkt =
      Packet.serialize(%{
        op: 1, htype: 1, hlen: 6, hops: 0,
        xid: xid, secs: 0, flags: 0,
        ciaddr: {0, 0, 0, 0}, yiaddr: {0, 0, 0, 0},
        siaddr: {0, 0, 0, 0}, giaddr: {0, 0, 0, 0},
        chaddr: padded_chaddr(mac),
        sname: "", file: "",
        options: [{53, 1}, {55, [1, 3, 6, 51]}]
      })

    :gen_udp.send(client, {127, 0, 0, 1}, port, pkt)
    xid
  end

  defp send_request(client, mac, xid, requested_ip, port) do
    pkt =
      Packet.serialize(%{
        op: 1, htype: 1, hlen: 6, hops: 0,
        xid: xid, secs: 0, flags: 0,
        ciaddr: {0, 0, 0, 0}, yiaddr: {0, 0, 0, 0},
        siaddr: {0, 0, 0, 0}, giaddr: {0, 0, 0, 0},
        chaddr: padded_chaddr(mac),
        sname: "", file: "",
        options: [{53, 3}, {50, requested_ip}]
      })

    :gen_udp.send(client, {127, 0, 0, 1}, port, pkt)
  end

  defp recv_packet(socket, timeout \\ 500) do
    receive do
      {:udp, ^socket, _ip, _port, data} ->
        {:ok, pkt} = Packet.parse(data)
        pkt
    after
      timeout -> flunk("no UDP packet received within #{timeout}ms")
    end
  end

  defp eventually(fun, attempts \\ 30) do
    if fun.() do
      true
    else
      if attempts > 0 do
        Process.sleep(10)
        eventually(fun, attempts - 1)
      else
        false
      end
    end
  end

  # ── DISCOVER → OFFER ───────────────────────────────────────────────────────

  test "OFFER op and message type", %{port: port} do
    client = open_client()
    send_discover(client, @mac_a, port)
    offer = recv_packet(client)

    assert offer.op == 2
    assert {53, 2} in offer.options

    :gen_udp.close(client)
  end

  test "OFFER xid echoes the DISCOVER xid", %{port: port} do
    client = open_client()
    xid = send_discover(client, @mac_a, port)
    offer = recv_packet(client)

    assert offer.xid == xid

    :gen_udp.close(client)
  end

  test "OFFER chaddr echoes the client hardware address", %{port: port} do
    client = open_client()
    send_discover(client, @mac_a, port)
    offer = recv_packet(client)

    assert binary_part(offer.chaddr, 0, 6) == @mac_a

    :gen_udp.close(client)
  end

  test "OFFER yiaddr is an IP from the pool", %{port: port} do
    client = open_client()
    send_discover(client, @mac_a, port)
    offer = recv_packet(client)

    assert offer.yiaddr in Pool.ip_range(@pool)

    :gen_udp.close(client)
  end

  test "OFFER carries correct subnet mask", %{port: port} do
    client = open_client()
    send_discover(client, @mac_a, port)
    offer = recv_packet(client)

    assert {1, @pool.subnet_mask} in offer.options

    :gen_udp.close(client)
  end

  test "OFFER carries correct gateway", %{port: port} do
    client = open_client()
    send_discover(client, @mac_a, port)
    offer = recv_packet(client)

    assert {3, [@pool.gateway]} in offer.options

    :gen_udp.close(client)
  end

  test "OFFER carries correct lease time", %{port: port} do
    client = open_client()
    send_discover(client, @mac_a, port)
    offer = recv_packet(client)

    assert {51, @pool.lease_duration_seconds} in offer.options

    :gen_udp.close(client)
  end

  test "OFFER creates a lease in :offered state in the store", %{port: port} do
    client = open_client()
    send_discover(client, @mac_a, port)
    offer = recv_packet(client)

    assert {:ok, lease} = Store.get_lease_by_ip(offer.yiaddr)
    assert lease.state == :offered
    assert lease.mac == @mac_a

    :gen_udp.close(client)
  end

  # ── DISCOVER → OFFER → REQUEST → ACK ──────────────────────────────────────

  test "ACK op and message type", %{port: port} do
    client = open_client()
    xid = send_discover(client, @mac_a, port)
    offer = recv_packet(client)
    send_request(client, @mac_a, xid, offer.yiaddr, port)
    ack = recv_packet(client)

    assert ack.op == 2
    assert {53, 5} in ack.options

    :gen_udp.close(client)
  end

  test "ACK yiaddr matches the offered IP", %{port: port} do
    client = open_client()
    xid = send_discover(client, @mac_a, port)
    offer = recv_packet(client)
    send_request(client, @mac_a, xid, offer.yiaddr, port)
    ack = recv_packet(client)

    assert ack.yiaddr == offer.yiaddr

    :gen_udp.close(client)
  end

  test "ACK xid echoes the exchange xid", %{port: port} do
    client = open_client()
    xid = send_discover(client, @mac_a, port)
    offer = recv_packet(client)
    send_request(client, @mac_a, xid, offer.yiaddr, port)
    ack = recv_packet(client)

    assert ack.xid == xid

    :gen_udp.close(client)
  end

  test "ACK transitions lease to :bound state in the store", %{port: port} do
    client = open_client()
    xid = send_discover(client, @mac_a, port)
    offer = recv_packet(client)
    send_request(client, @mac_a, xid, offer.yiaddr, port)
    _ack = recv_packet(client)

    assert {:ok, lease} = Store.get_lease_by_ip(offer.yiaddr)
    assert lease.state == :bound
    assert lease.mac == @mac_a

    :gen_udp.close(client)
  end

  test "handler terminates after ACK", %{port: port, sup: sup} do
    client = open_client()
    xid = send_discover(client, @mac_a, port)
    offer = recv_packet(client)
    send_request(client, @mac_a, xid, offer.yiaddr, port)
    _ack = recv_packet(client)

    assert eventually(fn -> DynamicSupervisor.count_children(sup).active == 0 end)

    :gen_udp.close(client)
  end

  # ── Concurrent exchanges ───────────────────────────────────────────────────

  test "two concurrent clients receive different IPs", %{port: port} do
    client_a = open_client()
    client_b = open_client()

    send_discover(client_a, @mac_a, port)
    send_discover(client_b, @mac_b, port)

    offer_a = recv_packet(client_a)
    offer_b = recv_packet(client_b)

    assert offer_a.yiaddr != offer_b.yiaddr
    assert offer_a.yiaddr in Pool.ip_range(@pool)
    assert offer_b.yiaddr in Pool.ip_range(@pool)

    :gen_udp.close(client_a)
    :gen_udp.close(client_b)
  end

  test "two clients can complete full exchanges concurrently without interference", %{port: port} do
    client_a = open_client()
    client_b = open_client()

    xid_a = send_discover(client_a, @mac_a, port)
    xid_b = send_discover(client_b, @mac_b, port)

    offer_a = recv_packet(client_a)
    offer_b = recv_packet(client_b)

    send_request(client_a, @mac_a, xid_a, offer_a.yiaddr, port)
    send_request(client_b, @mac_b, xid_b, offer_b.yiaddr, port)

    ack_a = recv_packet(client_a)
    ack_b = recv_packet(client_b)

    assert ack_a.yiaddr == offer_a.yiaddr
    assert ack_b.yiaddr == offer_b.yiaddr
    assert ack_a.yiaddr != ack_b.yiaddr

    assert {:ok, lease_a} = Store.get_lease_by_ip(offer_a.yiaddr)
    assert {:ok, lease_b} = Store.get_lease_by_ip(offer_b.yiaddr)
    assert lease_a.state == :bound
    assert lease_b.state == :bound

    :gen_udp.close(client_a)
    :gen_udp.close(client_b)
  end

  test "a second DISCOVER from the same MAC returns the same IP", %{port: port} do
    client = open_client()

    send_discover(client, @mac_a, port)
    offer1 = recv_packet(client)

    send_discover(client, @mac_a, port)
    offer2 = recv_packet(client)

    assert offer1.yiaddr == offer2.yiaddr

    :gen_udp.close(client)
  end

  # ── Robustness ─────────────────────────────────────────────────────────────

  test "malformed packet is ignored and listener keeps running", %{port: port} do
    client = open_client()
    :gen_udp.send(client, {127, 0, 0, 1}, port, <<0, 1, 2, 3>>)

    Process.sleep(50)

    xid = send_discover(client, @mac_a, port)
    offer = recv_packet(client)

    assert offer.xid == xid

    :gen_udp.close(client)
  end

  test "a crash in one handler does not affect another in-flight exchange", %{sup: sup, reg: reg} do
    # Start a dedicated listener with a long handler timeout so handler_a is
    # guaranteed to still be alive when we locate and kill it.
    listener_pid =
      start_supervised!(
        {Listener,
         port: 0,
         handler_supervisor: sup,
         handler_registry: reg,
         handler_timeout: 5_000},
        id: :crash_test_listener
      )

    port = Listener.port(listener_pid)

    client_a = open_client()
    client_b = open_client()

    send_discover(client_a, @mac_a, port)
    _offer_a = recv_packet(client_a)

    xid_b = send_discover(client_b, @mac_b, port)
    offer_b = recv_packet(client_b)

    # Poll until both handlers are alive — offer_a receipt only guarantees
    # handler_a ran handle_continue, not that handler_b is also up yet.
    handler_a_pid =
      Enum.reduce_while(1..30, nil, fn _, _ ->
        pids =
          DynamicSupervisor.which_children(sup)
          |> Enum.map(fn {_, pid, _, _} -> pid end)
          |> Enum.filter(&Process.alive?/1)

        if length(pids) >= 2 do
          {:halt, hd(pids)}
        else
          Process.sleep(10)
          {:cont, nil}
        end
      end)

    assert is_pid(handler_a_pid), "handler_a was not found alive before kill"

    Process.exit(handler_a_pid, :kill)

    send_request(client_b, @mac_b, xid_b, offer_b.yiaddr, port)
    ack_b = recv_packet(client_b)

    assert ack_b.yiaddr == offer_b.yiaddr
    assert {53, 5} in ack_b.options

    :gen_udp.close(client_a)
    :gen_udp.close(client_b)
  end
end
