/*  Part of SWI-Prolog

    Author:        Jan Wielemaker
    E-mail:        J.Wielemaker@cs.vu.nl
    WWW:           http://www.swi-prolog.org
    Copyright (C): 2011, VU University Amsterdam

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    as published by the Free Software Foundation; either version 2
    of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

    As a special exception, if you link this library with other files,
    compiled with a Free Software compiler, to produce an executable, this
    library does not by itself cause the resulting executable to be covered
    by the GNU General Public License. This exception does not however
    invalidate any other reasons why the executable file might be covered by
    the GNU General Public License.
*/

:- module(wiki_edit,
	  [
	  ]).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_parameters)).
:- use_module(library(http/html_write)).

/** <module> Edit PlDoc wiki pages


*/

:- http_handler(root(wiki_edit), wiki_edit, []).
:- http_handler(root(wiki_save), wiki_save, []).

%%	edit_button(+Location)//
%
%	Present a button for editing the web-page

:- public edit_button//1.
:- multifile edit_button//1.

edit_button(Location) -->
	{ http_link_to_id(wiki_edit, [location(Location)], HREF) },
	html(a(href(HREF),
	       img([ class(action),
		     alt(edit),
		     title('Edit wiki page'),
		     src(location_by_id(pldoc_resource)+'edit.gif')
		   ]))).


		 /*******************************
		 *	       SHOW		*
		 *******************************/

%%	wiki_edit(+Request)
%
%	HTTP handler that deals with editing a wiki page.

wiki_edit(Request) :-
	http_parameters(Request,
			[ location(Location,
				   [ description('Wiki location to edit')
				   ])
			]),
	location_wiki_file(Location, File),
	allowed_file(File),
	file_base_name(File, BaseName),
	reply_html_page(wiki,
			title('Edit ~w'-[BaseName]),
			\edit_page(Location, File)).

edit_page(Location, File) -->
	{ (   exists_file(File)
	  ->  read_file_to_codes(File, Codes, []),
	      string_to_list(Content, Codes),
	      Title = 'Edit'
	  ;   Content = '',
	      Title = 'Create'
	  ),
	  http_location_by_id(wiki_save, Action)
	},
	html(div(class(wiki_edit),
		 [ h1(class(wiki), [Title, ' ', Location]),
		   form(action(Action),
			[ \hidden(location, Location),
			  table([ tr(td(textarea([ cols(80),rows(20),name(text) ],
						 Content))),
				  tr(td(align(right),
					input([type(submit), value(save)])))
				])
			])
		 ])).


		 /*******************************
		 *	       SAVE		*
		 *******************************/

%%	wiki_save(+Request)
%
%	HTTP handler that saves a new or modified wiki page.

wiki_save(Request) :-
	http_parameters(Request,
			[ location(Location,
				   [ description('Path of the file to edit')
				   ]),
			  text(Text,
			       [ description('Wiki content for the file')
			       ])
			]),
	location_wiki_file(Location, File),
	allowed_file(File),
	save_file(File, Text),
	http_redirect(see_other, Location, Request).


		 /*******************************
		 *	       UTIL		*
		 *******************************/

%%	location_wiki_file(+Location, -Path)
%
%	@see find_file in plweb.pl

location_wiki_file(Relative, File) :-
	file_name_extension(Base, html, Relative),
	file_name_extension(Base, txt, WikiFile),
	absolute_file_name(document_root(WikiFile),
			   File,
			   [ access(write),
			     file_errors(fail)
			   ]), !.
location_wiki_file(Relative, File) :-
	file_name_extension(_, txt, Relative),
	absolute_file_name(document_root(Relative),
			   File,
			   [ access(write),
			     file_errors(fail)
			   ]).

%%	save_file(+File, +Text)
%
%	Modify the file.

save_file(File, Text) :-
	setup_call_cleanup(open(File, write, Out,
				[ encoding(utf8)
				]),
			   write(Out, Text),
			   close(Out)).


%%	allowed_file(+File) is semidet.

allowed_file(_).

hidden(Name, Value) -->
	html(input([type(hidden), name(Name), value(Value)])).
