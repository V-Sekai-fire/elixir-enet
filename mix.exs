defmodule EnetCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :enet_core,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      erlc_paths: if(Mix.env() == :test, do: ["test"], else: []),
      test_ignore_filters: [~r/\.ex$/],
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {EnetCore.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:gproc, git: "https://github.com/uwiger/gproc.git", branch: "master"},
      {:esockd, git: "https://github.com/emqx/esockd.git", branch: "master"},
      # Test dependencies
      {:propcheck, "~> 1.4", only: :test}
    ]
  end
end
