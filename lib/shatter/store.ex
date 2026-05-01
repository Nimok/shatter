defmodule Shatter.Store do
  @moduledoc false

  use GenServer

  import Bitwise, only: [&&&: 2]

  alias Shatter.{Lease, Pool}

  # ── Lifecycle ──────────────────────────────────────────────────────────────

  def start_link(opts), do: GenServer.start_link(__MODULE__, :ok, opts)

  @impl true
  def init(:ok) do
    table_type = Application.get_env(:shatter, __MODULE__, []) |> Keyword.get(:table_type, :disc_copies)
    :ok = ensure_schema(table_type)
    :ok = ensure_tables(table_type)
    {:ok, %{}}
  end

  defp ensure_schema(:ram_copies), do: :ok

  defp ensure_schema(_) do
    case :mnesia.create_schema([node()]) do
      :ok -> :ok
      {:error, {_, {:already_exists, _}}} -> :ok
    end
  end

  defp ensure_tables(table_type) do
    create_table(:leases, [
      {:attributes, [:ip, :mac, :expires_at, :state, :hostname, :client_id, :requested_options, :granted_by_node]},
      {:index, [:mac]},
      {table_type, [node()]}
    ])

    create_table(:pools, [
      {:attributes, [:id, :range_start, :range_end, :subnet_mask, :gateway, :dns_servers, :lease_duration_seconds, :local]},
      {table_type, [node()]}
    ])

    case :mnesia.wait_for_tables([:leases, :pools], 5_000) do
      :ok -> :ok
      {:timeout, tables} -> raise "Mnesia tables timed out waiting: #{inspect(tables)}"
      {:error, reason} -> raise "Mnesia wait_for_tables failed: #{inspect(reason)}"
    end
  end

  defp create_table(name, opts) do
    case :mnesia.create_table(name, opts) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, ^name}} -> migrate_table(name, opts)
      {:aborted, reason} -> raise "failed to create Mnesia table #{inspect(name)}: #{inspect(reason)}"
    end
  end

  @old_pool_attrs [:id, :range_start, :range_end, :subnet_mask, :gateway, :dns_servers, :lease_duration_seconds]
  @new_pool_attrs [:id, :range_start, :range_end, :subnet_mask, :gateway, :dns_servers, :lease_duration_seconds, :local]

  defp migrate_table(:pools, _opts) do
    case :mnesia.table_info(:pools, :attributes) do
      @old_pool_attrs ->
        case :mnesia.transform_table(
               :pools,
               fn {_, id, rs, re, sm, gw, dns, dur} -> {:pools, id, rs, re, sm, gw, dns, dur, false} end,
               @new_pool_attrs
             ) do
          {:atomic, :ok} -> :ok
          {:aborted, reason} -> raise "pools table migration failed: #{inspect(reason)}"
        end

      _ ->
        :ok
    end
  end

  defp migrate_table(_name, _opts), do: :ok

  # ── Lease API ──────────────────────────────────────────────────────────────

  @spec insert_lease(Lease.t()) :: :ok | {:error, term()}
  def insert_lease(%Lease{} = lease) do
    case :mnesia.transaction(fn -> :mnesia.write(lease_to_record(lease)) end) do
      {:atomic, :ok} -> :ok
      {:aborted, reason} -> {:error, reason}
    end
  end

  @spec get_lease_by_ip(:inet.ip4_address()) :: {:ok, Lease.t()} | {:error, :not_found} | {:error, term()}
  def get_lease_by_ip(ip) do
    case txn(fn -> :mnesia.read(:leases, ip) end) do
      {:ok, [record]} -> {:ok, record_to_lease(record)}
      {:ok, []} -> {:error, :not_found}
      err -> err
    end
  end

  @spec update_lease(Lease.t()) :: :ok | {:error, term()}
  def update_lease(%Lease{} = lease), do: insert_lease(lease)

  @spec delete_lease(:inet.ip4_address()) :: :ok | {:error, term()}
  def delete_lease(ip) do
    case :mnesia.transaction(fn -> :mnesia.delete(:leases, ip, :write) end) do
      {:atomic, :ok} -> :ok
      {:aborted, reason} -> {:error, reason}
    end
  end

  @spec list_leases() :: {:ok, [Lease.t()]} | {:error, term()}
  def list_leases do
    case txn(fn -> :mnesia.match_object({:leases, :_, :_, :_, :_, :_, :_, :_, :_}) end) do
      {:ok, records} -> {:ok, Enum.map(records, &record_to_lease/1)}
      err -> err
    end
  end

  @spec get_lease_by_mac(binary()) :: {:ok, Lease.t()} | {:error, :not_found} | {:error, term()}
  def get_lease_by_mac(mac) do
    case txn(fn -> :mnesia.index_read(:leases, mac, :mac) end) do
      {:ok, []} -> {:error, :not_found}
      {:ok, [record]} -> {:ok, record_to_lease(record)}
      {:ok, records} -> {:ok, records |> Enum.map(&record_to_lease/1) |> Enum.max_by(& &1.expires_at, DateTime)}
      err -> err
    end
  end

  # ── Pool API ───────────────────────────────────────────────────────────────

  @spec insert_pool(Pool.t()) :: :ok | {:error, term()}
  def insert_pool(%Pool{} = pool) do
    case :mnesia.transaction(fn -> :mnesia.write(pool_to_record(pool)) end) do
      {:atomic, :ok} -> :ok
      {:aborted, reason} -> {:error, reason}
    end
  end

  @spec get_pool(term()) :: {:ok, Pool.t()} | {:error, :not_found} | {:error, term()}
  def get_pool(id) do
    case txn(fn -> :mnesia.read(:pools, id) end) do
      {:ok, [record]} -> {:ok, record_to_pool(record)}
      {:ok, []} -> {:error, :not_found}
      err -> err
    end
  end

  @spec delete_pool(term()) :: :ok | {:error, term()}
  def delete_pool(id) do
    case :mnesia.transaction(fn -> :mnesia.delete(:pools, id, :write) end) do
      {:atomic, :ok} -> :ok
      {:aborted, reason} -> {:error, reason}
    end
  end

  @spec list_pools() :: {:ok, [Pool.t()]} | {:error, term()}
  def list_pools do
    case txn(fn -> :mnesia.match_object({:pools, :_, :_, :_, :_, :_, :_, :_, :_}) end) do
      {:ok, records} -> {:ok, Enum.map(records, &record_to_pool/1)}
      err -> err
    end
  end

  @spec find_pool_for_giaddr(:inet.ip4_address()) :: {:ok, Pool.t()} | {:error, :no_pool | term()}
  def find_pool_for_giaddr({0, 0, 0, 0}) do
    case txn(fn -> :mnesia.match_object({:pools, :_, :_, :_, :_, :_, :_, :_, true}) end) do
      {:ok, []} ->
        {:error, :no_pool}

      {:ok, records} ->
        pool = records |> Enum.map(&record_to_pool/1) |> Enum.min_by(& &1.id)
        {:ok, pool}

      err ->
        err
    end
  end

  def find_pool_for_giaddr(giaddr) do
    case list_pools() do
      {:ok, pools} ->
        case Enum.filter(pools, &(not &1.local and same_subnet?(&1, giaddr))) do
          [] -> {:error, :no_pool}
          matches -> {:ok, Enum.min_by(matches, & &1.id)}
        end

      err ->
        err
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp txn(fun) do
    case :mnesia.transaction(fun) do
      {:atomic, result} -> {:ok, result}
      {:aborted, reason} -> {:error, reason}
    end
  end

  defp lease_to_record(%Lease{} = l) do
    {:leases, l.ip, l.mac, l.expires_at, l.state, l.hostname, l.client_id, l.requested_options, l.granted_by_node}
  end

  defp record_to_lease({:leases, ip, mac, expires_at, state, hostname, client_id, requested_options, granted_by_node}) do
    %Lease{ip: ip, mac: mac, expires_at: expires_at, state: state, hostname: hostname, client_id: client_id, requested_options: requested_options, granted_by_node: granted_by_node}
  end

  defp pool_to_record(%Pool{} = p) do
    {:pools, p.id, p.range_start, p.range_end, p.subnet_mask, p.gateway, p.dns_servers, p.lease_duration_seconds, p.local}
  end

  defp record_to_pool({:pools, id, range_start, range_end, subnet_mask, gateway, dns_servers, lease_duration_seconds, local}) do
    %Pool{id: id, range_start: range_start, range_end: range_end, subnet_mask: subnet_mask, gateway: gateway, dns_servers: dns_servers, lease_duration_seconds: lease_duration_seconds, local: local}
  end

  defp record_to_pool({:pools, id, range_start, range_end, subnet_mask, gateway, dns_servers, lease_duration_seconds}) do
    %Pool{id: id, range_start: range_start, range_end: range_end, subnet_mask: subnet_mask, gateway: gateway, dns_servers: dns_servers, lease_duration_seconds: lease_duration_seconds, local: false}
  end

  defp same_subnet?(%Pool{range_start: start, subnet_mask: mask}, ip) do
    (ip_to_int(ip) &&& ip_to_int(mask)) == (ip_to_int(start) &&& ip_to_int(mask))
  end

  defp ip_to_int({a, b, c, d}), do: a * 16_777_216 + b * 65_536 + c * 256 + d
end
