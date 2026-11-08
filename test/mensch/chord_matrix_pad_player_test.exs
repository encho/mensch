defmodule Mensch.ChordMatrixPadPlayerTest do
  use ExUnit.Case, async: true

  alias Mensch.ChordMatrixPadPlayer
  alias Mensch.Harmony.ChordMatrix
  alias Mensch.Harmony.ChordSpec
  alias Mensch.Performance

  setup do
    ChordMatrixPadPlayer.clear_cache()
    :ok
  end

  test "builds a one-pad performance using matrix frame_mbeats" do
    chord_matrix =
      new_matrix!(%{
        number_rows: 1,
        number_columns: 1,
        bpm: 120,
        frame_mbeats: 25,
        duration_mbeats: 4000,
        time_signature: {4, 4},
        machine: %{
          blueprint_id: "progression__steady_strum__strum1",
          additional_params: %{
            "velocity" => 92,
            "pressure_attack_mbeats" => 120.0,
            "pressure_curve" => "sine"
          }
        }
      })
      |> assign_chord!(0, 0, chord(:c, :maj7))

    record = %{id: "matrix-1", updated_at: "2026-11-08T00:00:00Z", chord_matrix: chord_matrix}

    assert {:ok, %Performance{} = performance} =
             ChordMatrixPadPlayer.performance_for_pad(record, 0, 0)

    assert performance.granularity_ms == 13
    assert performance.frames != []
  end

  test "returns pad_unassigned for empty pads" do
    chord_matrix = new_matrix!(%{number_rows: 1, number_columns: 1})
    record = %{id: "matrix-2", updated_at: "2026-11-08T00:00:00Z", chord_matrix: chord_matrix}

    assert {:error, :pad_unassigned} = ChordMatrixPadPlayer.performance_for_pad(record, 0, 0)
  end

  defp chord(root, quality) do
    ChordSpec.new!(%{
      harmonic_identity: %ChordSpec.HarmonicIdentity{root: root, quality: quality},
      octave: 3,
      inversion: 0
    })
  end

  defp new_matrix!(attrs) do
    case ChordMatrix.new(attrs) do
      {:ok, chord_matrix} -> chord_matrix
      {:error, reason} -> raise "invalid matrix for test: #{inspect(reason)}"
    end
  end

  defp assign_chord!(chord_matrix, row, column, %ChordSpec{} = chord_spec) do
    case ChordMatrix.assign_chord_to_pad(chord_matrix, row, column, chord_spec, %{}) do
      {:ok, updated} -> updated
      {:error, reason} -> raise "failed to assign test chord: #{inspect(reason)}"
    end
  end
end
