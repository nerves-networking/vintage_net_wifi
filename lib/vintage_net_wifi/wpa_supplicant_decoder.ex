defmodule VintageNetWiFi.WPASupplicantDecoder do
  @moduledoc false

  @doc """
  Decode notifications from the wpa_supplicant
  """
  def decode_notification(<<"CTRL-REQ-", rest::binary>>) do
    [field, net_id, text] = String.split(rest, "-", parts: 3, trim: true)
    {:interactive, "CTRL-REQ-" <> field, String.to_integer(net_id), text}
  end

  def decode_notification(<<"CTRL-EVENT-BSS-ADDED", rest::binary>>) do
    [entry_id, bssid] = String.split(rest, " ", trim: true)
    {:event, "CTRL-EVENT-BSS-ADDED", String.to_integer(entry_id), bssid}
  end

  def decode_notification(<<"CTRL-EVENT-BSS-REMOVED", rest::binary>>) do
    [entry_id, bssid] = String.split(rest, " ", trim: true)
    {:event, "CTRL-EVENT-BSS-REMOVED", String.to_integer(entry_id), bssid}
  end

  # This message is just not shaped the same as others for some reason.
  def decode_notification(<<"CTRL-EVENT-CONNECTED", rest::binary>>) do
    ["-", "Connection", "to", bssid, status | info] = String.split(rest)

    info =
      Regex.scan(~r(\w+=[a-zA-Z0-9:\"_]+), Enum.join(info, " "))
      |> Map.new(fn [str] ->
        [key, val] = String.split(str, "=")
        {key, unescape_string(val)}
      end)

    {:event, "CTRL-EVENT-CONNECTED", bssid, status, info}
  end

  def decode_notification(<<"CTRL-EVENT-DISCONNECTED", rest::binary>>) do
    decode_kv_notification("CTRL-EVENT-DISCONNECTED", rest)
  end

  # "CTRL-EVENT-REGDOM-CHANGE init=CORE"
  def decode_notification(<<"CTRL-EVENT-REGDOM-CHANGE", rest::binary>>) do
    decode_kv_notification("CTRL-EVENT-REGDOM-CHANGE", rest)
  end

  # "CTRL-EVENT-ASSOC-REJECT bssid=00:00:00:00:00:00 status_code=16"
  def decode_notification(<<"CTRL-EVENT-ASSOC-REJECT", rest::binary>>) do
    decode_kv_notification("CTRL-EVENT-ASSOC-REJECT", rest)
  end

  # "CTRL-EVENT-SSID-TEMP-DISABLED id=1 ssid=\"FarmbotConnect\" auth_failures=1 duration=10 reason=CONN_FAILED"
  def decode_notification(<<"CTRL-EVENT-SSID-TEMP-DISABLED", rest::binary>>) do
    decode_kv_notification("CTRL-EVENT-SSID-TEMP-DISABLED", rest)
  end

  # "CTRL-EVENT-SUBNET-STATUS-UPDATE status=0"
  def decode_notification(<<"CTRL-EVENT-SUBNET-STATUS-UPDATE", rest::binary>>) do
    decode_kv_notification("CTRL-EVENT-SUBNET-STATUS-UPDATE", rest)
  end

  # CTRL-EVENT-SSID-REENABLED id=1 ssid=\"FarmbotConnect\""
  def decode_notification(<<"CTRL-EVENT-SSID-REENABLED", rest::binary>>) do
    decode_kv_notification("CTRL-EVENT-SSID-REENABLED", rest)
  end

  # "CTRL-EVENT-EAP-PEER-CERT depth=0 subject='/C=US/ST=California/L=San Luis Obispo/O=FarmBot Inc/CN=Connor Rigby/emailAddress=connor@farmbot.io' hash=ae7b11dc19b0ed3497540ac551d9730fd86380b3da9d494bb27cb8f2bda8fbd6"
  def decode_notification(<<"CTRL-EVENT-EAP-PEER-CERT ", rest::binary>>) do
    info = eap_peer_cert_decode(rest)
    {:event, "CTRL-EVENT-EAP-PEER-CERT", info}
  end

  def decode_notification(<<"CTRL-EVENT-EAP-STATUS", rest::binary>>) do
    info =
      Regex.scan(~r/\w+=(["'])(?:(?=(\\?))\2.)*?\1/, rest)
      |> Map.new(fn [str | _] ->
        [key, val] = String.split(str, "=", parts: 2)
        {key, unquote_string(val)}
      end)

    {:event, "CTRL-EVENT-EAP-STATUS", info}
  end

  def decode_notification(<<"CTRL-EVENT-EAP-FAILURE", rest::binary>>) do
    {:event, "CTRL-EVENT-EAP-FAILURE", String.trim(rest)}
  end

  def decode_notification(<<"CTRL-EVENT-EAP-METHOD", rest::binary>>) do
    {:event, "CTRL-EVENT-EAP-METHOD", String.trim(rest)}
  end

  def decode_notification(<<"CTRL-EVENT-EAP-PROPOSED-METHOD", rest::binary>>) do
    decode_kv_notification("CTRL-EVENT-EAP-PROPOSED-METHOD", rest)
  end

  def decode_notification(<<"CTRL-EVENT-", _type::binary>> = event) do
    {:event, String.trim_trailing(event)}
  end

  def decode_notification(<<"WPS-", _type::binary>> = event) do
    {:event, String.trim_trailing(event)}
  end

  def decode_notification(<<"AP-STA-CONNECTED ", mac::binary>>) do
    {:event, "AP-STA-CONNECTED", String.trim_trailing(mac)}
  end

  def decode_notification(<<"AP-STA-DISCONNECTED ", mac::binary>>) do
    {:event, "AP-STA-DISCONNECTED", String.trim_trailing(mac)}
  end

  # MESH-PEER-DISCONNECTED 00:00:00:00:00:00
  def decode_notification(<<"MESH-PEER-DISCONNECTED ", mac::binary>>) do
    {:event, "MESH-PEER-DISCONNECTED", String.trim_trailing(mac)}
  end

  # MESH-PEER-CONNECTED 00:00:00:00:00:00
  def decode_notification(<<"MESH-PEER-CONNECTED ", mac::binary>>) do
    {:event, "MESH-PEER-CONNECTED", String.trim_trailing(mac)}
  end

  # MESH-GROUP-STARTED ssid=\"my-mesh\" id=1
  def decode_notification(<<"MESH-GROUP-STARTED ", rest::binary>>) do
    decode_kv_notification("MESH-GROUP-STARTED", rest)
  end

  # MESH-GROUP-REMOVED mesh0
  def decode_notification(<<"MESH-GROUP-REMOVED ", ifname::binary>>) do
    {:event, "MESH-GROUP-REMOVED", String.trim_trailing(ifname)}
  end

  # MESH-SAE-AUTH-FAILURE addr=00:00:00:00:00:00
  def decode_notification(<<"MESH-SAE-AUTH-FAILURE ", rest::binary>>) do
    decode_kv_notification("MESH-SAE-AUTH-FAILURE", rest)
  end

  # MESH-SAE-AUTH-BLOCKED addr=00:00:00:00:00:00 duration=5
  def decode_notification(<<"MESH-SAE-AUTH-BLOCKED ", rest::binary>>) do
    decode_kv_notification("MESH-SAE-AUTH-BLOCKED", rest)
  end

  def decode_notification(string) do
    {:info, String.trim_trailing(string)}
  end

  defp eap_peer_cert_decode(
         binary,
         state \\ %{key?: true, in_quote?: false, key: <<>>, value: <<>>},
         acc \\ %{}
       )

  defp eap_peer_cert_decode(<<"=", rest::binary>>, %{key?: true} = state, acc) do
    eap_peer_cert_decode(rest, %{state | key?: false}, acc)
  end

  defp eap_peer_cert_decode(<<"\'", rest::binary>>, %{key?: false, in_quote?: false} = state, acc) do
    eap_peer_cert_decode(rest, %{state | in_quote?: true, value: state.value}, acc)
  end

  defp eap_peer_cert_decode(<<"\'", rest::binary>>, %{key?: false, in_quote?: true} = state, acc) do
    eap_peer_cert_decode(rest, %{state | in_quote?: false, value: state.value}, acc)
  end

  defp eap_peer_cert_decode(<<" ", rest::binary>>, %{key?: false, in_quote?: false} = state, acc) do
    eap_peer_cert_decode(
      rest,
      %{key?: true, in_quote?: false, key: <<>>, value: <<>>},
      Map.put(acc, state.key, String.trim(state.value))
    )
  end

  defp eap_peer_cert_decode(<<char::size(1)-binary, rest::binary>>, %{key?: true} = state, acc) do
    eap_peer_cert_decode(rest, %{state | key: state.key <> char}, acc)
  end

  defp eap_peer_cert_decode(<<char::size(1)-binary, rest::binary>>, %{key?: false} = state, acc) do
    eap_peer_cert_decode(rest, %{state | value: state.value <> char}, acc)
  end

  defp eap_peer_cert_decode(<<>>, state, acc) do
    Map.put(acc, state.key, String.trim(state.value))
  end

  defp decode_kv_notification(event, rest) do
    info =
      Regex.scan(~r(\w+=[\S*]+), rest)
      |> Map.new(fn [str] ->
        str = String.replace(str, "\'", "")
        [key, val] = String.split(str, "=", parts: 2)

        clean_val = val |> unquote_string() |> unescape_string()
        {key, clean_val}
      end)

    case Map.pop(info, "bssid") do
      {nil, _original} -> {:event, event, info}
      {bssid, new_info} -> {:event, event, bssid, new_info}
    end
  end

  @doc """
  Decode a key-value response from the wpa_supplicant
  """
  @spec decode_kv_response(String.t()) :: %{String.t() => String.t()}
  def decode_kv_response(resp) do
    resp
    |> String.split("\n", trim: true)
    |> decode_kv_pairs()
  end

  defp decode_kv_pairs(pairs) do
    Enum.reduce(pairs, %{}, fn pair, acc ->
      case String.split(pair, "=", parts: 2) do
        [key, value] ->
          clean_value = value |> String.trim_trailing() |> unescape_string()

          Map.put(acc, key, clean_value)

        _ ->
          # Skip
          acc
      end
    end)
  end

  defp unquote_string(<<"\"", _::binary>> = msg), do: String.trim(msg, "\"")
  defp unquote_string(<<"\'", _::binary>> = msg), do: String.trim(msg, "\'")
  defp unquote_string(other), do: other

  defp unescape_string(string) do
    unescape_string(string, [])
    |> Enum.reverse()
    |> :erlang.list_to_binary()
  end

  defp unescape_string("", acc), do: acc

  defp unescape_string(<<?\\, ?x, hex::binary-size(2), rest::binary>>, acc) do
    value = String.to_integer(hex, 16)
    unescape_string(rest, [value | acc])
  end

  defp unescape_string(<<other, rest::binary>>, acc) do
    unescape_string(rest, [other | acc])
  end

  @doc """
  Parse WiFi access point flags
  """
  @spec parse_flags(String.t()) :: [VintageNetWiFi.AccessPoint.flag()]
  def parse_flags(flags) do
    flags
    |> String.split(["]", "["], trim: true)
    |> Enum.flat_map(&parse_flag/1)
  end

  defp parse_flag("WPA2-PSK-CCMP"), do: [:wpa2_psk_ccmp]
  defp parse_flag("WPA2-EAP-CCMP"), do: [:wpa2_eap_ccmp]
  defp parse_flag("WPA2-PSK-CCMP+TKIP"), do: [:wpa2_psk_ccmp_tkip]
  defp parse_flag("WPA-PSK-CCMP+TKIP"), do: [:wpa_psk_ccmp_tkip]
  defp parse_flag("WPA-EAP-CCMP+TKIP"), do: [:wpa_eap_ccmp_tkip]
  defp parse_flag("IBSS"), do: [:ibss]
  defp parse_flag("MESH"), do: [:mesh]
  defp parse_flag("ESS"), do: [:ess]
  defp parse_flag("P2P"), do: [:p2p]
  defp parse_flag("WPS"), do: [:wps]
  defp parse_flag("RSN--CCMP"), do: [:rsn_ccmp]
  defp parse_flag(_other), do: []
end
