defmodule MenschWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use MenschWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :midi_status, :any,
    default: nil,
    doc: "current MIDI connection status, e.g. {:connected, name} or :disconnected"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="border-b border-white/15 px-4 sm:px-6 lg:px-8">
      <div class="mx-auto flex max-w-6xl items-center justify-between py-4">
        <a href="/" class="flex items-center gap-1.5">
          <img src={~p"/images/logo.svg"} width="20" />
          <span class="text-base font-bold text-white">mensch</span>
        </a>
        <div :if={@midi_status} class="relative">
          <button
            type="button"
            id="midi-status-button"
            phx-click={JS.toggle(to: "#midi-popup", display: "flex")}
            class="flex items-center gap-2 border border-white/20 px-3 py-1.5 text-xs uppercase tracking-wide text-white/70 hover:text-white"
          >
            <span class={["inline-block size-2.5 rounded-full", midi_status_dot_class(@midi_status)]} />
            Osmose
          </button>

          <div
            id="midi-popup"
            phx-click-away={JS.hide(to: "#midi-popup")}
            class="absolute right-0 top-full z-10 mt-3 hidden w-64 flex-col gap-3 border border-white/15 bg-black p-4"
          >
            <div class="flex items-center gap-2">
              <span class={[
                "inline-block size-2 rounded-full",
                midi_status_dot_class(@midi_status)
              ]} />
              <span class="font-mono text-sm text-white">
                {midi_status_label(@midi_status)}
              </span>
            </div>
            <button
              type="button"
              id="reconnect-midi"
              phx-click="reconnect_midi"
              class="border border-white/40 py-1.5 text-xs font-bold uppercase tracking-widest text-white transition-colors duration-150 hover:bg-white hover:text-black"
            >
              Reconnect
            </button>
          </div>
        </div>
      </div>
    </header>

    <main class="px-4 py-8 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-6xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  defp midi_status_dot_class({:connected, _name}), do: "bg-emerald-400"
  defp midi_status_dot_class(:disconnected), do: "bg-red-500"

  defp midi_status_label({:connected, name}), do: "Connected: #{name}"
  defp midi_status_label(:disconnected), do: "Disconnected"

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
