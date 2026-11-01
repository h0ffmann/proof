-module(fabric_ffi).
-export([args/0, getenv/1, halt/1, eprint/1, read_file/1, write_file/2, exists/1, is_dir/1,
         list_dir/1, make_dirs/1, temp_dir/0, remove_all/1, run/3, sha256_hex/1,
         regex_compile/2, regex_check/2, regex_scan/2, regex_replace/4, regex_split/2,
         json_decode/1, http/4, tar_gz_create/2, tar_gz_extract/2]).

args() -> [unicode:characters_to_binary(A) || A <- init:get_plain_arguments()].

getenv(Name) ->
    case os:getenv(binary_to_list(Name)) of
        false -> {error, nil};
        V -> {ok, unicode:characters_to_binary(V)}
    end.

halt(Code) -> erlang:halt(Code, [{flush, true}]).

eprint(S) -> io:put_chars(standard_error, S).

read_file(P) ->
    case file:read_file(P) of
        {ok, B} -> {ok, B};
        {error, R} -> {error, reason(P, R)}
    end.

write_file(P, B) ->
    case file:write_file(P, B) of
        ok -> {ok, nil};
        {error, R} -> {error, reason(P, R)}
    end.

exists(P) -> filelib:is_file(P).
is_dir(P) -> filelib:is_dir(P).

list_dir(P) ->
    case file:list_dir(P) of
        {ok, Names} -> {ok, lists:sort([unicode:characters_to_binary(N) || N <- Names])};
        {error, R} -> {error, reason(P, R)}
    end.

make_dirs(P) ->
    case filelib:ensure_path(P) of
        ok -> {ok, nil};
        {error, R} -> {error, reason(P, R)}
    end.

temp_dir() ->
    Base = case os:getenv("TMPDIR") of false -> "/tmp"; T -> T end,
    D = filename:join(Base, "fabric-" ++ integer_to_list(erlang:unique_integer([positive]))
                      ++ "-" ++ os:getpid()),
    ok = file:make_dir(D),
    unicode:characters_to_binary(D).

remove_all(P) -> _ = file:del_dir_r(P), nil.

reason(P, R) -> unicode:characters_to_binary([P, ": ", file:format_error(R)]).

%% run(Command, Args, Cwd): stdout is captured, stderr goes to ours, as Python's
%% subprocess.run(capture_output=True) with stderr left alone. Cwd "" keeps ours.
run(Cmd, Args, Cwd) ->
    case os:find_executable(binary_to_list(Cmd)) of
        false -> {error, <<Cmd/binary, ": command not found">>};
        Exe ->
            Opts = [{args, [binary_to_list(A) || A <- Args]}, exit_status, binary, use_stdio,
                    hide | case Cwd of <<>> -> []; _ -> [{cd, binary_to_list(Cwd)}] end],
            Port = open_port({spawn_executable, Exe}, Opts),
            collect(Port, [])
    end.

collect(Port, Acc) ->
    receive
        {Port, {data, D}} -> collect(Port, [Acc, D]);
        {Port, {exit_status, S}} -> {ok, {S, iolist_to_binary(Acc)}}
    end.

sha256_hex(B) -> binary:encode_hex(crypto:hash(sha256, B), lowercase).

regex_compile(Pattern, Opts) ->
    %% Gleam sends caseless, multiline and dotall, which are re option names already.
    case re:compile(Pattern, [unicode, ucp | Opts]) of
        {ok, R} -> {ok, {R, groups(unicode:characters_to_list(Pattern), 0)}};
        {error, {Msg, At}} -> {error, unicode:characters_to_binary(io_lib:format("~s at ~p", [Msg, At]))}
    end.

%% Erlang's re drops unset groups at the end of a match, so the group count is kept with the
%% pattern and every group is asked for by number.
groups([], N) -> N;
groups([$\\, _ | T], N) -> groups(T, N);
groups([$[ | T], N) -> groups(class(T), N);
groups([$(, $?, $< | [C | _] = T], N) when C =/= $=, C =/= $! -> groups(T, N + 1);
groups([$(, $?, $P, $< | T], N) -> groups(T, N + 1);
groups([$(, $? | T], N) -> groups(T, N);
groups([$( | T], N) -> groups(T, N + 1);
groups([_ | T], N) -> groups(T, N).

class([$] | T]) -> skip_class(T);
class([$^, $] | T]) -> skip_class(T);
class(T) -> skip_class(T).
skip_class([]) -> [];
skip_class([$\\, _ | T]) -> skip_class(T);
skip_class([$] | T]) -> T;
skip_class([_ | T]) -> skip_class(T).

regex_check({R, _}, S) -> re:run(S, R, [{capture, none}]) =:= match.

%% Every match, as [whole, group1, ...]; a group that took no part is "".
regex_scan({R, N}, S) ->
    case re:run(S, R, [global, {capture, lists:seq(0, N), binary}]) of
        {match, Ms} -> Ms;
        nomatch -> []
    end.

regex_replace({R, _}, S, With, All) ->
    Opts = [{return, binary} | case All of true -> [global]; false -> [] end],
    re:replace(S, R, With, Opts).

regex_split({R, _}, S) -> re:split(S, R, [{return, binary}]).

%% JSON with object key order kept, as Python's dict keeps it.
json_decode(B) ->
    try
        {V, ok, <<>>} = json:decode(B, ok, #{
            object_start => fun(_) -> [] end,
            object_push => fun(K, V, Acc) -> [{K, V} | Acc] end,
            object_finish => fun(Acc, Old) -> {{object, lists:reverse(Acc)}, Old} end,
            array_start => fun(_) -> [] end,
            array_push => fun(V, Acc) -> [V | Acc] end,
            array_finish => fun(Acc, Old) -> {{array, lists:reverse(Acc)}, Old} end,
            null => null}),
        {ok, wrap(V)}
    catch
        _:E -> {error, unicode:characters_to_binary(io_lib:format("~p", [E]))}
    end.

wrap(null) -> null;
wrap(true) -> {bool, true};
wrap(false) -> {bool, false};
wrap(I) when is_integer(I) -> {int, I};
wrap(F) when is_float(F) -> {float, F};
wrap(S) when is_binary(S) -> {string, S};
wrap({array, L}) -> {array, [wrap(X) || X <- L]};
wrap({object, KVs}) -> {object, [{K, wrap(V)} || {K, V} <- KVs]}.

%% http(Method, Url, Headers, Body) -> {ok, {Status, Body}}. HTTPS_PROXY and SSL_CERT_FILE are
%% honoured, since httpc reads neither on its own.
http(Method, Url, Headers, Body) ->
    {ok, _} = application:ensure_all_started([inets, ssl]),
    proxy(),
    Hs = [{binary_to_list(K), binary_to_list(V)} || {K, V} <- Headers],
    Ssl = [{ssl, [{verify, verify_peer}, cacerts(),
                  {customize_hostname_check, [{match_fun, public_key:pkix_verify_hostname_match_fun(https)}]}]},
           {timeout, 120000}],
    M = list_to_atom(string:lowercase(binary_to_list(Method))),
    %% A request without a body and without a Content-Type sends neither, as urllib does.
    Req = case {M, Body, lists:keymember("Content-Type", 1, Hs)} of
              {get, _, _} -> {binary_to_list(Url), Hs};
              {delete, _, _} -> {binary_to_list(Url), Hs};
              {_, <<>>, false} -> {binary_to_list(Url), Hs, "", Body};
              _ -> {binary_to_list(Url), Hs, content_type(Hs), Body}
          end,
    case httpc:request(M, Req, Ssl, [{body_format, binary}]) of
        {ok, {{_, Status, _}, _, RespBody}} -> {ok, {Status, RespBody}};
        {error, R} -> {error, unicode:characters_to_binary(io_lib:format("~p", [R]))}
    end.

content_type(Hs) ->
    case lists:keyfind("Content-Type", 1, Hs) of
        {_, T} -> T;
        false -> "application/octet-stream"
    end.

cacerts() ->
    case os:getenv("SSL_CERT_FILE") of
        false -> {cacerts, public_key:cacerts_get()};
        F -> {cacertfile, F}
    end.

proxy() ->
    case os:getenv("HTTPS_PROXY", os:getenv("https_proxy", "")) of
        "" -> ok;
        P ->
            #{host := H, port := Port} = uri_string:parse(P),
            NoProxy = string:split(os:getenv("NO_PROXY", os:getenv("no_proxy", "")), ",", all),
            ok = httpc:set_options([{https_proxy, {{H, Port}, NoProxy}}, {proxy, {{H, Port}, NoProxy}}])
    end.

%% tar_gz_create(Tarball, [{NameInArchive, Path}])
tar_gz_create(Tarball, Files) ->
    case erl_tar:create(binary_to_list(Tarball),
                        [{binary_to_list(N), binary_to_list(P)} || {N, P} <- Files], [compressed]) of
        ok -> {ok, nil};
        {error, R} -> {error, unicode:characters_to_binary(erl_tar:format_error(R))}
    end.

tar_gz_extract(Tarball, Dir) ->
    case erl_tar:extract(binary_to_list(Tarball), [compressed, {cwd, binary_to_list(Dir)}]) of
        ok -> {ok, nil};
        {error, R} -> {error, unicode:characters_to_binary(erl_tar:format_error(R))}
    end.
