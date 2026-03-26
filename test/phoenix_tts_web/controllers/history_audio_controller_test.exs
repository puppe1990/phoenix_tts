defmodule PhoenixTtsWeb.HistoryAudioControllerTest do
  use PhoenixTtsWeb.ConnCase, async: false

  defmodule FakeElevenLabsClient do
    def get_history_audio("hist_remote_1") do
      {:ok, %{audio: "REMOTE-HISTORY-MP3", content_type: "audio/mpeg"}}
    end

    def get_history_audio(_history_item_id) do
      {:error, "Item não encontrado na ElevenLabs."}
    end

    def list_voices(_params \\ %{}), do: {:ok, %{voices: [], has_more: false, next_page_token: nil}}
    def list_models, do: {:ok, []}
    def list_history(_params \\ %{}), do: {:ok, %{items: [], has_more: false, last_history_item_id: nil}}
    def synthesize_speech(_text, _opts), do: {:error, :not_implemented}
  end

  setup do
    Application.put_env(:phoenix_tts, :elevenlabs_client, FakeElevenLabsClient)
    Application.put_env(:phoenix_tts, :elevenlabs_api_key, "test-key")

    on_exit(fn ->
      Application.delete_env(:phoenix_tts, :elevenlabs_client)
      Application.delete_env(:phoenix_tts, :elevenlabs_api_key)
    end)

    :ok
  end

  test "streams history audio inline", %{conn: conn} do
    conn = get(conn, ~p"/history/hist_remote_1/audio")

    assert response(conn, 200) == "REMOTE-HISTORY-MP3"
    assert get_resp_header(conn, "content-type") == ["audio/mpeg; charset=utf-8"]
    assert get_resp_header(conn, "content-disposition") == ["inline; filename=\"history-hist_remote_1.mp3\""]
  end

  test "serves history audio as attachment when download is requested", %{conn: conn} do
    conn = get(conn, ~p"/history/hist_remote_1/audio?download=1")

    assert response(conn, 200) == "REMOTE-HISTORY-MP3"
    assert get_resp_header(conn, "content-disposition") == ["attachment; filename=\"history-hist_remote_1.mp3\""]
  end

  test "redirects back with flash when history audio fails", %{conn: conn} do
    conn = get(conn, ~p"/history/missing/audio")

    assert redirected_to(conn) == ~p"/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Item não encontrado na ElevenLabs."
  end
end
