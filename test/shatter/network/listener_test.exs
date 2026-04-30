defmodule Shatter.Network.ListenerTest do
  use ExUnit.Case, async: false

  alias Shatter.Network.{HandlerSupervisor, Listener}
  alias Shatter.{DHCP.Packet, Pool, Store}

  @local_pool %Pool{
    id: :local,
    range_start: {192, 168, 1, 100},
    range_end: {192, 168, 1, 110},
    subnet_mask: {255, 255, 255, 0},
    gateway: {192, 168, 1, 1},
    dns_servers: [{8, 8, 8, 8}],
    lease_duration_seconds: 3600,
    local: true
  }

  setup do
    {:atomic, :ok} = :mnesia.clear_table(:leases)
    {:atomic, :ok} = :mnesia.clear_table(:pools)

    n = System.unique_integer([:positive])
    sup_name = :"handler_sup_#{n}"
    reg_name = :"handler_reg_#{n}"

    start_supervised!({Registry, keys: :unique, name: reg_name})
    start_supervised!({HandlerSupervisor, [name: sup_name]})

    {:ok, sup: sup_name, reg: reg_name}
  end

  defp start_listener(ctx, opts \\ []) do
    opts = Keyword.merge([port: 0, handler_supervisor: ctx.sup, handler_registry: ctx.reg], opts)
    pid = start_supervised!({Listener, opts})
    port = Listener.port(pid)
    {pid, port}
  end

  defp discover(xid \\ nil) do
    xid = xid || :rand.uniform(0xFFFFFFFF)

    {xid,
     Packet.serialize(%{
       op: 1, htype: 1, hlen: 6, hops: 0,
       xid: xid, secs: 0, flags: 0,
       ciaddr: {0, 0, 0, 0}, yiaddr: {0, 0, 0, 0},
       siaddr: {0, 0, 0, 0}, giaddr: {0, 0, 0, 0},
       chaddr: <<0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>,
       sname: "", file: "",
       options: [{53, 1}]
     })}
  end

  defp request(xid, offered_ip) do
    Packet.serialize(%{
      op: 1, htype: 1, hlen: 6, hops: 0,
      xid: xid, secs: 0, flags: 0,
      ciaddr: {0, 0, 0, 0}, yiaddr: {0, 0, 0, 0},
      siaddr: {0, 0, 0, 0}, giaddr: {0, 0, 0, 0},
      chaddr: <<0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>,
      sname: "", file: "",
      options: [{53, 3}, {50, offered_ip}]
    })
  end

  defp recv_packet(socket, timeout \\ 500) do
    receive do
      {:udp, ^socket, _ip, _port, data} ->
        {:ok, packet} = Packet.parse(data)
        packet
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

  test "listener binds to the configured port", ctx do
    {_pid, port} = start_listener(ctx)
    assert is_integer(port) and port > 0
  end

  test "DHCPDISCOVER spawns a RequestHandler", ctx do
    :ok = Store.insert_pool(@local_pool)
    {_pid, port} = start_listener(ctx)

    {:ok, client} = :gen_udp.open(0, [:binary, active: true])
    {_xid, discover_pkt} = discover()
    :gen_udp.send(client, {127, 0, 0, 1}, port, discover_pkt)

    assert eventually(fn -> DynamicSupervisor.count_children(ctx.sup).active > 0 end)

    :gen_udp.close(client)
  end

  test "DHCPDISCOVER with a pool returns a DHCPOFFER with a valid IP", ctx do
    :ok = Store.insert_pool(@local_pool)
    {_pid, port} = start_listener(ctx)

    {:ok, client} = :gen_udp.open(0, [:binary, active: true])
    {_xid, discover_pkt} = discover()
    :gen_udp.send(client, {127, 0, 0, 1}, port, discover_pkt)

    offer = recv_packet(client)

    assert offer.op == 2
    assert {53, 2} in offer.options
    assert offer.yiaddr in Pool.ip_range(@local_pool)

    :gen_udp.close(client)
  end

  test "DHCPREQUEST after OFFER returns DHCPACK and handler terminates", ctx do
    :ok = Store.insert_pool(@local_pool)
    {_pid, port} = start_listener(ctx)

    {:ok, client} = :gen_udp.open(0, [:binary, active: true])
    {xid, discover_pkt} = discover()
    :gen_udp.send(client, {127, 0, 0, 1}, port, discover_pkt)

    offer = recv_packet(client)
    offered_ip = offer.yiaddr

    :gen_udp.send(client, {127, 0, 0, 1}, port, request(xid, offered_ip))

    ack = recv_packet(client)

    assert ack.op == 2
    assert {53, 5} in ack.options
    assert ack.yiaddr == offered_ip

    assert eventually(fn -> DynamicSupervisor.count_children(ctx.sup).active == 0 end)

    :gen_udp.close(client)
  end

  test "RequestHandler terminates after timeout if no REQUEST follows", ctx do
    :ok = Store.insert_pool(@local_pool)
    {_pid, port} = start_listener(ctx)

    {:ok, client} = :gen_udp.open(0, [:binary, active: true])
    {_xid, discover_pkt} = discover()
    :gen_udp.send(client, {127, 0, 0, 1}, port, discover_pkt)

    _offer = recv_packet(client)

    assert eventually(fn -> DynamicSupervisor.count_children(ctx.sup).active == 0 end, 20)

    :gen_udp.close(client)
  end
end
