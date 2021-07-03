defmodule VintageNetWiFi.WPSDataTest do
  use ExUnit.Case
  alias VintageNetWiFi.WPSData

  doctest WPSData

  test "decodes SSID and passphrase credentials" do
    assert WPSData.decode(
             "100e003e10260001011045000b574c414e2d414539343536100300020020100f00020008102700103535363532343936363039353639353710200006b827ebc48f5d"
           ) == {:ok,
             %{
               credential: %{
                 :network_key => "5565249660956957",
                 :ssid => "WLAN-AE9456",
                 4099 => <<0, 32>>,
                 4111 => <<0, 8>>,
                 4128 => <<184, 39, 235, 196, 143, 93>>,
                 4134 => <<1>>
               }
             }
           }
    assert WPSData.decode("100e00310262") == {:error, :unexpected_content}
  end
end
