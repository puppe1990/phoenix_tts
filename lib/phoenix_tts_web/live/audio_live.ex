defmodule PhoenixTtsWeb.AudioLive do
  use PhoenixTtsWeb, :live_view

  alias PhoenixTts.Audio

  @max_chars 5_000

  def mount(_params, _session, socket) do
    voices = Audio.available_voices()
    remote_history = Audio.remote_history()
    models = Audio.available_models()
    form_attrs = default_form_attrs(voices, models)

    {:ok,
     socket
     |> assign(:page_title, "ElevenLabs Audio Studio")
     |> assign(:voices, voices)
     |> assign(:models, models)
     |> assign(:remote_history, remote_history)
     |> assign(:generations, Audio.list_generations())
     |> assign(:recent_generation_id, nil)
     |> assign(:advanced_open, false)
     |> assign(:form_feedback, nil)
     |> assign(:max_chars, @max_chars)
     |> assign(:api_key_configured, Audio.api_key_configured?())
     |> assign_form(form_attrs)}
  end

  def handle_event("validate", %{"audio_generation" => params}, socket) do
    {:noreply,
     socket
     |> assign(:form_feedback, nil)
     |> assign_form(params)}
  end

  def handle_event("save", %{"audio_generation" => params}, socket) do
    case Audio.create_generation(params) do
      {:ok, generation} ->
        preserved_attrs =
          params
          |> normalize_form_attrs()
          |> Map.put("text", "")

        {:noreply,
         socket
         |> put_flash(:info, "Áudio gerado com sucesso.")
         |> assign(:recent_generation_id, generation.id)
         |> assign(:form_feedback, {:info, "Áudio pronto. A última configuração foi mantida para a próxima geração."})
         |> assign_form(preserved_attrs)
         |> assign(:generations, [generation | socket.assigns.generations])}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:form_feedback, {:error, feedback_message(changeset)})
         |> assign(:form_attrs, normalize_form_attrs(params))
         |> assign(:form, to_form(changeset, as: :audio_generation))}
    end
  end

  def handle_event("select_voice", %{"voice_id" => voice_id}, socket) do
    attrs =
      socket.assigns.form_attrs
      |> Map.put("voice_id", voice_id)

    {:noreply,
     socket
     |> assign(:form_feedback, nil)
     |> assign_form(attrs)}
  end

  def handle_event("toggle_advanced", _params, socket) do
    {:noreply, update(socket, :advanced_open, &(!&1))}
  end

  def handle_event("reuse_generation", %{"id" => id}, socket) do
    generation =
      Enum.find(socket.assigns.generations, fn generation ->
        Integer.to_string(generation.id) == id
      end)

    socket =
      if generation do
        attrs = %{
          "text" => socket.assigns.form_attrs["text"] || "",
          "voice_id" => generation.voice_id,
          "model_id" => generation.model_id,
          "output_format" => generation.output_format,
          "language_code" => generation.language_code || ""
        }

        socket
        |> assign(:advanced_open, true)
        |> assign(:form_feedback, {:info, "Configuração reaplicada. Ajuste o texto e gere novamente."})
        |> assign_form(attrs)
      else
        socket
      end

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="px-4 pb-14 pt-6 sm:px-6 lg:px-8 lg:pb-20">
        <div class="mx-auto flex w-full max-w-7xl flex-col gap-8">
          <section class="relative overflow-hidden rounded-[2rem] border border-white/10 bg-[#0b1325]/90 shadow-[0_40px_120px_rgba(0,0,0,0.45)]">
            <div class="absolute inset-0 bg-[radial-gradient(circle_at_top_left,rgba(255,184,120,0.16),transparent_26%),radial-gradient(circle_at_75%_20%,rgba(106,224,255,0.16),transparent_22%)]" />
            <div class="relative p-5 sm:p-8 xl:p-10">
              <div class="mx-auto max-w-5xl rounded-[1.9rem] border border-white/10 bg-[#08101f]/88 p-6 shadow-[inset_0_1px_0_rgba(255,255,255,0.06)] sm:p-8 xl:p-10">
                <div class="flex flex-col gap-6 border-b border-white/10 pb-6 sm:flex-row sm:items-end sm:justify-between">
                  <div class="max-w-3xl">
                    <p class="text-[11px] font-semibold uppercase tracking-[0.3em] text-[#7fd6e8]/70">
                      Nova geração
                    </p>
                    <h1 class="mt-3 font-['Iowan_Old_Style','Palatino_Linotype','Book_Antiqua',serif] text-4xl font-semibold leading-none text-[#f7f1e8] sm:text-5xl">
                      Transforme texto em voz
                    </h1>
                    <p class="mt-4 text-base leading-7 text-[#d6d0c7]/72 sm:text-lg">
                      Fluxo direto para operação: texto, voz, modelo e saída pronta sem ruído de integração.
                    </p>
                  </div>

                  <div class="flex flex-wrap gap-3 text-xs uppercase tracking-[0.22em] text-white/42">
                    <span class="rounded-full border border-white/10 px-3 py-2">
                      {character_count(@form_attrs["text"])} / {@max_chars} chars
                    </span>
                    <span class="rounded-full border border-white/10 px-3 py-2">
                      {character_usage_label(@form_attrs["text"])}
                    </span>
                  </div>
                </div>

                <div
                  :if={not @api_key_configured}
                  class="mt-6 rounded-[1.5rem] border border-[#f29c6b]/30 bg-[#f29c6b]/10 p-4 text-sm text-[#ffe0cf]"
                >
                  <p class="font-semibold uppercase tracking-[0.14em] text-[#ffd9c9]">
                    ElevenLabs não configurado
                  </p>
                  <p class="mt-2 leading-6">
                    Defina `ELEVENLABS_API_KEY` no arquivo `.env` para liberar a geração e o carregamento automático do catálogo.
                  </p>
                </div>

                <div
                  :if={@form_feedback}
                  class={[
                    "mt-6 rounded-[1.5rem] border p-4 text-sm leading-6",
                    feedback_class(elem(@form_feedback, 0))
                  ]}
                >
                  {elem(@form_feedback, 1)}
                </div>

                <.form
                  for={@form}
                  id="tts-form"
                  class="mt-6 space-y-6"
                  phx-change="validate"
                  phx-submit="save"
                >
                  <div class="grid gap-6 xl:grid-cols-[1.25fr_0.75fr]">
                    <div class="rounded-[1.45rem] border border-white/8 bg-white/[0.02] p-4">
                      <div class="flex items-center justify-between gap-4">
                        <label for={@form[:text].id} class="text-sm font-semibold text-[#f7f1e8]">
                          Texto
                        </label>
                        <div class="text-right">
                          <p class="text-xs uppercase tracking-[0.18em] text-white/38">
                            consumo estimado
                          </p>
                          <p class="mt-1 text-sm font-medium text-[#7fd6e8]">
                            {character_count(@form_attrs["text"])} / {@max_chars}
                          </p>
                        </div>
                      </div>

                      <.input
                        field={@form[:text]}
                        type="textarea"
                        rows="8"
                        placeholder="Cole aqui o texto que será enviado para a ElevenLabs."
                        class="mt-3 min-h-52 w-full rounded-[1.6rem] border border-white/10 bg-[linear-gradient(180deg,#10192d_0%,#0c1527_100%)] px-5 py-4 text-base leading-7 text-[#f7f1e8] placeholder:text-white/28"
                      />

                      <div class="mt-3 flex flex-wrap items-center justify-between gap-3 text-xs">
                        <span class="uppercase tracking-[0.18em] text-white/34">
                          limite prático para operação rápida
                        </span>
                        <span class={["font-semibold", usage_color(@form_attrs["text"])]}>
                          {character_usage_hint(@form_attrs["text"])}
                        </span>
                      </div>
                    </div>

                    <div class="space-y-4">
                      <div class="rounded-[1.45rem] border border-white/8 bg-white/[0.02] p-4">
                        <p class="text-xs uppercase tracking-[0.22em] text-[#7fd6e8]/70">
                          Básico
                        </p>

                        <.input
                          field={@form[:voice_id]}
                          type="select"
                          label="Voz"
                          options={voice_options(@voices)}
                          prompt={voice_prompt(@voices)}
                          class="rounded-[1.1rem] border border-white/10 bg-[#111b2f] px-4 py-3 text-[#f7f1e8]"
                        />

                        <.input
                          field={@form[:model_id]}
                          type="select"
                          label="Modelo"
                          options={Enum.map(@models, &{"#{&1.name}", &1.id})}
                          prompt={model_prompt(@models)}
                          class="rounded-[1.1rem] border border-white/10 bg-[#111b2f] px-4 py-3 text-[#f7f1e8]"
                        />

                        <.input
                          field={@form[:language_code]}
                          type="select"
                          label="Idioma"
                          options={language_options()}
                          class="rounded-[1.1rem] border border-white/10 bg-[#111b2f] px-4 py-3 text-[#f7f1e8]"
                        />

                        <div class="rounded-[1.2rem] border border-white/10 bg-[#0d1729] px-4 py-3 text-sm text-white/60">
                          <p class="font-medium text-[#f7f1e8]">Última configuração usada</p>
                          <p class="mt-2 leading-6">
                            {summary_voice(@voices, @form_attrs["voice_id"])} • {summary_model(@models, @form_attrs["model_id"])} • {summary_language(@form_attrs["language_code"])} • {summary_output(@form_attrs["output_format"])}
                          </p>
                        </div>
                      </div>

                      <div class="rounded-[1.45rem] border border-white/8 bg-white/[0.02] p-4">
                        <button
                          type="button"
                          phx-click="toggle_advanced"
                          class="flex w-full items-center justify-between text-left"
                        >
                          <div>
                            <p class="text-xs uppercase tracking-[0.22em] text-[#7fd6e8]/70">
                              Avançado
                            </p>
                            <p class="mt-1 text-sm text-white/58">
                              Output, idioma e Voice ID manual quando necessário.
                            </p>
                          </div>
                          <span class="text-xs uppercase tracking-[0.18em] text-white/38">
                            {if @advanced_open, do: "ocultar", else: "mostrar"}
                          </span>
                        </button>

                        <div :if={not @advanced_open}>
                          <.input field={@form[:output_format]} type="hidden" />
                        </div>

                        <div :if={@advanced_open} class="mt-4 space-y-3 border-t border-white/10 pt-4">
                          <.input
                            field={@form[:output_format]}
                            type="select"
                            label="Output format"
                            options={output_formats()}
                            class="rounded-[1.1rem] border border-white/10 bg-[#111b2f] px-4 py-3 text-[#f7f1e8]"
                          />

                          <div :if={Enum.empty?(@voices)}>
                            <.input
                              field={@form[:voice_id]}
                              type="text"
                              label="Voice ID manual"
                              placeholder="ex: voice_br"
                              class="rounded-[1.1rem] border border-white/10 bg-[#111b2f] px-4 py-3 text-[#f7f1e8] placeholder:text-white/30"
                            />
                          </div>

                          <div
                            :if={not Enum.empty?(@voices)}
                            class="rounded-[1.2rem] border border-white/10 bg-[#0d1729] px-4 py-3 text-sm text-white/58"
                          >
                            <p class="font-medium text-[#f7f1e8]">Voice ID atual</p>
                            <p class="mt-2 break-all">{@form_attrs["voice_id"]}</p>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>

                  <div
                    :if={Enum.empty?(@voices)}
                    class="rounded-[1.45rem] border border-dashed border-white/10 px-4 py-4 text-sm text-white/50"
                  >
                    Nenhuma voz carregada. Se a API estiver configurada, verifique a resposta da ElevenLabs ou use o `Voice ID manual` no bloco avançado.
                  </div>

                  <div
                    :if={Enum.empty?(@models)}
                    class="rounded-[1.45rem] border border-dashed border-white/10 px-4 py-4 text-sm text-white/50"
                  >
                    Nenhum modelo foi carregado. A geração fica bloqueada até o catálogo de modelos responder.
                  </div>

                  <div class="flex flex-col gap-4 border-t border-white/10 pt-5 lg:flex-row lg:items-center lg:justify-between">
                    <div>
                      <p class="text-sm font-medium text-white/58">
                        O áudio entra no histórico local com player, download e reaproveitamento de configuração.
                      </p>
                      <p class="mt-1 text-xs uppercase tracking-[0.2em] text-white/30">
                        submit com trava visual e persistência local
                      </p>
                    </div>

                    <button
                      type="submit"
                      phx-disable-with="Gerando áudio..."
                      disabled={submit_disabled?(@api_key_configured, @models, @form_attrs)}
                      class="inline-flex w-full items-center justify-center rounded-full bg-[#7fe3f5] px-8 py-4 text-sm font-semibold uppercase tracking-[0.18em] text-[#07111f] transition hover:bg-[#a2edfa] disabled:cursor-not-allowed disabled:opacity-50 lg:w-auto lg:min-w-72"
                    >
                      Gerar áudio
                    </button>
                  </div>
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
                  phx-click="select_voice"
                  phx-value-voice_id={voice.id}
                  class={[
                    "block w-full rounded-[1.4rem] border p-4 text-left transition",
                    selected_voice?(voice.id, @form_attrs) &&
                      "border-[#7fd6e8]/50 bg-[#0f1b31] shadow-[0_0_0_1px_rgba(127,214,232,0.15)]",
                    not selected_voice?(voice.id, @form_attrs) &&
                      "border-white/10 bg-white/[0.03] hover:border-[#7fd6e8]/35 hover:bg-[#0f1b31]"
                  ]}
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
                    <span class={if selected_voice?(voice.id, @form_attrs), do: "text-[#7fd6e8]", else: "text-white/40"}>
                      {if selected_voice?(voice.id, @form_attrs), do: "selecionada", else: "clique para usar"}
                    </span>
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
                    <p class="mt-2 text-xs text-white/30">{remote_history_datetime(item.date_unix)}</p>
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
                    class={[
                      "rounded-[1.5rem] border bg-white/[0.03] p-5",
                      generation_class(generation.id, @recent_generation_id)
                    ]}
                  >
                    <div class="flex items-start justify-between gap-3">
                      <div>
                        <p class="text-[11px] uppercase tracking-[0.24em] text-[#7fd6e8]/70">
                          {summary_voice(@voices, generation.voice_id)}
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
                      <p>{summary_model(@models, generation.model_id)}</p>
                      <p>{summary_language(generation.language_code)}</p>
                      <p>{summary_output(generation.output_format)}</p>
                      <p class="text-xs text-white/30">{local_datetime(generation.inserted_at)}</p>
                    </div>
                    <audio
                      id={"audio-player-#{generation.id}"}
                      class="mt-4 w-full opacity-90"
                      controls
                    >
                      <source src={"/#{generation.audio_path}"} type={generation.content_type} />
                    </audio>
                    <div class="mt-4 flex flex-wrap items-center gap-4">
                      <button
                        type="button"
                        phx-click="reuse_generation"
                        phx-value-id={generation.id}
                        class="text-sm font-semibold text-[#7fd6e8] underline decoration-[#7fd6e8]/35 underline-offset-4"
                      >
                        usar novamente esta configuração
                      </button>
                      <a
                        href={"/#{generation.audio_path}"}
                        download
                        class="text-sm font-semibold text-[#7fd6e8] underline decoration-[#7fd6e8]/35 underline-offset-4"
                      >
                        baixar mp3
                      </a>
                    </div>

                    <details class="mt-4 rounded-[1.2rem] border border-white/10 bg-[#0d1729] px-4 py-3 text-sm text-white/58">
                      <summary class="cursor-pointer list-none font-medium text-[#f7f1e8]">
                        Detalhes técnicos
                      </summary>
                      <div class="mt-3 space-y-2 text-xs uppercase tracking-[0.14em] text-white/38">
                        <p>Voice ID: {generation.voice_id}</p>
                        <p>Request ID: {generation.request_id || "sem request id"}</p>
                        <p>History item: {generation.remote_history_item_id || "sem history item"}</p>
                      </div>
                    </details>
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

  defp assign_form(socket, attrs) do
    normalized = normalize_form_attrs(attrs)

    socket
    |> assign(:form_attrs, normalized)
    |> assign(
      :form,
      normalized
      |> Audio.change_generation()
      |> to_form(as: :audio_generation)
    )
  end

  defp normalize_form_attrs(attrs) do
    %{
      "text" => Map.get(attrs, "text", ""),
      "voice_id" => Map.get(attrs, "voice_id", ""),
      "model_id" => Map.get(attrs, "model_id", ""),
      "output_format" => Map.get(attrs, "output_format", Audio.default_output_format()),
      "language_code" => Map.get(attrs, "language_code", "pt")
    }
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

  defp feedback_message(changeset) do
    cond do
      text_error = first_error(changeset, :text) ->
        "Revise o texto antes de gerar: #{text_error}"

      voice_error = first_error(changeset, :voice_id) ->
        "Selecione uma voz válida para continuar: #{voice_error}"

      model_error = first_error(changeset, :model_id) ->
        "Escolha um modelo disponível para continuar: #{model_error}"

      true ->
        "Não foi possível gerar o áudio. Revise os campos e tente novamente."
    end
  end

  defp first_error(changeset, field) do
    case Keyword.get_values(changeset.errors, field) do
      [{message, opts} | _] -> translate_error({message, opts})
      _ -> nil
    end
  end

  defp submit_disabled?(api_key_configured, models, attrs) do
    not api_key_configured or Enum.empty?(models) or blank?(attrs["voice_id"]) or blank?(attrs["model_id"])
  end

  defp blank?(value), do: value in [nil, ""]

  defp selected_voice?(voice_id, form_attrs), do: form_attrs["voice_id"] == voice_id

  defp voice_options(voices), do: Enum.map(voices, &{"#{&1.name} (#{&1.id})", &1.id})
  defp voice_prompt([]), do: "Nenhuma voz carregada"
  defp voice_prompt(_voices), do: nil

  defp model_prompt([]), do: "Nenhum modelo disponível"
  defp model_prompt(_models), do: nil

  defp summary_voice(voices, voice_id) do
    case Enum.find(voices, &(&1.id == voice_id)) do
      nil when voice_id in [nil, ""] -> "Sem voz selecionada"
      nil -> "Voice ID #{voice_id}"
      voice -> voice.name
    end
  end

  defp summary_model(models, model_id) do
    case Enum.find(models, &(&1.id == model_id)) do
      nil when model_id in [nil, ""] -> "Sem modelo selecionado"
      nil -> model_id
      model -> model.name
    end
  end

  defp summary_output(output_format) do
    case Enum.find(output_formats(), fn {_label, value} -> value == output_format end) do
      {label, _value} -> label
      nil when output_format in [nil, ""] -> "Formato padrão"
      nil -> output_format
    end
  end

  defp summary_language(language_code) do
    case Enum.find(language_options(), fn {_label, value} -> value == language_code end) do
      {label, _value} -> label
      nil when language_code in [nil, ""] -> "Idioma automático"
      nil -> language_code
    end
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

  defp language_options do
    [
      {"Português", "pt"},
      {"Inglês", "en"},
      {"Espanhol", "es"},
      {"Francês", "fr"},
      {"Italiano", "it"},
      {"Alemão", "de"},
      {"Japonês", "ja"}
    ]
  end

  defp character_count(text), do: text |> to_string() |> String.length()

  defp character_usage_label(text) do
    ratio = usage_ratio(text)

    cond do
      ratio >= 0.9 -> "perto do limite"
      ratio >= 0.6 -> "faixa média"
      true -> "baixo consumo"
    end
  end

  defp character_usage_hint(text) do
    ratio = usage_ratio(text)

    cond do
      ratio >= 0.9 -> "Texto grande. Se falhar, corte em blocos menores."
      ratio >= 0.6 -> "Texto saudável para geração contínua."
      true -> "Texto curto, bom para iteração rápida."
    end
  end

  defp usage_color(text) do
    ratio = usage_ratio(text)

    cond do
      ratio >= 0.9 -> "text-[#f7b38b]"
      ratio >= 0.6 -> "text-[#7fd6e8]"
      true -> "text-white/60"
    end
  end

  defp usage_ratio(text), do: character_count(text) / @max_chars

  defp feedback_class(:info), do: "border-[#7fd6e8]/30 bg-[#7fd6e8]/10 text-[#d7f9ff]"
  defp feedback_class(:error), do: "border-[#f29c6b]/30 bg-[#f29c6b]/10 text-[#ffe0cf]"

  defp generation_class(id, recent_generation_id) when id == recent_generation_id do
    "border-[#7fd6e8]/40 shadow-[0_0_0_1px_rgba(127,214,232,0.12)]"
  end

  defp generation_class(_id, _recent_generation_id), do: "border-white/10"

  defp local_datetime(nil), do: "Sem data"

  defp local_datetime(datetime) do
    Calendar.strftime(datetime, "%d/%m/%Y %H:%M")
  end

  defp remote_history_datetime(nil), do: "Data indisponível"

  defp remote_history_datetime(unix) when is_integer(unix) do
    unix
    |> DateTime.from_unix!()
    |> Calendar.strftime("%d/%m/%Y %H:%M")
  end
end
