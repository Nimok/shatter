defmodule Shatter.Network.HandlerRegistry do
  @moduledoc false

  def child_spec(opts) do
    Registry.child_spec(Keyword.merge([keys: :unique, name: __MODULE__], opts))
  end
end
