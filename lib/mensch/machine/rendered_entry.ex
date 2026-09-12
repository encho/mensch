defmodule Mensch.Machine.RenderedEntry do
  @moduledoc """
  Entry-local machine render result.

  Machines return this lightweight structure so they only describe note behavior
  over local millibeat frames. Global `%Mensch.Performance{}` construction,
  timeline alignment, merge, and channel allocation are owned by
  `Mensch.PerformanceAssembler`.
  """

  @type note_event :: map()

  @type frame :: %{
          at_mbeat: non_neg_integer(),
          notes: [note_event()]
        }

  @type t :: %__MODULE__{
          duration_mbeats: non_neg_integer(),
          music: [frame()]
        }

  @enforce_keys [:duration_mbeats, :music]
  defstruct [:duration_mbeats, :music]
end
