defmodule CompanionWeb.PageControllerTest do
  use CompanionWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, "/")
    assert html_response(conn, 200) =~ "Apps currently deployed:"
  end
end
