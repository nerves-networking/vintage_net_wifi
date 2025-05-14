# SPDX-FileCopyrightText: 2025 Jonatan Männchen <jonatan@maennchen.ch>
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Mix.Tasks.VintageNetWifi.AddNetwork.Docs do
  @moduledoc false

  @spec short_doc() :: String.t()
  def short_doc() do
    "Add network configuration to VintageNet wifi interface."
  end

  @spec example() :: String.t()
  def example() do
    ~S"""
    mix vintage_net_wifi.add_network \
      wlan0 \
      --ssid "MySSID" \
      --key-mgmt "wpa_psk" \
      --psk "MySecretPassword"
    """
  end

  @spec long_doc() :: String.t()
  def long_doc() do
    """
    #{short_doc()}

    ## Example

    ```bash
    #{example()}
    ```

    ## Options

    * `--ssid` or `-s` - The SSID of the network to add.
    * `--key-mgmt` or `-m` - The key management type to use.
      Currently only `wpa_psk` and `none` are supported.
    * `--psk` or `-p` - The pre-shared key to use for the network.
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.VintageNetWifi.AddNetwork do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"

    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    alias Igniter.Project.Config

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        # Groups allow for overlapping arguments for tasks by the same author
        # See the generators guide for more.
        group: :vintage_net_wifi,
        # *other* dependencies to add
        # i.e `{:foo, "~> 2.0"}`
        adds_deps: [],
        # *other* dependencies to add and call their associated installers, if they exist
        # i.e `{:foo, "~> 2.0"}`
        installs: [],
        # An example invocation
        example: __MODULE__.Docs.example(),
        # a list of positional arguments, i.e `[:file]`
        positional: [
          :interface
        ],
        # Other tasks your task composes using `Igniter.compose_task`, passing in the CLI argv
        # This ensures your option schema includes options from nested tasks
        composes: [
          "vintage_net.install"
        ],
        # `OptionParser` schema
        schema: [
          ssid: :string,
          key_mgmt: :string,
          psk: :string
        ],
        # Default values for the options in the `schema`
        defaults: [],
        # CLI aliases
        aliases: [
          s: :ssid,
          m: :key_mgmt
        ],
        # A list of options in the schema that are required
        required: [
          :ssid,
          :key_mgmt
        ]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      igniter
      |> Igniter.compose_task(
        "vintage_net_wifi.install",
        igniter.args.argv ++ ["--interface", igniter.args.positional.interface]
      )
      |> add_interface(igniter.args.positional.interface, igniter.args.options)
    end

    @spec add_interface(igniter :: Igniter.t(), interface :: String.t(), options :: Keyword.t()) ::
            Igniter.t()
    defp add_interface(igniter, interface, options) do
      options =
        options
        |> Keyword.take(~w(ssid key_mgmt psk)a)
        |> Keyword.update!(:key_mgmt, fn
          "wpa_psk" ->
            :wpa_psk

          "none" ->
            :none

          key_mgmt ->
            Mix.raise("Invalid key_mgmt: #{key_mgmt}, only 'wpa_psk' and 'none' are supported.")
        end)
        |> Enum.sort()
        |> Enum.map(fn {key, value} ->
          {{:__block__, [format: :keyword], [key]}, {:__block__, [], [value]}}
        end)
        |> then(&{:%{}, [], &1})

      Config.configure(
        igniter,
        "target.exs",
        :vintage_net,
        [:config],
        :unused_is_aways_an_update,
        updater: fn zipper ->
          {:ok, zipper} =
            Igniter.Code.List.move_to_list_item(zipper, fn zipper ->
              with true <- Igniter.Code.Tuple.tuple?(zipper),
                   {:ok, first} <- Igniter.Code.Tuple.tuple_elem(zipper, 0) do
                Igniter.Code.Common.nodes_equal?(first, interface)
              else
                _ ->
                  false
              end
            end)

          {:ok, zipper} = Igniter.Code.Tuple.tuple_elem(zipper, 1)

          Igniter.Code.Map.set_map_key(
            zipper,
            :networks,
            [options],
            &{:ok, Igniter.Code.List.append_to_list(&1, options)}
          )
        end
      )
    end
  end
else
  defmodule Mix.Tasks.VintageNetWifi.AddNetwork do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'vintage_net_wifi.add_network' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
