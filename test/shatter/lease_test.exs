defmodule Shatter.LeaseTest do
  use ExUnit.Case, async: true

  alias Shatter.Lease

  defp offered_lease do
    %Lease{
      ip: {192, 168, 1, 10},
      mac: "aa:bb:cc:dd:ee:ff",
      expires_at: ~U[2026-05-01 00:00:00Z],
      state: :offered,
      hostname: nil,
      client_id: nil,
      requested_options: [],
      granted_by_node: :node1
    }
  end

  test "offered → bound is a valid transition" do
    lease = offered_lease()
    assert {:ok, updated} = Lease.transition(lease, :bound)
    assert updated.state == :bound
  end

  test "bound → expired is a valid transition" do
    {:ok, bound} = Lease.transition(offered_lease(), :bound)
    assert {:ok, updated} = Lease.transition(bound, :expired)
    assert updated.state == :expired
  end

  test "offered → expired is a valid transition" do
    assert {:ok, updated} = Lease.transition(offered_lease(), :expired)
    assert updated.state == :expired
  end

  test "expired → bound is an invalid transition" do
    {:ok, expired} = Lease.transition(offered_lease(), :expired)
    assert {:error, :invalid_transition} = Lease.transition(expired, :bound)
  end

  test "bound → offered is an invalid transition" do
    {:ok, bound} = Lease.transition(offered_lease(), :bound)
    assert {:error, :invalid_transition} = Lease.transition(bound, :offered)
  end

  test "expired → offered is an invalid transition" do
    {:ok, expired} = Lease.transition(offered_lease(), :expired)
    assert {:error, :invalid_transition} = Lease.transition(expired, :offered)
  end
end
