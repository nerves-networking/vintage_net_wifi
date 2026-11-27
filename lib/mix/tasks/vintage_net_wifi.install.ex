# SPDX-FileCopyrightText: 2025 Jonatan Männchen <jonatan@maennchen.ch>
# SPDX-FileCopyrightText: 2026 Lars Wikman
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Mix.Tasks.VintageNetWifi.Install.Docs do
  @moduledoc false

  @spec short_doc() :: String.t()
  def short_doc() do
    "Installs vintage_net_wifi in your Nerves project."
  end

  @spec example() :: String.t()
  def example() do
    "mix igniter.install vintage_net_wifi --regulatory-domain US"
  end

  @spec long_doc() :: String.t()
  def long_doc() do
    """
    #{short_doc()}

    This adds a WiFi network interface and the WiFi regulatory domain to
    VintageNet's configuration in `config/target.exs`:

    ```elixir
    config :vintage_net,
      regulatory_domain: "00",
      config: [
        {"wlan0", %{type: VintageNetWiFi}}
      ]
    ```

    That's the same configuration that new Nerves projects start with. It
    enables WiFi without any networks to connect to. Network interfaces that
    are already configured are kept. If the project already configures a
    `VintageNetWiFi` interface and `--wifi-ifname` isn't specified, nothing is
    added.

    The regulatory domain is part of the `:vintage_net` configuration, but it
    only applies to WiFi, so it's this installer that sets it and not
    `mix vintage_net.install`.

    If the project doesn't have a `config/target.exs`, the configuration is
    written to `config/config.exs`.

    ## WiFi networks and passphrases

    This installer doesn't write SSIDs or passphrases to the project and has no
    options for it. Anything in `config/target.exs` ends up in version control
    and is readable in every firmware image built from it. Networks set at
    runtime are persisted on the device by VintageNet, so configure them by
    calling `VintageNetWiFi.quick_configure/2` from the IEx prompt or set them
    when writing the MicroSD card as described next.

    ## WiFi provisioning

    Pass `--wifi-provisioning` to be able to set the WiFi credentials when the
    firmware is written to a MicroSD card:

    ```bash
    NERVES_WIFI_SSID='my_access_point' NERVES_WIFI_PASSPHRASE='secret_passphrase' mix burn
    ```

    This is the mechanism that Nerves Livebook uses. The option adds:

    * `config/provisioning.conf` - has `fwup` store the `NERVES_WIFI_SSID`,
      `NERVES_WIFI_PASSPHRASE` and `NERVES_WIFI_FORCE` environment variables in
      the U-Boot environment block of the MicroSD card when it's written. It
      includes the Nerves system's provisioning file so that
      `NERVES_SERIAL_NUMBER` and anything else that the system provisions keeps
      working.
    * `config :nerves, :firmware, provisioning: "config/provisioning.conf"` in
      `config/config.exs` to have Nerves use that file. A `:provisioning`
      setting that's already there is kept.
    * A `WiFiProvisioning` module in your project. Its `setup/0` function reads
      the credentials with `Nerves.Runtime.KV` and calls
      `VintageNetWiFi.quick_configure/2` if `wlan0` doesn't have a network
      configured yet or if `NERVES_WIFI_FORCE` was set. It does nothing when the
      project is compiled for the host.
    * A call to `setup/0` at the start of your application's `start/2`.

    Nothing is added without the option. With it, no credentials are written
    to the project or to the firmware file.

    ## Example

    ```bash
    #{example()}
    ```

    ## Options

    * `--wifi-ifname` - The name of the WiFi network interface to configure.
      Defaults to `wlan0`. When specified, the interface is added even if
      another `VintageNetWiFi` interface is already configured.
    * `--regulatory-domain` - The ISO 3166-1 alpha-2 country code for where the
      device is used. E.g., `US`. When specified, it replaces a regulatory
      domain that's already configured. When not specified, an existing
      regulatory domain is kept and `00`, the world regulatory domain, is
      written if the project doesn't have one.
    * `--wifi-provisioning` - Set up the project for setting WiFi credentials
      when writing firmware to a MicroSD card. See the WiFi provisioning
      section. Defaults to `false`.
    """
  end
end

cond do
  Code.ensure_loaded?(Igniter) and Code.ensure_loaded?(VintageNet.Generator) ->
    defmodule Mix.Tasks.VintageNetWifi.Install do
      @shortdoc "#{__MODULE__.Docs.short_doc()}"

      @moduledoc __MODULE__.Docs.long_doc()

      use Igniter.Mix.Task

      alias Igniter.Code.Common
      alias Igniter.Code.Function, as: CodeFunction
      alias Igniter.Project.Application, as: ProjectApplication
      alias Igniter.Project.Config
      alias Igniter.Project.Deps
      alias Igniter.Project.Module, as: ProjectModule
      alias Sourceror.Zipper
      alias VintageNet.Generator

      @default_ifname "wlan0"
      @world_regulatory_domain "00"

      @provisioning_path "config/provisioning.conf"

      @provisioning_lines ~S"""
      uboot_setenv(uboot-env, "wifi_ssid", "\${NERVES_WIFI_SSID}")
      uboot_setenv(uboot-env, "wifi_passphrase", "\${NERVES_WIFI_PASSPHRASE}")
      uboot_setenv(uboot-env, "wifi_force", "\${NERVES_WIFI_FORCE}")
      """

      @provisioning_header ~S"""
      # Firmware provisioning
      #
      # fwup runs this when it writes the firmware to a MicroSD card. It's used
      # instead of the Nerves system's provisioning file. See the `:provisioning`
      # key of `config :nerves, :firmware` in the project's config.

      # Keep what the Nerves system provisions. For the official Nerves systems,
      # that's the device serial number, which can be set with $NERVES_SERIAL_NUMBER.
      include("${NERVES_SYSTEM}/images/fwup_include/provisioning.conf")

      # Support setting the initial WiFi credentials when creating MicroSD cards.
      # For example,
      #
      #   NERVES_WIFI_SSID='my_access_point' NERVES_WIFI_PASSPHRASE='secret' mix burn
      #
      # Note that the '$' is escaped so that environment variable replacement happens
      # when firmware is written to the MicroSD card rather than when the '.fw' file
      # is created. WiFi credentials are not stored in the .fw file. If left blank,
      # the device won't connect to WiFi and you'll need to configure it via an IEx
      # prompt by calling VintageNetWiFi.quick_configure/2.
      #
      # IMPORTANT: If you configure WiFi via the IEx prompt, that configuration will
      # be persisted and these won't be used unless $NERVES_WIFI_FORCE is set to
      # "true" (or anything other than "false")
      """

      @provisioning_conf @provisioning_header <> @provisioning_lines

      # The body of the module that applies the provisioned credentials. The
      # logic is `setup_wifi/0` from Nerves Livebook's application module.
      @provisioning_module ~S'''
      @moduledoc """
      Configures WiFi with credentials that were set when the MicroSD card was written

      WiFi credentials aren't part of the project or the firmware file. They're
      stored in the U-Boot environment block of the MicroSD card when the
      firmware is written to it. See `config/provisioning.conf`. To set them, run:

      ```sh
      NERVES_WIFI_SSID='my_access_point' NERVES_WIFI_PASSPHRASE='secret_passphrase' mix burn
      ```

      `setup/0` is called when the application starts. It configures WiFi with
      those credentials if `"wlan0"` doesn't have a network configured.
      VintageNet saves the configuration on the device, so WiFi that's
      configured later with `VintageNetWiFi.quick_configure/2` or
      `VintageNet.configure/3` is kept. To have the credentials from the MicroSD
      card replace it, also set `NERVES_WIFI_FORCE=true` when writing the card.
      """

      @doc """
      Configure WiFi if credentials were provisioned and they're needed

      This does nothing when the project is compiled for the host.
      """
      @spec setup() :: :ok

      if Mix.target() == :host do
        def setup(), do: :ok
      else
        require Logger

        def setup() do
          kv = Nerves.Runtime.KV.get_all()
          ssid = kv["wifi_ssid"]

          if not empty?(ssid) and (true?(kv["wifi_force"]) or not wlan0_configured?()) do
            case VintageNetWiFi.quick_configure(ssid, kv["wifi_passphrase"]) do
              :ok -> :ok
              {:error, reason} -> Logger.warning("Could not configure WiFi: #{inspect(reason)}")
            end
          end

          :ok
        end

        defp wlan0_configured?() do
          VintageNet.get_configuration("wlan0") |> VintageNetWiFi.network_configured?()
        catch
          _, _ -> false
        end

        defp true?(""), do: false
        defp true?(nil), do: false
        defp true?("false"), do: false
        defp true?("FALSE"), do: false
        defp true?(_), do: true

        defp empty?(""), do: true
        defp empty?(nil), do: true
        defp empty?(_), do: false
      end
      '''

      @impl Igniter.Mix.Task
      def info(_argv, _composing_task) do
        %Igniter.Mix.Task.Info{
          group: :vintage_net_wifi,
          example: __MODULE__.Docs.example(),
          composes: ["vintage_net.install"],
          schema: [
            wifi_ifname: :string,
            regulatory_domain: :string,
            wifi_provisioning: :boolean
          ],
          # `:wifi_ifname` and `:regulatory_domain` have no entries here so
          # that explicitly passing them can be told apart from the defaults.
          defaults: [wifi_provisioning: false]
        }
      end

      @impl Igniter.Mix.Task
      def igniter(igniter) do
        options = igniter.args.options
        explicit_ifname = options[:wifi_ifname]
        ifname = explicit_ifname || @default_ifname
        regulatory_domain = upcase(options[:regulatory_domain])
        provisioning? = options[:wifi_provisioning] == true

        case validate(ifname, regulatory_domain, provisioning?) do
          :ok ->
            # Look at the project before anything is changed
            quoted = quoted_config(igniter)
            wifi_configured? = configures_wifi?(quoted)
            world_domain? = configures_world_regulatory_domain?(quoted)
            domain_configured? = configures_regulatory_domain?(igniter)

            igniter
            |> restrict_dep_to_targets()
            |> add_regulatory_domain(regulatory_domain)
            |> Igniter.compose_task("vintage_net.install", [])
            |> maybe_add_interface(ifname, wifi_configured? and is_nil(explicit_ifname))
            |> maybe_add_regulatory_domain_notice(
              is_nil(regulatory_domain) and
                (not domain_configured? or (world_domain? and not wifi_configured?))
            )
            |> maybe_add_networks_notice(wifi_configured? or provisioning?)
            |> maybe_add_provisioning(provisioning?)

          {:error, issue} ->
            Igniter.add_issue(igniter, issue)
        end
      end

      defp validate(ifname, regulatory_domain, provisioning?) do
        cond do
          not valid_ifname?(ifname) ->
            {:error,
             """
             vintage_net_wifi: invalid --wifi-ifname #{inspect(ifname)}.

             Pass the name of the WiFi network interface like wlan0.
             """}

          regulatory_domain != nil and not valid_regulatory_domain?(regulatory_domain) ->
            {:error,
             """
             vintage_net_wifi: invalid --regulatory-domain #{inspect(regulatory_domain)}.

             Pass an ISO 3166-1 alpha-2 country code like US, SE or JP, or 00 for
             the world regulatory domain.
             """}

          provisioning? and ifname != @default_ifname ->
            {:error,
             """
             vintage_net_wifi: --wifi-provisioning can't be used with --wifi-ifname #{ifname}.

             WiFi provisioning uses VintageNetWiFi.quick_configure/2 and it
             configures #{@default_ifname}.
             """}

          true ->
            :ok
        end
      end

      # Keeps vintage_net_wifi off the host when the project restricts other
      # dependencies to its targets. See VintageNet.Generator.
      defp restrict_dep_to_targets(igniter) do
        Generator.restrict_dep_to_targets(igniter, :vintage_net_wifi)
      end

      # Linux limits network interface names to 15 bytes and doesn't allow
      # whitespace or slashes in them.
      defp valid_ifname?(ifname), do: ifname =~ ~r/\A[^\s\/:]{1,15}\z/

      defp upcase(nil), do: nil
      defp upcase(regulatory_domain), do: String.upcase(regulatory_domain)

      defp valid_regulatory_domain?(regulatory_domain) do
        regulatory_domain =~ ~r/\A([A-Z]{2}|00)\z/
      end

      # The regulatory domain is only for WiFi, so vintage_net.install and the
      # installers for the other technologies don't write it. This one does.
      # An explicit `--regulatory-domain` replaces what's configured. The
      # default never does.
      defp add_regulatory_domain(igniter, nil) do
        Generator.add_regulatory_domain(igniter, @world_regulatory_domain)
      end

      defp add_regulatory_domain(igniter, regulatory_domain) do
        Generator.add_regulatory_domain(igniter, regulatory_domain, overwrite?: true)
      end

      defp configures_regulatory_domain?(igniter) do
        file = Generator.config_file(igniter)

        Igniter.exists?(igniter, "config/#{file}") and
          Config.configures_key?(igniter, file, :vintage_net, :regulatory_domain)
      end

      defp maybe_add_interface(igniter, _ifname, true), do: igniter

      defp maybe_add_interface(igniter, ifname, false) do
        Generator.add_interface(igniter, ifname, %{type: VintageNetWiFi})
      end

      # The user is told about the world regulatory domain when this installer
      # writes it and when WiFi is added to a project that already has it.
      # Projects that already have WiFi configured were told when it was added.
      defp maybe_add_regulatory_domain_notice(igniter, false), do: igniter

      defp maybe_add_regulatory_domain_notice(igniter, true) do
        file = Generator.config_file(igniter)

        Igniter.add_notice(igniter, """
        vintage_net_wifi: the regulatory domain is "#{@world_regulatory_domain}" (world) in config/#{file}.

        Update `regulatory_domain` to the 2-letter country code for where the
        device is used. E.g., "US". The world regulatory domain restricts the
        WiFi channels and transmit power that are available. Rerun with
        `--regulatory-domain` to have it changed for you. If the device may be
        used in different countries, see the vintage_net_wifi README for setting
        it at runtime.
        """)
      end

      defp maybe_add_networks_notice(igniter, true), do: igniter

      defp maybe_add_networks_notice(igniter, false) do
        Igniter.add_notice(igniter, """
        vintage_net_wifi: no WiFi networks were configured.

        SSIDs and passphrases don't belong in the project's config files since
        they'd be in version control and in every firmware image. Set them at
        runtime instead. VintageNet saves them on the device:

            iex> VintageNetWiFi.quick_configure("my_access_point", "secret_passphrase")

        To be able to set them when writing a MicroSD card, rerun with
        `--wifi-provisioning`.
        """)
      end

      ## WiFi provisioning
      #
      # This sets up what Nerves Livebook does: fwup stores WiFi credentials
      # from environment variables in the U-Boot environment when a MicroSD
      # card is written and the application applies them when it starts.

      defp maybe_add_provisioning(igniter, false), do: igniter

      defp maybe_add_provisioning(igniter, true) do
        module = ProjectModule.module_name(igniter, "WiFiProvisioning")
        {module_exists?, igniter} = ProjectModule.module_exists(igniter, module)

        igniter
        |> add_provisioning_conf()
        |> add_provisioning_module(module, module_exists?)
        |> add_setup_call(module)
        |> maybe_add_nerves_runtime_notice(module_exists?)
        |> maybe_add_provisioning_notice(module, module_exists?)
      end

      # `config :nerves, :firmware` is in config/config.exs in Nerves projects.
      # config/target.exs is checked as well to not add a second one if that's
      # where a project has it.
      defp add_provisioning_conf(igniter) do
        files =
          Enum.filter(["config.exs", "target.exs"], &Igniter.exists?(igniter, "config/#{&1}"))

        configured_in = Enum.find(files, &configures_firmware?(igniter, &1, [:provisioning]))
        firmware_in = Enum.find(files, &configures_firmware?(igniter, &1, []))

        cond do
          configured_in == nil ->
            igniter
            |> Config.configure_new(
              firmware_in || "config.exs",
              :nerves,
              [:firmware, :provisioning],
              @provisioning_path
            )
            |> create_provisioning_conf()

          provisioning_value(igniter, configured_in) == inspect(@provisioning_path) ->
            create_provisioning_conf(igniter)

          true ->
            Igniter.add_notice(igniter, """
            vintage_net_wifi: the firmware provisioning setting in config/#{configured_in} was kept:

                config :nerves, :firmware, provisioning: #{provisioning_value(igniter, configured_in)}

            For WiFi provisioning, add the following to the fwup provisioning
            file that it refers to:

            #{indent(@provisioning_lines)}
            """)
        end
      end

      defp configures_firmware?(igniter, file, path) do
        Config.configures_key?(igniter, file, :nerves, [:firmware | path])
      end

      # The source code of the value of the `provisioning:` key
      defp provisioning_value(igniter, file) do
        zipper =
          igniter
          |> existing_source("config/#{file}")
          |> Rewrite.Source.get(:quoted)
          |> Zipper.zip()
          |> Zipper.find(&match?({{:__block__, _, [:provisioning]}, _value}, &1))

        case zipper do
          %Zipper{node: {_key, value}} -> Sourceror.to_string(value)
          nil -> "..."
        end
      end

      defp create_provisioning_conf(igniter) do
        cond do
          not Igniter.exists?(igniter, @provisioning_path) ->
            Igniter.create_new_file(igniter, @provisioning_path, @provisioning_conf)

          igniter |> existing_source(@provisioning_path) |> Rewrite.Source.get(:content) =~
              "wifi_ssid" ->
            igniter

          true ->
            Igniter.add_notice(igniter, """
            vintage_net_wifi: #{@provisioning_path} already exists and was kept.

            For WiFi provisioning, add the following to it:

            #{indent(@provisioning_lines)}
            """)
        end
      end

      defp add_provisioning_module(igniter, _module, true), do: igniter

      defp add_provisioning_module(igniter, module, false) do
        # Igniter would name the file wi_fi_provisioning.ex
        app = ProjectApplication.app_name(igniter)
        path = Path.join(["lib", to_string(app), "wifi_provisioning.ex"])

        ProjectModule.create_module(igniter, module, @provisioning_module, path: path)
      end

      defp add_setup_call(igniter, module) do
        call = "#{inspect(module)}.setup()"

        with app_module when not is_nil(app_module) <-
               ProjectApplication.app_module(igniter),
             {:ok, {igniter, _source, zipper}} <-
               ProjectModule.find_module(igniter, app_module),
             {:call?, false, igniter} <- {:call?, calls_setup?(zipper, module), igniter},
             {:ok, _zipper} <- CodeFunction.move_to_def(zipper, :start, 2),
             {:ok, igniter} <-
               ProjectModule.find_and_update_module(igniter, app_module, fn zipper ->
                 {:ok, zipper} = CodeFunction.move_to_def(zipper, :start, 2)
                 {:ok, Common.add_code(zipper, call, placement: :before)}
               end) do
          igniter
        else
          {:call?, true, igniter} -> igniter
          {:error, %Igniter{} = igniter} -> add_setup_call_notice(igniter, call)
          _ -> add_setup_call_notice(igniter, call)
        end
      end

      defp add_setup_call_notice(igniter, call) do
        Igniter.add_notice(igniter, """
        vintage_net_wifi: could not find the `start/2` function of an OTP
        application module in this project. Add the following to the start
        of it to configure WiFi when your application starts:

            #{call}
        """)
      end

      # Matches `MyApp.WiFiProvisioning.setup()` and the aliased
      # `WiFiProvisioning.setup()`
      defp calls_setup?(zipper, module) do
        name = module |> Module.split() |> List.last()

        Zipper.find(zipper, fn
          {{:., _, [{:__aliases__, _, aliases}, :setup]}, _, []} ->
            Atom.to_string(List.last(aliases)) == name

          _ ->
            false
        end) != nil
      end

      defp maybe_add_nerves_runtime_notice(igniter, true), do: igniter

      defp maybe_add_nerves_runtime_notice(igniter, false) do
        if Deps.has_dep?(igniter, :nerves_runtime) do
          igniter
        else
          Igniter.add_notice(igniter, """
          vintage_net_wifi: WiFi provisioning reads the WiFi credentials with
          Nerves.Runtime.KV. Add `:nerves_runtime` to the dependencies in
          mix.exs if your project doesn't get it from another dependency.
          """)
        end
      end

      defp maybe_add_provisioning_notice(igniter, _module, true), do: igniter

      defp maybe_add_provisioning_notice(igniter, module, false) do
        Igniter.add_notice(igniter, """
        vintage_net_wifi: WiFi provisioning was set up.

        Set the WiFi credentials when writing the firmware to a MicroSD card:

            NERVES_WIFI_SSID='my_access_point' NERVES_WIFI_PASSPHRASE='secret_passphrase' mix burn

        They're stored on the MicroSD card and not in your project or in the
        .fw file. #{inspect(module)}.setup/0 applies them when the
        device boots and #{@default_ifname} doesn't have a network configured. Also set
        NERVES_WIFI_FORCE=true to have them replace a configuration that's
        saved on the device.

        WiFi can still be configured at the IEx prompt. VintageNet saves the
        configuration on the device:

            iex> VintageNetWiFi.quick_configure("my_access_point", "secret_passphrase")

        VintageNetWiFi.quick_configure/2 creates WPA2 configurations by default.
        If your WiFi module supports WPA3, see the documentation of that
        function for how to have it create configurations for both.
        """)
      end

      defp indent(text) do
        text |> String.trim_trailing() |> String.replace(~r/^(?=.)/m, "    ")
      end

      defp existing_source(igniter, path) do
        igniter
        |> Igniter.include_existing_file(path)
        |> Map.fetch!(:rewrite)
        |> Rewrite.source!(path)
      end

      defp quoted_config(igniter) do
        path = "config/#{Generator.config_file(igniter)}"

        if Igniter.exists?(igniter, path) do
          igniter |> existing_source(path) |> Rewrite.Source.get(:quoted)
        end
      end

      defp configures_wifi?(quoted) do
        find_in_quoted?(
          quoted,
          &match?({{:__block__, _, [:type]}, {:__aliases__, _, [:VintageNetWiFi]}}, &1)
        )
      end

      defp configures_world_regulatory_domain?(quoted) do
        find_in_quoted?(quoted, fn
          # config :vintage_net, regulatory_domain: "00"
          {{:__block__, _, [:regulatory_domain]}, {:__block__, _, [@world_regulatory_domain]}} ->
            true

          # config :vintage_net, :regulatory_domain, "00"
          {:config, _,
           [
             {:__block__, _, [:vintage_net]},
             {:__block__, _, [:regulatory_domain]},
             {:__block__, _, [@world_regulatory_domain]}
           ]} ->
            true

          _ ->
            false
        end)
      end

      defp find_in_quoted?(nil, _pred), do: false

      defp find_in_quoted?(quoted, pred) do
        quoted |> Zipper.zip() |> Zipper.find(pred) != nil
      end
    end

  Code.ensure_loaded?(Igniter) ->
    defmodule Mix.Tasks.VintageNetWifi.Install do
      @shortdoc "#{__MODULE__.Docs.short_doc()} | Update `vintage_net` to use"

      @moduledoc __MODULE__.Docs.long_doc()

      use Mix.Task

      @impl Mix.Task
      def run(_argv) do
        Mix.shell().error("""
        The task 'vintage_net_wifi.install' requires a version of vintage_net that has
        VintageNet.Generator. Please update vintage_net (`mix deps.update vintage_net`)
        and try again.
        """)

        exit({:shutdown, 1})
      end
    end

  true ->
    defmodule Mix.Tasks.VintageNetWifi.Install do
      @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

      @moduledoc __MODULE__.Docs.long_doc()

      use Mix.Task

      @impl Mix.Task
      def run(_argv) do
        Mix.shell().error("""
        The task 'vintage_net_wifi.install' requires igniter. Please install igniter and try again.

        For more information, see: https://igniter.hexdocs.pm/readme.html#installation
        """)

        exit({:shutdown, 1})
      end
    end
end
