defmodule PhoenixTtsWeb.PageControllerTest do
  use PhoenixTtsWeb.ConnCase, async: true

  test "serves the openapi yaml", %{conn: conn} do
    conn = get(conn, ~p"/openapi.yaml")

    assert response(conn, 200) =~ "openapi: 3.1.0"
    assert response(conn, 200) =~ "title: PhoenixTts API"
    assert get_resp_header(conn, "content-type") == ["application/yaml; charset=utf-8"]
  end

  test "renders the api docs page", %{conn: conn} do
    conn = get(conn, ~p"/api-docs")
    html = html_response(conn, 200)

    assert html =~ "Integre o PhoenixTts por HTTP"
    assert html =~ "/openapi.yaml"
    assert html =~ "Swagger Editor"
  end

  test "serves the markdown api docs", %{conn: conn} do
    conn = get(conn, ~p"/api-docs.md")

    assert response(conn, 200) =~ "# API HTTP"
    assert response(conn, 200) =~ "POST /generations"
    assert get_resp_header(conn, "content-type") == ["text/markdown; charset=utf-8"]
  end
end
