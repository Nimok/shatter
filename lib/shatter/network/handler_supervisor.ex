defmodule Shatter.Network.HandlerSupervisor do
  @moduledoc false

  use DynamicSupervisor

  def start_link(opts), do: DynamicSupervisor.start_link(__MODULE__, :ok, opts)

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)
end
