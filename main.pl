%****************************************************************************************
%  Thesis Work
%
%   Author:        Madeleine Malmsten
%   E-mail:        info@malmsten.eu
%   WWW:           http://www.malmsten.eu
%   Copyright (C): 2015, Madeleine Malmsten
%
%****************************************************************************************


:- module(chat_server,
	  [ server/0,
	    server/1,
	    create_chat_room/0
	  ]).
:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/websocket)).
:- use_module(library(http/html_write)).
:- use_module(library(http/js_write)).
:- use_module(library(http/json)).
:- use_module(library(http/json_convert)).
:- use_module(library(debug)).
:- use_module(library(http/http_files)).
:- use_module(library(smtp)).

:- use_module(hub).
:- use_module(library(threadutil)).

:- use_module(library(error)).

:- dynamic event/12.


server :-
	server(80).

server(Port) :-
	(   debugging(chat),
	    current_prolog_flag(gui, true)
	->  prolog_ide(thread_monitor)
	;   true
	),
	create_chat_room,
	http_server(http_dispatch, [port(Port)]),
	init_events("event.pl"),
	init_emails("email.pl"),
	thread_create(sensor_simulator(), _, [alias(simulator)]),
	thread_create(tracker(), _, [alias(tracker)]),
	asserta(email('web@easyrider.nu',1,authenticated)),
	asserta(pass("1992")),
	asserta(status(0)).
		
%****************************************************************************************
%	Debug. (Restart Prolog after being used)
%		thread_signal(chatroom, (attach_console, trace)).
%****************************************************************************************	



%:- http_handler(root(.), serve_files, [prefix]).
:- http_handler(root(.), http_reply_from_files('assets', []), [prefix]).
:- http_handler(root(event),
	http_upgrade_to_websocket(
		accept_chat,
		[ guarded(false),
		  subprotocols([chat])
		]),
	[ id(chat_websocket)
	]).

serve_files(Request) :-
	http_reply_from_files('assets', [], Request).
serve_files(Request) :-
	http_404([], Request).

accept_chat(WebSocket) :-
	hub_add(chat, WebSocket, _Id).

:- dynamic
	visitor/1.

create_chat_room :-
	hub_create(chat, Room, _{}),
	thread_create(chatroom(Room), _, [alias(chatroom)]).

chatroom(Room) :-
	thread_get_message(Room.queues.event, Message),
	%debug(chat, 'Got message ~p', [Message]),
	handle_message(Message, Room),
	chatroom(Room).


%****************************************************************************************
% Sensor simulator
%****************************************************************************************

sensor_simulator() :-
	X is random(2),
	debug(chat, 'Simulator says ~p', [X]),
	retractall(status(_)),
	asserta(status(X)),
	event(Eventint1,_,_,_),
	assert_events(X,Eventint1),
	sleep(10),
	sensor_simulator().
%****************************************************************************************
% Tracker
% This predicate keeps tracking the event clauses for unusual things that should not happen or
% for things that has not happened but should happen.
%****************************************************************************************

tracker() :-
	sleep(10),
	debug(chat, 'Startar backtracking ~n', []),
	print_status("Startar backtracking"),
	format(atom(Javascript), 'correctPattern();', []), % remove brokenPattern
	hub_broadcast(chat, websocket{client:default,data:Javascript,format:string,hub:chat,opcode:text}),
	fail.

% If the stove is off, predicate tracking if event has happened about the same time before
% no matter which week or weekday. If true, send a warning to GUI.
tracker() :-
	status(0),	
	print_status("Maskinen är inte på, kollar om det är normalt..."),
	get_time(Timestamp),
	stamp_date_time(Timestamp, date(_, _, _, Currenthour, Currentminute, _, _, _, _), 'UTC'),
	findall(Starttime,(
		event(0,Starttime,Message,Endtime),
		\+(Message == ignore),
		check_if_old(Starttime),
		check_time(Starttime, Endtime, Currenthour, Currentminute) % At this time of day the stove is usually on, but since status is zero it is not on now
		), List),
	length(List,Length),
	Length > 1,	
	alert(0),
	print_status("Borde inte maskinen vara på nu?"),
	debug(chat, 'Borde maskinen inte vara på???', []),!,
	tracker().

% All good
tracker() :-
	status(0),	
	print_status("Allt verkar vara i sin ordning"),
	debug(chat, 'All good', []),!,
	tracker().

tracker() :-
	status(1),	
	time_check(),
	fail.

% If the stove is on, predicate tracking if event
% has happened about the same time before (+/- 30 minutes) and consider weekday
tracker() :-
	status(1),	
	print_status("Maskinen är på, kontrollerar om en händelse liknande den pågående inträffat tidigare"),
	get_time(Timestamp),
	stamp_date_time(Timestamp, date(_, _, _, Currenthour, Currentminute, _, _, _, _), 'UTC'),
	event(0,Starttime,Message,Endtime),
	\+(Message == ignore),
	check_if_old(Starttime),
	check_week_number(Timestamp, Starttime),
	check_day_of_week(Timestamp, Starttime),
	check_time(Starttime, Endtime, Currenthour, Currentminute),
	print_status("Maskinen är på, och det verkar vara normalt"),
	debug(chat, 'This event has happened this time before considering time of day, week number AND weekday', []),!,
	tracker().

% Same as above, but do NOT consider week number
tracker() :-
	status(1),	
	number_of_event_clauses(40), % Check if number of events is more than I
	print_status("Maskinen är på, kollar om det verkar vara normalt"),
	get_time(Timestamp),
	stamp_date_time(Timestamp, date(_, _, _, Currenthour, Currentminute, _, _, _, _), 'UTC'),
	event(0,Starttime,Message,Endtime),
	\+(Message == ignore) ,
	check_if_old(Starttime),
	check_day_of_week(Timestamp, Starttime),
	check_time(Starttime, Endtime, Currenthour, Currentminute),
	print_status("Maskinen är på, och det verkar vara normalt"),
	debug(chat, 'This event has happened this time before considering time of day AND weekday', []),!,
	tracker().

% Same as above, but do NOT consider week number OR weekday
tracker() :-
	status(1),
	number_of_event_clauses(25), % Check if number of events is more than I
	print_status("Maskinen är på, kollar om det verkar vara normalt"),
	get_time(Timestamp),
	stamp_date_time(Timestamp, date(_, _, _, Currenthour, Currentminute, _, _, _, _), 'UTC'),
	event(0,Starttime,Message,Endtime),
	\+(Message == ignore) ,
	check_if_old(Starttime),
	check_time(Starttime, Endtime, Currenthour, Currentminute),
	print_status("Maskinen är på, och det verkar vara normalt"),
	debug(chat, 'This event has happened this time before considering time of day', []),!,
	tracker().

% Fail backtracking
tracker() :-
	status(1),	
	print_status("Mönstret har brutits!"),
	debug(chat, 'Tracker FAIL!', []),
	alert(1),!,
	tracker().


% If the stove is on, calculate if event is at least 50% longer than normal consider time of day, odd/even week AND weekday
time_check() :-
	status(1),	
	get_time(Timestamp),
	event(1,Currentstarttime,Thismessage,Currentendtime),
	print_status("Kollar om maskinen varit på längre tid än normalt"),
	\+(Thismessage == ignore),
	findall(Starttime,(
		event(0,Starttime,Oldmessage,Endtime),
		check_if_old(Starttime),
		tracker_time_length(Oldmessage,Timestamp,Starttime,Endtime,Currentstarttime),
		check_week_number(Currentstarttime, Starttime),
		check_day_of_week(Currentstarttime, Starttime),
		check_time(Starttime, Endtime, Currentstarttime, Currentendtime)
	), _List),
	print_status("Maskinen har inte varit på längre tid än normalt"),
	debug(chat, 'Not longer time running than normal considering time of day AND weekday', []),!.

% Same as above, but do NOT consider odd/even week
time_check() :-
	status(1),	
	number_of_event_clauses(40), % Check if number of events is more than I
	get_time(Timestamp),
	event(1,Currentstarttime,Thismessage,Currentendtime),
	print_status("Kollar om maskinen varit på längre tid än normalt"),
	\+(Thismessage == ignore),
	findall(Starttime,(
		event(0,Starttime,Oldmessage,Endtime),
		check_if_old(Starttime),
		tracker_time_length(Oldmessage,Timestamp,Starttime,Endtime,Currentstarttime),
		check_day_of_week(Currentstarttime, Starttime),
		check_time(Starttime, Endtime, Currentstarttime, Currentendtime)
	), _List),
	print_status("Maskinen har inte varit på längre tid än normalt"),
	debug(chat, 'Not longer time running than normal considering time of day AND weekday', []),!.

% Same as above, but do NOT consider odd/even week OR weekday
time_check() :-
	status(1),	
	number_of_event_clauses(30), % Check if number of events is more than I
	get_time(Timestamp),
	event(1,Currentstarttime,Thismessage,Currentendtime),
	print_status("Kollar om maskinen varit på längre tid än normalt"),
	\+(Thismessage == ignore),
	findall(Starttime,(
		event(0,Starttime,Oldmessage,Endtime),
		check_if_old(Starttime),
		tracker_time_length(Oldmessage,Timestamp,Starttime,Endtime,Currentstarttime),
		check_time(Starttime, Endtime, Currentstarttime, Currentendtime)
	), _List),
	print_status("Maskinen har inte varit på längre tid än normalt"),
	debug(chat, 'Not longer time running than normal considering time of day', []),!.

% Same as above, but do NOT consider weekday, odd/even week OR time
time_check() :-
	status(1),	
	number_of_event_clauses(15), % Check if number of events is more than I
	get_time(Timestamp),
	print_status("Kollar om maskinen varit på längre tid än normalt"),
	event(1,Currentstarttime,Thismessage,_Currentendtime),
	\+(Thismessage == ignore),
	findall(Starttime,(
		event(0,Starttime,Oldmessage,Endtime),
		check_if_old(Starttime),
		tracker_time_length(Oldmessage,Timestamp,Starttime,Endtime,Currentstarttime)
	), _List),
	print_status("Maskinen har inte varit på längre tid än normalt"),
	debug(chat, 'Not longer time running than normal', []),!.

% Fail backtracking
time_check() :-
	status(1),	
	print_status("Maskinen har varit på längre tid än normalt!"),
	debug(chat, 'Tracker FAIL!', []),
	alert(1),!.

%****************************************************************************************
% Email a warning if status not changed in 1 min, and stop if status not changed in 3 minutes
%****************************************************************************************
alert(Status) :-
	print_status("Skickar varning till GUI att mönstret brutits!"),
	format(atom(Javascript), 'brokenPattern();', []),
	hub_broadcast(chat, websocket{client:default,data:Javascript,format:string,hub:chat,opcode:text}),
	findall(Email,email(Email,_,authorized),Emaillist),
	%alarm(60,send_email(Emaillist,warning, Status), _, [remove(true)]),
	thread_create(send_email(Emaillist,warning, Status), Id1, []),
	thread_join(Id1,_Returns1),
	%alarm(180,stop(Status), _, [remove(true)]).
	thread_create(stop(Status), Id2, []),
	thread_join(Id2,_Returns2).

stop(Status) :-
	sleep(180),
	print_status("Kommando om att stänga av spisen sänds nu till Raspberry Pi"),
	status(Status),
	format(atom(Json), '$', []), % Send a $ to Raspberry Pi
	hub_broadcast(chat, websocket{client:default,data:Json,format:string,hub:chat,opcode:text}).
	
stop(_).


%****************************************************************************************
% Check time, check week
%****************************************************************************************
check_if_old(Timestamp) :- % Make sure event is not older than two months
	get_time(X),
	X - 5184000 > Timestamp.

check_time(Starttime, Endtime, Currenthour, Currentminute) :-
	print_status("Kollar om En händelse liknande nuvarande har inträffat vid samma tid"),
	stamp_date_time(Starttime, date(_, _, _, Eventstarthour, Eventstartminute, _, _, _, _), 'UTC'),
	stamp_date_time(Endtime, date(_, _, _, Eventendhour, Eventendminute, _, _, _, _), 'UTC'),
	Startofevent = Eventstarthour * 60 + Eventstartminute,
	Endofevent = Eventendhour * 60 + Eventendminute,
	Nowinminutes = Currenthour * 60 + Currentminute,
	Nowinminutes > Startofevent - 30,
	Nowinminutes < Endofevent + 30,
	print_status("En händelse liknande nuvarande har inträffat vid samma tid").

check_week_number(Timestamp, Starttime) :-
	print_status("En händelse liknande nuvarande har samma jämna/udda vecka"),
	format_time(atom(TWN), '%V', Timestamp), % Set week number and check odd/ even
	atom_number(TWN, Thisweeknumber),
	format_time(atom(EWD), '%V', Starttime),
	atom_number(EWD, Eventweeknumber),
	Evenodd is Thisweeknumber + Eventweeknumber,
	Evenodd mod 2 =:= 0,
	print_status("En händelse liknande nuvarande har samma jämna/udda vecka").

check_day_of_week(Timestamp, Starttime) :-
	print_status("Kollar om en händelse liknande nuvarande har inträffat samma veckodag"),
	format_time(atom(TDW), '%u', Timestamp),
	atom_number(TDW, Thisdow),
	format_time(atom(EWD), '%u', Starttime),
	atom_number(EWD, Eventdow),
	Thisdow == Eventdow,
	print_status("En händelse liknande nuvarande har inträffat samma veckodag").

%****************************************************************************************
% Additional predicates to tracker
%****************************************************************************************
tracker_time_length(Oldmessage,Timestamp,Starttime,Endtime,Currentstarttime) :-
	print_status("Kollar om pågående händelse har ägt rum längre tid än normalt"),
	\+(Oldmessage == ignore),
	Currentsession = Timestamp - Currentstarttime,
	Eventsession = Endtime - Starttime,
	Currentsession < Eventsession * 1.5,
	print_status("Pågående händelse har inte ägt rum längre tid än normalt").

number_of_event_clauses(I) :-
	findall(Starttime,event(0,Starttime,_Message,_Endtime),Elist),
	length(Elist,Length),
	Length < I.

%****************************************************************************************
% The time status predicate (recursive), that will be runned every second to update the GUI
% If the stove is off, calculate and print next start time no matter which week or weekday.
%****************************************************************************************

time_status() :-
	status(1),
	get_time(Now), 
	event(_Status,Oldtime,_Message,_),
	Timestamp is Now - Oldtime, 
	stamp_date_time(Timestamp, date(_, _, _, H, M, S, _, _, _), 'UTC'),
    format(atom(Javascript), 'document.getElementById("info").innerHTML = "~|~`0t~d~2+:~|~`0t~d~2+:~|~`0t~0f~2+";', [H,M,S]),
	hub_broadcast(chat, websocket{client:default,data:Javascript,format:string,hub:chat,opcode:text}),
	time_status().

time_status() :-
    format(atom(Javascript), 'document.getElementById("info").innerHTML = "00:00:00";', []),
	hub_broadcast(chat, websocket{client:default,data:Javascript,format:string,hub:chat,opcode:text}),
	time_status().

%****************************************************************************************
% Get message from GUI
%****************************************************************************************

handle_message(Message, Room) :- 
	websocket{client:Client,data:Data,format:string,hub:chat,opcode:text} :< Message,
	atom_string(Data1,Data),
	json:atom_json_dict(Data1, Json, []),
	handle_json_message(Json, Client, Room).
handle_message(Message, Room) :- 
	websocket{client:Client,data:Data,format:string,hub:chat,opcode:text} :< Message,
	json:atom_json_dict(Data, Json, []),
	handle_json_message(Json, Client, Room).
handle_message(Message, _Room) :-
	hub{joined:Id} :< Message, !,
	assertz(visitor(Id)).
handle_message(Message, _Room) :-
	hub{left:Id} :< Message, !,
	retractall(visitor(Id)).
handle_message(Message, _Room) :-
	debug(chat, 'Ignoring message ~p', [Message]).


%****************************************************************************************
% Make JSON from message
%****************************************************************************************

handle_json_message(_{pid:"event",type:"make",values:[]}, Client, _Room) :- % Web page opened
	print_status("Välkommen! :)"),
	debug(chat, 'Make recieved ~p.', [Client]).
	
handle_json_message(_{status:0,id:_Id}, _Client, _Room) :- % Connection from Raspberry Pi 
	retractall(status(_)),
	asserta(status(0)),
	event(Eventint1,_,_,_),
	assert_events(0,Eventint1),
	debug(chat, 'Connection from Raspberry Pi. 0 ~p ~p', [0,Eventint1]). 

handle_json_message(_{status:_Status,id:_Id}, _Client, _Room) :- % Connection from Raspberry Pi 
	debug(chat, 'Status 1 from pi', []),
	retractall(status(_)),
	asserta(status(1)),
	event(Eventint1,_,_,_),
	assert_events(1,Eventint1),
	debug(chat, 'Connection from Raspberry Pi. ~p ~p', [1,Eventint1]). 

handle_json_message(_{pid:"chat",type:"post",values:["login",Email,Pwd]}, Client, _Room) :- % Successfull sign in
	print_status("Dags att logga in!"),
	debug(chat, 'Got login json from client', []),
	pass(Pwd),
	atom_string(Emailatom, Email),
	email(Emailatom,_,authenticated),
	%alarm(1,time_status(), _Id, [remove(true)]),
	thread_create(time_status(), _Id1, []),
	format(atom(Javascript), 'loginSuccess();', []),
	hub_send(Client, websocket{client:Client,data:Javascript,format:text,hub:chat,opcode:text}),
	format_events(1),
	print_status("Du är nu inloggad!").
	
handle_json_message(_{pid:"chat",type:"post",values:["login",Email,Pwd]}, Client, _Room) :- % Please authenticate
	print_status("Ojojoj, en oautenticerad e-post!"),
	pass(Pwd),
	sub_string(Email, _, _, _, "@"),
	atom_string(Emailatom, Email),
	debug(chat, 'Email ~a', [Emailatom]),
	assert_emails(Emailatom),
	format(atom(Javascript), 'loginFail("auth");', []),
	hub_send(Client, websocket{client:Client,data:Javascript,format:text,hub:chat,opcode:text}).

handle_json_message(_{pid:"chat",type:"post",values:["login",_Email,_Pass]}, Client, _Room) :- % Sign in fails!!!
	format(atom(Javascript), 'loginFail("bad");', []),
	hub_send(Client, websocket{client:Client,data:Javascript,format:text,hub:chat,opcode:text}),
	print_status("Inloggningen misslyckades").

handle_json_message(_{pid:"chat",type:"post",values:["auth",Strhash]}, _Client, _Room) :- % Authentification message
	debug(chat, 'Time to auth', []),
	number_codes(Hash, Strhash),
	Auth = email(Email,Hash,_),
	retract(Auth),
	Updateauth = email(Email,Hash,authenticated),
	asserta(Updateauth),
	open('email.pl', append, Stream),
	write(Stream, "email('"),
	write(Stream, Email),
	write(Stream, "',"),
	write(Stream, Hash),
	write(Stream, ',authenticated).'),
	nl(Stream),
	flush_output(Stream),
	debug(chat, 'Closing ~p', [Stream]),
	close(Stream),
	debug(chat, 'Authentification updated', []),
	print_status("Din ep-post är numera autentiserad"). 

handle_json_message(_{pid:"chat",type:"post",values:["addevent",Starttime,Endtime,_Email,Pwd]}, Client, _Room) :- % Manually add new event
	pass(Pwd),
	number_string(Start, Starttime),
	number_string(End, Endtime),
	asserta(event(0,Start,unknown,End)),
	format(atom(Javascript), 'printMessage("eventadded");', []),
	hub_send(Client, websocket{client:Client,data:Javascript,format:text,hub:chat,opcode:text}),
	print_status("En ny händelse har lagts till manuellt"). 

handle_json_message(_{pid:"chat",type:"post",values:["stop",_Email,Pwd]}, Client, Room) :-
	pass(Pwd),
	Event = event(Status,Oldtime,_Message,Endtime),
	retract(Event),
	Updateevent = event(Status,Oldtime,ignore,Endtime),
	asserta(Updateevent),
	format(atom(Json), '$', []), % Send a $ to Raspberry Pi
	hub_broadcast(Room.name, websocket{client:default,data:Json,format:string,hub:chat,opcode:text}),
	print_status("Spisen stängs nu av"),
	format(atom(Javascript), 'printMessage("stop");', []),
	hub_send(Client, websocket{client:Client,data:Javascript,format:text,hub:chat,opcode:text}),!.

handle_json_message(_{pid:"chat",type:"post",values:["ignore",_Email,Pwd]}, Client, _Room) :-
	pass(Pwd),
	Event = event(Status,Oldtime,_Message,Endtime),
	retract(Event),
	Updateevent = event(Status,Oldtime,ignore,Endtime),
	asserta(Updateevent),
	print_status("Pågående händelese kommer att ignoreras"),
	format(atom(Javascript), 'printMessage("ignore");', []),
	hub_send(Client, websocket{client:Client,data:Javascript,format:text,hub:chat,opcode:text}),!.

handle_json_message(_{pid:"chat",type:"post",values:["correct",_Email,Pwd]}, Client, _Room) :-
	pass(Pwd),
	print_status("Pågående händelse kommer att inkluderas i framtida beräkningar"),
	format(atom(Javascript), 'printMessage("correct");', []),
	hub_send(Client, websocket{client:Client,data:Javascript,format:text,hub:chat,opcode:text}),!.

handle_json_message(_, _, _) :-
	debug(chat, 'Ooops', []).


%****************************************************************************************
% Status bar
%****************************************************************************************

print_status(Message) :-
	format(atom(Javascript), 'statusBox(~p);', [Message]),
	hub_broadcast(chat, websocket{client:default,data:Javascript,format:string,hub:chat,opcode:text}),!,
	debug(chat, 'Status message ~p sent to client', [Message]). 

print_status(_) :-
	debug(chat, 'No client to send status to', []). 


%****************************************************************************************
% Send all event clauses to GUI as Javascript
%****************************************************************************************

format_events(I) :-
	format(atom(Javascript), 'cleanEvents();', []),
	hub_broadcast(chat, websocket{client:default,data:Javascript,format:string,hub:chat,opcode:text}),!,
	print_events(I).

print_events(I) :-
	I < 10,
	nth_clause(event(_,_,_,_), I, Ref),
	clause(event(Status,Starttime,Message,Endtime), _, Ref),
	format(atom(Javascript), 'printEvents("~p","~p","~p","~p");', [Status,Starttime,Message,Endtime]),
	hub_broadcast(chat, websocket{client:default,data:Javascript,format:string,hub:chat,opcode:text}),
	I1 is I + 1,
	print_events(I1).

print_events(_) :-
	print_status("Listan över event har uppdaterats"),!.

print_events(_).

%****************************************************************************************
% Add event to event clauses list (in event.pl) if status have changed
%****************************************************************************************

assert_events(Eventint,Eventint).

assert_events(1, _Eventint) :-
	debug(chat, 'assert_events status 1', []),
	get_time(Timestamp),
	Evt = event(1,Timestamp,unknown,0),
	asserta(Evt),
	format_events(1).
		
assert_events(0, _Eventint) :-
	debug(chat, 'assert_events status 0', []),
	Event = event(1,Oldtime,Message,0),
	retract(Event),
	get_time(Timestamp),
	Updateevent = event(0,Oldtime,Message,Timestamp),
	asserta(Updateevent),
	open('event.pl', append, Stream),
	write(Stream, Updateevent),
	write(Stream, '.'),
	nl(Stream),
	flush_output(Stream),
	close(Stream),
	format_events(1),
	print_status("En ny händelse har blivit tillagd permanent").
	
%****************************************************************************************
% If not already added, add email to email clauses list (later saved to email.pl)
%****************************************************************************************

assert_emails(Email) :-
	email(Email,_,unauthenticated),
	retractall(email(Email,_,unauthenticated)),
	debug(chat, 'Email already exists and is removed from database', []),
	print_status("E-posten finns redan i databasen, den kommer att tas bort"),
	fail.

assert_emails(Email) :-
	term_hash(Email, Hash),
	debug(chat, 'Email ~p', [Email]),
	debug(chat, 'Hash ~p', [Hash]),
	Mail = email(Email,Hash,unauthenticated),
	asserta(Mail),
	send_email(Email,auth),
	print_status("Ny e-post är tillagd och ett autentiserings-mail har skickats"),
	debug(chat, 'New email added and authentication email has been sent', []).

assert_emails(_Email) :-
	debug(chat, 'Bad email or already authenticated email', []),
	print_status("E-posten antingen felaktig eller redan autentiserad").
        		
%****************************************************************************************
% Send authentication email
%****************************************************************************************

send_email(Emaillist,warning,Status) :-
	sleep(60),
	status(Status),
	send_email(Emaillist,warning).

send_email(Email,_,_) :-
	debug(chat, 'Status has changed', [Email]).

send_email(Email,auth) :-
	smtp_send_mail(Email,send_auth_message,[smtp('127.0.0.1'),security(none),header(from('Elise')),
		auth_method(plain),subject('Verifiera epost'),from('elise@easyrider.nu'),content_type('text/html')]).

send_email([Email|Tail],warning) :-
	smtp_send_mail(Email,send_warning_message,[smtp('127.0.0.1'),security(none),header(from('Elise')),
		auth_method(plain),subject('Varning!'),from('elise@easyrider.nu'),content_type('text/html')]),
	debug(chat, 'Warning email sent to ~p', [Email]),
	send_email(Tail,warning).

send_email(Email,_) :-
	debug(chat, 'Problem sending email to ~p or all emails been sent', [Email]).

send_auth_message(Out) :-
		email(Email,Hash,_),
		debug(chat, 'Auth email to ~p is as follows: ~a', [Email,Hash]),
        format(Out, '<h1>Hej!</h1>\n', []),
        format(Out, '<p>Klicka här för att verifiera din epost: \n <a href="http://foderkalkylatorn.se:8000/index.html?auth=~a">Verifiera!</a></p>\n', [Hash,Hash]),
        format(Out, '<p>Med vänliga hälsningar,\nElise</p>\n', []).

send_warning_message(Out) :-
		email(Email,Hash,_),
		debug(chat, 'Warning email to ~p is as follows: ~a', [Email,Hash]),
        format(Out, '<h1>Hej!</h1>\n', []),
        format(Out, '<p><a href="http://localhost:8000/?stop=~a">Klicka här för att stänga av</a></p>\n', [Hash]),
        format(Out, '<p>Med vänliga hälsningar,\nElise</p>\n', []).        
        
%****************************************************************************************
% Read events from file
%****************************************************************************************

init_events(File) :-
	retractall(event(_,_,_,_)),
	open(File, read, Stream),
	call_cleanup(load_event(Stream),
	close(Stream)).

load_event(Stream) :-
	read(Stream, T0),
	load_event(T0, Stream).

load_event(end_of_file, _) :- !.

load_event(event(Status,Startstamp,Normal,Endstamp), Stream) :- !,
	asserta(event(Status,Startstamp,Normal,Endstamp)),
	read(Stream, T2),
	load_event(T2, Stream).
	
load_event(Term, _Stream) :-
	type_error(event, Term).


%****************************************************************************************
% Read emails from file
%****************************************************************************************

init_emails(File) :-
	retractall(email(_,_,_)),
	open(File, read, Stream),
	call_cleanup(load_email(Stream),
	close(Stream)).

load_email(Stream) :-
	read(Stream, T0),
	load_email(T0, Stream).

load_email(end_of_file, _) :- !.

load_email(email(Email,Hash,Status), Stream) :- !,
	assertz(email(Email,Hash,Status)),
	read(Stream, T2),
	load_email(T2, Stream).
	
load_email(Term, _Stream) :-
	type_error(email, Term).