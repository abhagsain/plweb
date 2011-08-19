/*  Part of SWI-Prolog

    Author:        Jan Wielemaker
    E-mail:        J.Wielemaker@cs.vu.nl
    WWW:           http://www.swi-prolog.org
    Copyright (C): 2009, VU University Amsterdam

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

:- module(plweb_download, []).
:- use_module(library(http/html_write)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_path)).
:- use_module(library(http/http_parameters)).
:- use_module(library(http/dcg_basics)).
:- use_module(library(http/http_dirindex)).
:- use_module(library(broadcast)).
:- use_module(library(pairs)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(error)).
:- use_module(library(filesex)).
:- use_module(wiki).

%%	download(+Request) is det.
%
%	HTTP handler for SWI-Prolog download pages.

:- http_handler(download(devel),  download_table, []).
:- http_handler(download(stable), download_table, []).
:- http_handler(download(old),    download_table, []).
:- http_handler(download(.),	  download,
		[prefix, spawn(download), priority(10)]).

%%	download_table(+Request)
%
%	Provide a table with possible download targets.

download_table(Request) :-
	http_parameters(Request,
			[ show(Show, [oneof([all,latest]), default(latest)])
			]),
	memberchk(path(Path), Request),
	http_absolute_location(root(download), DownLoadRoot, []),
	atom_concat(DownLoadRoot, DownLoadDir, Path),
	absolute_file_name(download(DownLoadDir),
			   Dir,
			   [ file_type(directory),
			     access(read)
			   ]),
	list_downloads(Dir, [show(Show), request(Request)]).

%%	list_downloads(+Directory)

list_downloads(Dir, Options) :-
	reply_html_page(title('SWI-Prolog downloads'),
			[ \wiki(Dir, 'header.txt'),
			  div(&(nbsp)),
			  table(class(downloads),
				\download_table(Dir, Options)),
			  \wiki(Dir, 'footer.txt')
			]).

wiki(Dir, File) -->
	{ directory_file_path(Dir, File, WikiFile),
	  access_file(WikiFile, read), !,
	  wiki_file_to_dom(WikiFile, DOM)
	},
	html(DOM).
wiki(_, _) -->
	[].

download_table(Dir, Options) -->
	list_files(Dir, bin, bin,    'Binaries',         Options),
	list_files(Dir, src, src,    'Sources',          Options),
	list_files(Dir, doc, doc,    'Documentation',    Options),
	list_files(Dir, bin, pkg(_), 'Package binaries', Options),
	toggle_show(Options).

%%	toggle_show(+Options) is det.
%
%	Add a toggle to switch between   showing only the latest version
%	and all versions.

toggle_show(Options) -->
	{ option(request(Request), Options),
	  memberchk(path(Path), Request), !,
	  file_base_name(Path, MySelf),
	  (   option(show(all), Options)
	  ->  NewShow = latest
	  ;   NewShow = all
	  )
	},
	html(tr(td([class(toggle), colspan(3)],
		   a(href(MySelf+'?show='+NewShow),
		     [ 'Show ', NewShow, ' files' ])))).
toggle_show(_) -->
	[].

%%	list_files(+Dir, +SubDir, +Class, +Label, +Options) is det.
%
%	Create table rows for all  files   in  Dir/SubDir.  If files are
%	present, emit a =tr= with Label  and   a  =tr= row for each each
%	matching file.  Options are:
%
%	    * show(Show)
%	    One of =all= or =latest= (default).

list_files(Dir, SubDir, Class, Label, Options) -->
	{ directory_file_path(Dir, SubDir, Directory),
	  atom_concat(Directory, '/*', Pattern),
	  expand_file_name(Pattern, Files),
	  classify_files(Files, Class, Classified),
	  sort_files(Classified, Sorted, Options),
	  Sorted \== [], !
	},
	html(tr(th(colspan(3), Label))),
	list_files(Sorted).
list_files(_, _, _, _, _) -->
	[].

list_files([]) --> [].
list_files([H|T]) -->
	list_file(H),
	list_files(T).

list_file(File) -->
	html(tr(class(download),
		[ td(class(dl_icon), \file_icon(File)),
		  td(class(dl_size), \file_size(File)),
		  td(class(dl_file), \file_description(File))
		])).

file_icon(file(Type, PlatForm, _, _, _)) -->
	{ icon_for_file(Type, PlatForm, Icon, Alt), !,
	  http_absolute_location(icons(Icon), HREF, [])
	},
	html(img([src(HREF), alt(Alt)])).
file_icon(_) -->
	html(?).			% no defined icon

icon_for_file(bin, linux(universal),
	      'linux.png', 'Linux 32/64 intel').
icon_for_file(bin, linux(_,_),
	      'linux32.gif', 'Linux RPM').
icon_for_file(bin, macos(snow_leopard,_),
	      'snowleopard.gif', 'Snow Leopard').
icon_for_file(bin, macos(_,_),
	      'mac.gif', 'MacOSX version').
icon_for_file(_, windows(win32),
	      'win32.gif', 'Windows version (32-bits)').
icon_for_file(_, windows(win64),
	      'win64.gif', 'Windows version (64-bits)').
icon_for_file(src, _,
	      'src.gif', 'Source archive').
icon_for_file(_, pdf,
	      'pdf.gif', 'PDF file').


file_size(file(_, _, _, _, Path)) -->
	{ size_file(Path, Bytes)
	},
	html('~D bytes'-[Bytes]).

file_description(file(bin, PlatForm, Version, _, Path)) -->
	{ down_file_href(Path, HREF)
	},
	html([ a(href(HREF),
		 [ 'SWI-Prolog/XPCE ', \version(Version), ' for ',
		   \platform(PlatForm)
		 ]),
	       \platform_notes(PlatForm, Path)
	     ]).
file_description(file(src, Format, Version, _, Path)) -->
	{ down_file_href(Path, HREF)
	},
	html([ a(href(HREF),
		 [ 'SWI-Prolog source for ', \version(Version)
		 ]),
	       \platform_notes(Format, Path)
	     ]).
file_description(file(doc, Format, Version, _, Path)) -->
	{ down_file_href(Path, HREF)
	},
	html([ a(href(HREF),
		 [ 'SWI-Prolog ', \version(Version),
		   ' reference manual in PDF'
		 ]),
	       \platform_notes(Format, Path)
	     ]).
file_description(file(pkg(Pkg), PlatForm, Version, _, Path)) -->
	{ down_file_href(Path, HREF)
	},
	html([ a(href(HREF),
		 [ \package(Pkg), ' (version ', \version(Version), ') for ',
		   \platform(PlatForm)
		 ]),
	       \platform_notes(pkg(Pkg), Path)
	     ]).

package(Name) -->
	html([ 'Package ', Name ]).

version(version(Major, Minor, Patch)) -->
	html(b('~w.~w.~w'-[Major, Minor, Patch])).

down_file_href(Path, HREF) :-
	absolute_file_name(download(.),
			   Dir,
			   [ file_type(directory),
			     access(read)
			   ]),
	atom_concat(Dir, SlashLocal, Path),
	delete_leading_slash(SlashLocal, Local),
	http_absolute_location(download(Local), HREF, []).

delete_leading_slash(SlashPath, Path) :-
	atom_concat(/, Path, SlashPath), !.
delete_leading_slash(Path, Path).

platform(linux(universal)) -->
	html(['Linux 32/64 bits (TAR)']).
platform(linux(rpm, _)) -->
	html(['i586/Linux (RPM)']).
platform(macos(Name, CPU)) -->
	html(['MacOSX ', \html_macos_version(Name), ' on ', b(CPU)]).
platform(windows(win32)) -->
	html(['Windows NT/2000/XP/Vista/7']).
platform(windows(win64)) -->
	html(['Windows XP/Vista/7 64-bit edition']).

html_macos_version(tiger)        --> html('10.4 (Tiger)').
html_macos_version(leopard)      --> html('10.5 (Leopard)').
html_macos_version(snow_leopard) --> html('10.6 (Snow Leopard)').
html_macos_version(lion)	 --> html('10.7 (Lion)').
html_macos_version(OS)	         --> html(OS).

%%	platform_notes(+Platform, +Path) is det.
%
%	Include notes on the platform. These notes  are stored in a wiki
%	file in the same directory as the download file.

platform_notes(Platform, Path) -->
	{ file_directory_name(Path, Dir),
	  platform_note_file(Platform, File),
	  atomic_list_concat([Dir, /, File], NoteFile),
	  debug(download, 'Trying note-file ~q', [NoteFile]),
	  access_file(NoteFile, read), !,
	  debug(download, 'Found note-file ~q', [NoteFile]),
	  wiki_file_to_dom(NoteFile, DOM)
	},
	html(DOM).
platform_notes(_, _) -->
	[].

platform_note_file(linux(rpm,_),     'linux-rpm.txt').
platform_note_file(linux(universal), 'linux.txt').
platform_note_file(windows(win32),   'win32.txt').
platform_note_file(windows(win64),   'win64.txt').
platform_note_file(pkg(Pkg),         File) :-
	file_name_extension(Pkg, txt, File).
platform_note_file(macos(Version,_), File) :-
	atomic_list_concat([macosx, -, Version, '.txt'], File).
platform_note_file(macos(_,_),	     'macosx.txt').
platform_note_file(tgz,		     'src-tgz.txt').
platform_note_file(pdf,		     'doc-pdf.txt').


		 /*******************************
		 *	   CLASSIFY FILES	*
		 *******************************/

classify_files([], _, []).
classify_files([H0|T0], Class, [H|T]) :-
	classify_file(H0, H),
	arg(1, H, Classification),
	subsumes_term(Class, Classification), !,
	classify_files(T0, Class, T).
classify_files([_|T0], Class, T) :-
	classify_files(T0, Class, T).

%%	classify_file(+Path, -Term) is semidet.

classify_file(Path, file(Type, Platform, Version, Name, Path)) :-
	file_base_name(Path, Name),
	atom_codes(Name, Codes),
	phrase(file(Type, Platform, Version), Codes).

file(bin, macos(OSVersion, CPU), Version) -->
	"swi-prolog-", opt_devel, long_version(Version), "-",
	macos_version(OSVersion),
	(   "-",
	    macos_cpu(CPU)
	->  ""
	;   { macos_def_cpu(OSVersion, CPU) }
	),
	".mpkg.zip", !.
file(bin, windows(WinType), Version) -->
	win_type(WinType), "pl",
	short_version(Version),
	".exe", !.
file(pkg(space), windows(WinType), Version) -->
	win_type(WinType), "swispace",
	short_version(Version),
	".exe", !.
file(bin, linux(rpm, suse), Version) -->
	(   "pl-"
	;   "swipl-"
	),
	long_version(Version), "-", digits(_Build),
	".i586.rpm", !.
file(bin, linux(universal), Version) -->
	"swipl-",
	long_version(Version), "-", "linux",
	".tar.gz", !.
file(src, tgz, Version) -->
	"pl-", long_version(Version), ".tar.gz", !.
file(doc, pdf, Version) -->
	"SWI-Prolog-", long_version(Version), ".pdf", !.

opt_devel -->
	"devel-", !.
opt_devel -->
	"".

macos_version(tiger)        --> "tiger".
macos_version(leopard)      --> "leopard".
macos_version(snow_leopard) --> "snow-leopard".
macos_version(lion)         --> "lion".

macos_cpu(ppc)   --> "powerpc".
macos_cpu(intel) --> "intel".
macos_cpu(x86)   --> "32bit".

macos_def_cpu(snow_leopard, intel) :- !.
macos_def_cpu(_, ppc).

win_type(win32) --> "w32".
win_type(win64) --> "w64".

long_version(version(Major, Minor, Patch)) -->
	int(Major, 1), ".", int(Minor, 2), ".", int(Patch, 2), !.

int(Value, MaxDigits) -->
	digits(Digits),
	{ length(Digits, Len),
	  Len =< MaxDigits,
	  number_codes(Value, Digits)
	}.

short_version(version(Major, Minor, Patch)) -->
	digits(Digits),
	{   Digits = [D1,D2,D3]
	->  number_codes(Major, [D1]),
	    number_codes(Minor, [D2]),
	    number_codes(Patch, [D3])
	;   Digits = [D1,D2,D3,D4]
	->  (   D2 == 0'1		% 5.1X.Y
	    ->  number_codes(Major, [D1]),
	        number_codes(Minor, [D2,D3]),
		number_codes(Patch, [D4])
	    ;   number_codes(Major, [D1]),
	        number_codes(Minor, [D2]),
		number_codes(Patch, [D3,D4])
	    )
	;   Digits = [D1,D2,D3,D4,D5]
	->  number_codes(Major, [D1]),
	    number_codes(Minor, [D2,D3]),
	    number_codes(Patch, [D4,D5])
	}.

%%	sort_files(+In, -Out, +Options)
%
%	Sort files by type and version. Type: linux, windows, mac, src,
%	doc.  Versions: latest first.
%
%	Options:
%
%	    * show(Show)
%	    One of =all= or =latest=.

sort_files(In, Out, Options) :-
	map_list_to_pairs(map_type, In, Typed0),
	(   option(show(all), Options)
	->  Typed = Typed0
	;   exclude(old_tagged_file, Typed0, Typed)
	),
	keysort(Typed, TSorted),
	group_pairs_by_key(TSorted, TGrouped),
	maplist(sort_group_by_version, TGrouped, TGroupSorted),
	(   option(show(all), Options)
	->  pairs_values(TGroupSorted, TValues),
	    flatten(TValues, Out)
	;   take_latest(TGroupSorted, Out)
	).

map_type(File, Tag) :-
	File = file(Type, Platform, _Version, _Name, _Path),
	type_tag(Type, Platform, Tag).

type_tag(bin, linux(A),   tag(10, linux(A))) :- !.
type_tag(bin, linux(A,B), tag(11, linux(A,B))) :- !.
type_tag(bin, windows(A), tag(20, windows(A))) :- !.
type_tag(bin, macos(A,B), tag(Tg, macos(A,B))) :- !,
	mac_tag(A, Tg2),
	Tg is 30+Tg2.
type_tag(src, Format,     tag(40, Format)) :- !.
type_tag(doc, Format,     tag(50, Format)) :- !.
type_tag(X,   Y,	  tag(60, X-Y)).

mac_tag(snow_leopard, 7).
mac_tag(leopard,      8).
mac_tag(tiger,        9).

sort_group_by_version(Tag-Files, Tag-Sorted) :-
	map_list_to_pairs(tag_version, Files, TFiles),
	keysort(TFiles, TRevSorted),
	pairs_values(TRevSorted, RevSorted),
	reverse(RevSorted, Sorted).

tag_version(File, Version) :-
	File = file(_,_,Version,_,_).

take_latest([], []).
take_latest([_-[H|_]|T0], [H|T]) :- !,
	take_latest(T0, T).
take_latest([_-[]|T0], T) :- !,		% emty set
	take_latest(T0, T).

%%	old_tagged_file(+TypeFile) is semidet.

old_tagged_file(tag(_,Type)-_File) :-
	old_file_type(Type).

old_file_type(linux(_)).
old_file_type(linux(_,_)).
old_file_type(macos(_,ppc)).
old_file_type(macos(tiger,_)).


		 /*******************************
		 *	     DOWNLOAD		*
		 *******************************/

%%	download(+Request) is det.
%
%	Actually download a file.

download(Request) :-
	memberchk(path_info(Download), Request),
	absolute_file_name(download(Download),
			   AbsFile,
			   [ access(read),
			     file_errors(fail)
			   ]), !,
	(   exists_directory(AbsFile)
	->  http_reply_dirindex(AbsFile, [unsafe(true)], Request)
	;   remote_ip(Request, Remote),
	    broadcast(download(Download, Remote)),
	    http_reply_file(AbsFile, [unsafe(true)], Request)
	).
download(Request) :-
	memberchk(path(Path), Request),
	existence_error(http_location, Path).

remote_ip(Request, IP) :-
	memberchk(x_forwarded_for(IP), Request), !.
remote_ip(Request, IP) :-
	memberchk(peer(IPTerm), Request), !,
	ip_term_to_atom(IPTerm, IP).
remote_ip(_, '0.0.0.0').

ip_term_to_atom(ip(A,B,C,D), Atom) :- !,
	format(atom(Atom), '~w.~w.~w.~w', [A,B,C,D]).
ip_term_to_atom(Term, Atom) :-
	term_to_atom(Term, Atom).
