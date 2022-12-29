defmodule CompanionWeb.OverviewLive do
  use Phoenix.LiveView
  use Phoenix.HTML

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Companion.PubSub, "deployment_updates")
      Companion.K8sManager.request_deployments()
    end

    socket =
      socket
      |> assign(deployments: [])
    {:ok, socket}
  end

  @impl true
  def handle_event("restart_app", %{"app" => app}, socket) do
    Logger.info("Clicked restart app: #{app}")

    Companion.K8sManager.restart_deployment(app)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:deployments, deployments}, socket) do
    Logger.debug("Web got updated deployments")
    socket =
      socket
      |> assign(deployments: convert_deployments(deployments))
    {:noreply, socket}
  end

  defp convert_deployments(deployments) do
    Enum.map(deployments, fn d -> %{
          name: d.name,
          image_version: d.image_version,
          replicas_from_spec: d.replicas_from_spec,
          ready_replicas: d.ready_replicas,
          backgrond_color: get_color_from_count(d.ready_replicas, d.replicas_from_spec)
        }
      end)
    |> Enum.sort_by(fn d -> d.name end)
  end

  defp get_color_from_count(ready_replicat, expected_replicas) do
    if ready_replicat < expected_replicas do
      "background-color: red;"
    else
      "background-color: green;"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
      <section class="phx-hero">
        <h1>Apps currently deployed:</h1>
        <div class="cards">
          <%= if length(@deployments) > 0 do %>
            <%= for deployment <- @deployments do %>
              <article class="card" style={deployment.backgrond_color}>
                <header>
                    <h2><%= deployment.name %></h2>
                </header>
                <div class="content">
                  <p class="card-paragraph"> Version: <%= deployment.image_version %> </p>
                  <p class="card-paragraph"> Replicas: <%= deployment.ready_replicas %>/<%= deployment.replicas_from_spec %> </p>
                </div>
                  <button class="card-button" phx-click="restart_app" phx-value-app={deployment.name} >Restart</button>
              </article>
            <% end %>
          <% else %>
            <h3>No apps found</h3>
          <% end %>
        </div>
      </section>
    """
  end

end
