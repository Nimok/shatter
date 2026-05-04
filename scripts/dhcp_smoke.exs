defmodule Shatter.Manual.DHCPSmoke do
  @moduledoc false

  alias Shatter.DHCP.Packet

  @default_host "127.0.0.1"
  @default_port 6767
  @default_mac "02:00:00:00:00:01"
  @default_timeout 1_000

  def main(argv) do
    with {:ok, opts} <- parse_args(argv),
         {:ok, server_ip} <- resolve_host(opts.host),
         {:ok, mac} <- parse_mac(opts.mac),
         {:ok, socket} <- :gen_udp.open(0, [:binary, active: false]) do
      try do
        run(socket, server_ip, opts.port, mac, opts)
      after
        :gen_udp.close(socket)
      end
    else
      {:error, message} ->
        IO.puts(:stderr, message)
        usage()
        System.halt(1)
    end
  end

  defp run(socket, server_ip, server_port, mac, opts) do
    xid = :rand.uniform(0xFFFFFFFF)

    IO.puts("DHCP smoke test")
    IO.puts("  server: #{opts.host}:#{server_port}")
    IO.puts("  mac:    #{format_mac(mac)}")
    IO.puts("  xid:    #{xid}")

    discover = discover_packet(mac, xid)
    :ok = send_packet(socket, server_ip, server_port, discover)
    IO.puts("sent DHCPDISCOVER")

    offer = receive_packet(socket, opts.timeout, "DHCPOFFER")
    assert_message_type!(offer, 2, "DHCPOFFER")
    assert_same_xid!(offer, xid, "DHCPOFFER")
    assert_same_mac!(offer, mac, "DHCPOFFER")

    IO.puts("received DHCPOFFER")
    IO.puts("  offered_ip: #{format_ip(offer.yiaddr)}")
    print_packet("offer", offer, opts.verbose)

    request = request_packet(mac, xid, offer.yiaddr, server_identifier(offer))
    :ok = send_packet(socket, server_ip, server_port, request)
    IO.puts("sent DHCPREQUEST")

    ack = receive_packet(socket, opts.timeout, "DHCPACK")
    assert_message_type!(ack, 5, "DHCPACK")
    assert_same_xid!(ack, xid, "DHCPACK")
    assert_same_mac!(ack, mac, "DHCPACK")

    IO.puts("received DHCPACK")
    IO.puts("  ack_ip:     #{format_ip(ack.yiaddr)}")
    print_packet("ack", ack, opts.verbose)

    if ack.yiaddr == offer.yiaddr do
      IO.puts("success: lease completed for #{format_ip(ack.yiaddr)}")
    else
      fail!("DHCPACK IP #{format_ip(ack.yiaddr)} did not match offered IP #{format_ip(offer.yiaddr)}")
    end
  end

  defp parse_args(argv) do
    {opts, _args, invalid} =
      OptionParser.parse(argv,
        strict: [
          host: :string,
          port: :integer,
          mac: :string,
          timeout: :integer,
          verbose: :boolean,
          help: :boolean
        ],
        aliases: [h: :host, p: :port, m: :mac, t: :timeout, v: :verbose]
      )

    cond do
      Keyword.get(opts, :help, false) ->
        usage()
        System.halt(0)

      invalid != [] ->
        {:error, "invalid option(s): #{inspect(invalid)}"}

      Keyword.get(opts, :port, @default_port) not in 1..65_535 ->
        {:error, "--port must be between 1 and 65535"}

      Keyword.get(opts, :timeout, @default_timeout) < 1 ->
        {:error, "--timeout must be at least 1 millisecond"}

      true ->
        {:ok,
         %{
           host: Keyword.get(opts, :host, @default_host),
           port: Keyword.get(opts, :port, @default_port),
           mac: Keyword.get(opts, :mac, @default_mac),
           timeout: Keyword.get(opts, :timeout, @default_timeout),
           verbose: Keyword.get(opts, :verbose, false)
         }}
    end
  end

  defp usage do
    IO.puts("""
    Usage:
      mix run --no-start scripts/dhcp_smoke.exs [options]

    Options:
      --host HOST       DHCP server host or IPv4 address (default: #{@default_host})
      --port PORT       DHCP server UDP port (default: #{@default_port})
      --mac MAC         Client MAC address (default: #{@default_mac})
      --timeout MS      Receive timeout in milliseconds (default: #{@default_timeout})
      --verbose         Print parsed OFFER and ACK packets
    """)
  end

  defp resolve_host(host) do
    case :inet.getaddr(String.to_charlist(host), :inet) do
      {:ok, ip} -> {:ok, ip}
      {:error, reason} -> {:error, "could not resolve #{inspect(host)}: #{inspect(reason)}"}
    end
  end

  defp parse_mac(mac) do
    parts = String.split(mac, ":")

    with 6 <- length(parts),
         {:ok, bytes} <- parse_mac_bytes(parts) do
      {:ok, :binary.list_to_bin(bytes)}
    else
      _ -> {:error, "invalid MAC address #{inspect(mac)}; expected format 02:00:00:00:00:01"}
    end
  end

  defp parse_mac_bytes(parts) do
    bytes =
      Enum.map(parts, fn part ->
        case Integer.parse(part, 16) do
          {byte, ""} when byte in 0..255 -> byte
          _ -> :error
        end
      end)

    if :error in bytes, do: :error, else: {:ok, bytes}
  end

  defp send_packet(socket, server_ip, server_port, packet) do
    :gen_udp.send(socket, server_ip, server_port, Packet.serialize(packet))
  end

  defp receive_packet(socket, timeout, label) do
    case :gen_udp.recv(socket, 0, timeout) do
      {:ok, {_ip, _port, data}} ->
        case Packet.parse(data) do
          {:ok, packet} -> packet
          {:error, reason} -> fail!("received invalid #{label}: #{inspect(reason)}")
        end

      {:error, :timeout} ->
        fail!("timed out waiting for #{label}; is Shatter running and seeded with a local pool?")

      {:error, reason} ->
        fail!("failed waiting for #{label}: #{inspect(reason)}")
    end
  end

  defp discover_packet(mac, xid) do
    %{
      op: 1,
      htype: 1,
      hlen: 6,
      hops: 0,
      xid: xid,
      secs: 0,
      flags: 0,
      ciaddr: {0, 0, 0, 0},
      yiaddr: {0, 0, 0, 0},
      siaddr: {0, 0, 0, 0},
      giaddr: {0, 0, 0, 0},
      chaddr: mac,
      sname: "",
      file: "",
      options: [{53, 1}, {55, [1, 3, 6, 51, 54]}]
    }
  end

  defp request_packet(mac, xid, requested_ip, nil) do
    request_packet(mac, xid, requested_ip, [])
  end

  defp request_packet(mac, xid, requested_ip, server_id) when is_tuple(server_id) do
    request_packet(mac, xid, requested_ip, [{54, server_id}])
  end

  defp request_packet(mac, xid, requested_ip, extra_options) do
    %{
      op: 1,
      htype: 1,
      hlen: 6,
      hops: 0,
      xid: xid,
      secs: 0,
      flags: 0,
      ciaddr: {0, 0, 0, 0},
      yiaddr: {0, 0, 0, 0},
      siaddr: {0, 0, 0, 0},
      giaddr: {0, 0, 0, 0},
      chaddr: mac,
      sname: "",
      file: "",
      options: [{53, 3}, {50, requested_ip} | extra_options]
    }
  end

  defp server_identifier(packet) do
    case List.keyfind(packet.options, 54, 0) do
      {54, ip} -> ip
      nil -> nil
    end
  end

  defp assert_message_type!(packet, expected, label) do
    actual =
      case List.keyfind(packet.options, 53, 0) do
        {53, type} -> type
        nil -> nil
      end

    if actual != expected do
      fail!("expected #{label} message type #{expected}, got #{inspect(actual)}")
    end
  end

  defp assert_same_xid!(packet, xid, label) do
    if packet.xid != xid do
      fail!("expected #{label} xid #{xid}, got #{packet.xid}")
    end
  end

  defp assert_same_mac!(packet, mac, label) do
    if binary_part(packet.chaddr, 0, byte_size(mac)) != mac do
      fail!("expected #{label} chaddr #{format_mac(mac)}, got #{format_mac(binary_part(packet.chaddr, 0, 6))}")
    end
  end

  defp print_packet(_label, _packet, false), do: :ok

  defp print_packet(label, packet, true) do
    IO.puts("  #{label}: #{inspect(packet, pretty: true)}")
  end

  defp format_mac(mac) do
    mac
    |> :binary.bin_to_list()
    |> Enum.map_join(":", &(&1 |> Integer.to_string(16) |> String.pad_leading(2, "0")))
    |> String.downcase()
  end

  defp format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"

  defp fail!(message) do
    IO.puts(:stderr, "error: #{message}")
    System.halt(1)
  end
end

Shatter.Manual.DHCPSmoke.main(System.argv())
