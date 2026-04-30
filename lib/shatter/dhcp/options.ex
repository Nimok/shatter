defmodule Shatter.DHCP.Options do
  @moduledoc false

  @magic_cookie <<99, 130, 83, 99>>

  @spec parse(binary()) :: {:ok, list()} | {:error, atom()}
  def parse(<<@magic_cookie, rest::binary>>), do: do_parse(rest, [])
  def parse(_), do: {:error, :invalid_magic_cookie}

  @spec serialize(list()) :: binary()
  def serialize(options) do
    IO.iodata_to_binary([@magic_cookie | Enum.map(options, &encode/1)] ++ [<<255>>])
  end

  defp do_parse(<<>>, acc), do: {:ok, Enum.reverse(acc)}
  defp do_parse(<<255, _::binary>>, acc), do: {:ok, Enum.reverse(acc)}
  defp do_parse(<<0, rest::binary>>, acc), do: do_parse(rest, acc)

  defp do_parse(<<type, len, value::binary-size(len), rest::binary>>, acc) do
    case decode(type, value) do
      {:ok, decoded} -> do_parse(rest, [{type, decoded} | acc])
      {:error, _} = err -> err
    end
  end

  defp do_parse(_, _), do: {:error, :truncated}

  defp decode(1, <<a, b, c, d>>), do: {:ok, {a, b, c, d}}
  defp decode(3, ips), do: decode_ips(ips)
  defp decode(6, ips), do: decode_ips(ips)
  defp decode(12, v), do: {:ok, v}
  defp decode(50, <<a, b, c, d>>), do: {:ok, {a, b, c, d}}
  defp decode(51, <<t::32>>), do: {:ok, t}
  defp decode(53, <<t>>), do: {:ok, t}
  defp decode(54, <<a, b, c, d>>), do: {:ok, {a, b, c, d}}
  defp decode(55, v), do: {:ok, :binary.bin_to_list(v)}
  defp decode(61, v), do: {:ok, v}
  defp decode(_, v), do: {:ok, v}

  defp decode_ips(bin), do: decode_ips(bin, [])
  defp decode_ips(<<a, b, c, d, rest::binary>>, acc), do: decode_ips(rest, [{a, b, c, d} | acc])
  defp decode_ips(<<>>, acc), do: {:ok, Enum.reverse(acc)}
  defp decode_ips(_, _), do: {:error, :invalid_ip_list_length}

  defp encode({1, {a, b, c, d}}), do: <<1, 4, a, b, c, d>>
  defp encode({3, ips}), do: encode_ip_list(3, ips)
  defp encode({6, ips}), do: encode_ip_list(6, ips)
  defp encode({12, v}), do: <<12, byte_size(v)>> <> v
  defp encode({50, {a, b, c, d}}), do: <<50, 4, a, b, c, d>>
  defp encode({51, t}), do: <<51, 4, t::32>>
  defp encode({53, t}), do: <<53, 1, t>>
  defp encode({54, {a, b, c, d}}), do: <<54, 4, a, b, c, d>>
  defp encode({55, list}), do: <<55, length(list)>> <> :binary.list_to_bin(list)
  defp encode({61, v}), do: <<61, byte_size(v)>> <> v
  defp encode({type, v}) when is_binary(v), do: <<type, byte_size(v)>> <> v

  defp encode_ip_list(type, ips) do
    ip_bin = IO.iodata_to_binary(Enum.map(ips, fn {a, b, c, d} -> <<a, b, c, d>> end))
    <<type, byte_size(ip_bin)>> <> ip_bin
  end
end
