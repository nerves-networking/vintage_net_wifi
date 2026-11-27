# SPDX-FileCopyrightText: 2025 Jonatan Männchen <jonatan@maennchen.ch>
# SPDX-FileCopyrightText: 2026 Lars Wikman
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Mix.Tasks.VintageNetWifi.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  alias Mix.Tasks.VintageNetWifi.Install

  # config/target.exs from `mix nerves.new`
  @nerves_new_config """
  import Config

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
  """

  defp nerves_project(target_exs \\ "import Config\n") do
    test_project(files: %{"config/target.exs" => target_exs})
  end

  defp install(igniter, argv \\ []) do
    Igniter.compose_task(igniter, "vintage_net_wifi.install", argv)
  end

  defp target_exs(igniter) do
    igniter.rewrite |> Rewrite.source!("config/target.exs") |> Rewrite.Source.get(:content)
  end

  defp notices_matching(igniter, text) do
    Enum.filter(igniter.notices, &(&1 =~ text))
  end

  test "adds wlan0 to config/target.exs in Nerves projects" do
    igniter =
      nerves_project()
      |> install()
      |> assert_has_patch("config/target.exs", """
      + |config :vintage_net, regulatory_domain: "00", config: [{"wlan0", %{type: VintageNetWiFi}}]
      """)
      |> assert_unchanged("config/config.exs")
      |> assert_has_notice(&(&1 =~ "vintage_net_wifi: no WiFi networks were configured"))
      |> assert_has_notice(&(&1 =~ "VintageNetWiFi.quick_configure"))

    # The default regulatory domain needs to be updated by the user
    assert [notice] = notices_matching(igniter, "regulatory domain")

    assert notice =~
             ~s|vintage_net_wifi: the regulatory domain is "00" (world) in config/target.exs|

    assert igniter.issues == []
    assert igniter.warnings == []
  end

  test "falls back to config/config.exs with a notice" do
    test_project()
    |> install()
    |> assert_creates("config/config.exs", """
    import Config
    config :vintage_net, regulatory_domain: "00", config: [{"wlan0", %{type: VintageNetWiFi}}]
    """)
    |> refute_creates("config/target.exs")
    |> assert_has_notice(&(&1 =~ "config/target.exs was not found"))
    |> assert_has_notice(&(&1 =~ "no WiFi networks were configured"))
  end

  test "is idempotent" do
    nerves_project()
    |> install()
    |> apply_igniter!()
    |> install()
    |> assert_unchanged()

    test_project()
    |> install(["--regulatory-domain", "US", "--wifi-ifname", "mlan0"])
    |> apply_igniter!()
    |> install(["--regulatory-domain", "US", "--wifi-ifname", "mlan0"])
    |> assert_unchanged()
  end

  test "leaves the mix nerves.new config alone" do
    igniter = nerves_project(@nerves_new_config) |> install() |> assert_unchanged()

    # Projects that already have WiFi configured aren't told anything
    assert notices_matching(igniter, "regulatory domain") == []
    assert notices_matching(igniter, "no WiFi networks were configured") == []
  end

  test "appends to interfaces that are already configured" do
    nerves_project("""
    import Config

    config :vintage_net,
      regulatory_domain: "SE",
      config: [{"eth0", %{type: VintageNetEthernet, ipv4: %{method: :dhcp}}}]
    """)
    |> install()
    |> assert_has_patch("config/target.exs", """
    - |  config: [{"eth0", %{type: VintageNetEthernet, ipv4: %{method: :dhcp}}}]
    + |  config: [
    + |    {"eth0", %{type: VintageNetEthernet, ipv4: %{method: :dhcp}}},
    + |    {"wlan0", %{type: VintageNetWiFi}}
    + |  ]
    """)
    |> then(fn igniter ->
      # "SE" was kept and there's nothing to say about it
      assert target_exs(igniter) =~ ~s|regulatory_domain: "SE"|
      assert notices_matching(igniter, "regulatory domain") == []
      igniter
    end)
  end

  test "doesn't change a wlan0 that's already configured" do
    config = """
    import Config

    config :vintage_net,
      regulatory_domain: "US",
      config: [
        {"wlan0",
         %{
           type: VintageNetWiFi,
           vintage_net_wifi: %{
             networks: [%{key_mgmt: :none, ssid: "open_network"}]
           },
           ipv4: %{method: :dhcp}
         }}
      ]
    """

    igniter = nerves_project(config) |> install() |> assert_unchanged()
    assert igniter.notices == []

    # Not even when the interface is named explicitly
    nerves_project(config) |> install(["--wifi-ifname", "wlan0"]) |> assert_unchanged()
  end

  test "doesn't add wlan0 when WiFi is configured on another interface" do
    config = """
    import Config

    config :vintage_net,
      regulatory_domain: "US",
      config: [{"mlan0", %{type: VintageNetWiFi}}]
    """

    igniter = nerves_project(config) |> install() |> assert_unchanged()
    assert igniter.notices == []
  end

  test "doesn't replace a wlan0 that isn't WiFi" do
    igniter =
      nerves_project("""
      import Config

      config :vintage_net,
        regulatory_domain: "US",
        config: [{"wlan0", %{type: MyApp.CustomWiFi}}]
      """)
      |> install()
      |> assert_unchanged()

    assert igniter.issues == []
  end

  describe "--wifi-ifname" do
    test "sets the interface name" do
      nerves_project()
      |> install(["--wifi-ifname", "mlan0"])
      |> assert_has_patch("config/target.exs", """
      + |config :vintage_net, regulatory_domain: "00", config: [{"mlan0", %{type: VintageNetWiFi}}]
      """)
    end

    test "adds the interface next to other WiFi interfaces" do
      nerves_project(@nerves_new_config)
      |> install(["--wifi-ifname", "wlan1"])
      |> assert_has_patch("config/target.exs", """
      - |    {"wlan0", %{type: VintageNetWiFi}}
      + |    {"wlan0", %{type: VintageNetWiFi}},
      + |    {"wlan1", %{type: VintageNetWiFi}}
      """)
    end

    test "rejects invalid names" do
      for ifname <- ["wlan 0", "", "a_very_long_interface_name", "wlan/0"] do
        igniter = nerves_project() |> install(["--wifi-ifname", ifname])

        assert Enum.any?(igniter.issues, &(&1 =~ "invalid --wifi-ifname")), ifname
        assert_unchanged(igniter, "config/target.exs")
      end
    end
  end

  describe "--regulatory-domain" do
    test "sets the regulatory domain" do
      igniter =
        nerves_project()
        |> install(["--regulatory-domain", "US"])
        |> assert_has_patch("config/target.exs", """
        + |config :vintage_net, regulatory_domain: "US", config: [{"wlan0", %{type: VintageNetWiFi}}]
        """)

      assert notices_matching(igniter, "regulatory domain") == []
    end

    test "replaces the regulatory domain when asked to" do
      igniter =
        nerves_project(@nerves_new_config)
        |> install(["--regulatory-domain", "jp"])
        |> assert_has_patch("config/target.exs", """
        - |  regulatory_domain: "00",
        + |  regulatory_domain: "JP",
        """)

      assert notices_matching(igniter, "regulatory domain") == []
    end

    test "is upcased" do
      nerves_project()
      |> install(["--regulatory-domain", "se"])
      |> assert_has_patch("config/target.exs", """
      + |config :vintage_net, regulatory_domain: "SE", config: [{"wlan0", %{type: VintageNetWiFi}}]
      """)
    end

    test "replaces the regulatory domain and nothing else" do
      nerves_project(@nerves_new_config)
      |> install(["--regulatory-domain", "US"])
      |> apply_igniter!()
      |> then(fn igniter ->
        assert target_exs(igniter) ==
                 String.replace(
                   @nerves_new_config,
                   ~s|regulatory_domain: "00"|,
                   ~s|regulatory_domain: "US"|
                 )

        igniter
      end)
      |> install()
      |> assert_unchanged()
    end

    test "is validated" do
      for bad <- ["USA", "1", "U1", ""] do
        igniter =
          nerves_project() |> install(["--regulatory-domain", bad]) |> assert_unchanged()

        assert Enum.any?(
                 igniter.issues,
                 &(&1 =~ "vintage_net_wifi: invalid --regulatory-domain")
               ),
               bad
      end
    end

    test "isn't an option of vintage_net.install" do
      info = Mix.Tasks.VintageNet.Install.info([], nil)

      refute Keyword.has_key?(info.schema, :regulatory_domain)
    end
  end

  test "keeps a regulatory domain that's already configured" do
    igniter =
      nerves_project("""
      import Config

      config :vintage_net, regulatory_domain: "US"
      """)
      |> install()
      |> assert_has_patch("config/target.exs", """
      - |config :vintage_net, regulatory_domain: "US"
      + |config :vintage_net, regulatory_domain: "US", config: [{"wlan0", %{type: VintageNetWiFi}}]
      """)

    assert notices_matching(igniter, "regulatory domain") == []
  end

  test "tells about the regulatory domain once, and not when run again" do
    igniter = nerves_project() |> install()
    assert [_] = notices_matching(igniter, "regulatory domain")

    igniter = igniter |> apply_igniter!() |> install()
    assert igniter.notices == []
  end

  test "adds the regulatory domain to what vintage_net.install wrote" do
    # nerves_pack.install runs vintage_net.install before this installer. It
    # doesn't write a regulatory domain or say anything about it.
    igniter = nerves_project() |> Igniter.compose_task("vintage_net.install", [])

    refute target_exs(igniter) =~ "regulatory_domain"
    assert notices_matching(igniter, "regulatory domain") == []

    igniter = install(igniter)

    assert target_exs(igniter) == """
           import Config
           config :vintage_net, regulatory_domain: "00", config: [{"wlan0", %{type: VintageNetWiFi}}]
           """

    assert [notice] = notices_matching(igniter, "regulatory domain")
    assert notice =~ "vintage_net_wifi: the regulatory domain is"
  end

  test "puts the regulatory domain before the interfaces of other installers" do
    # What the vintage_net_ethernet and vintage_net_direct installers leave
    igniter =
      nerves_project("""
      import Config

      config :vintage_net,
        config: [
          {"usb0", %{type: VintageNetDirect}},
          {"eth0", %{type: VintageNetEthernet, ipv4: %{method: :dhcp}}}
        ]
      """)
      |> install()
      |> apply_igniter!()

    assert target_exs(igniter) == """
           import Config

           config :vintage_net,
             regulatory_domain: "00",
             config: [
               {"usb0", %{type: VintageNetDirect}},
               {"eth0", %{type: VintageNetEthernet, ipv4: %{method: :dhcp}}},
               {"wlan0", %{type: VintageNetWiFi}}
             ]
           """

    igniter |> install() |> assert_unchanged()
  end

  test "adds the default regulatory domain when WiFi is configured without one" do
    igniter =
      nerves_project("""
      import Config

      config :vintage_net, config: [{"wlan0", %{type: VintageNetWiFi}}]
      """)
      |> install()
      |> assert_has_patch("config/target.exs", """
      - |config :vintage_net, config: [{"wlan0", %{type: VintageNetWiFi}}]
      + |config :vintage_net, regulatory_domain: "00", config: [{"wlan0", %{type: VintageNetWiFi}}]
      """)

    assert [_] = notices_matching(igniter, "vintage_net_wifi: the regulatory domain is")
  end

  test "notices the world regulatory domain when adding WiFi to a project that has it" do
    igniter =
      nerves_project("""
      import Config

      config :vintage_net,
        regulatory_domain: "00",
        config: [{"eth0", %{type: VintageNetEthernet, ipv4: %{method: :dhcp}}}]
      """)
      |> install()

    assert [_] = notices_matching(igniter, "vintage_net_wifi: the regulatory domain is")
  end

  test "notices the world regulatory domain in the 3-argument config form" do
    igniter =
      nerves_project("""
      import Config

      config :vintage_net, :regulatory_domain, "00"
      """)
      |> install()

    assert [_] = notices_matching(igniter, "vintage_net_wifi: the regulatory domain is")
    assert target_exs(igniter) =~ ~s|{"wlan0", %{type: VintageNetWiFi}}|
  end

  test "never writes network credentials" do
    # There's intentionally no option for SSIDs or passphrases. Unknown options
    # must not find their way into the config either.
    igniter = nerves_project() |> install()

    refute target_exs(igniter) =~ "psk"
    refute target_exs(igniter) =~ "ssid"
    refute target_exs(igniter) =~ "networks"

    info = Install.info([], nil)
    assert Keyword.keys(info.schema) == [:wifi_ifname, :regulatory_domain, :wifi_provisioning]
    assert info.defaults == [wifi_provisioning: false]
  end

  describe "restricting the dependency to the project's targets" do
    defp targets_mix_exs(deps) do
      """
      defmodule Test.MixProject do
        use Mix.Project

        @app :test
        @device_targets [:rpi4, :rpi5]
        @other_targets [:bbb]

        def project do
          [app: @app, version: "0.1.0", deps: deps()]
        end

        defp deps do
          [
            {:nerves, "~> 2.0", runtime: false},
            #{Enum.join(deps, ",\n      ")}
          ]
        end
      end
      """
    end

    defp targets_install(deps) do
      test_project(
        files: %{"mix.exs" => targets_mix_exs(deps), "config/target.exs" => "import Config\n"}
      )
      |> Igniter.compose_task("vintage_net_wifi.install", [])
    end

    defp targets_mix_exs_after(igniter) do
      igniter.rewrite |> Rewrite.source!("mix.exs") |> Rewrite.Source.get(:content)
    end

    test "uses the first targets attribute that another dependency uses" do
      igniter =
        targets_install([
          ~s|{:nerves_system_rpi4, "~> 2.0", runtime: false, targets: :rpi4}|,
          ~s|{:nerves_pack, "~> 0.7", targets: @device_targets}|,
          ~s|{:other, "~> 1.0", targets: @other_targets}|,
          ~s|{:vintage_net_wifi, "~> 1.0"}|
        ])

      assert targets_mix_exs_after(igniter) =~
               ~s|{:vintage_net_wifi, "~> 1.0", targets: @device_targets}|

      # Running it again changes nothing
      igniter
      |> apply_igniter!()
      |> Igniter.compose_task("vintage_net_wifi.install", [])
      |> assert_unchanged("mix.exs")
    end

    test "works for dependencies that only have options" do
      igniter =
        targets_install([
          ~s|{:nerves_pack, "~> 0.7", targets: @device_targets}|,
          ~s|{:vintage_net_wifi, path: "../vintage_net_wifi"}|
        ])

      assert targets_mix_exs_after(igniter) =~
               ~s|{:vintage_net_wifi, path: "../vintage_net_wifi", targets: @device_targets}|
    end

    test "keeps the targets that the dependency already has" do
      targets_install([
        ~s|{:nerves_pack, "~> 0.7", targets: @device_targets}|,
        ~s|{:vintage_net_wifi, "~> 1.0", targets: [:rpi0]}|
      ])
      |> assert_unchanged("mix.exs")
    end

    test "does nothing when no dependency uses a targets attribute" do
      targets_install([
        ~s|{:nerves_system_rpi4, "~> 2.0", runtime: false, targets: :rpi4}|,
        ~s|{:vintage_net_wifi, "~> 1.0"}|
      ])
      |> assert_unchanged("mix.exs")
    end

    test "falls back to @all_targets when it's defined but not used by a dependency" do
      mix_exs = """
      defmodule Test.MixProject do
        use Mix.Project

        @all_targets [:rpi4, :rpi5]

        def project do
          [app: :test, version: "0.1.0", deps: deps()]
        end

        defp deps do
          [
            {:nerves_system_rpi4, "~> 2.0", runtime: false, targets: :rpi4},
            {:vintage_net_wifi, "~> 1.0"}
          ]
        end
      end
      """

      igniter =
        test_project(files: %{"mix.exs" => mix_exs, "config/target.exs" => "import Config\n"})
        |> Igniter.compose_task("vintage_net_wifi.install", [])

      assert targets_mix_exs_after(igniter) =~
               ~s|{:vintage_net_wifi, "~> 1.0", targets: @all_targets}|
    end

    test "does nothing when the dependency isn't in mix.exs" do
      targets_install([~s|{:nerves_pack, "~> 0.7", targets: @device_targets}|])
      |> assert_unchanged("mix.exs")
    end
  end
end
