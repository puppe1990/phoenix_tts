defmodule PhoenixTtsWeb.GenerationAudioControllerTest do
  use PhoenixTtsWeb.ConnCase, async: false

  alias PhoenixTts.Audio
  alias PhoenixTts.Repo
  alias PhoenixTts.Audio.Generation

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "phoenix-tts-generation-audio-#{System.unique_integer([:positive])}")

    Application.put_env(:phoenix_tts, :audio_storage_dir, tmp_dir)

    on_exit(fn ->
      File.rm_rf(tmp_dir)
      Application.delete_env(:phoenix_tts, :audio_storage_dir)
    end)

    :ok
  end

  test "streams local generation audio inline", %{conn: conn} do
    relative_path = Path.join("generated", "inline.mp3")
    absolute_path = Path.join(Audio.storage_dir(), relative_path)
    File.mkdir_p!(Path.dirname(absolute_path))
    File.write!(absolute_path, "LOCAL-MP3")

    generation =
      %Generation{}
      |> Generation.persistence_changeset(%{
        text: "Texto de teste para tocar áudio local.",
        voice_id: "voice_local",
        model_id: "model_local",
        output_format: "mp3_44100_128",
        language_code: "pt",
        audio_path: relative_path,
        character_count: 34,
        content_type: "audio/mpeg"
      })
      |> Repo.insert!()

    conn = get(conn, ~p"/generations/#{generation.id}/audio")

    assert response(conn, 200) == "LOCAL-MP3"
    assert get_resp_header(conn, "content-type") == ["audio/mpeg; charset=utf-8"]
    assert get_resp_header(conn, "content-disposition") == ["inline; filename=\"generation-#{generation.id}.mp3\""]
  end

  test "serves local generation audio as attachment when download is requested", %{conn: conn} do
    relative_path = Path.join("generated", "download.mp3")
    absolute_path = Path.join(Audio.storage_dir(), relative_path)
    File.mkdir_p!(Path.dirname(absolute_path))
    File.write!(absolute_path, "LOCAL-DOWNLOAD")

    generation =
      %Generation{}
      |> Generation.persistence_changeset(%{
        text: "Texto de teste para baixar áudio local.",
        voice_id: "voice_local",
        model_id: "model_local",
        output_format: "mp3_44100_128",
        language_code: "pt",
        audio_path: relative_path,
        character_count: 35,
        content_type: "audio/mpeg"
      })
      |> Repo.insert!()

    conn = get(conn, ~p"/generations/#{generation.id}/audio?download=1")

    assert response(conn, 200) == "LOCAL-DOWNLOAD"
    assert get_resp_header(conn, "content-disposition") == ["attachment; filename=\"generation-#{generation.id}.mp3\""]
  end

  test "redirects back with flash when local generation audio is missing", %{conn: conn} do
    conn = get(conn, ~p"/generations/999999/audio")

    assert redirected_to(conn) == ~p"/recentes"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Áudio local não encontrado."
  end
end
