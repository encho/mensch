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

  @doc "Applies a Program Mode tap, within the active project's active pattern."
  @spec apply_program_tap(t(), pos_integer(), pos_integer(), atom()) :: t()
  def apply_program_tap(%__MODULE__{} = app, track_id, step, selected_type) do
    update_active_project(app, &Project.apply_program_tap(&1, track_id, step, selected_type))
  end

  @doc "Locks `key`, within the active project's active pattern."
  @spec lock_param(t(), pos_integer(), pos_integer(), atom()) :: t()
  def lock_param(%__MODULE__{} = app, track_id, step, key) do
    update_active_project(app, &Project.lock_param(&1, track_id, step, key))
  end

  @doc "Clears the lock for `key`, within the active project's active pattern."
  @spec clear_lock(t(), pos_integer(), pos_integer(), atom()) :: t()
  def clear_lock(%__MODULE__{} = app, track_id, step, key) do
    update_active_project(app, &Project.clear_lock(&1, track_id, step, key))
  end

  @doc "Nudges a locked value, within the active project's active pattern."
  @spec adjust_lock(t(), pos_integer(), pos_integer(), atom(), :up | :down) :: t()
  def adjust_lock(%__MODULE__{} = app, track_id, step, key, direction) do
    update_active_project(app, &Project.adjust_lock(&1, track_id, step, key, direction))
  end

  @doc "Sets the active track, within the active project's active pattern."
  @spec set_active_track(t(), pos_integer()) :: t()
  def set_active_track(%__MODULE__{} = app, track_id) do
    update_active_project(app, &Project.set_active_track(&1, track_id))
  end

  defp update_active_project(%__MODULE__{projects: projects, active_project_id: active_id} = app, fun) do
    projects =
      Enum.map(projects, fn
        %Project{id: ^active_id} = project -> fun.(project)
        project -> project
      end)

    %{app | projects: projects}
  end
end
