%%%-------------------------------------------------------------------
%%% @doc alara_uuid UUID generation agent.
%%%
%%% Exposes the full alara_uuid public API as an em_disco agent.
%%%
%%% === Actions (JSON body field: "action") ===
%%%
%%%   v7                  — Generate one RFC 9562 UUID v7.
%%%
%%%   v7 + "n"            — Generate N UUID v7s (param: "n", integer).
%%%
%%%   v5                  — Generate a deterministic UUID v5.
%%%                         Params: "namespace" ("dns"|"url"|"oid"|
%%%                         "x500", default "dns"), "name" (string).
%%%
%%%   to_string           — Format a UUID binary as a string.
%%%                         Params: "uuid" (hex or standard string),
%%%                         "format" ("standard"|"hex"|"urn"|"binary",
%%%                         default "standard").
%%%
%%%   ns_dns              — RFC 9562 DNS namespace UUID.
%%%   ns_url              — RFC 9562 URL namespace UUID.
%%%   ns_oid              — RFC 9562 OID namespace UUID.
%%%   ns_x500             — RFC 9562 X.500 namespace UUID.
%%%
%%% Default (no action): generate one UUID v7.
%%%
%%% Handler contract: handle/2 (Body, Memory) -> {RawList, Memory}.
%%% @end
%%%-------------------------------------------------------------------
-module(alara_uuid_filter_app).
-behaviour(application).

-export([start/2, stop/1]).
-export([handle/2, base_capabilities/0]).

%%====================================================================
%% Capability cascade
%%====================================================================

-spec base_capabilities() -> [binary()].
base_capabilities() ->
    em_filter:base_capabilities() ++ [<<"alara_uuid">>, <<"uuid">>,
                                      <<"uuidv7">>, <<"uuidv5">>,
                                      <<"erlang">>].

%%====================================================================
%% Application lifecycle
%%====================================================================

start(_Type, _Args) ->
    case alara_uuid_filter_sup:start_link() of
        {ok, Pid} ->
            ok = start_pop_and_http(),
            {ok, Pid};
        Error ->
            Error
    end.

stop(_State) ->
    catch cowboy:stop_listener(alara_uuid_filter_query_listener),
    catch em_pop_sup:stop_node(alara_uuid_filter),
    ok.

%%====================================================================
%% Internal
%%====================================================================

start_pop_and_http() ->
    PopPort   = application:get_env(alara_uuid_filter, pop_port,   9404),
    QueryPort = application:get_env(alara_uuid_filter, query_port, 9405),
    Seeds     = application:get_env(alara_uuid_filter, pop_seeds,  []),
    Vec = em_filter_vec:from_capabilities(base_capabilities()),
    catch em_pop_sup:stop_node(alara_uuid_filter),
    catch cowboy:stop_listener(alara_uuid_filter_query_listener),
    {ok, PopPid} = em_pop_sup:start_node(alara_uuid_filter, #{
        port            => PopPort,
        query_port      => QueryPort,
        vector          => Vec,
        max_peers       => 100,
        gossip_interval => 5_000
    }),
    lists:foreach(
        fun({H, P}) -> catch em_pop_node:add_peer(PopPid, H, P) end,
        Seeds),
    Dispatch = cowboy_router:compile([
        {'_', [{"/agent/query", em_filter_http,
                #{server => alara_uuid_filter_server}}]}
    ]),
    {ok, _} = cowboy:start_clear(alara_uuid_filter_query_listener,
                                  [{port, QueryPort}],
                                  #{env => #{dispatch => Dispatch}}),
    logger:notice("[alara_uuid_filter] gossip port ~w  query port ~w",
                  [PopPort, QueryPort]),
    ok.

handle(Body, Memory) when is_binary(Body) ->
    {dispatch(Body), Memory};
handle(_Body, Memory) ->
    {[], Memory}.

%%====================================================================
%% Dispatch
%%====================================================================

dispatch(Body) ->
    Params = decode_params(Body),
    case maps:get(<<"action">>, Params, <<"v7">>) of
        <<"v7">> ->
            case maps:get(<<"n">>, Params, undefined) of
                undefined ->
                    [uuid_embryo(alara_uuid:v7(), <<"v7">>)];
                N ->
                    Count = to_pos_int(N, 1),
                    [uuid_embryo(U, <<"v7">>) || U <- alara_uuid:v7(Count)]
            end;
        <<"v5">> ->
            NS   = parse_namespace(maps:get(<<"namespace">>, Params, <<"dns">>)),
            Name = maps:get(<<"name">>, Params, <<"">>),
            [uuid_embryo(alara_uuid:v5(NS, Name), <<"v5">>)];
        <<"to_string">> ->
            UuidHex = maps:get(<<"uuid">>, Params, <<"">>),
            Fmt     = parse_format(maps:get(<<"format">>, Params, <<"standard">>)),
            case hex_to_uuid(UuidHex) of
                error ->
                    [error_embryo(<<"to_string">>, <<"invalid uuid">>)];
                UUID ->
                    Str = alara_uuid:to_string(UUID, Fmt),
                    [format_embryo(Str, Fmt)]
            end;
        <<"ns_dns">> ->
            [ns_embryo(alara_uuid:ns_dns(), <<"dns">>)];
        <<"ns_url">> ->
            [ns_embryo(alara_uuid:ns_url(), <<"url">>)];
        <<"ns_oid">> ->
            [ns_embryo(alara_uuid:ns_oid(), <<"oid">>)];
        <<"ns_x500">> ->
            [ns_embryo(alara_uuid:ns_x500(), <<"x500">>)];
        _ ->
            [uuid_embryo(alara_uuid:v7(), <<"v7">>)]
    end.

%%====================================================================
%% Embryo builders
%%====================================================================

uuid_embryo(UUID, Type) when is_binary(UUID) ->
    Str = alara_uuid:to_string(UUID),
    #{<<"properties">> => #{
        <<"url">>    => <<"https://hex.pm/packages/alara_uuid">>,
        <<"title">>  => list_to_binary(Str),
        <<"resume">> => iolist_to_binary(
                            io_lib:format("UUID ~s", [Type])),
        <<"source">> => <<"alara_uuid">>
    }}.

format_embryo(Str, Fmt) ->
    FmtBin = if is_atom(Fmt) -> atom_to_binary(Fmt, utf8);
                is_binary(Fmt) -> Fmt;
                true -> <<"standard">>
             end,
    #{<<"properties">> => #{
        <<"url">>    => <<"https://hex.pm/packages/alara_uuid">>,
        <<"title">>  => list_to_binary(Str),
        <<"resume">> => iolist_to_binary(
                            io_lib:format("format: ~s", [FmtBin])),
        <<"source">> => <<"alara_uuid">>
    }}.

ns_embryo(UUID, NSName) ->
    Str = alara_uuid:to_string(UUID),
    #{<<"properties">> => #{
        <<"url">>    => <<"https://hex.pm/packages/alara_uuid">>,
        <<"title">>  => list_to_binary(Str),
        <<"resume">> => iolist_to_binary(
                            io_lib:format("namespace: ~s", [NSName])),
        <<"source">> => <<"alara_uuid">>
    }}.

error_embryo(Action, Reason) ->
    #{<<"properties">> => #{
        <<"url">>    => <<"https://hex.pm/packages/alara_uuid">>,
        <<"title">>  => iolist_to_binary(
                            io_lib:format("error: ~s", [Action])),
        <<"resume">> => Reason,
        <<"source">> => <<"alara_uuid">>
    }}.

%%====================================================================
%% Helpers
%%====================================================================

decode_params(Body) ->
    try json:decode(Body) of
        Map when is_map(Map) -> Map;
        _                    -> #{}
    catch _:_ -> #{} end.

to_pos_int(N, _Default) when is_integer(N), N > 0 -> N;
to_pos_int(B, Default) when is_binary(B) ->
    try
        N = binary_to_integer(B),
        if N > 0 -> N; true -> Default end
    catch _:_ -> Default end;
to_pos_int(_, Default) -> Default.

parse_namespace(<<"url">>)  -> url;
parse_namespace(<<"oid">>)  -> oid;
parse_namespace(<<"x500">>) -> x500;
parse_namespace(_)          -> dns.

parse_format(<<"hex">>)    -> hex;
parse_format(<<"urn">>)    -> urn;
parse_format(<<"binary">>) -> binary;
parse_format(_)            -> standard.

%% Convert a standard (xxxxxxxx-xxxx-...) or hex (32-char) UUID string
%% to a 128-bit binary.
hex_to_uuid(Str) when is_binary(Str) ->
    Hex = binary:replace(Str, <<"-">>, <<>>, [global]),
    try
        case byte_size(Hex) of
            32 ->
                << <<(binary_to_integer(<<H:2/binary>>, 16)):8>>
                   || <<H:2/binary>> <= Hex >>;
            _ -> error
        end
    catch _:_ -> error end;
hex_to_uuid(_) -> error.
