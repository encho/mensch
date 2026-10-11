defmodule Mensch.SampleBlueprints.Blueprint do
  @moduledoc """
  Behaviour for pluggable sample blueprints.

  A blueprint provides metadata for UI generation and owns sample-entry
  construction from normalized chords and global timing settings.
  """

  alias Mensch.ChordSpec
  alias Mensch.SampleContext

  @type additional_field_type :: :int | :float | :enum

  @type additional_param_option :: %{
          required(:value) => String.t(),
          required(:label) => String.t()
        }

  @type additional_param_schema_field :: %{
          required(:name) => String.t(),
          required(:label) => String.t(),
          required(:type) => additional_field_type(),
          required(:default) => integer() | float() | String.t(),
          optional(:min) => integer() | float(),
          optional(:max) => integer() | float(),
          optional(:step) => number(),
          optional(:options) => [additional_param_option()]
        }

  @type build_input :: %{
          required(:chords) => [ChordSpec.t()],
          required(:sample_context) => SampleContext.t(),
          required(:chord_duration_mbeats) => pos_integer(),
          required(:silence_after_chord_mbeats) => non_neg_integer(),
          required(:additional_params) => map()
        }

  @callback id() :: String.t()
  @callback label() :: String.t()
  @callback additional_param_schema() :: [additional_param_schema_field()]
  @callback default_additional_params() :: map()
  @callback build_sample_entries(build_input()) :: {:ok, [map()]} | {:error, String.t()}
end
