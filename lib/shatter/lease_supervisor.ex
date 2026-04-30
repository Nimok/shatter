defmodule Shatter.LeaseSupervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts), do: Supervisor.start_link(__MODULE__, :ok, opts)

  @impl true
  def init(:ok) do
    children = [
      {Shatter.LeaseReaper, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
