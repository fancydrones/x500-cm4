defmodule CompanionWeb.OverviewLive do
  use Phoenix.LiveView
  import Phoenix.HTML
  import Phoenix.HTML.Form
  use PhoenixHTMLHelpers

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Companion.PubSub, "deployment_updates")
      Phoenix.PubSub.subscribe(Companion.PubSub, "node_metrics_updates")
      Phoenix.PubSub.subscribe(Companion.PubSub, "pod_metrics_updates")
      Companion.K8sManager.request_deployments()
      Companion.K8sManager.request_node_metrics()
      Companion.K8sManager.request_pod_metrics()
    end

    socket =
      socket
      |> assign(deployments: [], nodes: [], pods_metrics: [])
    {:ok, socket}
  end

  @impl true
  def handle_event("restart_app", %{"app" => app}, socket) do
    Logger.info("Clicked restart app: #{app}")

    Companion.K8sManager.restart_deployment(app)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:deployments, deployments}, %{assigns: %{pods_metrics: pods_metrics}} = socket) do
    Logger.debug("Web got updated deployments")
    new_deployments = convert_deployments(deployments)
    new_deployments = add_metrics_to_deployments(new_deployments, pods_metrics)

    socket =
      socket
      |> assign(deployments: new_deployments)

    {:noreply, socket}
  end

  def handle_info({:node_metrics, node_metrics}, socket) do
    Logger.debug("Web got node metrics")
    socket =
      socket
      |> assign(nodes: convert_node(node_metrics))
    {:noreply, socket}
  end

  def handle_info({:pod_metrics, pod_metrics}, %{assigns: %{deployments: deployments}} = socket) do
    Logger.debug("Web got pod metrics")
    new_deployments = add_metrics_to_deployments(deployments, pod_metrics)

    socket =
      socket
      |> assign(pod_metrics: pod_metrics)
      |> assign(deployments: new_deployments)
    {:noreply, socket}
  end

  defp add_metrics_to_deployments([], _pod_metrics), do: []
  defp add_metrics_to_deployments(deployments, []), do: deployments

  defp add_metrics_to_deployments(deployments, pod_metrics) do
    deployments
    |> Enum.map(fn d ->
      case Enum.find(pod_metrics, fn p -> d.selector["app"] == p.labels["app"] end) do
        nil -> d
        p ->
          case Enum.find(p.containers, fn c -> c.name == d.name end) do
            nil -> d
            c ->
              %{
                d
                | cpu: scale_cpu(c.cpu),
                  memory: scale_memory(c.memory, "Mi"),
                  timestamp: p.timestamp
              }
          end
      end
    end)
  end

  defp convert_node(node_metrics) do
    Enum.map(node_metrics, fn n -> %{
          name: n.name,
          cpu: scale_cpu(n.cpu),
          memory: scale_memory(n.memory),
          timestamp: n.timestamp
        }
      end)
    |> Enum.sort_by(fn d -> d.name end)
  end

  defp scale_cpu(cpu) do
    l = String.length(cpu)
    {cpu, unit} = String.split_at(cpu, l - 1)
    String.to_integer(cpu) * get_unit_muliplier(unit) |> Float.round(3) |> to_string()
  end

  defp scale_memory(memory, print_unit \\ "Gi") do
    l = String.length(memory)
    {memory, unit} = String.split_at(memory, l - 2)
    value = String.to_integer(memory) * get_unit_muliplier(unit) / get_unit_muliplier(print_unit) |> Float.round(2) |> to_string()
    value <> print_unit
  end

  defp get_unit_muliplier(unit) do
    case unit do
      "n" -> 0.000000001
      "u" -> 0.000001
      "m" -> 0.001
      "k" -> 1000
      "M" -> 1000000
      "G" -> 1000000000
      "T" -> 1000000000000
      "P" -> 1000000000000000
      "E" -> 1000000000000000000
      "Z" -> 1000000000000000000000
      "Y" -> 1000000000000000000000000
      "Ki" -> 1024
      "Mi" -> 1048576
      "Gi" -> 1073741824
      "Ti" -> 1099511627776
      "Pi" -> 1125899906842624
      "Ei" -> 1152921504606846976
      "Zi" -> 1180591620717411303424
      "Yi" -> 1208925819614629174706176
      _ -> 1
    end
  end

  defp convert_deployments(deployments) do
    Enum.map(deployments, fn d -> %{
          name: d.name,
          image_version: d.image_version,
          replicas_from_spec: d.replicas_from_spec,
          ready_replicas: d.ready_replicas,
          backgrond_color: get_color_from_count(d.ready_replicas, d.replicas_from_spec),
          selector: d.selector,
          cpu: "",
          memory: "",
          timestamp: ""
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
                  <p class="card-paragraph"> CPU: <%= deployment.cpu %> </p>
                  <p class="card-paragraph"> Memory: <%= deployment.memory %> </p>
                  <p class="card-paragraph" style="font-size: small;">(<%= deployment.timestamp %>)</p>
                </div>
                <button class="card-button" phx-click="restart_app" phx-value-app={deployment.name} >Restart</button>
              </article>
            <% end %>
          <% else %>
            <h3>No apps found</h3>
          <% end %>
        </div>
      </section>
      <section class="phx-hero">
        <h1>Nodes:</h1>
        <div class="cards">
          <%= if length(@nodes) > 0 do %>
            <%= for node <- @nodes do %>
              <article class="card" style="background-color: blue;">
                <header>
                    <h2><%= node.name %></h2>
                </header>
                <div class="content" style="color: white;">
                  <p class="card-paragraph"> CPU: <%= node.cpu %> </p>
                  <p class="card-paragraph"> Memory: <%= node.memory %> </p>
                  <p class="card-paragraph" style="font-size: small;">(<%= node.timestamp %>)</p>
                </div>
              </article>
            <% end %>
          <% else %>
            <h3>No nodes found</h3>
          <% end %>
        </div>
      </section>
    """
  end

end
