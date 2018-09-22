-module(read_words).
-compile(export_all).

-record(word, {word, pronunciation, short_pronunciation}).

readlines(FileName) ->
    {ok, Data} = file:read_file(FileName),
    Lines = binary:split(Data, [<<"\n">>], [global]),
    Lines.

parse_lines(Lines, Db) ->
    try read_a_line(lists:nth(1, Lines), Db) of 
	_ -> ok
    catch
	exit:disconnected -> 
	    io:format("exit disconnected, reconnect"),
	    parse_lines(Lines, get_db())
    end,
    parse_lines(tl(Lines),
		Db).

short_pronunciation(String) ->
    binary:replace(
      binary:replace(
	binary:replace(String, <<"2">>, <<"">>, [global]), 
	<<"0">>, <<"">>, [global]), 
      <<"1">>, <<"">>, [global]).

read_a_line(<<"">>, Db) -> [];

read_a_line(Line, Db) ->
    [Word, Pronunciation]   = binary:split(Line, [<<"  ">>]),
    ShortPronunciation      = short_pronunciation(Pronunciation),
    io:format("word: ~p, pro1: ~p, pro2: ~p\n", 
	      [Word, Pronunciation, ShortPronunciation]),

    Object = riakc_obj:new(
	       <<"words">>, 
	       Word, 
	       jiffy:encode(
		 make_word(Word, Pronunciation, ShortPronunciation))),
    riakc_pb_socket:put(Db, Object),
    db_addtolist(<<"short_pronunciations">>, ShortPronunciation, Word, Db),
    [Object, Word, ShortPronunciation].

strip_nonalpha(String) ->
    list_to_binary(
      re:replace(String, "[^a-zA-Z ]", "", [global, {return, list}])).

sentance_to_pronunciation(String, Pid) ->
    Sentance          = strip_nonalpha(uppercase(String)),
    Words             = binary:split(Sentance, <<" ">>, [global]),
    Pronunciations    = lists:map(fun(Word) -> word_pronunciation(Word, Pid) end, 
				  Words),
    lists:map(fun(Word) -> binary_to_list(Word) end, Pronunciations).

join_pronunciations(Pronunciations) ->
    string:join(Pronunciations, " ").

make_word(Word, Pronunciation, ShortPronunciation) ->
    {[{word,                  strip_nonalpha(Word)},
      {pronunciation,         Pronunciation},
      {short_pronunciation,   ShortPronunciation}]}.
				
word_pronunciation(Word, Pid) ->				
    io:format("word parsing: ~p\n", [Word]),
    {ok, Result}   = riakc_pb_socket:get(Pid, <<"words">>, Word),
    Decoded        = jiffy:decode(riakc_obj:get_value(Result)),
    jget(<<"short_pronunciation">>, Decoded).

db_addtolist(Bucket, Name, AppendingValue, Pid) ->
    {Status, Value}    = riakc_pb_socket:get(Pid, Bucket, Name),
    if 
	Value == notfound ->
	    Encoded  = try
			   jiffy:encode([AppendingValue])
		       catch 
			   {error, {invalid_string, String}} -> jiffy:encode([])
		       end,

	    riakc_pb_socket:put(
	      Pid,
	      riakc_obj:new(Bucket,
			    Name,
			    Encoded));
	true ->
	    ListValue = jiffy:decode(riakc_obj:get_value(Value)),
	    Encoded   = try 
			    jiffy:encode([AppendingValue | ListValue])
			catch 
			    {error, {invalid_string, String}} -> jiffy:encode(ListValue)
			end,

	    riakc_pb_socket:put(
	      Pid,
	      riakc_obj:new(Bucket, 
			    Name, 
			    Encoded))
    end.

jget(Key, Obj) ->
    element(2, proplists:lookup(Key, element(1, Obj))).

jset(Key, Value, Obj) ->
    {lists:keyreplace(Key, 1, element(1, Obj), {Key, Value})}.

get_db() ->
    {ok, Db} = riakc_pb_socket:start_link("127.0.0.1", 8087),
    Db.

main() ->
%    couchbeam:start(),
%    Server          = couchbeam:server_connection(
%			"http://127.0.0.1:5984",
%			[]),
%    {ok, _Version}  = couchbeam:server_info(Server),
%    {ok, Db}        = couchbeam:create_db(Server, "words", []),        
    Db = get_db(),

%    riakc_pb_socket:get(Db, <<"pronunciations">>, "AH B AA S").

%   readlines("cmudict.txt", Db).
%    Lines = readlines("cmudict-0.7b.txt"),
%    parse_lines(Lines, Db).
						%  riakc_pb_socket:get(Db, <<"words2">>, "ASDF").
    
    sentance_to_pronunciation(<<"How are you doing today?">>, Db).

%    word_pronunciation(<<"AINU">>, Db).
% 

similar_pronunciations(Pronunciation) ->
    CodesTable = [["AA", "AE", "AH", "AO", "AW", "AY", "AXR",    % VOWELS
		   "AY", "EH", "ER", "EY", "IH", "IX", "IY", 
		   "OW", "OY", "UH", "UW", "UX"],
		  ["B", "D", "P"],
		  ["CH", "JH", "SH", "HH"],
		  ["G", "CH", "K"],
		  ["S", "Z", "ZH", "SH"],
		  ["TH", "T", "SH", "DH", "DX"],
		  ["EM", "EN", "N", "M"],
		  ["EL", "L"],
		  ["F", "TH"],
		  ["H", "JH"],
		  ["JH", "G"],
		  ["L", "R"],
		  ["NG", "NX", "N"],
		  ["Q"],
		  ["V", "W", "WH"],
		  ["Y"]],
    Codes           = lists:map(fun(Code) -> binary_to_list(Code) end,
			       binary:split(Pronunciation, [<<" ">>], [global])),
    Possibilities   = get_possibilities(Codes, CodesTable),
    Possibilities.
    
get_possibilities(Codes, CodesTable) ->
    lists:reverse(do_get_possibilities(Codes, CodesTable, [])).

do_get_possibilities([], CodesTable, List) ->
    List;
do_get_possibilities(Codes, CodesTable, List) ->
    do_get_possibilities(
      tl(Codes),
      CodesTable,
      [possibilities_for(lists:nth(1, Codes), CodesTable) | List]).

possibilities_for(Code, CodesTable) ->
    do_possibilities_for(Code, CodesTable, []).

do_possibilities_for(Code, [], List) ->
    List;
do_possibilities_for(Code, CodesTable, List) ->
    IsMatch   = lists:member(Code, lists:nth(1, CodesTable)),
    
    do_possibilities_for(
      Code, 
      tl(CodesTable),
      if 
	  IsMatch ->
	      lists:append(List, lists:nth(1, CodesTable));
	  true -> 
	      List
      end).
	
uppercase(String) ->
    Table = [{<<"a">>, <<"A">>},
	     {<<"b">>, <<"B">>}, 
	     {<<"c">>, <<"C">>}, 
	     {<<"d">>, <<"D">>}, 
	     {<<"e">>, <<"E">>}, 
	     {<<"f">>, <<"F">>}, 
	     {<<"g">>, <<"G">>}, 
	     {<<"h">>, <<"H">>}, 
	     {<<"i">>, <<"I">>}, 
	     {<<"j">>, <<"J">>}, 
	     {<<"k">>, <<"K">>}, 
	     {<<"l">>, <<"L">>}, 
	     {<<"m">>, <<"M">>}, 
	     {<<"n">>, <<"N">>}, 
	     {<<"o">>, <<"O">>}, 
	     {<<"p">>, <<"P">>}, 
	     {<<"q">>, <<"Q">>}, 
	     {<<"r">>, <<"R">>}, 
	     {<<"s">>, <<"S">>}, 
	     {<<"t">>, <<"T">>}, 
	     {<<"u">>, <<"U">>}, 
	     {<<"v">>, <<"V">>}, 
	     {<<"w">>, <<"W">>}, 
	     {<<"x">>, <<"X">>}, 
	     {<<"y">>, <<"Y">>}, 
	     {<<"z">>, <<"Z">>}],
    do_uppercase(String, Table).

do_uppercase(String, []) ->
    String;

do_uppercase(String, Table) ->
    Tuple = lists:nth(1, Table),
    do_uppercase(binary:replace(String,
				element(1, Tuple),
				element(2, Tuple),
				[global]),
		 tl(Table)).
        
    



