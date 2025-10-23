defmodule RouterEx.Endpoint.Supervisor do
  @moduledoc """
  Dynamic supervisor for managing endpoint connections.

  This supervisor manages all endpoint processes (Serial, UDP, TCP) with
  automatic restart and fault isolation. Each endpoint runs as an independent
  GenServer that can crash and restart without affecting other endpoints.

  ## Starting Endpoints

  Endpoints are started dynamically based on configuration:

      endpoint_config = %{
        name: "FlightController",
        type: :uart,
        device: "/dev/serial0",
        baud: 921_600
      }

      Supervisor.start_endpoint(endpoint_config)

  ## Endpoint Types

  - `:uart` - Serial UART connection (RouterEx.Endpoint.Serial)
  - `:udp_server` - UDP server listening for incoming messages
  - `:udp_client` - UDP client sending to specific address
  - `:tcp_server` - TCP server accepting connections
  - `:tcp_client` - TCP client connecting to specific address
  """

  use DynamicSupervisor
  require Logger

  @type endpoint_config :: %{
          required(:name) => String.t(),
          required(:type) => :uart | :udp_server | :udp_client | :tcp_server | :tcp_client,
          optional(:device) => String.t(),
          optional(:baud) => pos_integer(),
          optional(:address) => String.t(),
          optional(:port) => :inet.port_number(),
          optional(:allow_msg_ids) => [non_neg_integer()],
          optional(:block_msg_ids) => [non_neg_integer()]
        }

  ## Client API

  @doc """
  Starts the endpoint supervisor.

  This is already started by RouterEx.Application, you typically don't
  need to call this directly.
  """
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Starts a new endpoint based on configuration.

  Returns `{:ok, pid}` on success or `{:error, reason}` on failure.

  ## Examples

      iex> config = %{name: "FC", type: :uart, device: "/dev/ttyUSB0", baud: 57600}
      iex> RouterEx.Endpoint.Supervisor.start_endpoint(config)
      {:ok, #PID<0.123.0>}
  """
  @spec start_endpoint(endpoint_config()) :: DynamicSupervisor.on_start_child()
  def start_endpoint(config) do
    Logger.info("Starting endpoint: #{config.name} (#{config.type})")

    child_spec = endpoint_child_spec(config)
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  @doc """
  Stops an endpoint by connection ID.

  ## Examples

      iex> RouterEx.Endpoint.Supervisor.stop_endpoint({:uart, "FlightController"})
      :ok
  """
  @spec stop_endpoint(RouterEx.RouterCore.connection_id()) :: :ok | {:error, :not_found}
  def stop_endpoint(connection_id) do
    Logger.info("Stopping endpoint: #{inspect(connection_id)}")

    # Find the child process by connection_id
    children = DynamicSupervisor.which_children(__MODULE__)

    case Enum.find(children, fn {_id, pid, _type, _modules} ->
           pid != :undefined and get_connection_id(pid) == connection_id
         end) do
      {_id, pid, _type, _modules} ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Lists all running endpoints.

  Returns a list of `{connection_id, pid}` tuples.
  """
  @spec list_endpoints() :: [{RouterEx.RouterCore.connection_id(), pid()}]
  def list_endpoints do
    __MODULE__
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {_id, pid, _type, _modules} ->
      if pid != :undefined do
        {get_connection_id(pid), pid}
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  ## Supervisor Callbacks

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  ## Private Functions

  defp endpoint_child_spec(config) do
    case config.type do
      :uart ->
        {RouterEx.Endpoint.Serial, config}

      :udp_server ->
        {RouterEx.Endpoint.UdpServer, config}

      :udp_client ->
        {RouterEx.Endpoint.UdpClient, config}

      :tcp_server ->
        {RouterEx.Endpoint.TcpServer, config}

      :tcp_client ->
        {RouterEx.Endpoint.TcpClient, config}

      type ->
        raise ArgumentError, "Unknown endpoint type: #{inspect(type)}"
    end
  end

  defp get_connection_id(pid) when is_pid(pid) do
    # Each endpoint module should implement get_connection_id/0
    # For now, we'll use a catch-all approach
    try do
      GenServer.call(pid, :get_connection_id, 1000)
    catch
      :exit, _ -> nil
    end
  end
end
