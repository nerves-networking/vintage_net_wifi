defmodule VintageNetWiFi.WPSData do
  @moduledoc """
  Convert WPS data strings to and from maps
  """

  @doc """
  Decode WPS data
  """
  @spec decode(binary()) :: {:ok, map()} | :error
  def decode(hex_string) when is_binary(hex_string) do
    case Base.decode16(hex_string, case: :mixed) do
      {:ok, raw_bytes} -> decode_all_tlv(raw_bytes, %{})
      :error -> {:error, :hex_decoding}
    end
  end

  defp decode_all_tlv(<<>>, result), do: {:ok, result}

  defp decode_all_tlv(<<tag::16, len::16, value::binary-size(len), rest::binary>>, result) do
    with {t, v} <- decode_tlv(tag, value) do
      decode_all_tlv(rest, Map.put(result, t, v))
    end
  end

  defp decode_all_tlv(_unexpected, result) do
    case result do
      %{credential: %{ssid: _, network_key: _}} -> {:ok, result}
      _ -> {:error, :unexpected_content}
    end
  end

  defp decode_tlv(0x100E, value) do
    with {:ok, decoded} <- decode_all_tlv(value, %{}) do
      {:credential, decoded}
    end
  end

  defp decode_tlv(0x1045, value), do: {:ssid, value}
  defp decode_tlv(0x1027, value), do: {:network_key, value}
  defp decode_tlv(tag, value), do: {tag, value}
end
