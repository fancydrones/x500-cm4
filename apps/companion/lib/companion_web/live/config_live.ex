defmodule CompanionWeb.ConfigLive do
  use Phoenix.LiveView
  use PhoenixHTMLHelpers

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Companion.PubSub, "config_updates")
        Companion.K8sManager.request_configs()
      end
    end

    socket =
      socket
      |> assign(configs: [])

    {:ok, socket}
  end

  @impl true
  def handle_info({:configs, configs}, socket) do
    Logger.debug("Web got updated configs")

    socket =
      socket
      |> assign(configs: configs)

    {:noreply, socket}
  end

  @impl true
  def handle_event("save_config", %{"config" => update}, socket) do
    {key, value} =
      update
      |> Map.to_list()
      |> List.first()

    Logger.info("Key: #{key} -- Value: #{value}")

    Companion.K8sManager.update_config(key, value)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <CompanionWeb.Layouts.app flash={@flash}>
      <section class="phx-hero">
        <%= if length(@configs) > 0 do %>
          <h2>All configs</h2>
          <div class="config-cards-container">
            <%= for config <- @configs do %>
              <div class="config-card">
                <.form :let={f} for={%{}} as={:config} phx-submit="save_config">
                  <p class="config-key-header"><%= config.key %></p>
                  <div class="config-value-container">
                    <p class="config-original"><%= config.value %></p>
                    <%= textarea f, config.key, value: config.value, class: "config-editbox" %>
                  </div>
                  <%= submit "Save" %>
                </.form>
              </div>
            <% end %>
          </div>
        <% else %>
          <h2>No configs found</h2>
        <% end %>
      </section>
    </CompanionWeb.Layouts.app>
    """
  end
end
