defmodule CompanionWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.
  """
  use CompanionWeb, :html

  embed_templates("layouts/*")

  @doc """
  Renders the root layout (wraps all pages).
  This is set via put_root_layout in the router.
  """
  def root(assigns)

  @doc """
  Renders the app layout with header, navigation, and flash messages.
  """
  attr(:flash, :map, required: true)
  slot(:inner_block, required: true)

  def app(assigns)

  @doc """
  Renders flash notices.
  """
  attr(:flash, :map, required: true)
  attr(:id, :string, default: "flash-group")

  def flash_group(assigns) do
    ~H"""
    <div id={@id}>
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end

  @doc """
  Renders a single flash notice.
  """
  attr(:kind, :atom, values: [:info, :error], doc: "Type of flash message")
  attr(:flash, :map, required: true)
  attr(:rest, :global)

  def flash(assigns) do
    ~H"""
    <p
      :if={msg = Phoenix.Flash.get(@flash, @kind)}
      class={"alert alert-#{@kind}"}
      role="alert"
      phx-click="lv:clear-flash"
      phx-value-key={@kind}
      {@rest}
    >
      <%= msg %>
    </p>
    """
  end
end
