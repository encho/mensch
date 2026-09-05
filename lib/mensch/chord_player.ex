defmodule Mensch.ChordPlayer do
  @moduledoc """
  Plays one `%Mensch.Chord{}` live over MIDI.

  Starts one `Mensch.NotePlayer` child per chord tone, each on its own
  MPE member channel (checked out from `Mensch.Midi.ChannelPool`) with
  a distinct vibrato phase so their modulation is audibly independent
  (see `Mensch.Midi.Connection`).

  Reactive, not self-timed: each note self-schedules its own full
  attack/decay/sustain/release timeline and stops itself when it's
  done, checking its own channel back in as it goes. This
  `ChordPlayer` just watches its notes exit one by one (via `:EXIT`,
  since they're linked) and stops itself once the last one is gone -
  so a whole chord fades out asynchronously and precisely, never
  blocking whatever plays next (see `Mensch.Sequencer`).

  There is deliberately no chord-level envelope here: which notes
  actually sound and what individual `%Mensch.Envelope{}` each of them
  gets is entirely decided by a pluggable `:machine` (see
  `Mensch.Machine`) - `ChordPlayer` itself never synthesizes or derives
  one note's envelope from another's, it just starts a `NotePlayer` for
  every entry the machine hands back.

  An explicit `stop/1` (or any other forced shutdown, e.g. via
  `Mensch.ChordSupervisor.stop_chord/1`) is always instant: every
  still-alive note is stopped immediately, with no release fade -
  graceful release only ever happens for a note's own natural,
  self-timed end of life.

  Takes a `:chord` (`%Mensch.Chord{}`), `:envelope` (the step's
  `%Mensch.Envelope{}`, handed to the machine to derive individual
  per-note envelopes from), `:machine` (an id from `Mensch.Machine.options/0`),
  and an optional `:timing` (`%Mensch.Timing{}` snapshot of the global
  tempo/clock - defaults to `Mensch.Timing.now/0` if omitted).
  """

  use GenServer

  # `ChordPlayer` is a one-shot, ephemeral worker: its lifecycle is
  # entirely explicit (started by `Mensch.ChordSupervisor.start_chord/1`,
  # stopped naturally when its notes finish or forcibly via `stop_chord/1`).
  # `use GenServer`'s default child_spec is `restart: :permanent`, which
  # would make `DynamicSupervisor` immediately restart it (with the same
  # stale opts/timing) every time it exits `:normal` - a restart storm
  # that can exceed the supervisor's max_restarts and take down every
  # other concurrently-playing chord with it. Never restart automatically.
  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, restart: :temporary}
  end

  alias Mensch.Envelope
  alias Mensch.Harmony.Scale
  alias Mensch.Machine
  alias Mensch.Midi.ChannelPool
  alias Mensch.NotePlayer
  alias Mensch.Timing

  defstruct [:chord, :timing, notes: []]

  @default_velocity 100

  # Client API

  @doc """
  Starts playing a chord. `opts` must include `:chord`
  (`%Mensch.Chord{}`), `:envelope` (`%Mensch.Envelope{}`), and
  `:machine` (an id from `Mensch.Machine.options/0`, deciding which
  notes sound and their individual envelopes). Optionally takes
  `:timing` (`%Mensch.Timing{}`, defaults to `Mensch.Timing.now/0`).
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Stops the chord instantly, stopping every note (sending note-off for each)."
  def stop(pid) do
    GenServer.stop(pid, :normal)
  end

  @doc """
  Returns a list of `%{note:, octave:, number:, channel:, pressure:, bend:}`
  maps, one per currently sounding note, in the same order as the
  chord's tones.
  """
  def snapshot(pid) do
    GenServer.call(pid, :snapshot)
  catch
    :exit, _ -> []
  end

  @doc """
  Returns how far along (0.0..1.0) this chord is, based on the global
  tempo/clock captured in `:timing` and the longest `:total_ms` among
  all its notes' own envelopes - i.e. once this reaches `1.0`, every
  note is expected to have finished on its own. Returns `nil` if every
  note holds indefinitely (no note has a `:total_ms` to measure
  against).
  """
  def progress(pid) do
    GenServer.call(pid, :progress)
  catch
    :exit, _ -> nil
  end

  # Server callbacks

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    chord = Keyword.fetch!(opts, :chord)
    envelope = Keyword.fetch!(opts, :envelope)
    machine = Keyword.fetch!(opts, :machine)
    timing = Keyword.get(opts, :timing, Timing.now())

    plan = Machine.generate(machine, chord, envelope)
    note_count = length(plan)
    channels = ChannelPool.checkout(note_count)

    notes =
      [plan, channels]
      |> Enum.zip()
      |> Enum.with_index()
      |> Enum.map(fn {{%{note: note, envelope: note_envelope, delay_bars: delay_bars}, channel},
                      index} ->
        milestones = Envelope.milestones(note_envelope, timing)
        delay_ms = Timing.bars_to_ms(timing, delay_bars)

        {:ok, pid} =
          NotePlayer.start_link(
            number: midi_note_number(note, chord.octave),
            channel: channel,
            velocity: @default_velocity,
            phase: index / max(note_count, 1) * 2 * :math.pi(),
            emphasis: index == 0,
            milestones: milestones,
            start_delay_ms: delay_ms
          )

        %{note: note, channel: channel, pid: pid, milestones: milestones, delay_ms: delay_ms}
      end)

    state = %__MODULE__{chord: chord, timing: timing, notes: notes}

    {:ok, state}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, state) do
    case Enum.find(state.notes, &(&1.pid == pid)) do
      nil ->
        # Not one of our own notes - e.g. our supervisor asking us to
        # shut down (an explicit `stop/1`/`stop_chord/1`, always
        # instant). Since we trap exits, that signal would otherwise
        # just sit here ignored until forcibly `:kill`ed 5s later,
        # bypassing `terminate/2` and leaking every still-checked-out
        # channel - so treat any exit we don't recognize as our own
        # cue to stop immediately (terminate/2 force-stops any
        # still-alive notes and returns their channels).
        {:stop, reason, state}

      %{channel: channel} = exited ->
        ChannelPool.checkin(channel)
        notes = Enum.map(state.notes, &if(&1 == exited, do: %{&1 | pid: nil}, else: &1))
        state = %{state | notes: notes}

        if Enum.all?(notes, &is_nil(&1.pid)) do
          {:stop, :normal, state}
        else
          {:noreply, state}
        end
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    notes_info =
      state.notes
      |> Enum.map(fn %{note: note, pid: pid} ->
        case pid && NotePlayer.snapshot(pid) do
          nil -> nil
          info -> Map.merge(info, %{note: note, octave: state.chord.octave})
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:reply, notes_info, state}
  end

  def handle_call(:progress, _from, state) do
    case chord_total_ms(state.notes) do
      nil ->
        {:reply, nil, state}

      total_ms ->
        percent = Timing.elapsed_ms(state.timing) / total_ms
        {:reply, percent |> max(0.0) |> min(1.0), state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.notes, fn %{pid: pid, channel: channel} ->
      if pid do
        if Process.alive?(pid), do: NotePlayer.stop(pid)
        ChannelPool.checkin(channel)
      end
    end)

    :ok
  end

  # The chord as a whole is considered "done" once its slowest note
  # finishes (accounting for that note's own start delay, e.g. from a
  # machine's stagger) - nil if every note holds indefinitely.
  defp chord_total_ms(notes) do
    totals =
      notes
      |> Enum.map(fn %{milestones: milestones, delay_ms: delay_ms} ->
        milestones.total_ms && delay_ms + milestones.total_ms
      end)
      |> Enum.reject(&is_nil/1)

    case totals do
      [] -> nil
      totals -> Enum.max(totals)
    end
  end

  defp midi_note_number(note, octave) do
    semitone = Enum.find_index(Scale.notes(), &(&1 == note))
    (octave + 1) * 12 + semitone
  end
end
