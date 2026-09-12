defprotocol Mensch.Machine do
  @moduledoc """
  Polymorphic machine interface over machine structs.

  Each machine instance carries its typed params in its struct. Rendering is
  dispatched through this protocol.
  """

  @spec id(t()) :: atom()
  def id(machine)

  @spec controls(t()) :: map()
  def controls(machine)

  @spec render(
          t(),
          Mensch.ChordSpec.t(),
          Mensch.SampleContext.t(),
          Mensch.TimelineContext.t(),
          keyword()
        ) :: Mensch.Machine.RenderedEntry.t()
  def render(machine, chord_spec, sample_context, timeline_context, opts)
end
