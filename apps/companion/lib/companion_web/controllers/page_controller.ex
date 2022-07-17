defmodule CompanionWeb.PageController do
  use CompanionWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
