# SPDX-FileCopyrightText: 2019 Frank Hunleth
# SPDX-FileCopyrightText: 2020 Connor Rigby
# SPDX-FileCopyrightText: 2021 WN
# SPDX-FileCopyrightText: 2023 Ace Yanagida
# SPDX-FileCopyrightText: 2023 Jon Carstens
# SPDX-FileCopyrightText: 2024 Masatoshi Nishiguchi
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetWiFiTest do
  use ExUnit.Case

  import VintageNetWiFiTest.Utils
  import ExUnit.CaptureLog

  alias VintageNet.Interface.RawConfig

  test "old way of specifying ssid works" do
    # No one should be specifying SSIDs at top level with the
    # new module name, but it's such as easy mistake that it's
    # nice to have normalization fix it.
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{ssid: "guest", key_mgmt: :none}
    }

    normalized_input = %{
      type: VintageNetWiFi,
      ipv4: %{method: :dhcp},
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "guest",
            key_mgmt: :none,
            mode: :infrastructure
          }
        ]
      }
    }

    assert capture_log(fn ->
             assert normalized_input == VintageNetWiFi.normalize(input)
           end) =~ "deprecated"
  end

  test "old way of specifying WPA2 PSK works" do
    # No one should be specifying SSIDs at top level with the
    # new module name, but it's such as easy mistake that it's
    # nice to have normalization fix it.
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{ssid: "IEEE", key_mgmt: :wpa_psk, psk: "password"}
    }

    normalized_input = %{
      type: VintageNetWiFi,
      ipv4: %{method: :dhcp},
      vintage_net_wifi: %{
        networks: [
          %{
            key_mgmt: :wpa_psk,
            ssid: "IEEE",
            psk: "F42C6FC52DF0EBEF9EBB4B90B38A5F902E83FE1B135A70E23AED762E9710A12E",
            mode: :infrastructure
          }
        ]
      }
    }

    assert capture_log(fn ->
             assert normalized_input == VintageNetWiFi.normalize(input)
           end) =~ "deprecated"
  end

  test "old way of specifying ap mode works" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{mode: :host, ssid: "my_ap", key_mgmt: :none}
    }

    normalized_input = %{
      type: VintageNetWiFi,
      ipv4: %{method: :dhcp},
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "my_ap",
            key_mgmt: :none,
            mode: :ap
          }
        ]
      }
    }

    assert capture_log(fn ->
             assert normalized_input == VintageNetWiFi.normalize(input)
           end) =~ "deprecated"
  end

  test "normalizes really old way of specifying infrastructure mode" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "guest",
            key_mgmt: :none,
            mode: :client
          }
        ]
      }
    }

    normalized_input = %{
      type: VintageNetWiFi,
      ipv4: %{method: :dhcp},
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "guest",
            key_mgmt: :none,
            mode: :infrastructure
          }
        ]
      }
    }

    assert normalized_input == VintageNetWiFi.normalize(input)
  end

  test "normalizing an old config with unset fields goes to scan-only mode" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        key_mgmt: :wpa_psk,
        psk: nil,
        ssid: nil
      },
      ipv4: %{
        method: :dhcp
      }
    }

    normalized_input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{networks: []},
      ipv4: %{method: :dhcp}
    }

    assert capture_log(fn ->
             assert normalized_input == VintageNetWiFi.normalize(input)
           end) =~ "Dropping network with `nil` SSID"
  end

  test "normalizing an empty config works" do
    # An empty config should be normalized to a configuration that
    # allows the user to scan for networks.
    input = %{
      type: VintageNetWiFi
    }

    normalized = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{networks: []},
      ipv4: %{method: :disabled}
    }

    assert normalized == VintageNetWiFi.normalize(input)
  end

  test "an empty config enables wifi scanning" do
    input = %{
      type: VintageNetWiFi
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: false,
           verbose: false
         ]}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         """}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "verbose flag turns on wpa_supplicant debug" do
    input = %{
      type: VintageNetWiFi,
      verbose: true
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: false,
           verbose: true
         ]}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         """}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "normalization raises on bad ssids and psks" do
    # WPA2 PSK configs
    assert_raise ArgumentError, fn ->
      VintageNetWiFi.normalize(%{
        type: VintageNetWiFi,
        vintage_net_wifi: %{
          networks: [
            %{ssid: "123456789012345678901234567890123", psk: "supersecret", key_mgmt: :wpa_psk}
          ]
        }
      })
    end

    # No security configs
    assert_raise ArgumentError, fn ->
      VintageNetWiFi.normalize(%{
        type: VintageNetWiFi,
        vintage_net_wifi: %{
          networks: [%{ssid: "", key_mgmt: :none}]
        }
      })
    end

    assert_raise ArgumentError, fn ->
      VintageNetWiFi.normalize(%{
        type: VintageNetWiFi,
        vintage_net_wifi: %{
          networks: [%{ssid: "123456789012345678901234567890123", key_mgmt: :none}]
        }
      })
    end
  end

  test "normalization converts passphrases to PSKs" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [%{ssid: "IEEE", psk: "password", key_mgmt: :wpa_psk}]
      }
    }

    normalized_input = %{
      type: VintageNetWiFi,
      ipv4: %{method: :dhcp},
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "IEEE",
            psk: "F42C6FC52DF0EBEF9EBB4B90B38A5F902E83FE1B135A70E23AED762E9710A12E",
            key_mgmt: :wpa_psk,
            mode: :infrastructure
          }
        ]
      }
    }

    assert normalized_input == VintageNetWiFi.normalize(input)
  end

  test "normalization converts passphrases to psks for multiple networks" do
    input = %{
      type: VintageNetWiFi,
      ipv4: %{method: :dhcp},
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "IEEE",
            psk: "password",
            key_mgmt: :wpa_psk
          },
          %{
            ssid: "IEEE2",
            psk: "password",
            key_mgmt: :wpa_psk
          }
        ]
      }
    }

    normalized_input = %{
      type: VintageNetWiFi,
      ipv4: %{method: :dhcp},
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "IEEE",
            psk: "F42C6FC52DF0EBEF9EBB4B90B38A5F902E83FE1B135A70E23AED762E9710A12E",
            key_mgmt: :wpa_psk,
            mode: :infrastructure
          },
          %{
            ssid: "IEEE2",
            psk: "B06433395BD30B1455F538904B239D10A51964932A81D1407BAF2BA0767E22E9",
            key_mgmt: :wpa_psk,
            mode: :infrastructure
          }
        ]
      }
    }

    assert normalized_input == VintageNetWiFi.normalize(input)
  end

  test "create a WPA2 WiFi configuration" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "testing",
            psk: "1234567890123456789012345678901234567890123456789012345678901234",
            key_mgmt: :wpa_psk
          }
        ]
      },
      ipv4: %{method: :dhcp},
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: false,
           verbose: false
         ]},
        udhcpc_child_spec("wlan0", "unit_test"),
        {VintageNet.Connectivity.InternetChecker, "wlan0"}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         network={
         ssid="testing"
         key_mgmt=WPA-PSK
         mode=0
         psk=1234567890123456789012345678901234567890123456789012345678901234
         }
         """}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "create a pure WPA3 WiFi configuration" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "testing",
            sae_password: "hunter2",
            key_mgmt: :sae,
            ieee80211w: 2
          }
        ]
      },
      ipv4: %{method: :dhcp},
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: false,
           verbose: false
         ]},
        udhcpc_child_spec("wlan0", "unit_test"),
        {VintageNet.Connectivity.InternetChecker, "wlan0"}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         network={
         ssid="testing"
         key_mgmt=SAE
         mode=0
         ieee80211w=2
         sae_password="hunter2"
         }
         """}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "create a mixed WPA2-PSK/WPA3-SAE WiFi configuration" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "testing",
            psk: "password",
            key_mgmt: :wpa_psk_sha256,
            ieee80211w: 2
          }
        ]
      },
      ipv4: %{method: :dhcp},
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: false,
           verbose: false
         ]},
        udhcpc_child_spec("wlan0", "unit_test"),
        {VintageNet.Connectivity.InternetChecker, "wlan0"}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         network={
         ssid="testing"
         key_mgmt=WPA-PSK-SHA256
         mode=0
         ieee80211w=2
         psk=5747B578C5FAF01543C4CEC284A772E1037C7C84C03C9A2404DAB5CBF9C74394
         }
         """}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "normalize creates backwards compatible key_mgmt" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "testing",
            psk: "password",
            sae_password: "password",
            key_mgmt: [:wpa_psk, :wpa_psk_sha256, :sae],
            ieee80211w: 2
          }
        ]
      }
    }

    normalized_input = %{
      type: VintageNetWiFi,
      ipv4: %{method: :dhcp},
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "testing",
            psk: "5747B578C5FAF01543C4CEC284A772E1037C7C84C03C9A2404DAB5CBF9C74394",
            sae_password: "password",
            ieee80211w: 2,
            allowed_key_mgmt: [:wpa_psk, :wpa_psk_sha256, :sae],
            key_mgmt: :wpa_psk,
            mode: :infrastructure
          }
        ]
      }
    }

    assert normalized_input == VintageNetWiFi.normalize(input)
  end

  test "create a WPA2, WPA2 SHA256, WPA3 WiFi configuration" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "testing",
            psk: "password",
            sae_password: "password",
            key_mgmt: [:wpa_psk, :wpa_psk_sha256, :sae],
            ieee80211w: 1
          }
        ]
      },
      ipv4: %{method: :dhcp},
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: false,
           verbose: false
         ]},
        udhcpc_child_spec("wlan0", "unit_test"),
        {VintageNet.Connectivity.InternetChecker, "wlan0"}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         network={
         ssid="testing"
         key_mgmt=WPA-PSK WPA-PSK-SHA256 SAE
         mode=0
         ieee80211w=1
         psk=5747B578C5FAF01543C4CEC284A772E1037C7C84C03C9A2404DAB5CBF9C74394
         sae_password="password"
         }
         """}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "create an open WiFi configuration" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "guest"
          }
        ]
      },
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: false,
           verbose: false
         ]},
        udhcpc_child_spec("wlan0", "unit_test"),
        {VintageNet.Connectivity.InternetChecker, "wlan0"}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         network={
         ssid="guest"
         key_mgmt=NONE
         mode=0
         }
         """}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "Set regulatory_domain at runtime" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        regulatory_domain: "AU"
      },
      ipv4: %{method: :disabled},
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: false,
           verbose: false
         ]}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=AU
         wps_cred_processing=1
         """}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "create a WPA2 WiFi configuration with passphrase" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [%{ssid: "testing", psk: "a_passphrase_and_not_a_psk", key_mgmt: :wpa_psk}]
      },
      ipv4: %{method: :dhcp},
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: false,
           verbose: false
         ]},
        udhcpc_child_spec("wlan0", "unit_test"),
        {VintageNet.Connectivity.InternetChecker, "wlan0"}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         network={
         ssid="testing"
         key_mgmt=WPA-PSK
         mode=0
         psk=1EE0A473A954F61007E526365D4FDC056FE2A102ED2CE77D64492A9495B83030
         }
         """}
      ],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}],
      cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "create a password-less WiFi configuration" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{networks: [%{ssid: "testing", key_mgmt: :none}]},
      ipv4: %{method: :dhcp},
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: false,
           verbose: false
         ]},
        udhcpc_child_spec("wlan0", "unit_test"),
        {VintageNet.Connectivity.InternetChecker, "wlan0"}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         network={
         ssid="testing"
         key_mgmt=NONE
         mode=0
         }
         """}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "create a WEP WiFi configuration" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "testing",
            bssid: "00:11:22:33:44:55",
            wep_key0: "42FEEDDEAFBABEDEAFBEEFAA55",
            wep_key1: "42FEEDDEAFBABEDEAFBEEFAA55",
            wep_key2: "ABEDEA42FFBEEFAA55EEDDEAFB",
            wep_key3: "EDEADEAFBABFBEEFAA5542FEED",
            key_mgmt: :none,
            wep_tx_keyidx: 0
          }
        ]
      },
      ipv4: %{method: :dhcp},
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: false,
           verbose: false
         ]},
        udhcpc_child_spec("wlan0", "unit_test"),
        {VintageNet.Connectivity.InternetChecker, "wlan0"}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         network={
         ssid="testing"
         bssid=00:11:22:33:44:55
         key_mgmt=NONE
         mode=0
         wep_key0=42FEEDDEAFBABEDEAFBEEFAA55
         wep_key1=42FEEDDEAFBABEDEAFBEEFAA55
         wep_key2=ABEDEA42FFBEEFAA55EEDDEAFB
         wep_key3=EDEADEAFBABFBEEFAA5542FEED
         wep_tx_keyidx=0
         }
         """}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "create a hidden WiFi configuration" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "testing",
            psk: "1234567890123456789012345678901234567890123456789012345678901234",
            key_mgmt: :wpa_psk,
            scan_ssid: 1
          }
        ]
      },
      ipv4: %{method: :dhcp},
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: false,
           verbose: false
         ]},
        udhcpc_child_spec("wlan0", "unit_test"),
        {VintageNet.Connectivity.InternetChecker, "wlan0"}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         network={
         ssid="testing"
         key_mgmt=WPA-PSK
         scan_ssid=1
         mode=0
         psk=1234567890123456789012345678901234567890123456789012345678901234
         }
         """}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "create a basic EAP network" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "testing",
            key_mgmt: :wpa_eap,
            scan_ssid: 1,
            pairwise: "CCMP TKIP",
            group: "CCMP TKIP",
            eap: "PEAP",
            identity: "user1",
            password: "supersecret",
            phase1: "peapver=auto",
            phase2: "MSCHAPV2"
          }
        ]
      },
      ipv4: %{method: :dhcp},
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: false,
           verbose: false
         ]},
        udhcpc_child_spec("wlan0", "unit_test"),
        {VintageNet.Connectivity.InternetChecker, "wlan0"}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         network={
         ssid="testing"
         key_mgmt=WPA-EAP
         scan_ssid=1
         mode=0
         identity="user1"
         password="supersecret"
         pairwise=CCMP TKIP
         group=CCMP TKIP
         eap=PEAP
         phase1="peapver=auto"
         phase2="MSCHAPV2"
         }
         """}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "WPA-Personal(PSK) with TKIP and enforcement for frequent PTK rekeying" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "example",
            proto: "WPA",
            key_mgmt: :wpa_psk,
            scan_ssid: 1,
            pairwise: "TKIP",
            psk: "not so secure passphrase",
            wpa_ptk_rekey: 600
          }
        ]
      },
      ipv4: %{method: :dhcp},
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: false,
           verbose: false
         ]},
        udhcpc_child_spec("wlan0", "unit_test"),
        {VintageNet.Connectivity.InternetChecker, "wlan0"}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         network={
         ssid="example"
         key_mgmt=WPA-PSK
         scan_ssid=1
         mode=0
         psk=F7C00EB4F1A1BF28F0C6D18C689DB6634FC85C894286A11DE979F2BA1C022988
         wpa_ptk_rekey=600
         pairwise=TKIP
         }
         """}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "Only WPA-EAP is used. Both CCMP and TKIP is accepted" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "example",
            proto: "RSN",
            key_mgmt: :wpa_eap,
            pairwise: "CCMP TKIP",
            eap: "TLS",
            identity: "user@example.com",
            ca_cert: "/etc/cert/ca.pem",
            client_cert: "/etc/cert/user.pem",
            private_key: "/etc/cert/user.prv",
            private_key_passwd: "password",
            priority: 1
          }
        ]
      },
      ipv4: %{method: :dhcp},
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: false,
           verbose: false
         ]},
        udhcpc_child_spec("wlan0", "unit_test"),
        {VintageNet.Connectivity.InternetChecker, "wlan0"}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         network={
         ssid="example"
         key_mgmt=WPA-EAP
         priority=1
         mode=0
         identity="user@example.com"
         pairwise=CCMP TKIP
         eap=TLS
         ca_cert="/etc/cert/ca.pem"
         client_cert="/etc/cert/user.pem"
         private_key="/etc/cert/user.prv"
         private_key_passwd="password"
         }
         """}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "EAP-PEAP/MSCHAPv2 configuration for RADIUS servers that use the new peaplabel" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "example",
            key_mgmt: :wpa_eap,
            eap: "PEAP",
            identity: "user@example.com",
            password: "foobar",
            ca_cert: "/etc/cert/ca.pem",
            phase1: "peaplabel=1",
            phase2: "auth=MSCHAPV2",
            priority: 10
          }
        ]
      },
      ipv4: %{method: :dhcp},
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: false,
           verbose: false
         ]},
        udhcpc_child_spec("wlan0", "unit_test"),
        {VintageNet.Connectivity.InternetChecker, "wlan0"}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         network={
         ssid="example"
         key_mgmt=WPA-EAP
         priority=10
         mode=0
         identity="user@example.com"
         password="foobar"
         eap=PEAP
         phase1="peaplabel=1"
         phase2="auth=MSCHAPV2"
         ca_cert="/etc/cert/ca.pem"
         }
         """}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "EAP-TTLS/EAP-MD5-Challenge configuration with anonymous identity" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "example",
            key_mgmt: :wpa_eap,
            eap: "TTLS",
            identity: "user@example.com",
            anonymous_identity: "anonymous@example.com",
            password: "foobar",
            ca_cert: "/etc/cert/ca.pem",
            priority: 2
          }
        ]
      },
      ipv4: %{method: :dhcp},
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: false,
           verbose: false
         ]},
        udhcpc_child_spec("wlan0", "unit_test"),
        {VintageNet.Connectivity.InternetChecker, "wlan0"}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         network={
         ssid="example"
         key_mgmt=WPA-EAP
         priority=2
         mode=0
         identity="user@example.com"
         anonymous_identity="anonymous@example.com"
         password="foobar"
         eap=TTLS
         ca_cert="/etc/cert/ca.pem"
         }
         """}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "WPA-EAP, EAP-TTLS with different CA certificate used for outer and inner authentication" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "example",
            key_mgmt: :wpa_eap,
            eap: "TTLS",
            anonymous_identity: "anonymous@example.com",
            ca_cert: "/etc/cert/ca.pem",
            phase2: "autheap=TLS",
            ca_cert2: "/etc/cert/ca2.pem",
            client_cert2: "/etc/cer/user.pem",
            private_key2: "/etc/cer/user.prv",
            private_key2_passwd: "password",
            priority: 2
          }
        ]
      },
      ipv4: %{method: :dhcp},
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: false,
           verbose: false
         ]},
        udhcpc_child_spec("wlan0", "unit_test"),
        {VintageNet.Connectivity.InternetChecker, "wlan0"}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         network={
         ssid="example"
         key_mgmt=WPA-EAP
         priority=2
         mode=0
         anonymous_identity="anonymous@example.com"
         eap=TTLS
         phase2="autheap=TLS"
         ca_cert="/etc/cert/ca.pem"
         ca_cert2="/etc/cert/ca2.pem"
         client_cert2="/etc/cer/user.pem"
         private_key2="/etc/cer/user.prv"
         private_key2_passwd="password"
         }
         """}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "EAP-SIM with a GSM SIM or USIM" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [%{ssid: "eap-sim-test", key_mgmt: :wpa_eap, eap: "SIM", pin: "1234", pcsc: ""}]
      },
      ipv4: %{method: :dhcp},
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: false,
           verbose: false
         ]},
        udhcpc_child_spec("wlan0", "unit_test"),
        {VintageNet.Connectivity.InternetChecker, "wlan0"}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         network={
         ssid="eap-sim-test"
         key_mgmt=WPA-EAP
         mode=0
         eap=SIM
         pin="1234"
         pcsc=""
         }
         """}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "EAP PSK" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "eap-psk-test",
            key_mgmt: :wpa_eap,
            eap: "PSK",
            anonymous_identity: "eap_psk_user",
            password: "06b4be19da289f475aa46a33cb793029",
            identity: "eap_psk_user@example.com"
          }
        ]
      },
      ipv4: %{method: :dhcp},
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: false,
           verbose: false
         ]},
        udhcpc_child_spec("wlan0", "unit_test"),
        {VintageNet.Connectivity.InternetChecker, "wlan0"}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         network={
         ssid="eap-psk-test"
         key_mgmt=WPA-EAP
         mode=0
         identity="eap_psk_user@example.com"
         anonymous_identity="eap_psk_user"
         password="06b4be19da289f475aa46a33cb793029"
         eap=PSK
         }
         """}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "IEEE 802.1X/EAPOL with dynamically generated WEP keys" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "1x-test",
            key_mgmt: :IEEE8021X,
            eap: "TLS",
            identity: "user@example.com",
            ca_cert: "/etc/cert/ca.pem",
            client_cert: "/etc/cert/user.pem",
            private_key: "/etc/cert/user.prv",
            private_key_passwd: "password",
            eapol_flags: 3
          }
        ]
      },
      ipv4: %{method: :dhcp},
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: false,
           verbose: false
         ]},
        udhcpc_child_spec("wlan0", "unit_test"),
        {VintageNet.Connectivity.InternetChecker, "wlan0"}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         network={
         ssid="1x-test"
         key_mgmt=IEEE8021X
         mode=0
         identity="user@example.com"
         eap=TLS
         eapol_flags=3
         ca_cert="/etc/cert/ca.pem"
         client_cert="/etc/cert/user.pem"
         private_key="/etc/cert/user.prv"
         private_key_passwd="password"
         }
         """}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "configuration denying two APs" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "example",
            key_mgmt: :wpa_psk,
            psk: "very secret passphrase",
            bssid_denylist: "02:11:22:33:44:55 02:22:aa:44:55:66"
          }
        ]
      },
      ipv4: %{method: :dhcp},
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: false,
           verbose: false
         ]},
        udhcpc_child_spec("wlan0", "unit_test"),
        {VintageNet.Connectivity.InternetChecker, "wlan0"}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         network={
         ssid="example"
         key_mgmt=WPA-PSK
         bssid_blacklist=02:11:22:33:44:55 02:22:aa:44:55:66
         mode=0
         psk=3033345C1478F89E4BE9C4937401DEAFD58808CD3E63568DCBFBBD4A8D281175
         }
         """}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "configuration limiting AP selection to a specific set of APs" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "example",
            key_mgmt: :wpa_psk,
            psk: "very secret passphrase",
            bssid_allowlist:
              "02:55:ae:bc:00:00/ff:ff:ff:ff:00:00 00:00:77:66:55:44/00:00:ff:ff:ff:ff"
          }
        ]
      },
      ipv4: %{method: :dhcp},
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: false,
           verbose: false
         ]},
        udhcpc_child_spec("wlan0", "unit_test"),
        {VintageNet.Connectivity.InternetChecker, "wlan0"}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         network={
         ssid="example"
         key_mgmt=WPA-PSK
         bssid_whitelist=02:55:ae:bc:00:00/ff:ff:ff:ff:00:00 00:00:77:66:55:44/00:00:ff:ff:ff:ff
         mode=0
         psk=3033345C1478F89E4BE9C4937401DEAFD58808CD3E63568DCBFBBD4A8D281175
         }
         """}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "host AP mode" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{mode: :ap, ssid: "example ap", psk: "very secret passphrase", key_mgmt: :wpa_psk}
        ]
      },
      ipv4: %{method: :disabled},
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: true,
           verbose: false
         ]}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         network={
         ssid="example ap"
         key_mgmt=WPA-PSK
         mode=2
         psk=94A7360596213CEB96007A25A63FCBCF4D540314CEB636353C62A86632A6BD6E
         }
         """}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      cleanup_files: [
        "/tmp/vintage_net/wpa_supplicant/p2p-dev-wlan0",
        "/tmp/vintage_net/wpa_supplicant/wlan0"
      ]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "create a multi-network WiFi configuration" do
    # All of the IPv4 settings need to be the same for this configuration. This is
    # probably "good enough". `nerves_network` does better, though.
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "first_priority",
            psk: "1234567890123456789012345678901234567890123456789012345678901234",
            key_mgmt: :wpa_psk,
            priority: 100
          },
          %{
            ssid: "second_priority",
            psk: "1234567890123456789012345678901234567890123456789012345678901234",
            key_mgmt: :wpa_psk,
            priority: 1
          },
          %{
            ssid: "third_priority",
            key_mgmt: :none,
            priority: 0
          }
        ]
      },
      ipv4: %{method: :dhcp},
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: false,
           verbose: false
         ]},
        udhcpc_child_spec("wlan0", "unit_test"),
        {VintageNet.Connectivity.InternetChecker, "wlan0"}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         network={
         ssid="first_priority"
         key_mgmt=WPA-PSK
         priority=100
         mode=0
         psk=1234567890123456789012345678901234567890123456789012345678901234
         }
         network={
         ssid="second_priority"
         key_mgmt=WPA-PSK
         priority=1
         mode=0
         psk=1234567890123456789012345678901234567890123456789012345678901234
         }
         network={
         ssid="third_priority"
         key_mgmt=NONE
         priority=0
         mode=0
         }
         """}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "creates a static ip config" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [%{ssid: "example ap", psk: "very secret passphrase", key_mgmt: :wpa_psk}]
      },
      ipv4: %{
        method: :static,
        address: "192.168.1.2",
        netmask: "255.255.0.0",
        gateway: "192.168.1.1"
      },
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: false,
           verbose: false
         ]},
        {VintageNet.Connectivity.InternetChecker, "wlan0"}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         network={
         ssid="example ap"
         key_mgmt=WPA-PSK
         mode=0
         psk=94A7360596213CEB96007A25A63FCBCF4D540314CEB636353C62A86632A6BD6E
         }
         """}
      ],
      up_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip",
         [
           "addr",
           "add",
           "192.168.1.2/16",
           "dev",
           "wlan0",
           "broadcast",
           "192.168.255.255",
           "label",
           "wlan0"
         ]},
        {:run, "ip", ["link", "set", "wlan0", "up"]},
        {:fun, VintageNet.RouteManager, :set_route,
         ["wlan0", [{{192, 168, 1, 2}, 16}], {192, 168, 1, 1}]},
        {:fun, VintageNet.NameResolver, :clear, ["wlan0"]}
      ],
      down_cmds: [
        {:fun, VintageNet.RouteManager, :clear_route, ["wlan0"]},
        {:fun, VintageNet.NameResolver, :clear, ["wlan0"]},
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "create an AP running dhcpd config" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            mode: :ap,
            ssid: "example ap",
            key_mgmt: :none,
            scan_ssid: 1
          }
        ],
        ap_scan: 1,
        bgscan: :simple
      },
      ipv4: %{
        method: :static,
        address: "192.168.24.1",
        netmask: "255.255.255.0"
      },
      dhcpd: %{
        start: "192.168.24.2",
        end: "192.168.24.100",
        options: %{
          dns: ["192.168.24.1"],
          subnet: {255, 255, 255, 0},
          router: ["192.168.24.1"],
          domain: "example.com",
          search: ["example.com"]
        }
      },
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: true,
           verbose: false
         ]},
        {VintageNet.Connectivity.LANChecker, "wlan0"},
        udhcpd_child_spec("wlan0")
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         bgscan="simple"
         ap_scan=1
         network={
         ssid="example ap"
         key_mgmt=NONE
         scan_ssid=1
         mode=2
         }
         """},
        {"/tmp/vintage_net/udhcpd.conf.wlan0",
         """
         interface wlan0
         pidfile /tmp/vintage_net/udhcpd.wlan0.pid
         lease_file /tmp/vintage_net/udhcpd.wlan0.leases
         notify_file #{Application.app_dir(:beam_notify, ["priv", "beam_notify"])}

         end 192.168.24.100
         opt dns 192.168.24.1
         opt domain example.com
         opt router 192.168.24.1
         opt search example.com
         opt subnet 255.255.255.0
         start 192.168.24.2

         """}
      ],
      down_cmds: [
        {:fun, VintageNet.RouteManager, :clear_route, ["wlan0"]},
        {:fun, VintageNet.NameResolver, :clear, ["wlan0"]},
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      up_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip",
         [
           "addr",
           "add",
           "192.168.24.1/24",
           "dev",
           "wlan0",
           "broadcast",
           "192.168.24.255",
           "label",
           "wlan0"
         ]},
        {:run, "ip", ["link", "set", "wlan0", "up"]},
        {:fun, VintageNet.RouteManager, :clear_route, ["wlan0"]},
        {:fun, VintageNet.NameResolver, :clear, ["wlan0"]}
      ],
      cleanup_files: [
        "/tmp/vintage_net/wpa_supplicant/p2p-dev-wlan0",
        "/tmp/vintage_net/wpa_supplicant/wlan0"
      ]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "create an ad hoc network" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            mode: :ibss,
            ssid: "my_mesh",
            key_mgmt: :none,
            frequency: 2412
          }
        ]
      },
      ipv4: %{
        method: :static,
        address: "192.168.24.1",
        netmask: "255.255.255.0"
      },
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: true,
           verbose: false
         ]},
        {VintageNet.Connectivity.LANChecker, "wlan0"}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         network={
         ssid="my_mesh"
         key_mgmt=NONE
         mode=1
         frequency=2412
         }
         """}
      ],
      down_cmds: [
        {:fun, VintageNet.RouteManager, :clear_route, ["wlan0"]},
        {:fun, VintageNet.NameResolver, :clear, ["wlan0"]},
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      up_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip",
         [
           "addr",
           "add",
           "192.168.24.1/24",
           "dev",
           "wlan0",
           "broadcast",
           "192.168.24.255",
           "label",
           "wlan0"
         ]},
        {:run, "ip", ["link", "set", "wlan0", "up"]},
        {:fun, VintageNet.RouteManager, :clear_route, ["wlan0"]},
        {:fun, VintageNet.NameResolver, :clear, ["wlan0"]}
      ],
      cleanup_files: [
        "/tmp/vintage_net/wpa_supplicant/p2p-dev-wlan0",
        "/tmp/vintage_net/wpa_supplicant/wlan0"
      ]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "create a mesh network" do
    input = %{
      type: VintageNetWiFi,
      ipv4: %{method: :disabled},
      vintage_net_wifi: %{
        root_interface: "wlan0",
        networks: [
          %{
            mode: :mesh,
            ssid: "mesh",
            key_mgmt: :none,
            frequency: 2412
          }
        ]
      },
      hostname: "unit_test"
    }

    assert match?(
             %RawConfig{
               child_specs: [
                 {
                   VintageNetWiFi.WPASupplicant,
                   [
                     wpa_supplicant: "wpa_supplicant",
                     ifname: "mesh0",
                     wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.mesh0",
                     control_path: "/tmp/vintage_net/wpa_supplicant",
                     ap_mode: false,
                     verbose: false
                   ]
                 }
               ],
               cleanup_files: ["/tmp/vintage_net/wpa_supplicant/mesh0"],
               down_cmd_millis: 5000,
               down_cmds: [
                 {:run, _, ["wlan0", "mesh0", "del"]},
                 {:fun, _},
                 {:run_ignore_errors, "ip", ["addr", "flush", "dev", "mesh0", "label", "mesh0"]},
                 {:run, "ip", ["link", "set", "mesh0", "down"]}
               ],
               files: [
                 {"/tmp/vintage_net/wpa_supplicant.conf.mesh0",
                  "ctrl_interface=/tmp/vintage_net/wpa_supplicant\ncountry=00\nwps_cred_processing=1\nnetwork={\nssid=\"mesh\"\nkey_mgmt=NONE\nmode=5\nfrequency=2412\n}\n"}
               ],
               ifname: "mesh0",
               required_ifnames: ["wlan0"],
               restart_strategy: :rest_for_one,
               retry_millis: 30000,
               source_config: %{
                 hostname: "unit_test",
                 ipv4: %{method: :disabled},
                 type: VintageNetWiFi,
                 vintage_net_wifi: %{
                   networks: [%{frequency: 2412, key_mgmt: :none, mode: :mesh, ssid: "mesh"}],
                   root_interface: "wlan0"
                 }
               },
               type: VintageNetWiFi,
               up_cmd_millis: 5000,
               up_cmds: [
                 {:run, _, ["wlan0", "mesh0", "add"]},
                 {:fun, _},
                 {:run, "ip", ["link", "set", "mesh0", "up"]}
               ]
             },
             VintageNetWiFi.to_raw_config("mesh0", input, default_opts())
           )
  end

  test "create a mesh network with sae" do
    input = %{
      type: VintageNetWiFi,
      ipv4: %{method: :disabled},
      vintage_net_wifi: %{
        root_interface: "wlan0",
        networks: [
          %{
            mode: :mesh,
            ssid: "mesh",
            key_mgmt: :sae,
            sae_password: "password",
            frequency: 2412
          }
        ]
      },
      hostname: "unit_test"
    }

    assert match?(
             %RawConfig{
               child_specs: [
                 {
                   VintageNetWiFi.WPASupplicant,
                   [
                     wpa_supplicant: "wpa_supplicant",
                     ifname: "mesh0",
                     wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.mesh0",
                     control_path: "/tmp/vintage_net/wpa_supplicant",
                     ap_mode: false,
                     verbose: false
                   ]
                 }
               ],
               cleanup_files: ["/tmp/vintage_net/wpa_supplicant/mesh0"],
               down_cmd_millis: 5000,
               down_cmds: [
                 {:run, _, ["wlan0", "mesh0", "del"]},
                 {:fun, _},
                 {:run_ignore_errors, "ip", ["addr", "flush", "dev", "mesh0", "label", "mesh0"]},
                 {:run, "ip", ["link", "set", "mesh0", "down"]}
               ],
               files: [
                 {"/tmp/vintage_net/wpa_supplicant.conf.mesh0",
                  "ctrl_interface=/tmp/vintage_net/wpa_supplicant\ncountry=00\nwps_cred_processing=1\nnetwork={\nssid=\"mesh\"\nkey_mgmt=SAE\nmode=5\nfrequency=2412\nsae_password=\"password\"\n}\n"}
               ],
               ifname: "mesh0",
               required_ifnames: ["wlan0"],
               restart_strategy: :rest_for_one,
               retry_millis: 30000,
               source_config: %{
                 hostname: "unit_test",
                 ipv4: %{method: :disabled},
                 type: VintageNetWiFi,
                 vintage_net_wifi: %{
                   networks: [
                     %{
                       frequency: 2412,
                       key_mgmt: :sae,
                       sae_password: "password",
                       mode: :mesh,
                       ssid: "mesh"
                     }
                   ],
                   root_interface: "wlan0"
                 }
               },
               type: VintageNetWiFi,
               up_cmd_millis: 5000,
               up_cmds: [
                 {:run, _, ["wlan0", "mesh0", "add"]},
                 {:fun, _},
                 {:run, "ip", ["link", "set", "mesh0", "up"]}
               ]
             },
             VintageNetWiFi.to_raw_config("mesh0", input, default_opts())
           )
  end

  test "supplying wpa_supplicant_conf" do
    input = %{
      type: VintageNetWiFi,
      ipv4: %{method: :disabled},
      vintage_net_wifi: %{
        wpa_supplicant_conf: """
        network={
          ssid="home"
          scan_ssid=1
          key_mgmt=WPA-PSK
          psk="very secret passphrase"
        }
        """
      },
      hostname: "unit_test"
    }

    assert match?(
             %RawConfig{
               child_specs: [
                 {
                   VintageNetWiFi.WPASupplicant,
                   [
                     wpa_supplicant: "wpa_supplicant",
                     ifname: "wlan0",
                     wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
                     control_path: "/tmp/vintage_net/wpa_supplicant",
                     ap_mode: false,
                     verbose: false
                   ]
                 }
               ],
               cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"],
               down_cmd_millis: 5000,
               down_cmds: [
                 {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
                 {:run, "ip", ["link", "set", "wlan0", "down"]}
               ],
               files: [
                 {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
                  """
                  ctrl_interface=/tmp/vintage_net/wpa_supplicant
                  network={
                    ssid="home"
                    scan_ssid=1
                    key_mgmt=WPA-PSK
                    psk="very secret passphrase"
                  }
                  """}
               ],
               ifname: "wlan0",
               required_ifnames: ["wlan0"],
               restart_strategy: :rest_for_one,
               retry_millis: 30000,
               source_config: %{
                 hostname: "unit_test",
                 ipv4: %{method: :disabled},
                 type: VintageNetWiFi,
                 vintage_net_wifi: %{}
               },
               type: VintageNetWiFi,
               up_cmd_millis: 5000,
               up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}]
             },
             VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
           )
  end

  test "create a WiFi configuration with SSID that has nulls" do
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>,
            psk: "0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF",
            key_mgmt: :wpa_psk
          }
        ]
      },
      ipv4: %{method: :dhcp},
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: false,
           verbose: false
         ]},
        udhcpc_child_spec("wlan0", "unit_test"),
        {VintageNet.Connectivity.InternetChecker, "wlan0"}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         network={
         ssid="\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0"
         key_mgmt=WPA-PSK
         mode=0
         psk=0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF
         }
         """}
      ],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}],
      cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "create a WiFi configuration with SSID that exceeds max length with backslashes" do
    # This test works around an issue where backslashes count in the SSID length
    # calculation in wpa_supplicant. The workaround is to trim the SSID for now, since the
    # alternative is wpa_supplicant continuously restarting.

    # In this test, the SSID will be trimmed from 60 characters to 32 characters.
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: :binary.copy(<<0>>, 30),
            psk: "0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF",
            key_mgmt: :wpa_psk
          }
        ]
      },
      ipv4: %{method: :dhcp},
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: false,
           verbose: false
         ]},
        udhcpc_child_spec("wlan0", "unit_test"),
        {VintageNet.Connectivity.InternetChecker, "wlan0"}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         network={
         ssid="\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0"
         key_mgmt=WPA-PSK
         mode=0
         psk=0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF
         }
         """}
      ],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}],
      cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "create a WiFi configuration with SSID that exceeds max length with orphan backslash" do
    # This is a special case of the above test
    input = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "a" <> :binary.copy(<<0>>, 30),
            psk: "0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF",
            key_mgmt: :wpa_psk
          }
        ]
      },
      ipv4: %{method: :dhcp},
      hostname: "unit_test"
    }

    output = %RawConfig{
      ifname: "wlan0",
      type: VintageNetWiFi,
      source_config: VintageNetWiFi.normalize(input),
      required_ifnames: ["wlan0"],
      child_specs: [
        {VintageNetWiFi.WPASupplicant,
         [
           wpa_supplicant: "wpa_supplicant",
           ifname: "wlan0",
           wpa_supplicant_conf_path: "/tmp/vintage_net/wpa_supplicant.conf.wlan0",
           control_path: "/tmp/vintage_net/wpa_supplicant",
           ap_mode: false,
           verbose: false
         ]},
        udhcpc_child_spec("wlan0", "unit_test"),
        {VintageNet.Connectivity.InternetChecker, "wlan0"}
      ],
      restart_strategy: :rest_for_one,
      files: [
        {"/tmp/vintage_net/wpa_supplicant.conf.wlan0",
         """
         ctrl_interface=/tmp/vintage_net/wpa_supplicant
         country=00
         wps_cred_processing=1
         network={
         ssid="a\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0"
         key_mgmt=WPA-PSK
         mode=0
         psk=0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF
         }
         """}
      ],
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", "wlan0", "label", "wlan0"]},
        {:run, "ip", ["link", "set", "wlan0", "down"]}
      ],
      up_cmds: [{:run, "ip", ["link", "set", "wlan0", "up"]}],
      cleanup_files: ["/tmp/vintage_net/wpa_supplicant/wlan0"]
    }

    assert output == VintageNetWiFi.to_raw_config("wlan0", input, default_opts())
  end

  test "Summarize access_point list: When duplicate access points exist, keep the one with a stronger signal percent" do
    input = [
      %VintageNetWiFi.AccessPoint{
        bssid: "02:cb:7a:04:e9:52",
        frequency: 5220,
        band: :wifi_5_ghz,
        channel: 44,
        signal_dbm: -57,
        signal_percent: 90,
        flags: [:ess],
        ssid: "xfinitywifi"
      },
      %VintageNetWiFi.AccessPoint{
        bssid: "02:cb:7a:04:e9:54",
        frequency: 5220,
        band: :wifi_5_ghz,
        channel: 44,
        signal_dbm: -57,
        signal_percent: 81,
        flags: [:wpa2_eap_ccmp, :wpa2, :eap, :ccmp, :ess, :hs20],
        ssid: "anotherWifi"
      },
      %VintageNetWiFi.AccessPoint{
        bssid: "0e:51:a4:b2:e2:a1",
        frequency: 5180,
        band: :wifi_5_ghz,
        channel: 36,
        signal_dbm: -60,
        signal_percent: 86,
        flags: [:ess],
        ssid: "xfinitywifi"
      }
    ]

    expected_output = [
      %VintageNetWiFi.AccessPoint{
        ssid: "xfinitywifi",
        band: :wifi_5_ghz,
        bssid: "02:cb:7a:04:e9:52",
        channel: 44,
        flags: [:ess],
        frequency: 5220,
        signal_dbm: -57,
        signal_percent: 90
      },
      %VintageNetWiFi.AccessPoint{
        ssid: "anotherWifi",
        band: :wifi_5_ghz,
        bssid: "02:cb:7a:04:e9:54",
        channel: 44,
        flags: [:wpa2_eap_ccmp, :wpa2, :eap, :ccmp, :ess, :hs20],
        frequency: 5220,
        signal_dbm: -57,
        signal_percent: 81
      }
    ]

    assert expected_output == VintageNetWiFi.summarize_access_points(input)
  end

  test "Summarize access_point list: SSIDs that contain null characters are removed" do
    input = [
      %VintageNetWiFi.AccessPoint{
        bssid: "02:cb:7a:04:e9:52",
        frequency: 5220,
        band: :wifi_5_ghz,
        channel: 44,
        signal_dbm: -57,
        signal_percent: 90,
        flags: [:ess],
        ssid: "hidden\0"
      },
      %VintageNetWiFi.AccessPoint{
        bssid: "02:cb:7a:04:e9:54",
        frequency: 5220,
        band: :wifi_5_ghz,
        channel: 44,
        signal_dbm: -57,
        signal_percent: 81,
        flags: [:wpa2_eap_ccmp, :wpa2, :eap, :ccmp, :ess, :hs20],
        ssid: "\0\0\0"
      },
      %VintageNetWiFi.AccessPoint{
        bssid: "0e:51:a4:b2:e2:a1",
        frequency: 5180,
        band: :wifi_5_ghz,
        channel: 36,
        signal_dbm: -60,
        signal_percent: 86,
        flags: [:ess],
        ssid: "onlyRemainingWiFi"
      }
    ]

    expected_output = [
      %VintageNetWiFi.AccessPoint{
        bssid: "0e:51:a4:b2:e2:a1",
        frequency: 5180,
        band: :wifi_5_ghz,
        channel: 36,
        signal_dbm: -60,
        signal_percent: 86,
        flags: [:ess],
        ssid: "onlyRemainingWiFi"
      }
    ]

    assert expected_output == VintageNetWiFi.summarize_access_points(input)
  end

  test "Check if wlan is already configured" do
    configured = %{
      type: VintageNetWiFi,
      ipv4: %{method: :dhcp},
      vintage_net_wifi: %{
        networks: [
          %{
            key_mgmt: :wpa_psk,
            ssid: "IEEE",
            psk: "F42C6FC52DF0EBEF9EBB4B90B38A5F902E83FE1B135A70E23AED762E9710A12E",
            mode: :infrastructure
          }
        ]
      }
    }

    empty1 = %{
      type: VintageNetWiFi
    }

    empty2 = %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{networks: []},
      ipv4: %{method: :disabled}
    }

    assert VintageNetWiFi.network_configured?(configured)
    refute VintageNetWiFi.network_configured?(empty1)
    refute VintageNetWiFi.network_configured?(empty2)
    refute VintageNetWiFi.network_configured?(%{})
  end

  test "generating QR strings" do
    assert VintageNetWiFi.qr_string("Nerves", "IsCool") ==
             "WIFI:S:Nerves;T:WPA;P:IsCool;;"

    assert VintageNetWiFi.qr_string("Nerves", "") == "WIFI:S:Nerves;;"

    assert VintageNetWiFi.qr_string("Nerves", "IsCool", hidden: true) ==
             "WIFI:S:Nerves;T:WPA;P:IsCool;H:true;;"

    assert VintageNetWiFi.qr_string("Nerves", "IsCool", type: :WEP) ==
             "WIFI:S:Nerves;T:WEP;P:IsCool;;"

    assert VintageNetWiFi.qr_string("Nerves", "IsCool", type: :nopass) ==
             "WIFI:S:Nerves;;"

    # Obnoxious escaping example from docs
    assert VintageNetWiFi.qr_string("\"foo;bar\\baz\"", "") ==
             "WIFI:S:\\\"foo\\;bar\\\\baz\\\";;"

    # Ambiguous hex string example from docs
    assert VintageNetWiFi.qr_string("abcd", "abcd") == "WIFI:S:\"abcd\";T:WPA;P:\"abcd\";;"
  end
end
