defmodule EnetCore.PropertyTest do
  @moduledoc """
  Property-based tests for EnetCore using PropCheck.
  
  These tests use property-based testing to verify EnetCore behavior across
  many randomly generated sequences of operations.
  """

  use ExUnit.Case, async: false
  use PropCheck

  setup do
    # Ensure ENet application is started
    {:ok, _} = Application.ensure_all_started(:enet_core)
    {:ok, _} = Application.ensure_all_started(:gproc)

    on_exit(fn ->
      # Cleanup any remaining hosts
      :ok
    end)

    :ok
  end

  @tag :property
  property "sync loopback - all command sequences maintain invariants" do
    # Call the Erlang wrapper that uses PropEr macros
    # Reduced to ~50 iterations to complete in ~1 minute
    prop = :enet_property_wrapper.prop_sync_loopback()
    # Run with reduced iterations for faster testing
    # PropEr returns true on success
    true = :proper.quickcheck(prop, [{:numtests, 50}])
  end
end
