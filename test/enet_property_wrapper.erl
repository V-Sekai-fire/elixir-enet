-module(enet_property_wrapper).

-export([prop_sync_loopback/0]).

-include_lib("proper/include/proper.hrl").

-record(state, {
    hosts = []
}).

prop_sync_loopback() ->
    application:ensure_all_started(enet_core),
    application:ensure_all_started(gproc),
    ?FORALL(
        Commands,
        commands(enet_core_model),
        ?WHENFAIL(
            pretty_print_commands(Commands),
            ?TRAPEXIT(
                begin
                    {History, S, Res} = run_commands(enet_core_model, Commands),
                    lists:foreach(
                        fun(#{port := Port}) ->
                            case enet_core_sync:stop_host(Port) of
                                ok ->
                                    ok;
                                {error, Reason} ->
                                    io:format(
                                        "\n\nCleanup error: enet_core_sync:stop_host/1: ~p\n\n",
                                        [Reason]
                                    )
                            end
                        end,
                        S#state.hosts
                    ),
                    case Res of
                        ok ->
                            true;
                        _ ->
                            io:format(
                                "~nHistory: ~p~n~nState: ~p~n~nRes: ~p~n~n",
                                [History, S, Res]
                            ),
                            false
                    end
                end
            )
        )
    ).

pretty_print_commands(Commands) ->
    io:format("~n=TEST CASE=============================~n~n"),
    lists:foreach(
        fun(C) ->
            io:format("  ~s~n", [pprint(C)])
        end,
        Commands
    ),
    io:format("~n=======================================~n").

pprint({set, Var, Call}) ->
    io_lib:format("~s = ~s", [pprint(Var), pprint(Call)]);
pprint({var, N}) ->
    io_lib:format("Var~p", [N]);
pprint({call, M, F, Args}) ->
    PPArgs = [pprint(A) || A <- Args],
    io_lib:format("~p:~p(~s)", [M, F, lists:join(", ", PPArgs)]);
pprint(Other) ->
    io_lib:format("~p", [Other]).

