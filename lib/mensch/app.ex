defmodule Mensch.App do
  @moduledoc """
  Top-level in-memory application state.

  An app holds one or more projects, one of which is active.
  There is no persistence yet: state lives for the lifetime of the
  process that builds it (e.g. a LiveView's socket).
  """

  alias Mensch.Project

  defstruct [:active_project_id, projects: []]

  @type t :: %__MODULE__{projects: [Project.t()], active_project_id: pos_integer() | nil}

  @doc "Builds an app with a single default project."
  @spec new() :: t()
  def new do
    project = Project.new(1, "Untitled Project")
    %__MODULE__{projects: [project], active_project_id: project.id}
  end

  @doc "Returns the active project."
  @spec active_project(t()) :: Project.t() | nil
  def active_project(%__MODULE__{projects: projects, active_project_id: id}) do
    Enum.find(projects, &(&1.id == id))
  end

  @doc "Toggles the trig at `step` on `track_id`, within the active project's active pattern."
  @spec toggle_trig(t(), pos_integer(), pos_integer()) :: t()
  def toggle_trig(%__MODULE__{projects: projects, active_project_id: active_id} = app, track_id, step) do
    projects =
      Enum.map(projects, fn
        %Project{id: ^active_id} = project -> Project.toggle_trig(project, track_id, step)
        project -> project
      end)

    %{app | projects: projects}
  end

  @doc "Sets the active track, within the active project's active pattern."
  @spec set_active_track(t(), pos_integer()) :: t()
  def set_active_track(%__MODULE__{projects: projects, active_project_id: active_id} = app, track_id) do
    projects =
      Enum.map(projects, fn
        %Project{id: ^active_id} = project -> Project.set_active_track(project, track_id)
        project -> project
      end)

    %{app | projects: projects}
  end
end
