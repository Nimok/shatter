defmodule Shatter.Allocator do
  @moduledoc false

  alias Shatter.{Lease, Pool}

  @spec allocate(binary(), Pool.t()) :: {:ok, Lease.t()} | {:error, :pool_exhausted} | {:error, term()}
  def allocate(mac, %Pool{} = pool) do
    :mnesia.transaction(fn ->
      case find_active_lease(mac) do
        {:ok, lease} ->
          lease

        {:error, :not_found} ->
          case find_available_ip(pool) do
            {:ok, ip} ->
              lease = build_lease(ip, mac, pool)
              :ok = :mnesia.write(lease_record(lease))
              lease

            {:error, :pool_exhausted} ->
              :mnesia.abort(:pool_exhausted)
          end
      end
    end)
    |> case do
      {:atomic, lease} -> {:ok, lease}
      {:aborted, :pool_exhausted} -> {:error, :pool_exhausted}
      {:aborted, reason} -> {:error, reason}
    end
  end

  # ── Private ────────────────────────────────────────────────────────────────

  defp find_active_lease(mac) do
    active =
      :mnesia.index_read(:leases, mac, :mac)
      |> Enum.map(&record_to_lease/1)
      |> Enum.filter(&(&1.state in [:offered, :bound]))

    case active do
      [] -> {:error, :not_found}
      leases -> {:ok, Enum.max_by(leases, & &1.expires_at, DateTime)}
    end
  end

  defp find_available_ip(%Pool{} = pool) do
    taken = taken_ips()
    available = pool |> Pool.ip_range() |> Enum.find(&(not MapSet.member?(taken, &1)))
    if available, do: {:ok, available}, else: {:error, :pool_exhausted}
  end

  defp taken_ips do
    :mnesia.match_object({:leases, :_, :_, :_, :_, :_, :_, :_, :_})
    |> Enum.filter(fn {:leases, _ip, _mac, _exp, state, _, _, _, _} -> state in [:offered, :bound] end)
    |> Enum.map(fn {:leases, ip, _, _, _, _, _, _, _} -> ip end)
    |> MapSet.new()
  end

  defp build_lease(ip, mac, %Pool{lease_duration_seconds: dur}) do
    %Lease{
      ip: ip,
      mac: mac,
      expires_at: DateTime.add(DateTime.utc_now(), dur, :second),
      state: :offered,
      granted_by_node: node()
    }
  end

  defp lease_record(%Lease{} = l) do
    {:leases, l.ip, l.mac, l.expires_at, l.state, l.hostname, l.client_id, l.requested_options, l.granted_by_node}
  end

  defp record_to_lease({:leases, ip, mac, expires_at, state, hostname, client_id, requested_options, granted_by_node}) do
    %Lease{ip: ip, mac: mac, expires_at: expires_at, state: state, hostname: hostname, client_id: client_id, requested_options: requested_options, granted_by_node: granted_by_node}
  end
end
