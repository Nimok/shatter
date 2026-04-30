defmodule Shatter.Pool do
  @moduledoc false

  import Bitwise

  @enforce_keys [:id, :range_start, :range_end, :subnet_mask, :gateway, :dns_servers, :lease_duration_seconds]
  defstruct [:id, :range_start, :range_end, :subnet_mask, :gateway, :dns_servers, :lease_duration_seconds]

  @type ip :: {0..255, 0..255, 0..255, 0..255}
  @type t :: %__MODULE__{}

  @spec ip_range(t()) :: [ip()]
  def ip_range(%__MODULE__{range_start: start, range_end: stop}) do
    start_int = ip_to_int(start)
    stop_int = ip_to_int(stop)
    Enum.map(start_int..stop_int, &int_to_ip/1)
  end

  defp ip_to_int({a, b, c, d}), do: a * 16_777_216 + b * 65_536 + c * 256 + d

  defp int_to_ip(n) do
    {n >>> 24 &&& 255, n >>> 16 &&& 255, n >>> 8 &&& 255, n &&& 255}
  end
end
