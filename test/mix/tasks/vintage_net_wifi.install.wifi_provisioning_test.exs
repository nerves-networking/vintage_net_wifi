# SPDX-FileCopyrightText: 2026 Lars Wikman
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Mix.Tasks.VintageNetWifi.Install.WiFiProvisioningTest do
  # Not async since compiling the generated module for a device changes
  # `Mix.target/0`
  use ExUnit.Case, async: false

  import Igniter.Test

  # config/config.exs from `mix nerves.new` and `mix nerves.install`
  @config_exs """
  # This file is responsible for configuring your application and its
  # dependencies.
  #
  # This configuration file is loaded before any dependency and is restricted to
  # this project.
  import Config

  # Enable the Nerves integration with Mix
  Application.start(:nerves_bootstrap)

  # Customize non-Elixir parts of the firmware. See
  # https://nerves.hexdocs.pm/advanced-configuration.html for details.

  config :nerves, :firmware, rootfs_overlay: "rootfs_overlay"

  # Set the SOURCE_DATE_EPOCH date for reproducible builds.
  # See https://reproducible-builds.org/docs/source-date-epoch/ for more information

  config :nerves, source_date_epoch: "1764230400"

  if Mix.target() == :host do
    import_config "host.exs"
  else
    import_config "target.exs"
  end
  """

  # config/target.exs from `mix nerves.install`
  @nerves_install_target_exs """
  import Config

  # Influence OTP application start order to ensure that logging and basic Nerves
  # services start as early as allowed. This can help with debugging misbehaving
  # applications and can also help perceived start time on slow devices.

  config :nerves, application_sort: [init: [:nerves_runtime]]

  # Import target specific config. This must remain at the bottom
  # of this file so it overrides the configuration defined above.
  # Uncomment to use target specific configurations

  # import_config "\#{Mix.target()}.exs"
  """

  # The networking part of config/target.exs from `mix nerves.new`
  @nerves_new_target_exs """
  import Config

  config :nerves, application_sort: [init: [:logger_backends, :nerves_runtime, :nerves_pack]]

  # Advance the system clock on devices without a real-time clock.
  config :nerves, :erlinit, update_clock: true

  # Configure the network using vintage_net
  #
  # Update regulatory_domain to your 2-letter country code E.g., "US"
  #
  # See https://github.com/nerves-networking/vintage_net for more information
  config :vintage_net,
    regulatory_domain: "00",
    config: [
      {"usb0", %{type: VintageNetDirect}},
      {"eth0",
       %{
         type: VintageNetEthernet,
         ipv4: %{method: :dhcp}
       }},
      {"wlan0", %{type: VintageNetWiFi}}
    ]

  # import_config "\#{Mix.target()}.exs"
  """

  # lib/test/application.ex from `mix nerves.new` and `mix nerves.install`
  @application_ex """
  defmodule Test.Application do
    # See https://elixir.hexdocs.pm/Application.html
    # for more information on OTP Applications
    @moduledoc false

    use Application

    @impl true
    def start(_type, _args) do
      children =
        [
          # Children for all targets
          # Starts a worker by calling: Test.Worker.start_link(arg)
          # {Test.Worker, arg},
        ] ++ target_children()

      # See https://elixir.hexdocs.pm/Supervisor.html
      # for other strategies and supported options
      opts = [strategy: :one_for_one, name: Test.Supervisor]
      Supervisor.start_link(children, opts)
    end

    # List all child processes to be supervised
    if Mix.target() == :host do
      defp target_children() do
        [
          # Children that only run on the host during development or test.
          # In general, prefer using `config/host.exs` for differences.
          #
          # Starts a worker by calling: Host.Worker.start_link(arg)
          # {Host.Worker, arg},
        ]
      end
    else
      defp target_children() do
        [
          # Children for all targets except host
          # Starts a worker by calling: Target.Worker.start_link(arg)
          # {Target.Worker, arg},
        ]
      end
    end
  end
  """

  defp mix_exs(deps) do
    """
    defmodule Test.MixProject do
      use Mix.Project

      @app :test
      @all_targets [:rpi4, :rpi5]

      def project do
        [app: @app, version: "0.1.0", deps: deps(), releases: [{@app, release()}]]
      end

      def application do
        [
          extra_applications: [:logger, :runtime_tools],
          mod: {Test.Application, []}
        ]
      end

      defp deps do
        [
          {:nerves, "~> 2.0", runtime: false},
          {:nerves_runtime, "~> 0.13.12"},
          #{Enum.join(deps, ",\n      ")}
        ]
      end

      def release do
        [steps: [&Nerves.init_release/1, :assemble]]
      end
    end
    """
  end

  # A project that `mix nerves.install` set up and that vintage_net_wifi is
  # being added to
  defp nerves_install_project(files \\ %{}) do
    test_project(
      files:
        Map.merge(
          %{
            "mix.exs" => mix_exs([~s|{:vintage_net_wifi, "~> 0.12"}|]),
            "config/config.exs" => @config_exs,
            "config/host.exs" => "import Config\n",
            "config/target.exs" => @nerves_install_target_exs,
            "lib/test/application.ex" => @application_ex
          },
          files
        )
    )
  end

  # A project from `mix nerves.new`. It has WiFi via nerves_pack.
  defp nerves_new_project(files \\ %{}) do
    test_project(
      files:
        Map.merge(
          %{
            "mix.exs" => mix_exs([~s|{:nerves_pack, "~> 0.7.1", targets: @all_targets}|]),
            "config/config.exs" => @config_exs,
            "config/host.exs" => "import Config\n",
            "config/target.exs" => @nerves_new_target_exs,
            "lib/test/application.ex" => @application_ex
          },
          files
        )
    )
  end

  defp install(igniter, argv \\ ["--wifi-provisioning"]) do
    Igniter.compose_task(igniter, "vintage_net_wifi.install", argv)
  end

  defp content(igniter, path) do
    igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)
  end

  defp notices_matching(igniter, text) do
    Enum.filter(igniter.notices, &(&1 =~ text))
  end

  defp changed_paths(igniter) do
    igniter.rewrite
    |> Rewrite.sources()
    |> Enum.filter(&(Rewrite.Source.from?(&1, :string) or Rewrite.Source.updated?(&1)))
    |> Enum.map(& &1.path)
    |> Enum.sort()
  end

  describe "without --wifi-provisioning" do
    test "only the network configuration is touched" do
      igniter = nerves_install_project() |> install([])

      assert changed_paths(igniter) == ["config/target.exs", "mix.exs"]

      igniter
      |> assert_unchanged("config/config.exs")
      |> assert_unchanged("lib/test/application.ex")
      |> refute_creates("config/provisioning.conf")
      |> refute_creates("lib/test/wifi_provisioning.ex")

      assert notices_matching(igniter, "WiFi provisioning was set up") == []
      assert [_] = notices_matching(igniter, "rerun with\n`--wifi-provisioning`")
    end

    test "--no-wifi-provisioning is the same" do
      igniter = nerves_install_project() |> install(["--no-wifi-provisioning"])

      assert changed_paths(igniter) == ["config/target.exs", "mix.exs"]
    end

    test "mix nerves.new projects aren't changed" do
      nerves_new_project() |> install([]) |> assert_unchanged()
    end
  end

  describe "in a mix nerves.install project" do
    test "sets up provisioning" do
      igniter =
        nerves_install_project()
        |> install()
        |> assert_has_patch("config/config.exs", """
        - |config :nerves, :firmware, rootfs_overlay: "rootfs_overlay"
        + |config :nerves, :firmware,
        + |  rootfs_overlay: "rootfs_overlay",
        + |  provisioning: "config/provisioning.conf"
        """)
        |> assert_has_patch("lib/test/application.ex", """
          |  def start(_type, _args) do
        + |    Test.WiFiProvisioning.setup()
        + |
          |    children =
        """)
        |> assert_has_patch("config/target.exs", """
        + |config :vintage_net, regulatory_domain: "00", config: [{"wlan0", %{type: VintageNetWiFi}}]
        """)
        |> assert_creates("config/provisioning.conf")
        |> assert_creates("lib/test/wifi_provisioning.ex")
        |> assert_unchanged("config/host.exs")

      assert changed_paths(igniter) == [
               "config/config.exs",
               "config/provisioning.conf",
               "config/target.exs",
               "lib/test/application.ex",
               "lib/test/wifi_provisioning.ex",
               "mix.exs"
             ]

      assert igniter.issues == []
      assert igniter.warnings == []

      assert [notice] = notices_matching(igniter, "WiFi provisioning was set up")
      assert notice =~ "NERVES_WIFI_SSID='my_access_point'"
      assert notice =~ "NERVES_WIFI_PASSPHRASE='secret_passphrase' mix burn"
      assert notice =~ "NERVES_WIFI_FORCE"

      assert notice =~
               ~s|iex> VintageNetWiFi.quick_configure("my_access_point", "secret_passphrase")|

      # Covered by the provisioning notice
      assert notices_matching(igniter, "no WiFi networks were configured") == []
      # nerves_runtime is a dependency
      assert notices_matching(igniter, "Nerves.Runtime.KV") == []
    end

    test "the fwup provisioning file keeps the system's provisioning and adds WiFi" do
      igniter = nerves_install_project() |> install()
      conf = content(igniter, "config/provisioning.conf")

      # Evaluated when the firmware is created
      assert conf =~ ~S|include("${NERVES_SYSTEM}/images/fwup_include/provisioning.conf")|

      # Escaped so that they're evaluated when the MicroSD card is written
      assert conf =~ ~S|uboot_setenv(uboot-env, "wifi_ssid", "\${NERVES_WIFI_SSID}")|
      assert conf =~ ~S|uboot_setenv(uboot-env, "wifi_passphrase", "\${NERVES_WIFI_PASSPHRASE}")|
      assert conf =~ ~S|uboot_setenv(uboot-env, "wifi_force", "\${NERVES_WIFI_FORCE}")|

      # Every environment variable reference other than the include is escaped
      unescaped = Regex.scan(~r/^[^#\n]*(?<!\\)\$\{(\w+)\}/m, conf, capture: :all_but_first)
      assert unescaped == [["NERVES_SYSTEM"]]
    end

    test "is idempotent" do
      igniter = nerves_install_project() |> install() |> apply_igniter!()

      igniter = igniter |> install() |> assert_unchanged()
      assert igniter.notices == []

      # Not passing the option later doesn't remove anything
      igniter |> install([]) |> assert_unchanged()
    end

    test "can be added after installing without it" do
      igniter = nerves_install_project() |> install([]) |> apply_igniter!() |> install()

      assert changed_paths(igniter) == [
               "config/config.exs",
               "config/provisioning.conf",
               "lib/test/application.ex",
               "lib/test/wifi_provisioning.ex"
             ]

      assert [_] = notices_matching(igniter, "WiFi provisioning was set up")
    end

    test "--regulatory-domain still applies" do
      igniter =
        nerves_install_project() |> install(["--wifi-provisioning", "--regulatory-domain", "se"])

      assert content(igniter, "config/target.exs") =~
               ~s|config :vintage_net, regulatory_domain: "SE", config: [{"wlan0", %{type: VintageNetWiFi}}]|
    end
  end

  describe "in a mix nerves.new project" do
    test "sets up provisioning and leaves the network configuration alone" do
      igniter =
        nerves_new_project()
        |> install()
        |> assert_has_patch("config/config.exs", """
        + |  provisioning: "config/provisioning.conf"
        """)
        |> assert_has_patch("lib/test/application.ex", """
        + |    Test.WiFiProvisioning.setup()
        """)
        |> assert_creates("config/provisioning.conf")
        |> assert_creates("lib/test/wifi_provisioning.ex")
        |> assert_unchanged("config/target.exs")
        |> assert_unchanged("mix.exs")

      assert [_] = notices_matching(igniter, "WiFi provisioning was set up")
      assert notices_matching(igniter, "regulatory domain") == []

      igniter |> apply_igniter!() |> install() |> assert_unchanged()
    end
  end

  describe "existing provisioning" do
    test "a provisioning setting is kept and no file is created" do
      config_exs =
        String.replace(
          @config_exs,
          ~s|config :nerves, :firmware, rootfs_overlay: "rootfs_overlay"|,
          ~s|config :nerves, :firmware,\n  rootfs_overlay: "rootfs_overlay",\n  provisioning: "priv/factory.conf"|
        )

      igniter =
        nerves_new_project(%{"config/config.exs" => config_exs})
        |> install()
        |> assert_unchanged("config/config.exs")
        |> refute_creates("config/provisioning.conf")
        |> assert_creates("lib/test/wifi_provisioning.ex")

      assert [notice] =
               notices_matching(igniter, "provisioning setting in config/config.exs was kept")

      assert notice =~ ~s|provisioning: "priv/factory.conf"|
      assert notice =~ ~S|uboot_setenv(uboot-env, "wifi_ssid", "\${NERVES_WIFI_SSID}")|
    end

    test "provisioning from an application is kept" do
      config_exs = @config_exs <> "\nconfig :nerves, :firmware, provisioning: :nerves_hub_link\n"

      igniter =
        nerves_new_project(%{"config/config.exs" => config_exs})
        |> install()
        |> assert_unchanged("config/config.exs")
        |> refute_creates("config/provisioning.conf")

      assert [notice] =
               notices_matching(igniter, "provisioning setting in config/config.exs was kept")

      assert notice =~ "provisioning: :nerves_hub_link"
    end

    test "a provisioning setting in config/target.exs is kept" do
      target_exs =
        @nerves_new_target_exs <> "\nconfig :nerves, :firmware, provisioning: \"my.conf\"\n"

      igniter =
        nerves_new_project(%{"config/target.exs" => target_exs})
        |> install()
        |> assert_unchanged("config/config.exs")
        |> assert_unchanged("config/target.exs")
        |> refute_creates("config/provisioning.conf")

      assert [_] = notices_matching(igniter, "provisioning setting in config/target.exs was kept")
    end

    test "a provisioning file that isn't configured is kept and gets configured" do
      conf = "uboot_setenv(uboot-env, \"my_key\", \"\\${MY_KEY}\")\n"

      igniter =
        nerves_new_project(%{"config/provisioning.conf" => conf})
        |> install()
        |> assert_unchanged("config/provisioning.conf")
        |> assert_has_patch("config/config.exs", """
        + |  provisioning: "config/provisioning.conf"
        """)

      assert [notice] =
               notices_matching(igniter, "config/provisioning.conf already exists and was kept")

      assert notice =~
               ~S|uboot_setenv(uboot-env, "wifi_passphrase", "\${NERVES_WIFI_PASSPHRASE}")|
    end

    test "a provisioning file that has WiFi provisioning is kept without a notice" do
      conf = ~S"""
      uboot_setenv(uboot-env, "wifi_ssid", "\${NERVES_WIFI_SSID}")
      """

      config_exs =
        String.replace(
          @config_exs,
          ~s|rootfs_overlay: "rootfs_overlay"|,
          ~s|rootfs_overlay: "rootfs_overlay", provisioning: "config/provisioning.conf"|
        )

      igniter =
        nerves_new_project(%{
          "config/provisioning.conf" => conf,
          "config/config.exs" => config_exs
        })
        |> install()
        |> assert_unchanged("config/provisioning.conf")
        |> assert_unchanged("config/config.exs")

      assert notices_matching(igniter, "was kept") == []
    end

    test "an existing module is kept" do
      module = """
      defmodule Test.WiFiProvisioning do
        def setup(), do: :mine
      end
      """

      for path <- [
            "lib/test/wifi_provisioning.ex",
            "lib/test/wi_fi_provisioning.ex",
            "lib/other.ex"
          ] do
        igniter =
          nerves_new_project(%{path => module})
          |> install()
          |> assert_unchanged(path)
          |> assert_has_patch("lib/test/application.ex", """
          + |    Test.WiFiProvisioning.setup()
          """)

        assert content(igniter, path) == module
        refute Enum.any?(changed_paths(igniter), &(&1 =~ "provisioning.ex"))
      end
    end

    test "an existing call is kept" do
      for call <- ["Test.WiFiProvisioning.setup()", "_ = WiFiProvisioning.setup()"] do
        application_ex =
          String.replace(
            @application_ex,
            "    children =\n",
            "    children =\n      [] ++ []\n\n    #{call}\n\n    children =\n",
            global: false
          )

        nerves_new_project(%{"lib/test/application.ex" => application_ex})
        |> install()
        |> assert_unchanged("lib/test/application.ex")
        |> assert_creates("lib/test/wifi_provisioning.ex")
      end
    end
  end

  describe "projects that it can't be fully set up in" do
    test "a notice has the line to add when there's no application module" do
      igniter =
        test_project(files: %{"config/target.exs" => "import Config\n"})
        |> install()
        |> assert_creates("lib/test/wifi_provisioning.ex")
        |> assert_creates("config/provisioning.conf")
        |> assert_creates("config/config.exs", """
        import Config
        config :nerves, firmware: [provisioning: "config/provisioning.conf"]
        """)

      assert [notice] = notices_matching(igniter, "could not find the `start/2` function")
      assert notice =~ "    Test.WiFiProvisioning.setup()\n"

      # The test project doesn't depend on nerves_runtime
      assert [_] = notices_matching(igniter, "Nerves.Runtime.KV")

      igniter = igniter |> apply_igniter!() |> install() |> assert_unchanged()
      assert notices_matching(igniter, "WiFi provisioning was set up") == []
    end

    test "a notice has the line to add when the application has no start/2" do
      application_ex = """
      defmodule Test.Application do
        use Application
        use Test.Starter
      end
      """

      igniter =
        nerves_new_project(%{"lib/test/application.ex" => application_ex})
        |> install()
        |> assert_unchanged("lib/test/application.ex")

      assert [_] = notices_matching(igniter, "could not find the `start/2` function")
    end

    test "--wifi-ifname other than wlan0 is an issue" do
      igniter =
        nerves_install_project() |> install(["--wifi-provisioning", "--wifi-ifname", "mlan0"])

      assert_unchanged(igniter)

      assert Enum.any?(
               igniter.issues,
               &(&1 =~ "--wifi-provisioning can't be used with --wifi-ifname mlan0")
             )

      # Naming wlan0 is fine
      igniter =
        nerves_install_project() |> install(["--wifi-provisioning", "--wifi-ifname", "wlan0"])

      assert igniter.issues == []
      assert_creates(igniter, "lib/test/wifi_provisioning.ex")
    end
  end

  test "no credentials are written" do
    for project <- [nerves_install_project(), nerves_new_project()] do
      igniter = install(project)

      for path <- changed_paths(igniter), not String.starts_with?(path, "lib/test/wifi_") do
        text = content(igniter, path)

        refute text =~ ~r/psk|ssid:|networks:|my_access_point.*secret_passphrase/, path
      end

      # The only values for the U-Boot environment are references to
      # environment variables that are read when the MicroSD card is written
      conf = content(igniter, "config/provisioning.conf")

      for [value] <-
            Regex.scan(~r/^uboot_setenv\(uboot-env, "\w+", "(.*)"\)$/m, conf,
              capture: :all_but_first
            ) do
        assert value =~ ~r/^\\\$\{NERVES_WIFI_\w+\}$/
      end

      # The module gets them from the U-Boot environment on the device
      module = content(igniter, "lib/test/wifi_provisioning.ex")
      assert module =~ ~s|Nerves.Runtime.KV.get_all()|
      assert module =~ ~s|kv["wifi_ssid"]|
      assert module =~ ~s|kv["wifi_passphrase"]|
      refute module =~ ~r/quick_configure\("/
    end
  end

  describe "the generated module" do
    # Stands in for nerves_runtime, which isn't a dependency of vintage_net_wifi
    defmodule KV do
      @moduledoc false
      @spec get_all() :: %{String.t() => String.t()}
      def get_all(), do: Process.get(:wifi_provisioning_kv, %{})
    end

    # These stand in for VintageNet and VintageNetWiFi when the module is run
    # so that the tests don't configure the network of the machine they run on.
    defmodule FakeVintageNet do
      @moduledoc false
      @spec get_configuration(String.t()) :: map()
      def get_configuration("wlan0") do
        case Process.get(:wifi_provisioning_config, %{type: VintageNetWiFi}) do
          :raise -> raise ArgumentError, "wlan0 isn't configured"
          config -> config
        end
      end
    end

    defmodule FakeVintageNetWiFi do
      @moduledoc false
      @spec quick_configure(String.t(), String.t() | nil) :: :ok | {:error, term()}
      def quick_configure(ssid, passphrase) do
        send(self(), {:quick_configure, ssid, passphrase})
        Process.get(:wifi_provisioning_result, :ok)
      end

      defdelegate network_configured?(config), to: VintageNetWiFi
    end

    setup do
      target = Mix.target()

      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "wifi_provisioning_test_#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp_dir)

      on_exit(fn ->
        Mix.target(target)
        purge()
        File.rm_rf!(tmp_dir)
      end)

      source =
        nerves_install_project()
        |> install()
        |> content("lib/test/wifi_provisioning.ex")

      {:ok, source: source, tmp_dir: tmp_dir}
    end

    # The module doesn't exist when the tests are compiled
    defp setup_wifi() do
      module = Test.WiFiProvisioning
      module.setup()
    end

    defp purge() do
      :code.purge(Test.WiFiProvisioning)
      :code.delete(Test.WiFiProvisioning)
    end

    # Compiles like `mix compile` does so that calls to undefined modules and
    # functions are reported
    defp compile(source, tmp_dir, target) do
      purge()
      Mix.target(target)
      path = Path.join(tmp_dir, "wifi_provisioning_#{target}.ex")
      File.write!(path, source)

      # The diagnostics are returned, so there's no need to print them too
      {result, _stderr} =
        ExUnit.CaptureIO.with_io(:stderr, fn ->
          Kernel.ParallelCompiler.compile([path], return_diagnostics: true)
        end)

      result
    end

    # Replaces the modules that need a device
    defp with_fakes(source, fakes) do
      Enum.reduce(fakes, source, fn {module, fake}, source ->
        String.replace(
          source,
          ~r/(?<![\w.])#{Regex.escape(inspect(module))}\./,
          "#{inspect(fake)}."
        )
      end)
    end

    test "is formatted", %{source: source} do
      assert Code.format_string!(source) |> IO.iodata_to_binary() == String.trim_trailing(source)
    end

    test "compiles without warnings for the host and does nothing", %{
      source: source,
      tmp_dir: tmp_dir
    } do
      assert Mix.target() == :host

      assert {:ok, [Test.WiFiProvisioning], %{compile_warnings: [], runtime_warnings: []}} =
               compile(source, tmp_dir, :host)

      Process.put(:wifi_provisioning_kv, %{
        "wifi_ssid" => "my_ap",
        "wifi_passphrase" => "12345678"
      })

      # Nothing that it would need on a device is referenced
      assert setup_wifi() == :ok
      refute_received {:quick_configure, _, _}
    end

    test "compiles without warnings for devices", %{source: source, tmp_dir: tmp_dir} do
      # VintageNet and VintageNetWiFi are the real ones here, so this checks
      # that the functions it calls exist. It isn't run.
      source = with_fakes(source, %{Nerves.Runtime.KV => KV})

      assert {:ok, [Test.WiFiProvisioning], %{compile_warnings: [], runtime_warnings: []}} =
               compile(source, tmp_dir, :rpi4)
    end

    test "reports calls to functions that don't exist", %{source: source, tmp_dir: tmp_dir} do
      # Makes sure that the check in the test above can fail
      assert {:ok, _, %{runtime_warnings: [warning]}} = compile(source, tmp_dir, :rpi4)
      assert warning.message =~ "Nerves.Runtime.KV.get_all/0 is undefined"
    end

    defp compile_for_device!(source, tmp_dir) do
      source =
        with_fakes(source, %{
          Nerves.Runtime.KV => KV,
          VintageNet => FakeVintageNet,
          VintageNetWiFi => FakeVintageNetWiFi
        })

      assert {:ok, [Test.WiFiProvisioning], %{compile_warnings: [], runtime_warnings: []}} =
               compile(source, tmp_dir, :rpi4)

      :ok
    end

    test "configures WiFi when credentials were provisioned and wlan0 has no network",
         %{source: source, tmp_dir: tmp_dir} do
      compile_for_device!(source, tmp_dir)

      Process.put(:wifi_provisioning_kv, %{
        "wifi_ssid" => "my_ap",
        "wifi_passphrase" => "12345678",
        "wifi_force" => ""
      })

      assert setup_wifi() == :ok
      assert_received {:quick_configure, "my_ap", "12345678"}

      # No network interface configuration at all. E.g., VintageNet raised.
      Process.put(:wifi_provisioning_config, :raise)
      assert setup_wifi() == :ok
      assert_received {:quick_configure, "my_ap", "12345678"}

      # Open network
      Process.put(:wifi_provisioning_kv, %{"wifi_ssid" => "open", "wifi_passphrase" => ""})
      assert setup_wifi() == :ok
      assert_received {:quick_configure, "open", ""}
    end

    test "does nothing when no credentials were provisioned", %{source: source, tmp_dir: tmp_dir} do
      compile_for_device!(source, tmp_dir)

      # `mix burn` without the environment variables stores empty strings
      for kv <- [
            %{},
            %{"wifi_ssid" => "", "wifi_passphrase" => "", "wifi_force" => ""},
            %{"wifi_ssid" => "", "wifi_passphrase" => "12345678", "wifi_force" => "true"}
          ] do
        Process.put(:wifi_provisioning_kv, kv)

        assert setup_wifi() == :ok
        refute_received {:quick_configure, _, _}
      end
    end

    test "keeps WiFi that's configured on the device unless forced", %{
      source: source,
      tmp_dir: tmp_dir
    } do
      compile_for_device!(source, tmp_dir)

      Process.put(:wifi_provisioning_config, %{
        type: VintageNetWiFi,
        vintage_net_wifi: %{networks: [%{ssid: "other", key_mgmt: :wpa_psk, psk: "x"}]}
      })

      for force <- [nil, "", "false", "FALSE"] do
        Process.put(:wifi_provisioning_kv, %{
          "wifi_ssid" => "my_ap",
          "wifi_passphrase" => "12345678",
          "wifi_force" => force
        })

        assert setup_wifi() == :ok
        refute_received {:quick_configure, _, _}
      end

      for force <- ["true", "1", "yes"] do
        Process.put(:wifi_provisioning_kv, %{
          "wifi_ssid" => "my_ap",
          "wifi_passphrase" => "12345678",
          "wifi_force" => force
        })

        assert setup_wifi() == :ok
        assert_received {:quick_configure, "my_ap", "12345678"}
      end
    end

    test "logs and carries on when the credentials can't be used", %{
      source: source,
      tmp_dir: tmp_dir
    } do
      compile_for_device!(source, tmp_dir)

      Process.put(:wifi_provisioning_kv, %{"wifi_ssid" => "my_ap", "wifi_passphrase" => "short"})
      Process.put(:wifi_provisioning_result, {:error, :password_too_short})

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert setup_wifi() == :ok
        end)

      assert log =~ "Could not configure WiFi: :password_too_short"
      refute log =~ "short\""
    end
  end
end
