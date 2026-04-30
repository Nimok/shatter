defmodule Shatter.StoreTest do
  use ExUnit.Case, async: false

  alias Shatter.{Lease, Store}

  setup do
    {:atomic, :ok} = :mnesia.clear_table(:leases)
    {:atomic, :ok} = :mnesia.clear_table(:pools)
    :ok
  end

  @lease %Lease{
    ip: {192, 168, 1, 100},
    mac: <<0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF>>,
    expires_at: ~U[2026-05-01 00:00:00Z],
    state: :offered
  }

  test "insert_lease and get_lease_by_ip round-trip" do
    assert :ok = Store.insert_lease(@lease)
    assert {:ok, @lease} == Store.get_lease_by_ip({192, 168, 1, 100})
  end

  test "get_lease_by_mac returns lease for known MAC" do
    assert :ok = Store.insert_lease(@lease)
    assert {:ok, @lease} == Store.get_lease_by_mac(<<0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF>>)
  end

  test "get_lease_by_mac returns not_found for unknown MAC" do
    assert {:error, :not_found} = Store.get_lease_by_mac(<<0x00, 0x11, 0x22, 0x33, 0x44, 0x55>>)
  end

  test "update_lease overwrites existing lease" do
    assert :ok = Store.insert_lease(@lease)
    updated = %{@lease | state: :bound}
    assert :ok = Store.update_lease(updated)
    assert {:ok, ^updated} = Store.get_lease_by_ip(@lease.ip)
  end

  test "delete_lease removes the lease" do
    assert :ok = Store.insert_lease(@lease)
    assert :ok = Store.delete_lease(@lease.ip)
    assert {:error, :not_found} = Store.get_lease_by_ip(@lease.ip)
  end

  test "list_leases returns all inserted leases" do
    lease2 = %Lease{
      ip: {192, 168, 1, 101},
      mac: <<0x11, 0x22, 0x33, 0x44, 0x55, 0x66>>,
      expires_at: ~U[2026-05-01 00:00:00Z],
      state: :offered
    }

    assert :ok = Store.insert_lease(@lease)
    assert :ok = Store.insert_lease(lease2)
    {:ok, leases} = Store.list_leases()
    assert length(leases) == 2
    assert @lease in leases
    assert lease2 in leases
  end
end
