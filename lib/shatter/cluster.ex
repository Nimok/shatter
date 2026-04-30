defmodule Shatter.Cluster do
  @moduledoc false

  def child_spec(_opts) do
    topologies = Application.get_env(:libcluster, :topologies, [])

    %{
      id: __MODULE__,
      start: {Cluster.Supervisor, :start_link, [[topologies, [name: __MODULE__]]]},
      type: :supervisor
    }
  end
end
