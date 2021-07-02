defmodule VintageNetWiFi.WPSDataTest do
  use ExUnit.Case
  alias VintageNetWiFi.WPSData

  doctest WPSData

  test "decodes SSID and passphrase credentials" do
    assert WPSData.decode(
             "100e003e10260001011045000b574c414e2d414539343536100300020020100f00020008102700104142434445463936363039353639353710200006b217eac18f1d"
           ) == {
             :ok,
             %{
               credential: %{
                 4099 => <<0, 32>>,
                 4111 => <<0, 8>>,
                 :network_key => "ABCDEF9660956957",
                 :ssid => "WLAN-AE9456",
                 :mac_address => "B2:17:EA:C1:8F:1D",
                 :network_index => 1
               }
             }
           }
  end

  test "errors on malformed strings" do
    assert WPSData.decode("100e00310262") == :error
    assert WPSData.decode("Hello") == :error
  end
end
