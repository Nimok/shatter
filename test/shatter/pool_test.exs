defmodule Shatter.PoolTest do
  use ExUnit.Case, async: true

  alias Shatter.Pool

  defp small_pool do
    %Pool{
      id: "test-pool",
      range_start: {10, 0, 0, 1},
      range_end: {10, 0, 0, 3},
      subnet_mask: {255, 255, 255, 0},
      gateway: {10, 0, 0, 254},
      dns_servers: [{8, 8, 8, 8}],
      lease_duration_seconds: 86_400
    }
  end

  test "ip_range enumerates all IPs in a small range" do
    assert Pool.ip_range(small_pool()) == [
             {10, 0, 0, 1},
             {10, 0, 0, 2},
             {10, 0, 0, 3}
           ]
  end
end
