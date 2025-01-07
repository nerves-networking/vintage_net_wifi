defmodule Utils do
  @spec default_opts() :: keyword()
  def default_opts() do
    # Use the defaults in mix.exs, but normalize the paths to commands
    Application.get_all_env(:vintage_net)
  end
end

File.rm_rf!("test/tmp")

# Networking support has enough pieces that are singleton in nature
# that parallel running of tests can't be done.
ExUnit.start(max_cases: 1)
