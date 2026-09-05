defmodule Mensch.ChordPlayer do
  @moduledoc """
  Plays one `%Mensch.Chord{}` live over MIDI.

  Starts one `Mensch.NotePlayer` child per chord tone, each on its own
  MPE member channel (checked out from `Mensch.Midi.ChannelPool`) with
  a distinct vibrato phase so their modulation is audibly independent
  (see `Mensch.Midi.Connection`).

  Reactive, not self-timed: each note self-schedules its own full
  attack/decay/sustain/release timeline from `:envelope` (see
  `Mensch.Envelope`) and stops itself when it's done, checking its own
  channel back in as it goes. This `ChordPlayer` just watches its
  notes exit one by one (via `:EXIT`, since they're linked) and stops
  itself once the last one is gone - so a whole chord fades out
  asynchronously and precisely, never blocking whatever plays next
  (see `Mensch.Sequencer`).

  An explicit `stop/1` (or any other forced shutdown, e.g. via
  `Mensch.ChordSupervisor.stop_chord/1`) is always instant: every
  still-alive note is stopped immediately, with no release fade -
  graceful release only ever happens for a note's own natural,
  self-timed end of life.

  Takes a `:chord` (`%Mensch.Chord{}`), an `:envelope`
  (`%Mensch.Envelope{}`), and an optional `:timing`
  (`%Mensch.Timing{}` snapshot of the global tempo/clock - defaults to
  `Mensch.Timing.now/0` if omitted). All notes share the exact same
  `:timing` snapshot and envelope milestones, so they move through
  their attack/decay/sustain/release phases in lockstep.
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

  alias Mensch.Chord
  alias Mensch.Envelope
  alias Mensch.Harmony.Scale
  alias Mensch.Midi.ChannelPool
  alias Mensch.NotePlayer
  alias Mensch.Timing

  defstruct [:chord, :envelope, :timing, :milestones, notes: []]

  @default_velocity 100

  # Client API

  @doc """
  Starts playing a chord. `opts` must include `:chord`
  (`%Mensch.Chord{}`) and `:envelope` (`%Mensch.Envelope{}`).
  Optionally takes `:timing` (`%Mensch.Timing{}`, defaults to
  `Mensch.Timing.now/0`).
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
  Returns how far along (0.0..1.0) this chord is through its own
  envelope, based on the global tempo/clock captured in `:timing` -
  or `nil` when `:duration_bars` is `0` (holds indefinitely, so it has
  no total duration to measure against).
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
    timing = Keyword.get(opts, :timing, Timing.now())
    milestones = Envelope.milestones(envelope, timing)

    tones = Chord.notes(chord)
    note_count = length(tones)
    channels = ChannelPool.checkout(note_count)

    notes =
      tones
      |> Enum.zip(channels)
      |> Enum.with_index()
      |> Enum.map(fn {{note, channel}, index} ->
        {:ok, pid} =
          NotePlayer.start_link(
            number: midi_note_number(note, chord.octave),
            channel: channel,
            velocity: @default_velocity,
            phase: index / max(note_count, 1) * 2 * :math.pi(),
            emphasis: index == 0,
            milestones: milestones
          )

        %{note: note, channel: channel, pid: pid}
      end)

    state = %__MODULE__{
      chord: chord,
      envelope: envelope,
      timing: timing,
      milestones: milestones,
      notes: notes
    }

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

  def handle_call(:progress, _from, %{milestones: %{total_ms: nil}} = state) do
    {:reply, nil, state}
  end

  def handle_call(:progress, _from, state) do
    percent = Timing.elapsed_ms(state.timing) / state.milestones.total_ms
    {:reply, percent |> max(0.0) |> min(1.0), state}
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

  defp midi_note_number(note, octave) do
    semitone = Enum.find_index(Scale.notes(), &(&1 == note))
    (octave + 1) * 12 + semitone
  end
end
