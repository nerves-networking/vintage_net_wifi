# SPDX-FileCopyrightText: 2026 Jon Carstens
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetWiFi.HaLow.MorseCli do
  @moduledoc """
  Helpers for building optional `morse_cli` commands for S1G-specific tunables
  that are not expressed through the `wpa_supplicant` config.

  These are returned as `VintageNet.Interface.RawConfig` `up_cmds` using
  `{:run_ignore_errors, cmd, args}` so a failure to apply an optional tunable
  does not tear down the whole interface.

  > #### morse_cli is optional {: .info}
  >
  > The *mandatory* S1G channel/op-class `morse_cli` calls are made by the
  > Morse `wpa_supplicant`/`hostapd` fork itself during bring-up, not by this
  > module. This helper is only for genuinely optional extras (e.g. duty
  > cycle), so `morse_cli` never becomes a hard runtime requirement of the
  > Elixir code.
  """

  alias VintageNetWiFi.HaLow.Config

  @doc """
  Build the list of optional `morse_cli` `up_cmds` for `config`.

  Currently emits a duty-cycle command when `:duty_cycle` is set. More S1G
  tunables can be added here as they are validated.
  """
  @spec up_cmds(Config.t()) :: [{:run_ignore_errors, String.t(), [String.t()]}]
  def up_cmds(%Config{duty_cycle: nil}), do: []

  def up_cmds(%Config{duty_cycle: mode, ifname: ifname, morse_cli: bin}) do
    [{:run_ignore_errors, bin, ["-i", ifname] ++ duty_cycle_args(mode)}]
  end

  defp duty_cycle_args(:disable), do: ["duty_cycle", "disable"]
  defp duty_cycle_args(:spread), do: ["duty_cycle", "enable", "-m", "0"]
  defp duty_cycle_args(:burst), do: ["duty_cycle", "enable", "-m", "1"]
end
