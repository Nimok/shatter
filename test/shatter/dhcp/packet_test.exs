defmodule Shatter.DHCP.PacketTest do
  use ExUnit.Case, async: true

  alias Shatter.DHCP.{Options, Packet}

  # Builds a minimal valid DHCP packet binary with the given op and message type.
  defp raw(op, message_type, extra_opts \\ []) do
    opts_bin = Options.serialize([{53, message_type} | extra_opts])

    <<
      op, 1, 6, 0,
      0xDEADBEEF::32,
      0::16, 0x8000::16,
      0::32,
      0::32,
      0::32,
      0::32,
      0xAABBCCDDEEFF::48, 0::80,
      0::512,
      0::1024,
      opts_bin::binary
    >>
  end

  test "parse returns error for truncated binary" do
    assert {:error, :truncated} = Packet.parse(<<1, 2, 3>>)
  end

  test "parse returns error for valid header but invalid options" do
    bad_opts = <<0, 0, 0, 0>>
    bin = raw(1, 1) |> binary_part(0, 236) |> Kernel.<>(bad_opts)
    assert {:error, _} = Packet.parse(bin)
  end

  test "parse DISCOVER (op=1, msg_type=1)" do
    assert {:ok, packet} = raw(1, 1) |> Packet.parse()
    assert packet.op == 1
    assert {53, 1} in packet.options
  end

  test "parse OFFER (op=2, msg_type=2)" do
    opts = [{1, {255, 255, 255, 0}}, {51, 86_400}, {54, {192, 168, 1, 1}}]
    assert {:ok, packet} = raw(2, 2, opts) |> Packet.parse()
    assert packet.op == 2
    assert {53, 2} in packet.options
  end

  test "parse REQUEST (op=1, msg_type=3)" do
    assert {:ok, packet} = raw(1, 3) |> Packet.parse()
    assert packet.op == 1
    assert {53, 3} in packet.options
  end

  test "parse ACK (op=2, msg_type=5)" do
    assert {:ok, packet} = raw(2, 5) |> Packet.parse()
    assert packet.op == 2
    assert {53, 5} in packet.options
  end

  test "parse NAK (op=2, msg_type=6)" do
    assert {:ok, packet} = raw(2, 6) |> Packet.parse()
    assert packet.op == 2
    assert {53, 6} in packet.options
  end

  test "parse RELEASE (op=1, msg_type=7)" do
    assert {:ok, packet} = raw(1, 7) |> Packet.parse()
    assert packet.op == 1
    assert {53, 7} in packet.options
  end

  test "parse decodes fixed header fields correctly" do
    assert {:ok, packet} = raw(1, 1) |> Packet.parse()
    assert packet.htype == 1
    assert packet.hlen == 6
    assert packet.hops == 0
    assert packet.xid == 0xDEADBEEF
    assert packet.flags == 0x8000
    assert packet.ciaddr == {0, 0, 0, 0}
    assert packet.chaddr == <<0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>
    assert packet.sname == ""
    assert packet.file == ""
  end

  test "round-trip: parse(serialize(packet)) == packet" do
    {:ok, original} = raw(1, 1) |> Packet.parse()
    assert {:ok, ^original} = original |> Packet.serialize() |> Packet.parse()
  end

  test "round-trip with full options" do
    opts = [
      {1, {255, 255, 255, 0}},
      {3, [{192, 168, 1, 1}]},
      {6, [{8, 8, 8, 8}]},
      {51, 86_400},
      {54, {192, 168, 1, 1}}
    ]

    {:ok, original} = raw(2, 2, opts) |> Packet.parse()
    assert {:ok, ^original} = original |> Packet.serialize() |> Packet.parse()
  end
end
