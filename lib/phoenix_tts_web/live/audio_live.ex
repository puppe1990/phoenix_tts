defmodule PhoenixTtsWeb.AudioLive do
  use PhoenixTtsWeb, :live_view

  alias PhoenixTts.Audio

  @max_chars 5_000

  def mount(_params, _session, socket) do
    voices = Audio.available_voices()
    models = Audio.available_models()
    form_attrs = default_form_attrs(voices, models)
    {remote_history, remote_history_cursor, remote_history_has_more} = load_remote_history()
    subscription = load_subscription_overview()

    {:ok,
     socket
     |> allow_upload(:samples,
       accept: :any,
       max_entries: 10,
       max_file_size: 25_000_000
     )
     |> assign(:voices, voices)
     |> assign(:models, models)
     |> assign(:subscription, subscription)
     |> assign(:remote_history, remote_history)
     |> assign(:remote_history_cursor, remote_history_cursor)
     |> assign(:remote_history_has_more, remote_history_has_more)
     |> assign(:remote_history_loading, false)
     |> assign(:generations, Audio.list_generations())
     |> assign(:recent_generation_id, nil)
     |> assign(:advanced_open, false)
     |> assign(:form_feedback, nil)
     |> assign(:generation_pending, false)
     |> assign(:clone_feedback, nil)
     |> assign(:clone_result, nil)
     |> assign(:clone_samples, [])
     |> assign(:max_chars, @max_chars)
     |> assign(:api_key_configured, Audio.api_key_configured?())
     |> assign(:recent_voice_search, "")
     |> assign(:voice_box_open, false)
     |> assign(:model_box_open, false)
     |> assign(:language_box_open, false)
     |> assign(:clone_form, to_form(Audio.change_clone_voice(), as: :clone_voice))
     |> assign_form(form_attrs)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :page_title, page_title(socket.assigns.live_action))}
  end

  def handle_event("validate", %{"audio_generation" => params}, socket) do
    {:noreply,
     socket
     |> assign(:form_feedback, nil)
     |> assign_form(params)}
  end

  def handle_event("save", %{"audio_generation" => params}, socket) do
    normalized_params = normalize_form_attrs(params)
    changeset = Audio.change_generation(normalized_params)

    cond do
      socket.assigns.generation_pending ->
        {:noreply, socket}

      changeset.valid? ->
        {:noreply,
         socket
         |> assign(:form_feedback, {:info, "Gerando áudio em background. Aguarde a finalização."})
         |> assign(:generation_pending, true)
         |> assign_form(normalized_params)
         |> start_async(:generate_audio, fn ->
           {Audio.create_generation(normalized_params), normalized_params}
         end)}

      true ->
        {:noreply,
         socket
         |> assign(:generation_pending, false)
         |> assign(:form_feedback, {:error, feedback_message(changeset)})
         |> assign(:form_attrs, normalized_params)
         |> assign(:form, to_form(changeset, as: :audio_generation))}
    end
  end

  def handle_event("validate_clone", %{"clone_voice" => params}, socket) do
    changeset = Audio.change_clone_voice(params, available_clone_samples_count(socket))

    {:noreply,
     socket
     |> maybe_clear_clone_feedback()
     |> assign(:clone_form, to_form(changeset, as: :clone_voice))}
  end

  def handle_event("save_clone", %{"clone_voice" => params}, socket) do
    changeset = Audio.change_clone_voice(params, available_clone_samples_count(socket))

    if changeset.valid? do
      {socket, samples} = clone_samples_for_request(socket)

      case Audio.clone_voice(params, samples) do
        {:ok, clone} ->
          voices = prepend_cloned_voice(socket.assigns.voices, clone)

          {:noreply,
           socket
           |> assign(:voices, voices)
           |> assign(:clone_result, clone)
           |> assign(:clone_samples, [])
           |> assign(
             :clone_feedback,
             {:info, "Voice clone criada com sucesso. O novo voice ID está pronto para uso."}
           )
           |> assign(:clone_form, to_form(Audio.change_clone_voice(), as: :clone_voice))}

        {:error, changeset} ->
          {:noreply,
           socket
           |> assign(:clone_result, nil)
           |> assign(:clone_feedback, {:error, clone_feedback_message(changeset)})
           |> assign(:clone_form, to_form(changeset, as: :clone_voice))}
      end
    else
      {:noreply,
       socket
       |> assign(:clone_result, nil)
       |> assign(:clone_feedback, {:error, clone_feedback_message(changeset)})
       |> assign(:clone_form, to_form(changeset, as: :clone_voice))}
    end
  end

  def handle_event("select_voice", %{"voice_id" => voice_id}, socket) do
    attrs =
      socket.assigns.form_attrs
      |> Map.put("voice_id", voice_id)

    {:noreply,
     socket
     |> assign(:form_feedback, nil)
     |> assign(:voice_box_open, false)
     |> assign_form(attrs)}
  end

  def handle_event("filter_recent_voices", %{"value" => value}, socket) do
    {:noreply, assign(socket, :recent_voice_search, value)}
  end

  def handle_event("open_combobox", %{"field" => field}, socket) do
    {:noreply, toggle_combobox(socket, field, true)}
  end

  def handle_event("close_combobox", %{"field" => field}, socket) do
    {:noreply,
     socket
     |> toggle_combobox(field, false)
     |> reset_combobox_query(field)}
  end

  def handle_event("filter_combobox", %{"field" => field, "value" => value}, socket) do
    {:noreply,
     socket
     |> toggle_combobox(field, true)
     |> assign_combobox_query(field, value)}
  end

  def handle_event("select_combobox", %{"field" => field, "option" => option}, socket) do
    if blank?(option) do
      {:noreply, close_all_comboboxes(socket)}
    else
      attrs =
        case field do
          "voice" -> Map.put(socket.assigns.form_attrs, "voice_id", option)
          "model" -> Map.put(socket.assigns.form_attrs, "model_id", option)
          "language" -> Map.put(socket.assigns.form_attrs, "language_code", option)
        end

      {:noreply,
       socket
       |> assign(:form_feedback, nil)
       |> close_all_comboboxes()
       |> assign_form(attrs)}
    end
  end

  def handle_event("toggle_advanced", _params, socket) do
    {:noreply, update(socket, :advanced_open, &(!&1))}
  end

  def handle_event("load_more_remote_history", _params, socket) do
    socket = assign(socket, :remote_history_loading, true)

    case Audio.remote_history_page(%{
           start_after_history_item_id: socket.assigns.remote_history_cursor
         }) do
      {:ok, %{items: items, has_more: has_more, last_history_item_id: last_history_item_id}} ->
        {:noreply,
         socket
         |> assign(:remote_history_loading, false)
         |> assign(:remote_history, socket.assigns.remote_history ++ items)
         |> assign(:remote_history_has_more, has_more)
         |> assign(
           :remote_history_cursor,
           history_cursor(items, last_history_item_id, socket.assigns.remote_history_cursor)
         )}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:remote_history_loading, false)
         |> assign(
           :form_feedback,
           {:error, "Não foi possível carregar mais itens recentes agora."}
         )}
    end
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
        |> assign(
          :form_feedback,
          {:info, "Configuração reaplicada. Ajuste o texto e gere novamente."}
        )
        |> assign_form(attrs)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_async(:generate_audio, {:ok, {{:ok, generation}, params}}, socket) do
    preserved_attrs =
      params
      |> normalize_form_attrs()
      |> Map.put("text", "")

    {:noreply,
     socket
     |> put_flash(:info, "Áudio gerado com sucesso.")
     |> assign(:generation_pending, false)
     |> assign(:recent_generation_id, generation.id)
     |> assign(
       :form_feedback,
       {:info, "Áudio pronto. A última configuração foi mantida para a próxima geração."}
     )
     |> assign_form(preserved_attrs)
     |> assign(:generations, [generation | socket.assigns.generations])}
  end

  def handle_async(:generate_audio, {:ok, {{:error, changeset}, params}}, socket) do
    {:noreply,
     socket
     |> assign(:generation_pending, false)
     |> assign(:form_feedback, {:error, feedback_message(changeset)})
     |> assign(:form_attrs, normalize_form_attrs(params))
     |> assign(:form, to_form(changeset, as: :audio_generation))}
  end

  def handle_async(:generate_audio, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:generation_pending, false)
     |> assign(:form_feedback, {:error, "A geração falhou internamente. Tente novamente."})}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="px-4 pb-14 pt-6 sm:px-6 lg:px-8 lg:pb-20">
        <div class="mx-auto flex w-full max-w-7xl flex-col gap-8">
          <header class="rounded-[2rem] border border-white/10 bg-[#0a1120]/90 px-5 py-5 sm:px-6">
            <div class="flex flex-col gap-5 lg:flex-row lg:items-center lg:justify-between">
              <div>
                <p class="text-[11px] uppercase tracking-[0.28em] text-[#7fd6e8]/70">
                  Phoenix TTS
                </p>
                <h1 class="mt-2 text-2xl font-semibold text-[#f7f1e8]">Operação ElevenLabs</h1>
              </div>

              <nav class="flex flex-wrap gap-3 text-sm">
                <.link
                  navigate={~p"/"}
                  class={nav_link_class(@live_action == :index)}
                >
                  Studio
                </.link>
                <.link
                  navigate={~p"/clone"}
                  class={nav_link_class(@live_action == :clone)}
                >
                  Clone Voice
                </.link>
                <.link
                  navigate={~p"/recentes"}
                  class={nav_link_class(@live_action == :recentes)}
                >
                  Recentes
                </.link>
                <.link
                  navigate={~p"/config"}
                  class={nav_link_class(@live_action == :config)}
                >
                  Configuração
                </.link>
              </nav>
            </div>
          </header>

          <section :if={@live_action == :config} class="grid gap-6">
            <article class="rounded-[2rem] border border-white/10 bg-[#0a1120]/90 p-5 sm:p-6">
              <div class="flex items-center justify-between gap-4">
                <div>
                  <p class="text-[11px] uppercase tracking-[0.28em] text-[#7fd6e8]/70">
                    Configuração
                  </p>
                  <h2 class="mt-2 text-2xl font-semibold text-[#f7f1e8]">
                    Credits restantes
                  </h2>
                </div>
                <div class="rounded-full border border-white/10 px-3 py-1 text-[11px] uppercase tracking-[0.2em] text-white/50">
                  {subscription_status_label(@subscription)}
                </div>
              </div>

              <div :if={@subscription} class="mt-6 grid gap-4 sm:grid-cols-3">
                <div class="rounded-[1.4rem] border border-white/10 bg-white/[0.03] p-4">
                  <p class="text-[11px] uppercase tracking-[0.2em] text-white/35">
                    credits restantes
                  </p>
                  <p class="mt-2 text-3xl font-semibold text-[#7fd6e8]">
                    {format_number(@subscription.remaining_credits)}
                  </p>
                </div>
                <div class="rounded-[1.4rem] border border-white/10 bg-white/[0.03] p-4">
                  <p class="text-[11px] uppercase tracking-[0.2em] text-white/35">
                    credits consumidos
                  </p>
                  <p class="mt-2 text-3xl font-semibold text-[#f7f1e8]">
                    {format_number(@subscription.used_credits)}
                  </p>
                </div>
                <div class="rounded-[1.4rem] border border-white/10 bg-white/[0.03] p-4">
                  <p class="text-[11px] uppercase tracking-[0.2em] text-white/35">
                    limite de credits
                  </p>
                  <p class="mt-2 text-3xl font-semibold text-[#f7f1e8]">
                    {format_number(@subscription.total_credits)}
                  </p>
                </div>
              </div>

              <div :if={@subscription} class="mt-4 flex flex-wrap gap-3 text-sm text-white/58">
                <span class="rounded-full border border-white/10 px-3 py-2">
                  Plano {String.upcase(@subscription.tier || "unknown")}
                </span>
                <span class="rounded-full border border-white/10 px-3 py-2">
                  Reset {reset_label(@subscription.next_reset_unix)}
                </span>
              </div>

              <div
                :if={is_nil(@subscription)}
                class="mt-6 rounded-[1.4rem] border border-dashed border-white/10 p-5 text-sm text-white/50"
              >
                Não foi possível consultar o saldo restante da conta agora.
              </div>
            </article>
          </section>

          <section
            :if={@live_action == :index}
            class="relative overflow-hidden rounded-[2rem] border border-white/10 bg-[#0b1325]/90 shadow-[0_40px_120px_rgba(0,0,0,0.45)]"
          >
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
                      {estimated_credit_spend(@form_attrs["text"], @form_attrs["model_id"], @models)} credits
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
                  <fieldset
                    disabled={@generation_pending}
                    class="grid gap-6 disabled:opacity-80 xl:grid-cols-[1.25fr_0.75fr]"
                  >
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

                      <div class="mt-4 rounded-[1.2rem] border border-white/10 bg-[#0d1729] px-4 py-4">
                        <div class="flex flex-wrap items-center justify-between gap-3">
                          <div>
                            <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">
                              estimativa de gasto
                            </p>
                            <p class="mt-2 text-lg font-semibold text-[#f7f1e8]">
                              {estimated_credit_spend(
                                @form_attrs["text"],
                                @form_attrs["model_id"],
                                @models
                              )} credits
                            </p>
                          </div>

                          <div :if={@subscription} class="text-right">
                            <p class="text-[11px] uppercase tracking-[0.18em] text-white/35">
                              saldo após gerar
                            </p>
                            <p class="mt-2 text-lg font-semibold text-[#7fd6e8]">
                              {remaining_after_generation(
                                @subscription,
                                @form_attrs["text"],
                                @form_attrs["model_id"],
                                @models
                              )} credits
                            </p>
                          </div>
                        </div>

                        <p class="mt-3 text-sm leading-6 text-white/55">
                          Estimativa baseada no tamanho do texto e no modelo selecionado. Flash e Turbo consomem menos credits por caractere em planos self-serve; o custo real pode variar conforme a conta e a voz usada.
                        </p>
                      </div>
                    </div>

                    <div class="space-y-4">
                      <div class="rounded-[1.45rem] border border-white/8 bg-white/[0.02] p-4">
                        <p class="text-xs uppercase tracking-[0.22em] text-[#7fd6e8]/70">
                          Básico
                        </p>

                        <.input field={@form[:voice_id]} type="hidden" />
                        <.combobox
                          id="voice-combobox"
                          field="voice"
                          label="Voz"
                          value={@voice_query}
                          open={@voice_box_open}
                          placeholder="Buscar voz por nome, accent ou voice id"
                          options={
                            voice_combobox_options(
                              @voices,
                              active_voice_query(@voice_query, @voices, @form_attrs["voice_id"])
                            )
                          }
                          empty_label="Nenhuma voz encontrada"
                        />

                        <.input field={@form[:model_id]} type="hidden" />
                        <.combobox
                          id="model-combobox"
                          field="model"
                          label="Modelo"
                          value={@model_query}
                          open={@model_box_open}
                          placeholder="Buscar por nome ou id do modelo"
                          options={
                            model_combobox_options(
                              @models,
                              active_model_query(@model_query, @models, @form_attrs["model_id"])
                            )
                          }
                          empty_label="Nenhum modelo encontrado"
                        />

                        <.input field={@form[:language_code]} type="hidden" />
                        <.combobox
                          id="language-combobox"
                          field="language"
                          label="Idioma"
                          value={@language_query}
                          open={@language_box_open}
                          placeholder="Buscar por nome ou código"
                          options={
                            language_combobox_options(
                              active_language_query(@language_query, @form_attrs["language_code"])
                            )
                          }
                          empty_label="Nenhum idioma encontrado"
                        />

                        <div class="rounded-[1.2rem] border border-white/10 bg-[#0d1729] px-4 py-3 text-sm text-white/60">
                          <p class="font-medium text-[#f7f1e8]">Última configuração usada</p>
                          <p class="mt-2 leading-6">
                            {summary_voice(@voices, @form_attrs["voice_id"])} • {summary_model(
                              @models,
                              @form_attrs["model_id"]
                            )} • {summary_language(@form_attrs["language_code"])} • {summary_output(
                              @form_attrs["output_format"]
                            )}
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
                  </fieldset>

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
                      phx-disable-with="Iniciando..."
                      disabled={
                        @generation_pending or
                          submit_disabled?(@api_key_configured, @models, @form_attrs)
                      }
                      class="inline-flex w-full items-center justify-center rounded-full bg-[#7fe3f5] px-8 py-4 text-sm font-semibold uppercase tracking-[0.18em] text-[#07111f] transition hover:bg-[#a2edfa] disabled:cursor-not-allowed disabled:opacity-50 lg:w-auto lg:min-w-72"
                    >
                      {if @generation_pending, do: "Gerando áudio...", else: "Gerar áudio"}
                    </button>
                  </div>
                </.form>
              </div>
            </div>
          </section>

          <section
            :if={@live_action == :clone}
            class="relative overflow-hidden rounded-[2rem] border border-white/10 bg-[#0b1325]/90 shadow-[0_40px_120px_rgba(0,0,0,0.45)]"
          >
            <div class="absolute inset-0 bg-[radial-gradient(circle_at_top_left,rgba(127,214,232,0.18),transparent_28%),radial-gradient(circle_at_75%_20%,rgba(255,184,120,0.14),transparent_22%)]" />
            <div class="relative grid gap-6 p-5 sm:p-8 xl:grid-cols-[0.9fr_1.1fr] xl:p-10">
              <article class="rounded-[1.8rem] border border-white/10 bg-[#08101f]/88 p-6 shadow-[inset_0_1px_0_rgba(255,255,255,0.06)] sm:p-8">
                <p class="text-[11px] font-semibold uppercase tracking-[0.3em] text-[#7fd6e8]/70">
                  Instant Voice Clone
                </p>
                <h2 class="mt-3 font-['Iowan_Old_Style','Palatino_Linotype','Book_Antiqua',serif] text-4xl font-semibold leading-none text-[#f7f1e8]">
                  Clone sua voz com amostras curtas
                </h2>
                <p class="mt-4 text-base leading-7 text-[#d6d0c7]/72">
                  Envie uma ou mais amostras, defina um nome claro e gere um novo `voice_id` via ElevenLabs Instant Voice Clone.
                </p>

                <div class="mt-6 grid gap-3 text-sm text-white/60">
                  <div class="rounded-[1.2rem] border border-white/10 bg-white/[0.03] p-4">
                    Quanto mais arquivos você enviar, melhor tende a ficar o clone.
                  </div>
                  <div class="rounded-[1.2rem] border border-white/10 bg-white/[0.03] p-4">
                    Formatos aceitos: MP3, WAV, AAC, FLAC e OGG.
                  </div>
                  <div class="rounded-[1.2rem] border border-white/10 bg-white/[0.03] p-4">
                    Depois da criação, o `voice_id` já pode ser usado no Studio.
                  </div>
                </div>
              </article>

              <article class="rounded-[1.8rem] border border-white/10 bg-[#08101f]/88 p-6 shadow-[inset_0_1px_0_rgba(255,255,255,0.06)] sm:p-8">
                <div
                  :if={not @api_key_configured}
                  class="rounded-[1.5rem] border border-[#f29c6b]/30 bg-[#f29c6b]/10 p-4 text-sm text-[#ffe0cf]"
                >
                  Configure `ELEVENLABS_API_KEY` no `.env` para liberar a clonagem.
                </div>

                <div
                  :if={@clone_feedback}
                  class={[
                    "mt-4 rounded-[1.5rem] border p-4 text-sm leading-6",
                    feedback_class(elem(@clone_feedback, 0))
                  ]}
                >
                  <p class="text-[11px] uppercase tracking-[0.18em] opacity-70">
                    {if elem(@clone_feedback, 0) == :info,
                      do: "status da clonagem",
                      else: "falha na clonagem"}
                  </p>
                  {elem(@clone_feedback, 1)}
                </div>

                <.form
                  for={@clone_form}
                  id="clone-form"
                  class="mt-4 space-y-5"
                  phx-change="validate_clone"
                  phx-submit="save_clone"
                >
                  <div>
                    <label for="clone-name" class="mb-1 block text-sm font-medium text-[#f7f1e8]">
                      Nome da voz
                    </label>
                    <input
                      id="clone-name"
                      name="clone_voice[name]"
                      type="text"
                      value={Phoenix.HTML.Form.normalize_value("text", @clone_form[:name].value)}
                      placeholder="Minha Voz Clone"
                      class="w-full rounded-[1.1rem] border border-white/10 bg-[#111b2f] px-4 py-3 text-sm text-[#f7f1e8] placeholder:text-white/30"
                    />
                    <p :if={@clone_form[:name].errors != []} class="mt-2 text-sm text-[#f7b38b]">
                      {elem(List.first(@clone_form[:name].errors), 0)}
                    </p>
                  </div>

                  <div>
                    <label class="mb-1 block text-sm font-medium text-[#f7f1e8]">
                      Amostras de áudio
                    </label>
                    <div class="rounded-[1.2rem] border border-dashed border-white/15 bg-white/[0.02] p-4">
                      <.live_file_input
                        upload={@uploads.samples}
                        class="block w-full cursor-pointer text-sm text-white/60 file:mr-4 file:rounded-full file:border-0 file:bg-[#7fe3f5] file:px-4 file:py-2 file:text-sm file:font-semibold file:text-[#07111f]"
                      />
                      <div
                        :if={clone_sample_entries(@uploads.samples.entries, @clone_samples) != []}
                        class="mt-4 space-y-2"
                      >
                        <div
                          :for={
                            entry <- clone_sample_entries(@uploads.samples.entries, @clone_samples)
                          }
                          class="rounded-xl border border-white/10 bg-[#0d1729] px-3 py-3 text-sm text-white/70"
                        >
                          {clone_sample_label(entry)}
                        </div>
                      </div>
                    </div>
                    <p
                      :if={@clone_samples != []}
                      class="mt-2 text-xs uppercase tracking-[0.16em] text-white/35"
                    >
                      amostras preservadas para nova tentativa
                    </p>
                    <p
                      :if={clone_files_error(@clone_form)}
                      class="mt-2 text-sm text-[#f7b38b]"
                    >
                      {clone_files_error(@clone_form)}
                    </p>
                  </div>

                  <button
                    type="submit"
                    phx-disable-with="Clonando voz..."
                    disabled={not @api_key_configured}
                    class="inline-flex w-full items-center justify-center rounded-full bg-[#7fe3f5] px-8 py-4 text-sm font-semibold uppercase tracking-[0.18em] text-[#07111f] transition hover:bg-[#a2edfa] disabled:cursor-not-allowed disabled:opacity-50"
                  >
                    Enviar para clonagem
                  </button>
                </.form>

                <div
                  :if={@clone_result}
                  class="mt-5 rounded-[1.4rem] border border-white/10 bg-[#0d1729] p-4 text-sm text-white/65"
                >
                  <p class="text-[11px] uppercase tracking-[0.24em] text-[#7fd6e8]/70">
                    Voice ID gerado
                  </p>
                  <p class="mt-3 text-lg font-semibold text-[#f7f1e8]">{@clone_result.voice_id}</p>
                  <p class="mt-2 text-sm text-white/55">{@clone_result.name}</p>
                </div>
              </article>
            </div>
          </section>

          <section :if={@live_action == :recentes} class="grid gap-6 xl:grid-cols-[0.82fr_1.18fr]">
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

                <div class="mt-4">
                  <label
                    for="recent-voice-search"
                    class="mb-1 block text-sm font-medium text-[#f7f1e8]"
                  >
                    Buscar voz
                  </label>
                  <input
                    id="recent-voice-search"
                    type="text"
                    value={@recent_voice_search}
                    phx-keyup="filter_recent_voices"
                    phx-debounce="150"
                    placeholder="Filtrar por nome, accent ou voice id"
                    autocomplete="off"
                    class="w-full rounded-[1.1rem] border border-white/10 bg-[#111b2f] px-4 py-3 text-sm text-[#f7f1e8] placeholder:text-white/30"
                  />
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
                  :for={voice <- matching_voices(@voices, @recent_voice_search)}
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
                    <span class={
                      if selected_voice?(voice.id, @form_attrs),
                        do: "text-[#7fd6e8]",
                        else: "text-white/40"
                    }>
                      {if selected_voice?(voice.id, @form_attrs),
                        do: "selecionada",
                        else: "clique para usar"}
                    </span>
                  </div>
                </button>

                <div
                  :if={@voices != [] and matching_voices(@voices, @recent_voice_search) == []}
                  class="rounded-[1.4rem] border border-dashed border-white/10 p-4 text-sm text-white/45"
                >
                  Nenhuma voz encontrada para esse filtro.
                </div>
              </div>
            </aside>

            <div class="grid gap-6">
              <section
                :if={@live_action == :recentes}
                class="rounded-[2rem] border border-white/10 bg-[#0a1120]/90 p-5 sm:p-6"
              >
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
                    <p class="mt-2 text-xs text-white/30">
                      {remote_history_datetime(item.date_unix)}
                    </p>
                    <audio
                      id={"remote-audio-player-#{item.history_item_id}"}
                      class="mt-4 w-full opacity-90"
                      controls
                      preload="none"
                    >
                      <source src={~p"/history/#{item.history_item_id}/audio"} type="audio/mpeg" />
                    </audio>
                    <div class="mt-4 flex flex-wrap items-center gap-4">
                      <a
                        href={~p"/history/#{item.history_item_id}/audio"}
                        class="text-sm font-semibold text-[#7fd6e8] underline decoration-[#7fd6e8]/35 underline-offset-4"
                      >
                        ouvir agora
                      </a>
                      <a
                        href={~p"/history/#{item.history_item_id}/audio?download=1"}
                        class="text-sm font-semibold text-[#7fd6e8] underline decoration-[#7fd6e8]/35 underline-offset-4"
                      >
                        baixar áudio
                      </a>
                    </div>
                  </article>
                </div>

                <div :if={@remote_history_has_more} class="mt-6 flex justify-center">
                  <button
                    type="button"
                    phx-click="load_more_remote_history"
                    phx-disable-with="Carregando mais..."
                    disabled={@remote_history_loading}
                    class="inline-flex items-center justify-center rounded-full border border-white/10 px-5 py-3 text-sm font-semibold text-[#7fd6e8] transition hover:border-[#7fd6e8]/40 hover:bg-[#0f1b31] disabled:cursor-not-allowed disabled:opacity-50"
                  >
                    Carregar mais
                  </button>
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
                      <source
                        src={~p"/generations/#{generation.id}/audio"}
                        type={generation.content_type}
                      />
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
                        href={~p"/generations/#{generation.id}/audio?download=1"}
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

  attr :id, :string, required: true
  attr :field, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, default: ""
  attr :open, :boolean, default: false
  attr :placeholder, :string, default: ""
  attr :options, :list, default: []
  attr :empty_label, :string, default: "Nenhuma opção encontrada"

  def combobox(assigns) do
    ~H"""
    <div
      class="relative mt-4"
      phx-click-away="close_combobox"
      phx-value-field={@field}
    >
      <label for={"#{@id}-input"} class="mb-1 block text-sm font-medium text-[#f7f1e8]">
        {@label}
      </label>
      <input
        id={"#{@id}-input"}
        type="text"
        value={@value}
        phx-focus="open_combobox"
        phx-keyup="filter_combobox"
        phx-value-field={@field}
        phx-debounce="150"
        placeholder={@placeholder}
        autocomplete="off"
        class="w-full rounded-[1.1rem] border border-white/10 bg-[#111b2f] px-4 py-3 pr-10 text-sm text-[#f7f1e8] placeholder:text-white/30"
      />
      <button
        type="button"
        phx-click="open_combobox"
        phx-value-field={@field}
        class="absolute right-3 top-[2.35rem] text-white/45"
      >
        <.icon name="hero-chevron-down" class="size-4" />
      </button>

      <div
        :if={@open}
        id={"#{@id}-menu"}
        class="absolute z-20 mt-2 max-h-64 w-full overflow-y-auto rounded-[1.1rem] border border-white/10 bg-[#0d1729] p-2 shadow-[0_24px_80px_rgba(0,0,0,0.35)]"
      >
        <button
          :for={option <- @options}
          type="button"
          phx-click="select_combobox"
          phx-value-field={@field}
          phx-value-option={option.value}
          class="block w-full rounded-xl px-3 py-3 text-left text-sm text-[#f7f1e8] transition hover:bg-[#13233c]"
        >
          <div class="font-medium">{option.label}</div>
          <div :if={option[:hint]} class="mt-1 text-xs uppercase tracking-[0.14em] text-white/35">
            {option.hint}
          </div>
        </button>

        <div
          :if={Enum.empty?(@options)}
          class="rounded-xl px-3 py-3 text-sm text-white/45"
        >
          {@empty_label}
        </div>
      </div>
    </div>
    """
  end

  defp assign_form(socket, attrs) do
    normalized = normalize_form_attrs(attrs)

    socket
    |> assign(:form_attrs, normalized)
    |> assign_combobox_defaults(normalized)
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
      runtime_error = first_error(changeset, :runtime) ->
        runtime_error

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

  defp clone_feedback_message(changeset) do
    cond do
      name_error = first_error(changeset, :name) ->
        "Revise o nome da voz antes de enviar: #{name_error}"

      files_error = first_error(changeset, :files) ->
        "Adicione amostras de áudio para continuar: #{files_error}"

      runtime_error = first_error(changeset, :runtime) ->
        "A ElevenLabs recusou a clonagem agora: #{runtime_error}"

      true ->
        "Não foi possível criar a voice clone agora."
    end
  end

  defp first_error(changeset, field) do
    case Keyword.get_values(changeset.errors, field) do
      [{message, opts} | _] -> translate_error({message, opts})
      _ -> nil
    end
  end

  defp submit_disabled?(api_key_configured, models, attrs) do
    not api_key_configured or Enum.empty?(models) or blank?(attrs["voice_id"]) or
      blank?(attrs["model_id"])
  end

  defp blank?(value), do: value in [nil, ""]

  defp selected_voice?(voice_id, form_attrs), do: form_attrs["voice_id"] == voice_id

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

  defp prepend_cloned_voice(voices, %{voice_id: voice_id, name: name})
       when is_binary(voice_id) and voice_id != "" and is_binary(name) and name != "" do
    cloned_voice = %{id: voice_id, name: name, category: "cloned", labels: %{}}

    [cloned_voice | Enum.reject(voices, &(&1.id == voice_id))]
  end

  defp prepend_cloned_voice(voices, _clone), do: voices

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

  defp matching_voices(voices, query) do
    Enum.filter(voices, fn voice ->
      query == "" or
        contains_query?(voice.name, query) or
        contains_query?(voice.id, query) or
        contains_query?(voice.labels["accent"], query)
    end)
  end

  defp matching_models(models, query) do
    Enum.filter(models, fn model ->
      query == "" or contains_query?(model.name, query) or contains_query?(model.id, query)
    end)
  end

  defp matching_languages(query) do
    Enum.filter(language_options(), fn {label, value} ->
      query == "" or contains_query?(label, query) or contains_query?(value, query)
    end)
  end

  defp contains_query?(value, query) when is_binary(value) do
    String.contains?(String.downcase(value), String.downcase(query))
  end

  defp contains_query?(_, _), do: false

  defp voice_combobox_options(voices, query) do
    Enum.map(matching_voices(voices, query), fn voice ->
      %{
        value: voice.id,
        label: voice.name,
        hint: [voice.id, voice.labels["accent"]] |> Enum.reject(&blank?/1) |> Enum.join(" • ")
      }
    end)
  end

  defp model_combobox_options(models, query) do
    Enum.map(matching_models(models, query), fn model ->
      %{value: model.id, label: model.name, hint: model.id}
    end)
  end

  defp language_combobox_options(query) do
    Enum.map(matching_languages(query), fn {label, value} ->
      %{value: value, label: label, hint: value}
    end)
  end

  defp assign_combobox_defaults(socket, attrs) do
    socket
    |> assign(:voice_query, combobox_voice_value(socket.assigns.voices, attrs["voice_id"]))
    |> assign(:model_query, combobox_model_value(socket.assigns.models, attrs["model_id"]))
    |> assign(:language_query, combobox_language_value(attrs["language_code"]))
  end

  defp toggle_combobox(socket, "voice", open), do: assign(socket, :voice_box_open, open)
  defp toggle_combobox(socket, "model", open), do: assign(socket, :model_box_open, open)
  defp toggle_combobox(socket, "language", open), do: assign(socket, :language_box_open, open)

  defp assign_combobox_query(socket, "voice", value), do: assign(socket, :voice_query, value)
  defp assign_combobox_query(socket, "model", value), do: assign(socket, :model_query, value)

  defp assign_combobox_query(socket, "language", value),
    do: assign(socket, :language_query, value)

  defp reset_combobox_query(socket, "voice"),
    do:
      assign(
        socket,
        :voice_query,
        combobox_voice_value(socket.assigns.voices, socket.assigns.form_attrs["voice_id"])
      )

  defp reset_combobox_query(socket, "model"),
    do:
      assign(
        socket,
        :model_query,
        combobox_model_value(socket.assigns.models, socket.assigns.form_attrs["model_id"])
      )

  defp reset_combobox_query(socket, "language"),
    do:
      assign(
        socket,
        :language_query,
        combobox_language_value(socket.assigns.form_attrs["language_code"])
      )

  defp close_all_comboboxes(socket) do
    socket
    |> assign(:voice_box_open, false)
    |> assign(:model_box_open, false)
    |> assign(:language_box_open, false)
  end

  defp active_voice_query(query, voices, selected_id) do
    if query == combobox_voice_value(voices, selected_id), do: "", else: query
  end

  defp active_model_query(query, models, selected_id) do
    if query == combobox_model_value(models, selected_id), do: "", else: query
  end

  defp active_language_query(query, selected_code) do
    if query == combobox_language_value(selected_code), do: "", else: query
  end

  defp combobox_voice_value(voices, voice_id) do
    case Enum.find(voices, &(&1.id == voice_id)) do
      nil -> ""
      voice -> voice.name
    end
  end

  defp combobox_model_value(models, model_id) do
    case Enum.find(models, &(&1.id == model_id)) do
      nil -> ""
      model -> model.name
    end
  end

  defp combobox_language_value(language_code) do
    case Enum.find(language_options(), fn {_label, value} -> value == language_code end) do
      nil -> ""
      {label, _value} -> label
    end
  end

  defp load_remote_history do
    case Audio.remote_history_page() do
      {:ok, %{items: items, has_more: has_more, last_history_item_id: last_history_item_id}} ->
        {items, history_cursor(items, last_history_item_id, nil), has_more}

      {:error, _reason} ->
        {[], nil, false}
    end
  end

  defp load_subscription_overview do
    case Audio.subscription_overview() do
      {:ok, subscription} -> subscription
      {:error, _reason} -> nil
    end
  end

  defp history_cursor([], last_history_item_id, fallback), do: last_history_item_id || fallback

  defp history_cursor(items, last_history_item_id, _fallback) do
    case List.last(items) do
      %{history_item_id: history_item_id} when is_binary(history_item_id) -> history_item_id
      _ -> last_history_item_id
    end
  end

  defp nav_link_class(true) do
    "rounded-full border border-[#7fd6e8]/35 bg-[#0f1b31] px-4 py-2 font-semibold text-[#7fd6e8]"
  end

  defp nav_link_class(false) do
    "rounded-full border border-white/10 px-4 py-2 text-white/60 transition hover:border-[#7fd6e8]/35 hover:text-[#f7f1e8]"
  end

  defp subscription_status_label(nil), do: "indisponível"
  defp subscription_status_label(subscription), do: subscription.status || "status desconhecido"

  defp format_number(number) when is_integer(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(.{3})(?=.)/, "\\1.")
    |> String.reverse()
  end

  defp format_number(number) when is_float(number) do
    [integer_part, decimal_part] =
      number
      |> :erlang.float_to_binary(decimals: 1)
      |> String.split(".")

    format_number(String.to_integer(integer_part)) <> "," <> decimal_part
  end

  defp format_number(_), do: "-"

  defp reset_label(nil), do: "sem data"

  defp reset_label(unix) when is_integer(unix) do
    unix
    |> DateTime.from_unix!()
    |> Calendar.strftime("%d/%m/%Y %H:%M")
  end

  defp page_title(:clone), do: "Clone Voice"
  defp page_title(:recentes), do: "Itens recentes"
  defp page_title(:config), do: "Configuração"
  defp page_title(_), do: "ElevenLabs Audio Studio"

  defp uploaded_samples_count(socket) do
    length(socket.assigns.uploads.samples.entries)
  end

  defp available_clone_samples_count(socket) do
    uploaded_samples_count(socket) + length(socket.assigns.clone_samples)
  end

  defp clone_samples_for_request(socket) do
    uploaded =
      consume_uploaded_entries(socket, :samples, fn %{path: path}, entry ->
        {:ok,
         %{
           binary: File.read!(path),
           filename: entry.client_name,
           content_type: entry.client_type
         }}
      end)

    samples =
      case uploaded do
        [] -> socket.assigns.clone_samples
        _ -> uploaded
      end

    {assign(socket, :clone_samples, samples), samples}
  end

  defp clone_sample_entries(upload_entries, preserved_samples) do
    cond do
      upload_entries != [] -> upload_entries
      preserved_samples != [] -> preserved_samples
      true -> []
    end
  end

  defp clone_sample_label(%Phoenix.LiveView.UploadEntry{client_name: client_name}),
    do: client_name

  defp clone_sample_label(%{filename: filename}) when is_binary(filename), do: filename
  defp clone_sample_label(_entry), do: "Amostra carregada"

  defp maybe_clear_clone_feedback(socket) do
    if elem(socket.assigns.clone_feedback || {:info, nil}, 0) == :error do
      socket
    else
      assign(socket, :clone_feedback, nil)
    end
  end

  defp clone_files_error(form) do
    case form[:files].errors do
      [{message, _opts} | _] -> message
      _ -> nil
    end
  end

  defp estimated_credit_spend(text, model_id, models) do
    text
    |> estimated_credits(model_id, models)
    |> format_number()
  end

  defp remaining_after_generation(subscription, text, model_id, models) do
    remaining =
      max((subscription.remaining_credits || 0) - estimated_credits(text, model_id, models), 0.0)

    format_number(remaining)
  end

  defp character_count(text), do: text |> to_string() |> String.length()

  defp estimated_credits(text, model_id, models) do
    character_count(text) * credit_multiplier(model_id, models)
  end

  defp credit_multiplier(model_id, models) do
    case Enum.find(models, &(&1.id == model_id)) do
      %{id: id, name: name} ->
        if flash_or_turbo_model?(id) or flash_or_turbo_model?(name), do: 0.5, else: 1.0

      _ ->
        if flash_or_turbo_model?(model_id), do: 0.5, else: 1.0
    end
  end

  defp flash_or_turbo_model?(value) when is_binary(value) do
    normalized = String.downcase(value)
    String.contains?(normalized, "flash") or String.contains?(normalized, "turbo")
  end

  defp flash_or_turbo_model?(_), do: false

  defp character_usage_label(text) do
    ratio = usage_ratio(text)

    cond do
      ratio > 1.0 -> "2 chamadas"
      ratio >= 0.9 -> "perto do limite"
      ratio >= 0.6 -> "faixa média"
      true -> "baixo consumo"
    end
  end

  defp character_usage_hint(text) do
    ratio = usage_ratio(text)

    cond do
      ratio > 1.0 -> "Texto acima de 5000 chars. O Phoenix TTS divide em 2 chamadas separadas."
      ratio >= 0.9 -> "Texto grande. Se falhar, corte em blocos menores."
      ratio >= 0.6 -> "Texto saudável para geração contínua."
      true -> "Texto curto, bom para iteração rápida."
    end
  end

  defp usage_color(text) do
    ratio = usage_ratio(text)

    cond do
      ratio > 1.0 -> "text-[#ffd36a]"
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
