defmodule Enet.MixProject do
  use Mix.Project

  def project do
    [
      app: :enet,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      authors: ["K. S. Ernest (iFire) Lee <ernest.lee@chibifire.com>"],
      source_url: "https://github.com/V-Sekai-fire/elixir-enet",
      homepage_url: "https://github.com/V-Sekai-fire/elixir-enet",
      test_paths: ["test"],
      erlc_paths: if(Mix.env() == :test, do: ["test"], else: []),
      test_ignore_filters: [~r/\.ex$/],
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Enet.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:gproc, git: "https://github.com/uwiger/gproc.git", branch: "master"},
      {:esockd, git: "https://github.com/emqx/esockd.git", branch: "master"},
      # Code analysis
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      # Test dependencies
      {:propcheck, git: "https://github.com/alfert/propcheck.git", branch: "master", only: :test}
    ]
  end
end
