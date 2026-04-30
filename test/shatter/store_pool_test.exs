defmodule Shatter.Store.PoolTest do
  use ExUnit.Case, async: false

  alias Shatter.{Pool, Store}

  setup do
    :mnesia.clear_table(:leases)
    :mnesia.clear_table(:pools)
    :ok
  end

  @pool %Pool{
    id: :test_pool,
    range_start: {192, 168, 1, 100},
    range_end: {192, 168, 1, 110},
    subnet_mask: {255, 255, 255, 0},
    gateway: {192, 168, 1, 1},
    dns_servers: [{8, 8, 8, 8}],
    lease_duration_seconds: 3600
  }

  test "insert_pool and get_pool round-trip" do
    assert :ok = Store.insert_pool(@pool)
    assert {:ok, @pool} == Store.get_pool(:test_pool)
  end

  test "get_pool returns not_found for unknown id" do
    assert {:error, :not_found} = Store.get_pool(:missing)
  end

  test "delete_pool removes the pool" do
    assert :ok = Store.insert_pool(@pool)
    assert :ok = Store.delete_pool(:test_pool)
    assert {:error, :not_found} = Store.get_pool(:test_pool)
  end

  test "list_pools returns all inserted pools" do
    pool2 = %Pool{@pool | id: :pool2, range_start: {10, 0, 0, 1}, range_end: {10, 0, 0, 10}}
    assert :ok = Store.insert_pool(@pool)
    assert :ok = Store.insert_pool(pool2)
    {:ok, pools} = Store.list_pools()
    assert length(pools) == 2
    assert @pool in pools
    assert pool2 in pools
  end
end
