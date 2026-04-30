defmodule Shatter.AllocatorTest do
  use ExUnit.Case, async: false

  alias Shatter.{Allocator, Pool, Store}

  setup do
    :mnesia.clear_table(:leases)
    :mnesia.clear_table(:pools)
    :ok
  end

  @pool %Pool{
    id: :test_pool,
    range_start: {192, 168, 1, 100},
    range_end: {192, 168, 1, 102},
    subnet_mask: {255, 255, 255, 0},
    gateway: {192, 168, 1, 1},
    dns_servers: [{8, 8, 8, 8}],
    lease_duration_seconds: 3600
  }

  @mac <<0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF>>

  test "first allocation returns ok with a lease" do
    assert {:ok, lease} = Allocator.allocate(@mac, @pool)
    assert lease.mac == @mac
    assert lease.ip in Pool.ip_range(@pool)
    assert lease.state == :offered
  end

  test "same MAC twice returns the same IP" do
    assert {:ok, first} = Allocator.allocate(@mac, @pool)
    assert {:ok, second} = Allocator.allocate(@mac, @pool)
    assert first.ip == second.ip
  end

  test "expired lease IP is reallocated to a new MAC" do
    assert {:ok, original} = Allocator.allocate(@mac, @pool)
    expired = %{original | state: :expired}
    :ok = Store.update_lease(expired)

    new_mac = <<0x11, 0x22, 0x33, 0x44, 0x55, 0x66>>
    assert {:ok, new_lease} = Allocator.allocate(new_mac, @pool)
    assert new_lease.ip == original.ip
    assert new_lease.mac == new_mac
  end

  test "pool exhausted returns error when all IPs are taken" do
    pool_ips = Pool.ip_range(@pool)
    pool_ips
    |> Enum.with_index()
    |> Enum.each(fn {_ip, i} ->
      mac = <<0xAA, 0xBB, 0xCC, 0xDD, 0xEE, i>>
      assert {:ok, _} = Allocator.allocate(mac, @pool)
    end)

    new_mac = <<0x11, 0x22, 0x33, 0x44, 0x55, 0x66>>
    assert {:error, :pool_exhausted} = Allocator.allocate(new_mac, @pool)
  end
end
