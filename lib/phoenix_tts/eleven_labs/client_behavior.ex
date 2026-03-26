defmodule PhoenixTts.ElevenLabs.ClientBehaviour do
  @callback synthesize_speech(String.t(), keyword()) ::
              {:ok,
               %{
                 audio: binary(),
                 content_type: String.t(),
                 request_id: String.t() | nil,
                 history_item_id: String.t() | nil,
                 character_count: integer() | nil
               }}
              | {:error, term()}
  @callback list_voices(map()) ::
              {:ok,
               %{voices: list(map()), has_more: boolean(), next_page_token: String.t() | nil}}
              | {:error, term()}
  @callback list_models() :: {:ok, list(map())} | {:error, term()}
  @callback list_history(map()) ::
              {:ok,
               %{items: list(map()), has_more: boolean(), last_history_item_id: String.t() | nil}}
              | {:error, term()}

  @callback get_history_audio(String.t()) ::
              {:ok, %{audio: binary(), content_type: String.t() | nil}} | {:error, term()}
end
