defmodule MenschWeb.SampleEntryViz.TimelineComponent do
  use MenschWeb, :html

  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  attr :timeline_context, TimelineContext, required: true
  attr :sample_context, SampleContext, required: true

  def panel(assigns) do
    start_mbeat =
      SampleContext.position_to_mbeat(assigns.sample_context, assigns.timeline_context.start_beat)

    duration_mbeats = TimelineContext.duration_mbeats(assigns.timeline_context)

    duration_beats =
      Float.round(duration_mbeats / SampleContext.mbeats_per_beat(assigns.sample_context), 3)

    end_mbeat = start_mbeat + duration_mbeats
    start_ms = SampleContext.mbeats_to_ms(assigns.sample_context, start_mbeat)
    end_ms = SampleContext.mbeats_to_ms(assigns.sample_context, end_mbeat)
    duration_ms = SampleContext.mbeats_to_ms(assigns.sample_context, duration_mbeats)
    end_beat = SampleContext.mbeat_to_position(assigns.sample_context, end_mbeat)

    assigns =
      assign(assigns,
        start_mbeat: start_mbeat,
        duration_beats: duration_beats,
        duration_mbeats: duration_mbeats,
        start_ms: start_ms,
        end_mbeat: end_mbeat,
        end_ms: end_ms,
        end_beat: end_beat,
        duration_ms: duration_ms
      )

    ~H"""
    <section class="ui-radius-card border border-zinc-800 bg-zinc-900/50 p-3">
      <div class="mb-2 text-[11px] uppercase tracking-wide text-zinc-400">Timeline</div>

      <dl class="grid grid-cols-2 gap-x-4 gap-y-1 font-mono text-[11px] text-zinc-200">
        <dt class="text-zinc-500">Start beat</dt>
        <dd>
          bar {@timeline_context.start_beat.bar} beat {@timeline_context.start_beat.beat} mbeat {@timeline_context.start_beat.mbeat}
        </dd>

        <dt class="text-zinc-500">Start mbeat</dt>
        <dd>{@start_mbeat}</dd>

        <dt class="text-zinc-500">Start ms</dt>
        <dd>{@start_ms}</dd>

        <dt class="text-zinc-500">End beat</dt>
        <dd>bar {@end_beat.bar} beat {@end_beat.beat} mbeat {@end_beat.mbeat}</dd>

        <dt class="text-zinc-500">End mbeat</dt>
        <dd>{@end_mbeat}</dd>

        <dt class="text-zinc-500">End ms</dt>
        <dd>{@end_ms}</dd>

        <dt class="text-zinc-500">Duration mbeat</dt>
        <dd>{@duration_mbeats}</dd>

        <dt class="text-zinc-500">Duration beats</dt>
        <dd>{@duration_beats}</dd>

        <dt class="text-zinc-500">Duration ms</dt>
        <dd>{@duration_ms}</dd>
      </dl>
    </section>
    """
  end
end
