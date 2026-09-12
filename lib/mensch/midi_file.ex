defmodule Mensch.MidiFile do
  @moduledoc """
  Encodes rendered performances into a Standard MIDI File (SMF).

  The exporter writes MPE-relevant channel data as regular MIDI 1.0
  events per channel: Note On/Off, Channel Pressure, Pitch Bend, and
  CC74 (slide/timbre).
  """

  alias Mensch.Performance
  alias Mensch.SampleContext

  import Bitwise

  @spec from_performance(Performance.t(), SampleContext.t(), keyword()) :: binary()
  def from_performance(
        %Performance{} = performance,
        %SampleContext{} = sample_context,
        opts \\ []
      ) do
    ppq = SampleContext.ticks_per_beat(sample_context)

    channel_events =
      performance
      |> build_channel_events()
      |> maybe_trim_events(Keyword.get(opts, :trim_end_tick))

    setup_events = mpe_setup_events(channel_events)

    midi_events =
      [
        %{tick: 0, sort: {-1, -1, -1, -1}, bytes: tempo_meta(performance.bpm)},
        %{tick: 0, sort: {-1, -1, -1, 0}, bytes: time_signature_meta(performance.time_signature)}
      ] ++ setup_events ++ channel_events

    last_tick =
      case channel_events do
        [] -> 0
        _ -> channel_events |> Enum.map(& &1.tick) |> Enum.max()
      end

    track_data =
      midi_events
      |> with_end_of_track(last_tick)
      |> encode_track_events()

    encode_smf(0, ppq, [track_data])
  end

  @doc "Bitwig-friendly variant: SMF format 1 with one track per active channel."
  @spec from_performance_bitwig(Performance.t(), SampleContext.t(), keyword()) :: binary()
  def from_performance_bitwig(
        %Performance{} = performance,
        %SampleContext{} = sample_context,
        opts \\ []
      ) do
    ppq = SampleContext.ticks_per_beat(sample_context)

    channel_events =
      performance
      |> build_channel_events()
      |> maybe_trim_events(Keyword.get(opts, :trim_end_tick))

    setup_events = mpe_setup_events(channel_events)

    last_tick =
      case channel_events do
        [] -> 0
        _ -> channel_events |> Enum.map(& &1.tick) |> Enum.max()
      end

    channel_numbers =
      channel_events
      |> Enum.map(fn event -> status_channel(event_status(event.bytes)) end)
      |> Enum.uniq()
      |> Enum.sort()

    conductor_events =
      [
        %{tick: 0, sort: {-1, -1, -1, -1}, bytes: tempo_meta(performance.bpm)},
        %{tick: 0, sort: {-1, -1, -1, 0}, bytes: time_signature_meta(performance.time_signature)}
      ]
      |> Kernel.++(
        setup_events
        |> Enum.filter(fn event -> status_channel(event_status(event.bytes)) == 0 end)
      )

    conductor_track = encode_track_events(with_end_of_track(conductor_events, last_tick))

    channel_tracks =
      Enum.map(channel_numbers, fn channel ->
        events =
          [
            %{tick: 0, sort: {-1, -1, -1, -50}, bytes: track_name_meta("MPE Channel #{channel}")}
          ]
          |> Kernel.++(
            Enum.filter(setup_events, fn event ->
              status_channel(event_status(event.bytes)) == channel
            end)
          )
          |> Kernel.++(
            Enum.filter(channel_events, fn event ->
              status_channel(event_status(event.bytes)) == channel
            end)
          )

        encode_track_events(with_end_of_track(events, last_tick))
      end)

    tracks = [conductor_track | channel_tracks]
    encode_smf(1, ppq, tracks)
  end

  @spec mpe_report(Performance.t()) :: binary()
  def mpe_report(%Performance{} = performance) do
    header = "mbeat\tms\tchannel\tnote\ttype\tvalue_1\tvalue_2\n"

    rows =
      performance
      |> build_channel_events()
      |> Enum.map(fn %{tick: mbeat, at_ms: at_ms, label: label, bytes: bytes} ->
        {ch, note, type, v1, v2} = report_fields(label, bytes)
        "#{mbeat}\t#{at_ms}\t#{ch}\t#{note}\t#{type}\t#{v1}\t#{v2}\n"
      end)

    [header | rows] |> IO.iodata_to_binary()
  end

  defp build_channel_events(%Performance{music: music}) do
    music
    |> Enum.flat_map(fn frame ->
      mbeat = Map.get(frame, :at_mbeat, Map.get(frame, :at_tick, 0))
      at_ms = Map.get(frame, :at_ms, 0)

      Enum.flat_map(frame.notes, fn note ->
        ch = clamp_u7(Map.get(note, :channel, 0))
        midi_note = clamp_u7(Map.get(note, :note, 0))
        velocity = clamp_u7(Map.get(note, :velocity, 0))
        event_index = Map.get(note, :event_index, 999)

        events =
          []
          |> maybe_add(Map.get(note, :note_on, false), %{
            tick: mbeat,
            at_ms: at_ms,
            sort: {event_index, ch, midi_note, 1},
            label: :note_on,
            note: midi_note,
            bytes: <<0x90 + ch, midi_note, velocity>>
          })
          |> maybe_add(
            Map.get(note, :phase) != :pending and not Map.get(note, :note_off, false),
            %{
              tick: mbeat,
              at_ms: at_ms,
              sort: {event_index, ch, midi_note, 2},
              label: :pressure,
              note: midi_note,
              bytes: <<0xD0 + ch, clamp_u7(Map.get(note, :pressure, 0))>>
            }
          )
          |> maybe_add(
            Map.get(note, :phase) != :pending and not Map.get(note, :note_off, false),
            %{
              tick: mbeat,
              at_ms: at_ms,
              sort: {event_index, ch, midi_note, 3},
              label: :bend,
              note: midi_note,
              bytes: bend_bytes(ch, Map.get(note, :bend, 0.0))
            }
          )
          |> maybe_add(
            Map.get(note, :phase) != :pending and not Map.get(note, :note_off, false),
            %{
              tick: mbeat,
              at_ms: at_ms,
              sort: {event_index, ch, midi_note, 4},
              label: :slide,
              note: midi_note,
              bytes: <<0xB0 + ch, 74, clamp_u7(Map.get(note, :slide, 0))>>
            }
          )
          |> maybe_add(Map.get(note, :note_off, false), %{
            tick: mbeat,
            at_ms: at_ms,
            sort: {event_index, ch, midi_note, 5},
            label: :note_off,
            note: midi_note,
            bytes: <<0x80 + ch, midi_note, 0>>
          })

        events
      end)
    end)
    |> Enum.sort_by(fn %{tick: tick, sort: sort} -> {tick, sort} end)
  end

  defp encode_track_events(events) do
    {chunks, _last_tick} =
      events
      |> Enum.sort_by(fn %{tick: tick, sort: sort} -> {tick, sort} end)
      |> Enum.reduce({[], 0}, fn %{tick: tick, bytes: bytes}, {acc, last_tick} ->
        delta = max(tick - last_tick, 0)
        {[acc, vlq(delta), bytes], tick}
      end)

    IO.iodata_to_binary(chunks)
  end

  defp maybe_trim_events(events, nil), do: events

  defp maybe_trim_events(events, trim_end_tick)
       when is_integer(trim_end_tick) and trim_end_tick >= 0 do
    {trimmed_rev, active} =
      events
      |> Enum.sort_by(fn %{tick: tick, sort: sort} -> {tick, sort} end)
      |> Enum.reduce({[], %{}}, fn event, {acc, active} ->
        channel = status_channel(event_status(event.bytes))
        note = Map.get(event, :note)
        note_key = {channel, note}

        cond do
          event.tick <= trim_end_tick and event.label == :note_on ->
            {[event | acc], Map.put(active, note_key, true)}

          event.tick <= trim_end_tick and event.label == :note_off ->
            {[event | acc], Map.delete(active, note_key)}

          event.tick <= trim_end_tick ->
            {[event | acc], active}

          event.tick > trim_end_tick and event.label == :note_off and
              Map.has_key?(active, note_key) ->
            clipped = %{
              event
              | tick: trim_end_tick,
                at_ms: nil,
                sort: put_elem(event.sort, 3, 6)
            }

            {[clipped | acc], Map.delete(active, note_key)}

          true ->
            {acc, active}
        end
      end)

    forced_offs =
      active
      |> Map.keys()
      |> Enum.with_index(1)
      |> Enum.map(fn {{channel, note}, idx} ->
        %{
          tick: trim_end_tick,
          at_ms: nil,
          sort: {9_000, channel, note, idx},
          label: :note_off,
          note: note,
          bytes: <<0x80 + channel, note, 0>>
        }
      end)

    (Enum.reverse(trimmed_rev) ++ forced_offs)
    |> Enum.sort_by(fn %{tick: tick, sort: sort} -> {tick, sort} end)
  end

  defp maybe_trim_events(events, _trim_end_tick), do: events

  defp encode_smf(format, ppq, tracks) do
    track_count = length(tracks)

    header = "MThd" <> <<0, 0, 0, 6, format::16, track_count::16, ppq::16>>

    body =
      Enum.map(tracks, fn track_data ->
        "MTrk" <> <<byte_size(track_data)::32>> <> track_data
      end)

    IO.iodata_to_binary([header | body])
  end

  defp with_end_of_track(events, tick) do
    events ++ [%{tick: tick, sort: {9_999, 9_999, 9_999, 9_999}, bytes: end_of_track_meta()}]
  end

  defp tempo_meta(bpm) do
    mpqn = round(60_000_000 / max(bpm, 1))
    <<0xFF, 0x51, 0x03, mpqn::24>>
  end

  defp track_name_meta(name) when is_binary(name) do
    size = byte_size(name)
    <<0xFF, 0x03>> <> vlq(size) <> name
  end

  defp time_signature_meta({num, den}) do
    denom_pow = den |> max(1) |> Integer.digits(2) |> length() |> Kernel.-(1)
    <<0xFF, 0x58, 0x04, clamp_u7(num), clamp_u7(denom_pow), 24, 8>>
  end

  defp end_of_track_meta do
    <<0xFF, 0x2F, 0x00>>
  end

  defp mpe_setup_events(channel_events) do
    member_channels =
      channel_events
      |> Enum.map(&status_channel(event_status(&1.bytes)))
      |> Enum.filter(&(&1 >= 1 and &1 <= 15))
      |> Enum.uniq()
      |> Enum.sort()

    member_count = member_channels |> length() |> min(15)
    bend_range = Application.get_env(:mensch, :mpe_pitch_bend_range, 48)

    zone_events =
      rpn_messages(0, 0, 6, member_count, 0)
      |> Enum.with_index(1)
      |> Enum.map(fn {bytes, index} ->
        %{tick: 0, sort: {-1, -1, -1, 10 + index}, bytes: bytes}
      end)

    bend_events =
      ([0] ++ member_channels)
      |> Enum.flat_map(fn channel -> rpn_messages(channel, 0, 0, bend_range, 0) end)
      |> Enum.with_index(1)
      |> Enum.map(fn {bytes, index} ->
        %{tick: 0, sort: {-1, -1, -1, 30 + index}, bytes: bytes}
      end)

    zone_events ++ bend_events
  end

  defp rpn_messages(channel, rpn_msb, rpn_lsb, data_msb, data_lsb) do
    [
      <<0xB0 + channel, 101, clamp_u7(rpn_msb)>>,
      <<0xB0 + channel, 100, clamp_u7(rpn_lsb)>>,
      <<0xB0 + channel, 6, clamp_u7(data_msb)>>,
      <<0xB0 + channel, 38, clamp_u7(data_lsb)>>,
      <<0xB0 + channel, 101, 127>>,
      <<0xB0 + channel, 100, 127>>
    ]
  end

  defp event_status(<<status, _rest::binary>>), do: status
  defp event_status(_), do: 0

  defp bend_bytes(channel, bend) do
    bend_value = (8192 + bend * 8192) |> round() |> max(0) |> min(16_383)
    <<0xE0 + channel, rem(bend_value, 128), div(bend_value, 128)>>
  end

  defp report_fields(:note_on, <<status, note, velocity>>),
    do: {status_channel(status), note, "note_on", velocity, ""}

  defp report_fields(:note_off, <<status, note, _zero>>),
    do: {status_channel(status), note, "note_off", 0, ""}

  defp report_fields(:pressure, <<status, pressure>>),
    do: {status_channel(status), "", "pressure", pressure, ""}

  defp report_fields(:bend, <<status, lsb, msb>>) do
    value = msb * 128 + lsb
    centered = value - 8192
    {status_channel(status), "", "bend", centered, value}
  end

  defp report_fields(:slide, <<status, 74, value>>),
    do: {status_channel(status), "", "slide", value, ""}

  defp report_fields(_label, _bytes), do: {"", "", "unknown", "", ""}

  defp status_channel(status), do: rem(status, 16)

  defp maybe_add(events, true, event), do: [event | events]
  defp maybe_add(events, false, _event), do: events

  defp clamp_u7(value) when is_integer(value), do: value |> max(0) |> min(127)
  defp clamp_u7(value) when is_float(value), do: value |> round() |> clamp_u7()
  defp clamp_u7(_value), do: 0

  defp vlq(value) when is_integer(value) and value >= 0 do
    value
    |> do_vlq([band(value, 0x7F)])
    |> :erlang.list_to_binary()
  end

  defp do_vlq(value, acc) when value < 128, do: acc

  defp do_vlq(value, acc) do
    shifted = bsr(value, 7)
    byte = bor(band(shifted, 0x7F), 0x80)
    do_vlq(shifted, [byte | acc])
  end
end
