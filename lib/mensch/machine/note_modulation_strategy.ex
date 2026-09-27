defmodule Mensch.Machine.NoteModulationStrategy do
  @moduledoc """
  Behavior for the note-modulation stage in the machine pipeline.

  Strategy modules attach pressure/slide/bend modulators to each
  `%Mensch.Machine.NotePlanItem{}` after note planning and before frame
  rendering.
  """

  alias Mensch.Machine.NotePlanItem

  @type strategy :: struct()
  @type modulation_context :: term()
  @type render_context :: term()

  @callback build_context(strategy(), [NotePlanItem.t()], render_context()) ::
              modulation_context()

  @callback with_note_modulators(
              strategy(),
              NotePlanItem.t(),
              modulation_context(),
              render_context()
            ) :: NotePlanItem.t()

  @spec build_context(strategy(), [NotePlanItem.t()], render_context()) :: modulation_context()
  def build_context(%module{} = strategy, note_plan, render_context)
      when is_atom(module) and is_list(note_plan) do
    module.build_context(strategy, note_plan, render_context)
  end

  @spec with_note_modulators(strategy(), NotePlanItem.t(), modulation_context(), render_context()) ::
          NotePlanItem.t()
  def with_note_modulators(%module{} = strategy, %NotePlanItem{} = note, context, render_context)
      when is_atom(module) do
    module.with_note_modulators(strategy, note, context, render_context)
  end
end
