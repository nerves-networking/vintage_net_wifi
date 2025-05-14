# SPDX-FileCopyrightText: 2025 Jonatan Männchen <jonatan@maennchen.ch>
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Mix.Tasks.VintageNetWifi.Install.Docs do
  @moduledoc false

  @spec short_doc() :: String.t()
  def short_doc() do
    "Install & Setup VintageNetWiFi"
  end

  @spec example() :: String.t()
  def example() do
    ~S"""
    mix vintage_net_wifi.install \
      --regulatory-domain 00"
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

    * `--regulatory-domain` or `-r` - Regulatory domains to use for the wifi
      module. This is a string of 2 characters, e.g. "US" for the United
      States or "00" for the world. This is required for the wifi module
      to work.
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.VintageNetWifi.Install do
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
        installs: [{:vintage_net, "~> 0.13"}],
        # An example invocation
        example: __MODULE__.Docs.example(),
        # A list of environments that this should be installed in.
        only: nil,
        # a list of positional arguments, i.e `[:file]`
        positional: [],
        # Other tasks your task composes using `Igniter.compose_task`, passing in the CLI argv
        # This ensures your option schema includes options from nested tasks
        composes: [],
        # `OptionParser` schema
        schema: [
          interface: :string,
          regulatory_domain: :string
        ],
        # Default values for the options in the `schema`
        defaults: [
          interface: "wlan0"
        ],
        # CLI aliases
        aliases: [
          i: :interface,
          r: :regulatory_domain
        ],
        # A list of options in the schema that are required
        required: []
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      igniter
      |> add_regulatory_domain(igniter.args.options)
      |> add_wifi_interface(igniter.args.options[:interface])
    end

    @spec add_regulatory_domain(igniter :: Igniter.t(), options :: Keyword.t()) :: Igniter.t()
    defp add_regulatory_domain(igniter, options) do
      exists? =
        Config.configures_key?(
          igniter,
          "target.exs",
          :vintage_net,
          [:regulatory_domain]
        )

      if exists? do
        igniter
      else
        regulatory_domain =
          options[:regulatory_domain] ||
            Mix.shell().prompt("Regulatory domain (e.g. 'US' or '00')?")

        Config.configure(
          igniter,
          "target.exs",
          :vintage_net,
          [:regulatory_domain],
          regulatory_domain
        )
      end
    end

    @spec add_wifi_interface(igniter :: Igniter.t(), interface :: String.t()) :: Igniter.t()
    defp add_wifi_interface(igniter, interface) do
      Config.configure(
        igniter,
        "target.exs",
        :vintage_net,
        [:config],
        {:code,
         fix_ast(
           quote do
             [{unquote(interface), %{type: VintageNetWiFi}}]
           end
         )},
        updater: fn config_zipper ->
          type_config =
            Sourceror.Zipper.find(
              config_zipper,
              &match?({{:__block__, _, [:type]}, {:__aliases__, _, [:VintageNetWiFi]}}, &1)
            )

          case type_config do
            nil ->
              {:ok,
               Sourceror.Zipper.append_child(
                 config_zipper,
                 fix_ast(
                   quote do
                     {"wlan0", %{type: VintageNetWiFi}}
                   end
                 )
               )}

            _ ->
              {:ok, config_zipper}
          end
        end
      )
    end

    @spec fix_ast(ast :: Macro.t()) :: Macro.t()
    defp fix_ast(ast), do: ast |> Sourceror.to_string() |> Sourceror.parse_string!()
  end
else
  defmodule Mix.Tasks.VintageNetWifi.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'vintage_net_wifi.install' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
