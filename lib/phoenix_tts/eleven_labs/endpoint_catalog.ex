defmodule PhoenixTts.ElevenLabs.EndpointCatalog do
  @docs_base "https://elevenlabs.io/docs"

  def list do
    [
      %{
        slug: "text-to-speech-convert",
        group: "Text to Speech",
        method: "POST",
        path: "/v1/text-to-speech/:voice_id",
        doc_url: "#{@docs_base}/api-reference/text-to-speech/convert",
        summary:
          "Converte texto em áudio e retorna bytes de áudio com headers de custo e request."
      },
      %{
        slug: "voices-search",
        group: "Voices",
        method: "GET",
        path: "/v1/voices/search",
        doc_url: "#{@docs_base}/api-reference/voices/search",
        summary: "Lista vozes com busca, filtros e paginação."
      },
      %{
        slug: "voices-clone-instant",
        group: "Voices",
        method: "POST",
        path: "/v1/voices/add",
        doc_url: "#{@docs_base}/api-reference/voices/add",
        summary:
          "Cria uma Instant Voice Clone a partir de uma ou mais amostras de áudio enviadas em multipart."
      },
      %{
        slug: "models-list",
        group: "Models",
        method: "GET",
        path: "/v1/models",
        doc_url: "#{@docs_base}/api-reference/models/list",
        summary:
          "Retorna o catálogo de modelos e capacidades como TTS e limite máximo por request."
      },
      %{
        slug: "history-list",
        group: "History",
        method: "GET",
        path: "/v1/history",
        doc_url: "#{@docs_base}/api-reference/history/list",
        summary: "Lista itens gerados com filtros por voz, modelo, data e busca."
      }
    ]
  end
end
