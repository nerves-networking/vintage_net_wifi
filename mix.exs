defmodule VintageNetWiFi.MixProject do
  use Mix.Project

  @version "0.12.6"
  @source_url "https://github.com/nerves-networking/vintage_net_wifi"

  def project do
    [
      app: :vintage_net_wifi,
      version: @version,
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],
      start_permanent: Mix.env() == :prod,
      compilers: [:elixir_make | Mix.compilers()],
      make_targets: ["all"],
      make_clean: ["mix_clean"],
      make_error_message: "",
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      package: package(),
      description: description()
    ]
  end

  def application do
    [
      extra_applications: [:crypto, :logger]
    ]
  end

  def cli do
    [
      preferred_envs: %{
        docs: :docs,
        "hex.publish": :docs,
        "hex.build": :docs,
        credo: :test,
        "coveralls.circle": :test
      }
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description do
    "WiFi networking for VintageNet"
  end

  defp package do
    %{
      files: [
        "CHANGELOG.md",
        "c_src/*.[ch]",
        "c_src/test-c99.sh",
        "lib",
        "LICENSES/*",
        "mix.exs",
        "Makefile",
        "NOTICE",
        "README.md",
        "REUSE.toml"
      ],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "REUSE Compliance" =>
          "https://api.reuse.software/info/github.com/nerves-networking/vintage_net_wifi"
      }
    }
  end

  defp deps do
    [
      {:vintage_net, "~> 0.12.0 or ~> 0.13.0"},
      {:credo, "~> 1.2", only: :test, runtime: false},
      {:credo_binary_patterns, "~> 0.2.2", only: :test, runtime: false},
      {:dialyxir, "~> 1.1", only: :dev, runtime: false},
      {:elixir_make, "~> 0.6", runtime: false},
      {:ex_doc, "~> 0.22", only: :docs, runtime: false},
      {:excoveralls, "~> 0.13", only: :test, runtime: false}
    ]
  end

  defp dialyzer() do
    [
      flags: [:missing_return, :extra_return, :unmatched_returns, :error_handling, :underspecs],
      plt_file: {:no_warn, "_build/plts/dialyzer.plt"}
    ]
  end

  defp docs do
    [
      extras: ["README.md", "CHANGELOG.md"],
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end
end
