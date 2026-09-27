defmodule Mensch.Machine.RenderContextCommon do
  @moduledoc """
  Shared helper for machine render-context timing fields.

  Machines keep their own typed render-context structs, while this module
  centralizes validation and assembly of the common timing/sample fields.
  """

  alias Mensch.SampleContext

  @enforce_keys [
    :sample_context,
    :chord_start_mbeat,
    :absolute_chord_start_mbeat,
    :frame_mbeats,
    :chord_duration_mbeats
  ]
  defstruct [
    :sample_context,
    :chord_start_mbeat,
    :absolute_chord_start_mbeat,
    :frame_mbeats,
    :chord_duration_mbeats
  ]

  @type t :: %__MODULE__{
          sample_context: SampleContext.t(),
          chord_start_mbeat: non_neg_integer(),
          absolute_chord_start_mbeat: non_neg_integer(),
          frame_mbeats: pos_integer(),
          chord_duration_mbeats: non_neg_integer()
        }

  @type common_fields :: t()

  @spec common_fields(
          SampleContext.t(),
          non_neg_integer(),
          non_neg_integer(),
          pos_integer(),
          non_neg_integer()
        ) :: common_fields()
  def common_fields(
        %SampleContext{} = sample_context,
        chord_start_mbeat,
        absolute_chord_start_mbeat,
        frame_mbeats,
        chord_duration_mbeats
      )
      when is_integer(chord_start_mbeat) and chord_start_mbeat >= 0 and
             is_integer(absolute_chord_start_mbeat) and absolute_chord_start_mbeat >= 0 and
             is_integer(frame_mbeats) and frame_mbeats > 0 and
             is_integer(chord_duration_mbeats) and chord_duration_mbeats >= 0 do
    %__MODULE__{
      sample_context: sample_context,
      chord_start_mbeat: chord_start_mbeat,
      absolute_chord_start_mbeat: absolute_chord_start_mbeat,
      frame_mbeats: frame_mbeats,
      chord_duration_mbeats: chord_duration_mbeats
    }
  end
end
