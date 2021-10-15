defmodule VintageNetWiFi.Event do

  @moduledoc ~S"""
  WiFi events.



  Currently supported:
  * `CTRL-EVENT-ASSOC-REJECT` - occurs when authentication fails
  * `CTRL-EVENT-SSID-TEMP-DISABLED` - association with SSID is temporarily blocked by `wpa_supplicant` in some cases.
  * `CTRL-EVENT-SSID-REENABLED` - matching event when SSID is re-enabled.

  All events have a `:name`, and the other fields are optional.
  * `CTRL-EVENT-ASSOC-REJECT`
    * `:bssid` - a unique address for the access point
    * `:status_code` - status code of the event 
  * `CTRL-EVENT-SSID-TEMP-DISABLED`
    * `:id` - event identifier?
    * `:ssid` - the access point's name
    * `:auth_failures` - how many failures occured to lead to disabling
    * `:duration` - time of block in seconds
    * `:reason` - why the SSID is disabled
  * `CTRL-EVENT-SSID-REENABLED`
    * `:id` - event identifier?
    * `:ssid` - the access point's name

  ## Examples:

      iex> VintageNetWiFi.Event.new("CTRL-EVENT-ASSOC-REJECT", "ab:cd:ef:01:02:03", "1")
      %VintageNetWiFi.Event{
        name: "CTRL-EVENT-ASSOC-REJECT", 
        bssid: "ab:cd:ef:01:02:03", 
        status_code: 1
      }
  """

  @enforce_keys [:name]

  defstruct [:name, :bssid, :status_code, :id, :ssid, :auth_failures, :duration, :reason]

  @typedoc """
  WiFi event structure.
  """
  @type t :: %__MODULE__{
          name: String.t(),
          bssid: String.t(),
          status_code: non_neg_integer(),
          id: non_neg_integer(),
          ssid: String.t(),
          auth_failures: non_neg_integer(),
          duration: non_neg_integer(),
          reason: String.t(),
        }

  @doc """
  Create an event with the appropriate fields
  """
  def new(name, arg1, arg2)

  @spec new(String.t(), String.t(), non_neg_integer()) :: VintageNetWiFi.Event.t()
  def new(name = "CTRL-EVENT-ASSOC-REJECT", bssid, status_code) 
    when is_integer(status_code) and status_code >= 0 do
    %__MODULE__{
      name: name,
      bssid: bssid,
      status_code: status_code,
    }
  end
  @spec new(String.t(), String.t(), String.t()) :: VintageNetWiFi.Event.t()
  def new(name = "CTRL-EVENT-ASSOC-REJECT", bssid, status_code) do
    new(name, bssid, String.to_integer(status_code))
  end

  @spec new(String.t(), non_neg_integer(), String.t()) :: VintageNetWiFi.Event.t()
  def new(name = "CTRL-EVENT-SSID-REENABLED", id, ssid)
    when is_integer(id) and id >= 0 do
    %__MODULE__{
      name: name,
      id: id,
      ssid: ssid,
    }
  end
  @spec new(String.t(), String.t(), String.t()) :: VintageNetWiFi.Event.t()
  def new(name = "CTRL-EVENT-SSID-REENABLED", id, ssid) do
    new(name, String.to_integer(id), ssid)
  end

  @doc """
  Create an event with the appropriate fields
  """
  @spec new(String.t(), non_neg_integer(), String.t(), non_neg_integer(), non_neg_integer(), String.t()) :: VintageNetWiFi.Event.t()
  def new(name = "CTRL-EVENT-SSID-TEMP-DISABLED", id, ssid, auth_failures, duration, reason) 
    when is_integer(id) and id >= 0 and is_integer(auth_failures) and auth_failures >= 0 and is_integer(duration) and duration >= 0 do
    %__MODULE__{
      name: name,
      id: id,
      ssid: ssid,
      auth_failures: auth_failures,
      duration: duration,
      reason: reason,
    }
  end
  @spec new(String.t(), String.t(), String.t(), String.t(), String.t(), String.t()) :: VintageNetWiFi.Event.t()
  def new(name = "CTRL-EVENT-SSID-TEMP-DISABLED", id, ssid, auth_failures, duration, reason) do
    new(name, String.to_integer(id), ssid, String.to_integer(auth_failures), String.to_integer(duration), reason)
  end



end
