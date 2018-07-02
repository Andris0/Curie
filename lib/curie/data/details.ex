defmodule Curie.Data.Details do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:member, :integer, []}
  schema "details" do
    field(:online, :integer)
    field(:spoke, :integer)
    field(:channel, :string)
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [:member, :online, :spoke, :channel])
    |> validate_required([:member])
  end
end
