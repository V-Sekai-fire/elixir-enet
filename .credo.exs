%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      checks: [
        {Credo.Check.Readability.PreferImplicitTry, false},
        {Credo.Check.Consistency.LineEndings, false}
      ]
    }
  ]
}


