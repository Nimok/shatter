defmodule Shatter.Lease do
  @moduledoc false

  @valid_transitions %{
    offered: [:bound, :expired],
    bound: [:expired],
    expired: []
  }

  @enforce_keys [:ip, :mac, :expires_at, :state]
  defstruct [:ip, :mac, :expires_at, :state, :hostname, :client_id, :requested_options, :granted_by_node]

  @type t :: %__MODULE__{}
  @type state :: :offered | :bound | :expired

  @spec transition(t(), state()) :: {:ok, t()} | {:error, :invalid_transition}
  def transition(%__MODULE__{state: from} = lease, to) do
    if to in Map.fetch!(@valid_transitions, from) do
      {:ok, %{lease | state: to}}
    else
      {:error, :invalid_transition}
    end
  end
end
