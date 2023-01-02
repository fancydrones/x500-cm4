defmodule Companion.Echo do
  use GenServer

  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(_) do
    #XMAVLink.Router.subscribe([source_system: 1])
    #XMAVLink.Router.subscribe([source_system: 1, source_component: 1, message: Common.Message.Heartbeat])
    XMAVLink.Router.subscribe([])
    {:ok, :nil}
  end

  #%Common.Message.Heartbeat

  def handle_info(msg, state) do
    Logger.debug("Got message: #{inspect(msg)}")
    {:noreply, state}
  end
end
