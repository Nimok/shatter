defmodule Shatter.DHCP.OptionsTest do
  use ExUnit.Case, async: true

  alias Shatter.DHCP.Options

  @magic <<99, 130, 83, 99>>

  test "parse rejects missing magic cookie" do
    assert {:error, :invalid_magic_cookie} = Options.parse(<<1, 2, 3, 4, 255>>)
  end

  test "parse accepts bare end byte" do
    assert {:ok, []} = Options.parse(@magic <> <<255>>)
  end

  test "parse skips PAD bytes" do
    assert {:ok, [{53, 1}]} = Options.parse(@magic <> <<0, 0, 53, 1, 1, 255>>)
  end

  test "parse subnet mask (option 1)" do
    bin = @magic <> <<1, 4, 255, 255, 255, 0, 255>>
    assert {:ok, [{1, {255, 255, 255, 0}}]} = Options.parse(bin)
  end

  test "parse DHCP message type (option 53)" do
    bin = @magic <> <<53, 1, 3, 255>>
    assert {:ok, [{53, 3}]} = Options.parse(bin)
  end

  test "parse lease time (option 51)" do
    bin = @magic <> <<51, 4, 0, 1, 81, 128, 255>>
    assert {:ok, [{51, 86_400}]} = Options.parse(bin)
  end

  test "parse hostname (option 12)" do
    hostname = "myhost"
    bin = @magic <> <<12, byte_size(hostname)>> <> hostname <> <<255>>
    assert {:ok, [{12, "myhost"}]} = Options.parse(bin)
  end

  test "parse DNS servers (option 6, multiple)" do
    bin = @magic <> <<6, 8, 8, 8, 8, 8, 8, 8, 4, 4, 255>>
    assert {:ok, [{6, [{8, 8, 8, 8}, {8, 8, 4, 4}]}]} = Options.parse(bin)
  end

  test "parse router list (option 3)" do
    bin = @magic <> <<3, 4, 192, 168, 1, 1, 255>>
    assert {:ok, [{3, [{192, 168, 1, 1}]}]} = Options.parse(bin)
  end

  test "parse returns error for truncated options" do
    assert {:error, :truncated} = Options.parse(@magic <> <<53, 10>>)
  end

  test "parse returns error for IP list option with non-multiple-of-4 length" do
    bin = @magic <> <<3, 5, 192, 168, 1, 1, 0, 255>>
    assert {:error, :invalid_ip_list_length} = Options.parse(bin)
  end

  test "round-trip preserves all supported option types" do
    options = [
      {1, {255, 255, 255, 0}},
      {3, [{192, 168, 1, 1}]},
      {6, [{8, 8, 8, 8}, {8, 8, 4, 4}]},
      {12, "myhostname"},
      {50, {192, 168, 1, 50}},
      {51, 86_400},
      {53, 1},
      {54, {192, 168, 1, 1}},
      {55, [1, 3, 6, 15]},
      {61, <<1, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF>>}
    ]

    assert {:ok, ^options} = options |> Options.serialize() |> Options.parse()
  end
end
