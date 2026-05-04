defmodule Shatter.Store.PoolTest do
  use ExUnit.Case, async: false

  alias Shatter.{Pool, Store}

  setup do
    {:atomic, :ok} = :mnesia.clear_table(:leases)
    {:atomic, :ok} = :mnesia.clear_table(:pools)
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

  # ── find_pool_for_giaddr ────────────────────────────────────────────────────

  @local_pool %Pool{
    id: :local,
    range_start: {10, 0, 0, 100},
    range_end: {10, 0, 0, 200},
    subnet_mask: {255, 255, 255, 0},
    gateway: {10, 0, 0, 1},
    dns_servers: [{8, 8, 8, 8}],
    lease_duration_seconds: 3600,
    local: true
  }

  @relay_pool %Pool{
    id: :relay,
    range_start: {100, 64, 0, 10},
    range_end: {100, 64, 0, 200},
    subnet_mask: {255, 255, 255, 0},
    gateway: {100, 64, 0, 1},
    dns_servers: [{1, 1, 1, 1}],
    lease_duration_seconds: 3600,
    local: false
  }

  test "giaddr {0,0,0,0} returns the local pool" do
    :ok = Store.insert_pool(@local_pool)
    assert {:ok, pool} = Store.find_pool_for_giaddr({0, 0, 0, 0})
    assert pool.id == :local
  end

  test "giaddr {0,0,0,0} returns error when no local pool exists" do
    :ok = Store.insert_pool(@relay_pool)
    assert {:error, :no_pool} = Store.find_pool_for_giaddr({0, 0, 0, 0})
  end

  test "giaddr on relay subnet selects the relay pool" do
    :ok = Store.insert_pool(@local_pool)
    :ok = Store.insert_pool(@relay_pool)
    # relay agent IP is the gateway, on the same /24 as the pool
    assert {:ok, pool} = Store.find_pool_for_giaddr({100, 64, 0, 1})
    assert pool.id == :relay
  end

  test "giaddr on relay subnet does not select local pool" do
    :ok = Store.insert_pool(@local_pool)
    :ok = Store.insert_pool(@relay_pool)
    assert {:ok, pool} = Store.find_pool_for_giaddr({100, 64, 0, 1})
    assert pool.local == false
  end

  test "giaddr on unknown subnet returns error" do
    :ok = Store.insert_pool(@local_pool)
    :ok = Store.insert_pool(@relay_pool)
    assert {:error, :no_pool} = Store.find_pool_for_giaddr({172, 16, 0, 1})
  end

  test "multiple local pools: selection is deterministic" do
    local_a = %Pool{@local_pool | id: :local_a}
    local_b = %Pool{@local_pool | id: :local_b}
    :ok = Store.insert_pool(local_a)
    :ok = Store.insert_pool(local_b)
    {:ok, first} = Store.find_pool_for_giaddr({0, 0, 0, 0})
    {:ok, second} = Store.find_pool_for_giaddr({0, 0, 0, 0})
    assert first.id == second.id
  end
end
