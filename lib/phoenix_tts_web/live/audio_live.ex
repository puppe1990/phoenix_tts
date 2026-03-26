defmodule PhoenixTtsWeb.AudioLive do
  use PhoenixTtsWeb, :live_view

  alias PhoenixTts.Audio

  def mount(_params, _session, socket) do
    voices = Audio.available_voices()
    remote_history = Audio.remote_history()
    models = Audio.available_models()

    form =
      Audio.change_generation(default_form_attrs(voices, models))
      |> to_form(as: :audio_generation)

    {:ok,
     socket
     |> assign(:page_title, "ElevenLabs Audio Studio")
     |> assign(:voices, voices)
     |> assign(:models, models)
     |> assign(:remote_history, remote_history)
     |> assign(:generations, Audio.list_generations())
     |> assign(:form, form)}
  end

  def handle_event("validate", %{"audio_generation" => params}, socket) do
    form =
      params
      |> Audio.change_generation()
      |> Map.put(:action, :validate)
      |> to_form(as: :audio_generation)

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"audio_generation" => params}, socket) do
    case Audio.create_generation(params) do
      {:ok, generation} ->
        form =
          Audio.change_generation(%{
            "voice_id" => params["voice_id"],
            "model_id" => params["model_id"],
            "output_format" => params["output_format"],
            "language_code" => params["language_code"],
            "text" => ""
          })
          |> to_form(as: :audio_generation)

        {:noreply,
         socket
         |> put_flash(:info, "Áudio gerado com sucesso.")
         |> assign(:form, form)
         |> assign(:generations, [generation | socket.assigns.generations])}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :audio_generation))}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="px-4 pb-14 pt-6 sm:px-6 lg:px-8 lg:pb-20">
        <div class="mx-auto flex w-full max-w-7xl flex-col gap-8">
          <section class="relative overflow-hidden rounded-[2rem] border border-white/10 bg-[#0b1325]/90 shadow-[0_40px_120px_rgba(0,0,0,0.45)]">
            <div class="absolute inset-0 bg-[radial-gradient(circle_at_top_left,rgba(255,184,120,0.16),transparent_26%),radial-gradient(circle_at_75%_20%,rgba(106,224,255,0.16),transparent_22%)]" />
            <div class="relative grid gap-6 p-5 sm:p-8 xl:grid-cols-[1.2fr_0.8fr] xl:p-10">
              <div class="flex flex-col justify-between">
                <div>
                  <div class="flex flex-wrap items-center gap-3">
                    <span class="rounded-full border border-[#f29c6b]/30 bg-[#f29c6b]/10 px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.28em] text-[#ffd4bd]">
                      LiveView + ElevenLabs
                    </span>
                    <span class="rounded-full border border-white/10 px-3 py-1 text-[11px] uppercase tracking-[0.28em] text-white/55">
                      Elixir {System.version()} / Phoenix {Application.spec(:phoenix, :vsn)}
                    </span>
                  </div>

                  <div class="mt-8 max-w-3xl">
                    <p class="text-sm uppercase tracking-[0.3em] text-[#7fd6e8]/70">
                      Studio de narração
                    </p>
                    <h1 class="mt-3 font-['Iowan_Old_Style','Palatino_Linotype','Book_Antiqua',serif] text-5xl font-semibold leading-[0.95] text-[#f7f1e8] sm:text-6xl xl:text-7xl">
                      ElevenLabs <br /> Audio Studio
                    </h1>
                    <p class="mt-6 max-w-2xl text-base leading-7 text-[#d6d0c7]/78 sm:text-lg">
                      Gere áudios em português com uma interface que prioriza texto, voz e playback sem esmagar a tela inteira num card estreito.
                    </p>
                  </div>

                  <div class="mt-8 grid gap-3 sm:grid-cols-3">
                    <div class="rounded-[1.5rem] border border-white/10 bg-white/[0.04] p-4">
                      <p class="text-[11px] uppercase tracking-[0.28em] text-white/45">Vozes</p>
                      <p class="mt-3 text-3xl font-semibold text-[#f7f1e8]">{length(@voices)}</p>
                      <p class="mt-1 text-sm text-white/55">sincronizadas no banco</p>
                    </div>
                    <div class="rounded-[1.5rem] border border-white/10 bg-white/[0.04] p-4">
                      <p class="text-[11px] uppercase tracking-[0.28em] text-white/45">Modelos</p>
                      <p class="mt-3 text-3xl font-semibold text-[#f7f1e8]">{length(@models)}</p>
                      <p class="mt-1 text-sm text-white/55">{hero_model_label(@models)}</p>
                    </div>
                    <div class="rounded-[1.5rem] border border-white/10 bg-white/[0.04] p-4">
                      <p class="text-[11px] uppercase tracking-[0.28em] text-white/45">
                        Histórico remoto
                      </p>
                      <p class="mt-3 text-3xl font-semibold text-[#f7f1e8]">
                        {length(@remote_history)}
                      </p>
                      <p class="mt-1 text-sm text-white/55">itens recentes da API</p>
                    </div>
                  </div>
                </div>

                <div class="mt-10 flex flex-wrap gap-3 text-xs uppercase tracking-[0.24em] text-white/45">
                  <span class="rounded-full border border-white/10 px-3 py-2">SQLite local</span>
                  <span class="rounded-full border border-white/10 px-3 py-2">Playback imediato</span>
                  <span class="rounded-full border border-white/10 px-3 py-2">Fluxo pt-BR</span>
                </div>
              </div>

              <div class="rounded-[1.75rem] border border-white/10 bg-[#08101f]/85 p-5 shadow-[inset_0_1px_0_rgba(255,255,255,0.05)] sm:p-6">
                <div class="flex items-center justify-between gap-3">
                  <div>
                    <p class="text-[11px] uppercase tracking-[0.28em] text-[#7fd6e8]/70">
                      Nova geração
                    </p>
                    <h2 class="mt-2 text-2xl font-semibold text-[#f7f1e8]">Enviar texto</h2>
                  </div>
                  <div class="rounded-full border border-white/10 px-3 py-1 text-[11px] uppercase tracking-[0.22em] text-white/45">
                    até 5.000 chars
                  </div>
                </div>

                <.form
                  for={@form}
                  id="tts-form"
                  class="mt-6 space-y-5"
                  phx-change="validate"
                  phx-submit="save"
                >
                  <.input
                    field={@form[:text]}
                    type="textarea"
                    label="Texto"
                    rows="9"
                    placeholder="Cole aqui o texto que será enviado para a ElevenLabs."
                    class="min-h-56 rounded-[1.4rem] border border-white/10 bg-[#111b2f] text-[#f7f1e8] placeholder:text-white/30"
                  />

                  <div class="grid gap-4 sm:grid-cols-2">
                    <.input
                      field={@form[:voice_id]}
                      type="text"
                      label="Voice ID"
                      placeholder="ex: voice_br"
                      class="rounded-[1.2rem] border border-white/10 bg-[#111b2f] text-[#f7f1e8] placeholder:text-white/30"
                    />
                    <.input
                      field={@form[:model_id]}
                      type="select"
                      label="Modelo"
                      options={Enum.map(@models, &{"#{&1.name}", &1.id})}
                      class="rounded-[1.2rem] border border-white/10 bg-[#111b2f] text-[#f7f1e8]"
                    />
                  </div>

                  <div class="grid gap-4 sm:grid-cols-2">
                    <.input
                      field={@form[:output_format]}
                      type="select"
                      label="Output format"
                      options={output_formats()}
                      class="rounded-[1.2rem] border border-white/10 bg-[#111b2f] text-[#f7f1e8]"
                    />
                    <.input
                      field={@form[:language_code]}
                      type="text"
                      label="Language code"
                      placeholder="pt"
                      class="rounded-[1.2rem] border border-white/10 bg-[#111b2f] text-[#f7f1e8] placeholder:text-white/30"
                    />
                  </div>

                  <button class="inline-flex w-full items-center justify-center rounded-full bg-[#7fe3f5] px-5 py-4 text-sm font-semibold uppercase tracking-[0.18em] text-[#07111f] transition hover:bg-[#a2edfa]">
                    Gerar áudio
                  </button>
                </.form>
              </div>
            </div>
          </section>

          <section class="grid gap-6 xl:grid-cols-[0.82fr_1.18fr]">
            <aside class="overflow-hidden rounded-[2rem] border border-white/10 bg-[#0a1120]/90">
              <div class="border-b border-white/10 px-5 py-5 sm:px-6">
                <div class="flex items-center justify-between gap-3">
                  <div>
                    <p class="text-[11px] uppercase tracking-[0.28em] text-[#7fd6e8]/70">
                      Vozes disponíveis
                    </p>
                    <h2 class="mt-2 text-2xl font-semibold text-[#f7f1e8]">Escolha rápida</h2>
                  </div>
                  <div class="rounded-full border border-white/10 px-3 py-1 text-[11px] uppercase tracking-[0.2em] text-white/50">
                    {length(@voices)} vozes
                  </div>
                </div>
              </div>

              <div class="max-h-[42rem] space-y-3 overflow-y-auto px-5 py-5 sm:px-6">
                <div
                  :if={Enum.empty?(@voices)}
                  class="rounded-[1.4rem] border border-[#f29c6b]/25 bg-[#f29c6b]/10 p-4 text-sm text-[#ffe0cf]"
                >
                  Configure `ELEVENLABS_API_KEY` para carregar automaticamente as vozes.
                </div>

                <button
                  :for={voice <- @voices}
                  type="button"
                  class="block w-full rounded-[1.4rem] border border-white/10 bg-white/[0.03] p-4 text-left transition hover:border-[#7fd6e8]/35 hover:bg-[#0f1b31]"
                >
                  <div class="flex items-start justify-between gap-4">
                    <div>
                      <p class="text-lg font-semibold text-[#f7f1e8]">{voice.name}</p>
                      <p class="mt-1 text-xs uppercase tracking-[0.18em] text-white/35">{voice.id}</p>
                    </div>
                    <span class="rounded-full border border-white/10 px-3 py-1 text-[11px] uppercase tracking-[0.16em] text-[#ffd4bd]">
                      {voice_category_label(voice.category)}
                    </span>
                  </div>
                  <div class="mt-4 flex items-center justify-between gap-3 text-sm text-white/55">
                    <span>{voice.labels["accent"] || "Sem accent"}</span>
                    <span class="text-[#7fd6e8]">catálogo</span>
                  </div>
                </button>
              </div>
            </aside>

            <div class="grid gap-6">
              <section class="rounded-[2rem] border border-white/10 bg-[#0a1120]/90 p-5 sm:p-6">
                <div class="flex flex-wrap items-center justify-between gap-3">
                  <div>
                    <p class="text-[11px] uppercase tracking-[0.28em] text-[#7fd6e8]/70">
                      History API
                    </p>
                    <h2 class="mt-2 text-2xl font-semibold text-[#f7f1e8]">
                      Itens recentes da ElevenLabs
                    </h2>
                  </div>
                  <div class="rounded-full border border-white/10 px-3 py-1 text-[11px] uppercase tracking-[0.2em] text-white/50">
                    {length(@remote_history)} itens
                  </div>
                </div>

                <div
                  :if={Enum.empty?(@remote_history)}
                  class="mt-6 rounded-[1.5rem] border border-dashed border-white/10 p-10 text-center text-white/45"
                >
                  Nenhum item remoto carregado.
                </div>

                <div :if={not Enum.empty?(@remote_history)} class="mt-6 grid gap-4 md:grid-cols-2">
                  <article
                    :for={item <- @remote_history}
                    class="rounded-[1.5rem] border border-white/10 bg-white/[0.03] p-5"
                  >
                    <div class="flex items-start justify-between gap-3">
                      <div>
                        <p class="text-[11px] uppercase tracking-[0.24em] text-[#7fd6e8]/70">
                          {item.voice_id}
                        </p>
                        <h3 class="mt-3 text-lg font-semibold leading-6 text-[#f7f1e8]">
                          {excerpt(item.text)}
                        </h3>
                      </div>
                      <span class="rounded-full border border-white/10 px-3 py-1 text-[11px] text-white/55">
                        {item.character_count_change_to || "?"} chars
                      </span>
                    </div>
                    <p class="mt-4 text-sm text-white/60">{item.model_id}</p>
                    <p class="mt-2 text-xs uppercase tracking-[0.14em] text-white/28">
                      {item.history_item_id}
                    </p>
                  </article>
                </div>
              </section>

              <section class="rounded-[2rem] border border-white/10 bg-[#0a1120]/90 p-5 sm:p-6">
                <div class="flex flex-wrap items-center justify-between gap-3">
                  <div>
                    <p class="text-[11px] uppercase tracking-[0.28em] text-[#7fd6e8]/70">Histórico</p>
                    <h2 class="mt-2 text-2xl font-semibold text-[#f7f1e8]">Últimos áudios</h2>
                  </div>
                  <div class="rounded-full border border-white/10 px-3 py-1 text-[11px] uppercase tracking-[0.2em] text-white/50">
                    {length(@generations)} locais
                  </div>
                </div>

                <div
                  :if={Enum.empty?(@generations)}
                  class="mt-6 rounded-[1.5rem] border border-dashed border-white/10 p-10 text-center text-white/45"
                >
                  Nenhum áudio gerado ainda
                </div>

                <div :if={not Enum.empty?(@generations)} class="mt-6 grid gap-4 lg:grid-cols-2">
                  <article
                    :for={generation <- @generations}
                    class="rounded-[1.5rem] border border-white/10 bg-white/[0.03] p-5"
                  >
                    <div class="flex items-start justify-between gap-3">
                      <div>
                        <p class="text-[11px] uppercase tracking-[0.24em] text-[#7fd6e8]/70">
                          {generation.voice_id}
                        </p>
                        <h3 class="mt-3 text-lg font-semibold leading-6 text-[#f7f1e8]">
                          {excerpt(generation.text)}
                        </h3>
                      </div>
                      <span class="rounded-full border border-white/10 px-3 py-1 text-[11px] text-white/55">
                        {generation.character_count} chars
                      </span>
                    </div>
                    <div class="mt-4 space-y-1 text-sm text-white/58">
                      <p>{generation.model_id}</p>
                      <p class="text-xs uppercase tracking-[0.14em] text-white/32">
                        {generation.request_id}
                      </p>
                      <p class="text-xs uppercase tracking-[0.14em] text-white/32">
                        {generation.output_format}
                      </p>
                    </div>
                    <audio
                      id={"audio-player-#{generation.id}"}
                      class="mt-4 w-full opacity-90"
                      controls
                    >
                      <source src={"/#{generation.audio_path}"} type={generation.content_type} />
                    </audio>
                    <a
                      href={"/#{generation.audio_path}"}
                      download
                      class="mt-4 inline-flex text-sm font-semibold text-[#7fd6e8] underline decoration-[#7fd6e8]/35 underline-offset-4"
                    >
                      baixar mp3
                    </a>
                  </article>
                </div>
              </section>
            </div>
          </section>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp default_form_attrs(voices, models) do
    %{
      "voice_id" => first_voice_id(voices) || "",
      "model_id" => first_model_id(models) || "",
      "output_format" => Audio.default_output_format(),
      "language_code" => "pt",
      "text" => ""
    }
  end

  defp excerpt(nil), do: "Sem texto disponível"

  defp excerpt(text) do
    text
    |> String.trim()
    |> String.slice(0, 72)
  end

  defp first_voice_id([%{id: id} | _]), do: id
  defp first_voice_id(_), do: nil

  defp first_model_id([%{id: id} | _]), do: id
  defp first_model_id(_), do: nil

  defp hero_model_label([model | _]), do: model.name
  defp hero_model_label(_), do: "sem catálogo"

  defp voice_category_label(nil), do: "voice"
  defp voice_category_label(value), do: value

  defp output_formats do
    [
      {"MP3 44.1kHz / 128kbps", "mp3_44100_128"},
      {"MP3 22.05kHz / 32kbps", "mp3_22050_32"},
      {"PCM 16kHz", "pcm_16000"},
      {"u-law 8kHz", "ulaw_8000"}
    ]
  end
end
