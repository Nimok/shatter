defmodule Shatter.Network.Listener do
  @moduledoc false

  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, :ok, opts)

  @impl true
  def init(:ok), do: {:ok, %{}}
end
