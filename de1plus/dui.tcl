# ##### TEMPORAL DEV COMMENTS ####
# source "D:/Enrique/OneDrive/Documentos/Personal/Leisure/Coffee/Decent/de1plus_git/de1app/de1plus/logging.tcl"
# source "D:/Enrique/OneDrive/Documentos/Personal/Leisure/Coffee/Decent/de1plus_git/de1app/de1plus/utils.tcl"
# source "D:/Enrique/OneDrive/Documentos/Personal/Leisure/Coffee/Decent/de1plus_git/de1app/de1plus/updater.tcl"
# source "D:/Enrique/OneDrive/Documentos/Personal/Leisure/Coffee/Decent/de1plus_git/de1app/de1plus/dui.tcl"
# THINGS THIS DOES:
#	- Remove duplication & hardcoded values
#	- Consistent API instead of scattered functions
#	- Set default aspect values by theme. User only has to defined options that differ from the default.
#		Also allow to define item styles within a theme, so all style options are applied to those items that 
#		have that -style.
#	- Allow users to define the name/tag of canvas items and widgets, so they can be easily retrieved.
#	- Fontawesome symbols by name
#	- Add "widget combos" as a unit with a single command (e.g. button+label+clickable_button, or 
#		listbox+label+scrollbar) and operate with them as a unit too for showing/hiding, enabling/disabling, etc.
#		Avoid having to manually configure scrollbars and the like on page show.
#	- Pages as namespaces. A default "page container parent namespace" is offered (::dui::pages::<page_name>), but any
#		namespace can be used through the '-namespace' option of 'dui page add', or even a single namespace for 
#		several pages.
#	- Pages load/show/hide events, can be added directly with 'dui page add_action' or through page namespace 
#		standard procs with the same names.
#	- Allow to pass arguments to pages, so they can be loaded/started/shown with a set of parameters. This allows 
#		more easily apply the same page to different data/object, as the data reference to be used can be passed
#		as a parameter (instead of always using global variables).
#	- Map all coordinates and dimensions in pixels to the current resolution (before widths and the like were not 
#		mapped, only the positions)
#
# IMPORTANT DESIGN CONSIDERATION:
#	- In this package we're building item/widget compound bundles in a very simple way.  
#		Several options were studied, like overloading megawidgets (see https://wiki.tcl-lang.org/page/Overloading+widgets),
#		but that seemed to add unneeded complexity vs the simple design here, which is relativelly easy to follow.
#
# TODOs: CHANGES TO DECOUPLE THIS LAYER AS A TOTALLY INDEPENDENT COMPONENT
#	- Global variables that must change to the dui namespace variables:
#		::de1(current_context) -> ::dui::page::current_page
#		::existing_labels array (one item per page)
#		::all_labels (list with all labels, sorted) Can't this be get from the canvas tags???)
#		screensaver integrated in the dui or not? -> An action on the "saver" page can make it work
#		Idle/stress test in page display_change ?? -> Add a way to add before_show/after_show/hide actions
#		::delayed_image_load system
#		::screen_size_width and ::screen_size_height
#
#	- Global utility functions that are used here:
#		ifexists
#		$::fontm, $::globals(entry_length_multiplier)
#		$::android, $::undroid

package provide de1_dui 1.0

package require de1_logging 1.0
package require de1_updater 1.1
package require de1_utils 1.1
package require Tk
package require tksvg
catch {
	# tkblt has replaced BLT in current TK distributions, not on Androwish, they still use BLT and it is preloaded
	package require tkblt
	namespace import blt::*
}


namespace eval ::dui {
	namespace export init setup_ui canvas theme aspect symbol font page item add hide_android_keyboard
	namespace ensemble create

	# Set to 1 while debugging to see the "clickable" areas. Also may need to redefine aspect 
	#	'<theme>.button.debug_outline' so it's visible against the theme background.
	variable debug_buttons 0
	
	# Set to 1 to default to create a namespace ::dui::page::<page_name> for each new created page
 
	variable create_page_namespaces 0
	# Set to 1 to trim leading and trailing whitespace when modifying the value in entry boxes 
	variable trim_entries 0
	# Set to 1 to default to use editor pages if available 
	variable use_editor_pages 1
	
	### THEME SUB-ENSEMBLE ###
	# Themes are just names that serve as groupings for sets of aspect variables. They define a "visual identity"
	#	by setting default option values for widgets (colors, fonts, backgrounds, etc.), which are called "aspects"
	#	in this framework.
	namespace eval theme {
		namespace export add get set exists list
		namespace ensemble create
		
		variable themes { default }
		variable current default
		
		proc add { args } {
			variable themes
			foreach theme $args {
				if { [lsearch $themes $theme] == -1 } {
					lappend themes $theme
				} else {
					msg -NOTICE [namespace current] "theme '$theme' already in the list of available themes"
				}
			}
			return $themes
		}

		# Returns the current active theme
		proc get {} {
			variable current
			return $current
		}
		
		# Changes the current active theme, adding it to the list if it doesn't exist (with a NOTICE on the log).
		proc set { {theme {}} } {
			variable current
			if { ![exists $theme] } {
				msg -NOTICE [namespace current] "current theme '$theme' not previously added"
				add $theme
			}
			::set current $theme
		}
		
		proc exists { theme } {
			variable themes
			return [expr { [lsearch $themes $theme] > -1 } ]
		}
		
		proc list {} {
			variable themes
			return $themes
		}
	}
	
	### ASPECT SUB-ENSEMBLE ###
	# Aspects are the variables that define the default options for each item/widget in a theme.
	# They are stored with labels that use the syntax "<theme>.<widget/type>.<option>?.<style>?".
	# The theme is always specified globally using 'dui theme current <theme_name>', and cannot be modified for 
	#	individual items/widgets.
	# Whenever an item/widget is added to the canvas using the 'dui add *' commands, its default options are
	#	taken from the theme aspects, unless they are overridden explicitly in the 'add *' call.
	# Different styles can be added to any item/widget type, by adding aspects with a ".<style>" suffix.
	# If the 'add *' call includes a -style option, each default aspect option will be taken from the style. If that
	#	option is not available for the style, the non-style option version will be used. 
	# If an aspect is not defined for the current theme, the aspect from the 'default' theme will be used,
	#	or a default can be provided directly by client code using the -default tag of the 'dui aspect get' command.  
	namespace eval aspect {
		namespace export set get exists list
		namespace ensemble create
		
		variable aspects
		# TBD default.button_label.activefill needed? On buttons the invisible rectangle "hides" the text and
		#	it seems they never become active.
		# $::helvetica_font
		
		#default.button_label.font_family notosansuiregular
		#default.page.bg_color "#edecfa"
#		default.listbox.highlightthickness 1
#		default.listbox.highlightcolor orange
#		default.listbox.foreground "#7f879a"
#		default.symbol.font_family "Font Awesome 5 Pro-Regular-400"
		array set aspects {
			default.page.bg_img {}
			default.page.bg_color "#d7d9e6"
			
			default.font.font_family notosansuiregular
			default.font.font_size 16
			
			default.text.font_family notosansuiregular
			default.text.font_size 16
			default.text.fill "#7f879a"
			default.text.disabledfill "#ddd"
			default.text.anchor nw
			default.text.justify left
			
			default.text.fill.remark "#4e85f4"
			default.text.fill.error red
			default.text.font_family.section_title notosansuibold
			
			default.text.font_family.page_title notosansuibold
			default.text.font_size.page_title 26
			default.text.fill.page_title "#35363d"
			default.text.anchor.page_title center
			default.text.justify.page_title center
						
			default.symbol.font_family "Font Awesome 5 Pro-Regular-400"
			default.symbol.font_size 16
			default.symbol.fill "#7f879a"
			default.symbol.disabledfill "#ddd"
			default.symbol.anchor nw
			default.symbol.justify left
			
			default.entry.relief flat
			default.entry.bg white
			
			default.button.debug_outline black
			default.button.fill "#c0c5e3"
			default.button.disabledfill "#ddd"
			default.button.outline white
			default.button.disabledoutline "pink"
			default.button.activeoutline "orange"
			default.button.width 0
			
			default.button_label.pos {0.5 0.5}
			default.button_label.anchor center
			default.button_label.font_size 18
			default.button_label.justify center
			default.button_label.fill white
			default.button_label.disabledfill "#ccc"

			default.button_symbol.pos {0.2 0.5}
			default.button_symbol.font_size 24
			default.button_symbol.anchor center
			default.button_symbol.justify center
			default.button_symbol.fill white
			default.button_symbol.disabledfill "#ccc"

			default.button_state.pos {0.5 0.5}
			default.button_state.anchor center
			default.button_state.justify center
			default.button_state.fill "#ffffff"
			default.button_state.activefill "#ffffff"
			default.button_state.disabledfill black
			
			default.button.shape.insight_ok round
			default.button.radius.insight_ok 30
			default.button.bwidth.insight_ok 480
			default.button.bheight.insight_ok 118
			default.button_label.font_family.insight_ok notosansuibold
			default.button_label.font_size.insight_ok 19
			
			default.entry.relief flat
			default.entry.bg white
			default.entry.width 2
			default.entry.font_family notosansuiregular
			default.entry.font_size 16
			
			default.entry.relief.special flat
			default.entry.bg.special yellow
			default.entry.width.special 1
			
			default.checkbox.font_family "Font Awesome 5 Pro-Regular-400"
			default.checkbox.font_size 18
			default.checkbox.fill black
			default.checkbox.anchor nw
			default.checkbox.justify left
			
			default.checkbox_label.pos "e 80 0"
			default.checkbox_label.anchor w
			default.checkbox_label.justify left
			
			default.listbox.relief flat
			default.listbox.borderwidth 0
			default.listbox.foreground "#7f879a"
			default.listbox.background white
			default.listbox.selectforeground white
			default.listbox.selectbackground black
			default.listbox.selectborderwidth 0
			default.listbox.disabledforeground "#cccccc"
			default.listbox.selectbackground "#cccccc"
			default.listbox.selectmode browser
			default.listbox.justify left

			default.listbox_label.pos "wn -10 0"
			default.listbox_label.anchor ne
			default.listbox_label.justify right
			
			default.listbox_label.font_family.section_title notosansuibold
			
			default.scrollbar.width 50
			default.scrollbar.length 75
			default.scrollbar.sliderlength 75
			default.scrollbar.from 0.0
			default.scrollbar.to 1.0
			default.scrollbar.bigincrement 0.2
			default.scrollbar.borderwidth 1
			default.scrollbar.showvalue 0
			default.scrollbar.resolution 0.01
			default.scrollbar.background "#d3dbf3"
			default.scrollbar.foreground "#FFFFFF"
			default.scrollbar.troughcolor "#f7f6fa"
			default.scrollbar.relief flat
			default.scrollbar.borderwidth 0
			default.scrollbar.highlightthickness 0
	
			default.dscale.foreground "#4e85f4"
			default.dscale.background "#7f879a"
			
			default.rect.fill.insight_back_box "#ededfa"
			default.rect.width.insight_back_box 0
			default.line.fill.insight_back_box_shadow "#c7c9d5"
			default.line.width.insight_back_box_shadow 2
			default.rect.fill.insight_front_box white
			default.rect.width.insight_front_box 0
		}
		#default.button.disabledfill "#ddd"
		#default.button.radius 40 -- only include if the button style has shape=round
		#default.button.arc_offset 50 -- only include if the button style has shape=outline
				
		# Named options:
		# 	-theme theme_name: to add to a theme different than the current one.
		#	-type type_name: adds this type for all added aspects.
		# 	-style style_name: adds this style for all added aspects.
		# value-pairs can be passed directly in the args, or as a single-argument list.
		proc set { args } {
			variable aspects
			::set theme [dui::args::get_option -theme [dui theme get] 1]
			::set type [dui::args::get_option -type "" 1]
			::set style [dui::args::get_option -style "" 1]
			::set prefix "$theme."
			if { $type ne "" } {
				append prefix "$type."
			}
			::set suffix ""
			if { $style ne "" } {
				::set suffix ".$style"
			}
			
			if { [llength $args] == 1 } {
				::set args [lindex $args 0]
			}
			for { ::set i 0 } { $i < [llength $args] } { incr i 2 } {
				::set var "$prefix[lindex $args $i]$suffix"
#				if { $style ne "" && [string range $var end-[string length $style] end] ne ".$style" } {
#					append var ".$style"
#				}
				::set value [lindex $args [expr {$i+1}]]
				if { [info exists aspects($var)] } {
					if { $aspects($var) eq $value } {
						msg -NOTICE [namespace current] "aspect '$var' already exists, new value is equal to old"
					} else {
						msg -NOTICE [namespace current] "aspect '$var' already exists, old value='$aspects($var)', new value='$value'"
					}
				}
				::set aspects($var) $value
			}
		}
		
		# Named options:
		# 	-theme theme_name to get for a theme different than the current one
		#	-style style_name to get only that style. If the aspect is not found in that style, the non-styled
		#		value of the aspect is returned instead, if available
		#	-default value to return in case the aspect is undefined
		#	-default_type to search the same aspect in this type, in case it's not defined for the requested type
		proc get { type aspect args } {
			variable aspects
			::set theme [dui::args::get_option -theme [dui theme get]]
			::set style [dui::args::get_option -style ""]			
			::set default [dui::args::get_option -default ""]
			::set default_type [dui::args::get_option -default_type ""]
			
			if { $style ne "" && [info exists aspects($theme.$type.$aspect.$style)] } {
				return $aspects($theme.$type.$aspect.$style)
			} elseif { [info exists aspects($theme.$type.$aspect)] } {
				return $aspects($theme.$type.$aspect)
			} elseif { $default ne "" } {
				return $default
			} elseif { $default_type ne "" && $default_type ne $type } {
				return [get $default_type $aspect -theme $theme -style $style]
			} elseif { [string range $aspect 0 4] eq "font_" && [info exists aspects($theme.font.$aspect)] } {
				return $aspects($theme.font.$aspect)
			} elseif { $theme ne "default" } {
				return [get $default_type $aspect -theme default -style $style]
			} else {
				msg -NOTICE [namespace current] "aspect '$theme.$aspect' not found and no alternative available"
				return ""
			}
		}
		
		# Named options:
		#	-theme theme_name to check for a theme different than the current one
		#	-style style_name to query only that style
		proc exists { type aspect args } {
			variable aspects
			::set theme [dui::args::get_option -theme [dui theme get]]
			::set style [dui::args::get_option -style ""]
			::set aspect_name "$theme.$type.$aspect"
			if { $style ne "" } {
				append aspect_name .$style
			}
			return [info exists aspects($aspect_name)]
		}
				
		# Returns the defined aspect names according to the request parameters.
		# Named options:
		# 	-theme theme_name to return for a theme different than the current one. If not specified and -all_themes=0
		#		(the default), returns aspects for the currently active theme only.
		#	-type to return only the aspects for that type (e.g. "entry", "text", etc.)
		# 	-style to return only the aspects for that style 
		#	-values if 1, returns {<aspect name> <aspect value>} pairs. Defaults to 0 for returning only the aspect names.
		# If the returned values are for a single theme, the theme name prefix is not included, but if -all_themes is 1,
		#	returns the full aspect name including the theme prefix.
		proc list { args } {
			variable aspects
			::set theme [dui::args::get_option -theme [dui theme get]]
			::set pattern "^${theme}\\."
			
			::set type [dui::args::get_option -type ""]
			if { $type eq "" } {
				append pattern "\[0-9a-zA-Z_\]+\\."
			} elseif { [llength $type] == 1 } {
				append pattern "${type}\\."
			} else {
				append pattern "(?:[join $type |])\\."
			}
			
			::set style [dui::args::get_option -style ""]
			if { $style eq "" } {
				append pattern "\[0-9a-zA-Z_\]+\$"
			} else {
				# Return aspects with the requested style AND with no style
				append pattern "\[0-9a-zA-Z_\]+(\\.${style})?\$"
			}
			
			#msg [namespace current] list "pattern='$pattern'"
			::set values [string is true [dui::args::get_option -values 0]]
			
			::set result {}			
			foreach full_aspect [array names aspects -regexp $pattern] {
				::set aspect_parts [split $full_aspect .]
				::set aspect [lindex $aspect_parts 2]
				if { $aspect ne "" } {
					lappend result $aspect
				}
				if { $values == 1 } {
					lappend result $aspects($full_aspect)
				}
			}
			
			if { $values != 1 && ([llength $type] > 1 || $style ne "") } {
				return [unique_list $result]
			} else {
				return $result
			}
		}
	}	
	
	### SYMBOL SUB-ENSEMBLE ###
	# This set of commands allow defining Fontawesome Regular symbols by name, then use them in the code by their name.
	# To find out the unicode values of the available symbols, see https://fontawesome.com/icons?d=gallery
	namespace eval symbol {
		namespace export set get exists list
		namespace ensemble create
				
		variable font_filename "Font Awesome 5 Pro-Regular-400"
		
		variable symbols
		array set symbols {
			square "\uf0c8"
			square_check "\uf14a"
			sort_down "\uf0dd"
			star "\uf005"
			half_star "\uf089"
			chevron_left "\uf053"
			chevron_double_left "\uf323"
			arrow_to_left "\uf33e"
			chevron_right "\uf054"
			chevron_double_right "\uf324"
			arrow_to_right "\uf340"
			eraser "\uf12d"
			eye "\uf06e"
		}

		# Used to map booleans to their checkbox representation (square/square_check) in fontawesome.
		variable checkbox_symbols_map {"\uf0c8" "\uf14a"}

		# Define Fontawesome symbols by name. If a symbol name is already defined and the value differs, it is NOT 
		#	redefined, and a warning added to the log.
		# value-pairs can be passed directly in the args, or as a single-argument list.
		proc set { args } {
			variable symbols
			
			::set n [expr {[llength $args]-1}]
			if { $n == 0 } {
				::set args [lindex $args 0]
				::set n [expr {[llength $args]-1}]
			}
			for { ::set i 0 } { $i < $n } { incr i 2 } {
				::set sn [lindex $args $i]
				::set sv [lindex $args [expr {$i+1}]]
				::set idx [lsearch [array names symbols] $sn]
				if { $idx == -1 } {
					msg -INFO [namespace current] "add symbol $sn='$sv'"
					::set symbols($sn) $sv
				} elseif { $symbols($sn) ne $sv } {
					msg -WARN [namespace current ] "symbol '$sn' already defined with a different value"
				}
			}
		}
		
		# If undefined, warns in the log and returns the provided symbol name.
		proc get { symbol } {
			variable symbols
			if { [info exists symbols($symbol)] } {
				return $symbols($symbol)
			} else {
				msg -WARN [namespace current] "symbol '$symbol' not recognized"
				return $symbol
			}
		}
			
		proc exists { symbol } {
			variable symbols
			return [info exists symbols($symbol)]
		}
		
		proc list {} {
			variable symbols
			return [array names symbols]
		}
	}

	### FONTS SUB-ENSEMBLE ###
	namespace eval font {
		namespace export add_dirs dirs load get width list
		namespace ensemble create

		# A list of paths where to look for font files
		variable font_dirs {}
		# A list with loaded family_name-font_filename pairs. Remembers which fonts have been added with 'sdltk addfont' 
		variable loaded_fonts {}
		# A list with each loaded & created font (each font identified by family+size+options)
		# TBD Why this needed? Just use 'font names'
		variable skin_fonts {}
		
		proc add_dirs { args } {
			variable font_dirs
			if { [llength $args] == 1 } {
				set args [lindex $args 0]
			}
			
			foreach dir $args {
				if { [file isdirectory $dir] } {
					if { $dir in $font_dirs } {
						msg -NOTICE [namespace current] "font directory '$dir' was already in the list"
					} else {
						lappend font_dirs $dir
					}
				} else {
					msg -ERROR [namespace current] "font directory '$dir' not found"
				}
			}
		}
		
		proc dirs {} {
			variable font_dirs
			return $font_dirs
		}
		
		# Returns the font family name corresponding to the font filename. If it's not yet added and 'add_if_needed=1'
		#	(the default), loads the font family. 
		# filename can take several forms:
		#	- A full path, with or without extension. If no extension is provided, both .otf and .ttf are tried.
		#	- A basename, with or without extension. Searches sequentially in each of the font_dirs folders until a 
		#		match is found, trying both .otf and .ttf extensions if the basename has no extension.
		#	- A font family name. In this case, the same family name is returned if the family name is loaded. 
		proc add_or_get_familyname { filename {add_if_needed 1} } {
			variable loaded_fonts
			variable font_dirs
			set familyname ""
			
			set fontindex [lsearch $loaded_fonts $filename]
			if {$fontindex != -1} {
				if { $fontindex % 2 == 1 } {
					set familyname $filename
				} else {
					set familyname [lindex $loaded_fonts [expr $fontindex + 1]]
				}
			} elseif {($::android == 1 || $::undroid == 1) && $filename != "" && [string is true $add_if_needed] } {
				set file_found 0
				if { [file dirname $filename] eq "." } {
					set ndirs [llength $font_dirs]
					for { set i 0 } { $i < $ndirs && !$file_found } { incr i } {
						set dir [lindex $font_dirs $i]
						if { [file extension $filename] ne "" && [file exists "$dir/$filename"] } {
							set filename "$dir/$filename"
							set file_found 1
						} elseif { [file exists "$dir/$filename.otf"] } {
							#load $font_key "$dir/$font_name.otf" $size "" {*}$args
							#lappend skin_fonts $font_key
							set filename  "$dir/$filename.otf"
							set file_found 1
						} elseif { [file exists "$dir/$filename.ttf"] } {
#							load $font_key "$dir/$font_name.ttf" $size "" {*}$args
#							lappend skin_fonts $font_key
							set filename  "$dir/$filename.ttf"
							set file_found 1
						}
					}
				} else {
					if { [file extension $filename] ne "" && [file exists $filename] } {
						set file_found 1
					} elseif { [file exists "$filename.otf"] } {
						set filename  "$filename.otf"
						set file_found 1
					} elseif { [file exists "$filename.ttf"] } {
						set filename  "$filename.ttf"
						set file_found 1
					}					
				}
				
				if { $file_found } {
					set fontindex [lsearch $loaded_fonts $filename]
					if { $fontindex != -1 } {
						set familyname [lindex $loaded_fonts [expr $fontindex + 1]]
					} else {
						try {
							foreach familyname [sdltk addfont $filename] {
								lappend loaded_fonts $filename $familyname
							}
						} on error err {
							msg -ERROR [namespace current] load "unable to get familyname from 'sdltk addfont $filename', or font already added: $err"
						}
					}
				} else {
					msg -WARN [namespace current] "can't find font file '$filename'"
				}
			}
			return $familyname
		}
		
		proc key { family_name size args } {
			array set opts $args
			
			set font_key "\"$family_name\" $size"
			if { [array size opts] > 0 } {
				set suffix ""
				if { [info exists opts(-weight)] && $opts(-weight) eq "bold" } {
					append suffix "b"
				} else {
					append suffix "n"
				}
				
				if { [info exists opts(-slant)] && $opts(-slant) eq "italic" } {
					append suffix "i"
				} else {
					append suffix "r"
				}
				
				if { [info exists opts(-underline)] && [string is true $opts(-underline)] } {
					append suffix "1"
				} else {
					append suffix "0"
				}
				
				if { [info exists opts(-overstrike)] && [string is true $opts(-overstrike)] } {
					append suffix "1"
				} else {
					append suffix "0"
				}
				
				if { $suffix ne "nr00" } {
					append font_key " $suffix"
				}
			}
			
			return $font_key
		}
		
		# Based on Barney's load_font: 
		#	https://3.basecamp.com/3671212/buckets/7351439/documents/2208672342#__recording_2349428596
		# args options are passed-through to 'font create', so they may include:
		#	-weight "normal" (default) or "bold"
		#	-slant "roman" (default) or "italic"
		#	-underline false (default) or true
		#	-overstrike false (default) or true
		proc load { filename pcsize {androidsize {}} args } {
			#variable skin_fonts
			array set opts $args

			# calculate font size 
			# TODO: INCORPORATE STUFF FROM utils.tcl - proc setup_environment
			if {($::android == 1 || $::undroid == 1) && $androidsize != ""} {
				set pcsize $androidsize
			}
			set platform_font_size [expr {int(1.0 * $::fontm * $pcsize)}]
		
			# Load or get the already-loaded font family name.
			set familyname [add_or_get_familyname $filename]
			if { $familyname eq "" } {
				msg -NOTICE [namespace current] load: "font familyname not available; using filename '$filename'"
				set familyname $filename
			}
			
			set key [key $familyname $platform_font_size {*}$args]
			if { $key in [::font names] } {
				msg -NOTICE [namespace current] "font with key '$key' is already loaded"
			} else {
				# Create the named font instance
				try {
					font create $key -family $familyname -size $platform_font_size {*}$args
					msg -INFO [namespace current] "load font key: \"$key\", family: \"$familyname\",\
size: $platform_font_size, filename: \"$filename\", options: $args"
				} on error err {
					msg -ERROR [namespace current] "unable to create font with key '$key': $err"
				}
			}
			return $key
		}
		
		
		# Based on Barney's get_font wrapper: 
		#	https://3.basecamp.com/3671212/buckets/7351439/documents/2208672342#__recording_2349428596
		# "I created a wrapper function that you might be interested in adopting. It makes working with fonts even simpler 
		#	by removing the need to pre-load fonts before using them."
		# family_name can also be a font filename (with or without path and/or extension), then it will be auto-loaded
		#	first.
		proc get { family_name size args } {
			#variable skin_fonts
			#variable font_dirs			
			set family_name [add_or_get_familyname $family_name]
			set font_key [key $family_name $size {*}$args]
			if { $font_key ni [::font names] } {
				set font_key [load $family_name $size "" {*}$args]
			}
		
			return $font_key
		}
		
		
		proc width {untranslated_txt font} {
			set x [font measure $font -displayof [dui canvas] [translate $untranslated_txt]]
			#if {$::android != 1} {    
				# not sure why font measurements are half off on osx but not on android
				return [expr {2 * $x}]
			#}
			#return $x
		}

		proc list { {loaded 0} } {
			if { [string is true $loaded] } {
				variable loaded_fonts
				return $loaded_fonts
			} else {
#				variable skin_fonts
#				return $skin_fonts
				return [::font names]
			}
		}
			
		# Returns the current fonts directory (if path is not specified) or sets it to path. 
#		proc dir { {font_path {}} } {
#			variable dir
#			if { $font_path eq "" } {
#				return $dir
#			} else {
#				set dir $font_path
#				if { ![file isdirectory $font_path] } {
#					msg -ERROR [namespace current] "dir" "'$font_path' is not a valid path"
#				}
#			}
#		}
	}
	
	### ARGS SUB-ENSEMBLE ###
	# A set of tools to manipulate named options in the 'args' argument to dui commands. 
	# These are heavily used in the 'add' commands that create widgets, with the general objectives of:
	#	1) pass-through any aspect parameter explicitly defined by the user to the main widget creation command,
	#		or otherwise use the theme and style default values. 	
	#	2) extract the options that won't be passed through to the main widget creation command, but to other one,
	#		like aspect values passed to the label creation command in 'add button' (-label_font, -label_fill...)
	# These namespace commands are not exported, should normally only be used inside the dui namespace, where
	#	they're called using qualified names.
	namespace eval args {
		variable item_cnt 0
				
		# Adds a named option "-option_name option_value" to a named argument list if the option doesn't exist in the list.
		# Returns the option value.
		proc add_option_if_not_exists { option_name option_value {args_name args} } {
			upvar $args_name largs	
			if { [string range $option_name 0 0] ne "-" } { set option_name "-$option_name" }
			set opt_idx [lsearch $largs $option_name]
			if {  $opt_idx == -1 } {
				lappend largs $option_name $option_value
			} else {
				set option_value [lindex $largs [expr {$opt_idx+1}]]
			}
			return $option_value
		}
		
		# Removes the named option "-option_name" from the named argument list, if it exists.
		proc remove_option { option_name {args_name args} } {
			upvar $args_name largs
			if { [string range $option_name 0 0] ne "-" } { set option_name "-$option_name" }	
			set option_idx [lsearch $largs $option_name]
			if { $option_idx > -1 } {
				if { $option_idx == [expr {[llength $largs]-1}] } {
					set value_idx $option_idx 
				} else {
					set value_idx [expr {$option_idx+1}]
				}
				set largs [lreplace $largs $option_idx $value_idx]
			}
		}
		
		# Returns 1 if the named arguments list has a named option "-option_name".
		proc has_option { option_name {args_name args} } {
			upvar $args_name largs
			if { [string range $option_name 0 0] ne "-" } { set option_name "-$option_name" }	
			set n [llength $largs]
			set option_idx [lsearch $largs $option_name]
			return [expr {$option_idx > -1 && $option_idx < [expr {$n-1}]}]
		}
		
		# Returns the value of the named option in the named argument list
		proc get_option { option_name {default_value {}} {rm_option 0} {args_name args} } {
			upvar $args_name largs	
			if { [string range $option_name 0 0] ne "-" } { set option_name "-$option_name" }
			set n [llength $largs]
			set option_idx [lsearch $largs $option_name]
			if { $option_idx > -1 && $option_idx < [expr {$n-1}] } {
				set result [lindex $largs [expr {$option_idx+1}]]
				if { $rm_option == 1 } {
					set largs [lreplace $largs $option_idx [expr {$option_idx+1}]]
				}
			} else {
				set result $default_value
			}	
			return $result
		}
		
		# Extracts from args all pairs whose key start by the prefix. And returns the extracted named options in a new
		# args list that contains the pairs, with the prefix stripped from the keys. 
		# For example, "-label_fill X" will return "-fill X" if prefix="-label_", and args will be emptied.
		proc extract_prefixed { prefix {args_name args} } {
			upvar $args_name largs
			set new_args {}
			set n [expr {[string length $prefix]-1}]
			set i 0 
			while { $i < [llength $largs] } { 
				if { [string range [lindex $largs $i] 0 $n] eq $prefix } {
					lappend new_args "-[string range [lindex $largs $i] [expr {$n+1}] end]"
					lappend new_args [lindex $largs [expr {$i+1}]]
					set largs [lreplace $largs $i [expr {$i+1}]]
				} else {
					incr i 2
				}
			}
			return $new_args
		}
		
		
		### NON-EXPORTED COMMANDS TO PARSE AND PROCESS ITEM CREATION args ###
		### These are used from most 'dui add *' commands, for homogeneous handling of the same types of named options.
		
		# Complete the tags and -<type>variable arguments in the args list in a standard way.
		# If -tags is in the args, use the first tag as main tag, otherwise assigns an auto-increment counter tag,
		#	using 2 counters, one for text items, another for widgets.
		# Raises an error if a main tag already exists, as no duplicates are allowed.
		# Adds page tags in the form "p:$page" to the tags. This allows showing and hiding pages, or retrieving items
		#	by their tag name plus the page in which they appear.
		# If a varoption argument is specified (e.g. "-textvariable"), and the first page in $pages is a page
		#	namespace, then:
		#		- if the varoption is not found in the arguments, or it's the empty string, uses the namespace 
		#			variable data(<main_tag>)
		#		- if the varoption is found and it is a plain name instead of a fully qualified name, such as 
		#			"-textvariable pressure", uses the namespace variable data(<varoption>), e.g. data(pressure).
		proc process_tags_and_var { pages type {varoption {}} {add_multi 0} {args_name args} {rm_tags 0} } {
			variable item_cnt
			upvar $args_name largs
			set can [dui canvas]
			
			set tags [get_option -tags {} 1 largs]
			set auto_assign_tag 0
			if { [llength $tags] == 0 } {
				# Add 'dui_' prefix to avoid clashing with the existing tag system. 
				# TODO Remove 'dui_' when base code has been migrated.
				set main_tag "dui_${type}_[incr item_cnt]"
				set tags $main_tag
				set auto_assign_tag 1
			} else {				
				set main_tag [lindex $tags 0]
				if { [string is integer $main_tag] || ![regexp {^([A-Za-z0-9_\-])+$} $main_tag] } {
					set msg "Main tag '$main_tag' can only have letters, numbers, underscores and hyphens, and cannot be a number"
					msg [namespace current] process_tags_and_var: $msg
					error $msg
					return
				}
			}
			# We need to ensure GLOBAL main tag uniqueness while we coexist with the old labelling system.
			# Once it's unified, we'll request only uniqueness PER PAGE.
			if { [$can find withtag $main_tag] ne "" } {
				set msg "Main tag '$main_tag' already exists in canvas, duplicates are not allowed"
				msg [namespace current] process_tags_and_var: $msg
				error $msg
				return
			}
			# Change to this when there's no need to coexist with the old labelling system
#			foreach page $pages { 
#				if { [$can find withtag p:$page&&$main_tag] ne "" } {
#					set msg "Main tag '$main_tag' already exists in canvas page '$page', duplicates are not allowed"
#					msg [namespace current] process_tags_and_var $msg
#					error $msg
#					return
#				}
#			}
			
			if { $add_multi == 1 && "$main_tag*" ni $tags } {
				lappend tags "$main_tag*"
			}
			
			foreach p $pages {
				if { "p:$p" ni $tags } { 
					lappend tags "p:$p"
				}
			}
			if { $rm_tags == 0 } {
				add_option_if_not_exists -tags $tags largs
			}
						
			if { $varoption ne "" } {
				set first_page [lindex $pages 0]
				set ns [dui::page::get_namespace $first_page]
	
				if { $ns ne "" } {
					if { [string range $varoption 0 0 ] ne "-" } {
						set varoption -$varoption
					}
					set varname [get_option $varoption "" 1 largs]
					if { $varname eq "" } {
						if { ! $auto_assign_tag } {
							if { $type eq "variable" } {
								set varname "\$${ns}::data($main_tag)"
							} else {
								set varname "${ns}::data($main_tag)"
							}
						}
					} elseif { [string is wordchar $varname] } {
						if { $type eq "variable" } {
							set varname "\$${ns}::data($varname)"
						} else {
							set varname "${ns}::data($varname)"
						}
					} else {
						regsub -all {%NS} $varname $ns varname
					}
					
					if { $varname eq "" } {
						msg -WARN [namespace current] complete_tags_and_var "no $varoption specified for item $main_tag"
					} else {
						add_option_if_not_exists $varoption $varname largs
					}
				}
			}
			
			return $tags
		}

		# For each of the requested aspects, modifies the args adding the default option value for the current 
		#	theme and optional style. If an option is already in the args, does not modify it.
		# A fixed set of aspects can be provided on 'aspects', but most frequently this is left empty so that
		#	all options available for the type in the theme aspects are applied.
		# Note that -aspect_type, if provided in the args, has precedence over 'type'.
		# TBD: Allow 'type' to be a list from higher to lower precedence. 
		proc process_aspects { type {style {}} {aspects {}} {exclude {}} {args_name args} } {
			upvar $args_name largs
			if { $style eq "" } {
				set style [get_option -style "" 0 largs]
			}
			set default_type ""
			if { [dui::args::has_option -aspect_type largs] } {
				set default_type $type
				set type [dui::args::get_option -aspect_type "" 1 largs]
				set types [unique_list [list $type $default_type]]
			} else {
				set types $type
			}
			
			if { $aspects eq "" } {
				set aspects [dui aspect list -type $types -style $style]
			}
			foreach aspect $aspects {
				if { $aspect ni $exclude } {
					add_option_if_not_exists -$aspect [dui aspect get $type $aspect -style $style \
						-default_type $default_type] largs
				}
			}
		}
		
		
		# Handles -font_* options in the args:
		#	1) if -font is provided in the args, does nothing
		#	2) otherwise, uses -font_family and -font_size in the args, or, if not provided, from the theme type & style,
		#		and modifies the args to use a -font specification according to the provided options..
		#		If the type does not provide any font definition, uses the <theme>.font.font_* value.
		#		Relative font sizes +1/-1/+2 etc. can be defined, with respect to whatever font size is defined in the 
		#		theme for that type & style.
		# Returns the font.
		proc process_font { type {style {}} {args_name args} } {
			upvar $args_name largs
			if { $type eq "" } {
				set type font
			}
			if { $style eq "" } {
				set style [get_option -style "" 0 largs]
			}
			
			if { [has_option -font largs] } {
				set font [get_option -font "" 0 largs]
				foreach f {family size weight slant underline overstrike} {
					remove_option -font_$f largs
				}
			} else {
				set font_family [get_option -font_family [dui aspect get $type font_family -style $style] 1 largs]
				set default_size [dui aspect get $type font_size -style $style]				
				set font_size [get_option -font_size $default_size 1 largs]
				if { [string range $font_size 0 0] in "- +" } {
					set font_size [expr $default_size$font_size]
				}
				set weight [get_option -font_weight normal 1 largs]
				set slant [get_option -font_slant roman 1 largs]
				set underline [get_option -font_underline false 1 largs]
				set overstrike [get_option -font_overstrike false 1 largs]
				set font [dui font get $font_family $font_size -weight $weight -slant $slant -underline $underline -overstrike $overstrike]
				add_option_if_not_exists -font $font largs
			}
			return $font
		}

		# Processes the -label* named options in 'args' and produces the label according to the provided options.
		# All the -label* options are removed from 'args'.
		# Returns the main tag of the created text.
		# pos_type can be either 'rel' (relative, normally outside of the main widget) or 'inside' (inside the widget,
		#	as for buttons)
		proc process_label { pages x y type {style {}} {wrt_tag {}} {args_name args} } {
			upvar $args_name largs
			set label [get_option -label "" 1 largs]
			set labelvar [get_option -labelvariable "" 1 largs]
			if { $label eq "" && $labelvar eq "" } {
				return ""
			}
			if { $style eq "" } {
				set style [get_option -style "" 0 largs]
			}
			
			set tags [get_option -tags "" 0 largs]
			set main_tag [lindex $tags 0]
			if { $wrt_tag eq "" } {
				set wrt_tag $main_tag
			}
			
			set label_tags [list ${main_tag}-lbl {*}[lrange $tags 1 end]]	
			set label_args [extract_prefixed -label_ largs]
#			foreach aspect "anchor justify fill activefill disabledfill font_family font_size" {
#				add_option_if_not_exists -$aspect [dui aspect get ${type}_label $aspect -style $style \
#					-default {} -default_type text] label_args
#			}
			foreach aspect [dui aspect list -type [list ${type}_label text] -style $style] {
				add_option_if_not_exists -$aspect [dui aspect get ${type}_label $aspect -style $style \
					-default {} -default_type text] label_args
			}
						
			set label_pos [get_option -pos "w -20 0" 1 label_args]
			#[dui aspect get ${type}_label pos -style $style -default "w -20 0"] 
			if { [llength $label_pos] == 2 && [string is integer [lindex $label_pos 0]] && \
					[string is integer [lindex $label_pos 1]] } {
				set xlabel [lindex $label_pos 0]
				if { [string range $xlabel 0 0] in "- +" } {
					set xlabel [expr {$x+$xlabel}]
				}
				set ylabel [lindex $label_pos 1]
				if { [string range $ylabel 0 0] in "- +" } {
					set ylabel [expr {$y+$ylabel}]
				}				
			} else {
				set xlabel [expr {$x-20}]
				set ylabel [expr {$y-3}]
				set xlabel_offset 0
				set ylabel_offset 0
				if { [llength $label_pos] > 1 } {
					set xlabel_offset [rescale_x_skin [lindex $label_pos 1]] 
				}
				if { [llength $label_pos] > 2 } {
					set ylabel_offset [rescale_y_skin [lindex $label_pos 2]] 
				}				
				foreach page $pages {
					set after_show_cmd "::dui::item::relocate_text_wrt $page ${main_tag}-lbl $wrt_tag [lindex $label_pos 0] \
						$xlabel_offset $ylabel_offset [get_option -anchor nw 0 label_args]"	
					dui page add_action $page show $after_show_cmd
				}
			}

			if { $label ne "" } {
				set id [dui add text $pages $xlabel $ylabel -text $label -tags $label_tags -aspect_type ${type}_label \
					{*}$label_args]
			} elseif { $labelvar ne "" } {
				set id [dui add variable $pages $xlabel $ylabel -textvariable $labelvar -tags $label_tags \
					-aspect_type ${type}_label {*}$label_args] 
			}
			return $id
		}

		# Processes the -yscrollbar* named options in 'args' and produces the scrollbar slider widget according to 
		#	the provided options.
		# All the -yscrollbar* options are removed from 'args'.
		# Returns 0 if the scrollbar is not created, or the widget name if it is. 
		proc process_yscrollbar { pages x y type {style {}} {args_name args} } {
			upvar $args_name largs			
			set ysb [get_option -yscrollbar "" 1 largs]
			
			if { $ysb eq "" } {
				set sb_args [extract_prefixed -yscrollbar_ largs]
				if { [llength $sb_args] == 0 } {
					return 0
				}
			} elseif { [string is false $ysb] } {
				return 0
			} else {
				set sb_args [extract_prefixed -yscrollbar_ largs]
			}
		
			if { $style eq "" } {
				set style [get_option -style "" 0 largs]
			}
						
			set tags [get_option -tags "" 0 largs]
			set main_tag [lindex $tags 0]			
			set sb_tags [list ${main_tag}-ysb {*}[lrange $tags 1 end]]

			foreach a [dui aspect list -type scrollbar -style $style] {
				set a_value [dui aspect get ${type}_yscrollbar $a -style $style -default {} -default_type scrollbar]
				if { $a eq "height" } {
					if { $a_value eq "" } {
						set a_value 75
					}
					set a_value [rescale_y_skin $a_value]
				} elseif { $a in "length sliderlength" } {
					if { $a_value eq "" } {
						set a_value 75
					}
					set a_value [rescale_x_skin $a_value]
				}
				add_option_if_not_exists -$a $a_value sb_args
			}
			
			set var [get_option -variable "" 1 sb_args]
			if { $var eq "" } {
				set var "::dui::item::sliders($main_tag)"
				set $var 0
			}
			set cmd [get_option -command "" 1 sb_args]
			if { $cmd eq "" } {
				set cmd "::dui::item::listbox_moveto $main_tag \$$var"
			}
			
			foreach page $pages {
				dui page add_action $page show "::dui::item::set_yscrollbar_dim $page $main_tag ${main_tag}-ysb"
			}
			
			return [dui add widget scale $pages 10000 $y -tags $sb_tags -variable $var -command $cmd {*}$sb_args]
		}		
	}

	### PAGE SUB-ENSEMBLE ###
	# AT THE MOMENT ONLY page_add SHOULD BE USED AS OTHERS MAY BREAK BACKWARDS COMPATIBILITY #
	namespace eval page {
		namespace export add current exists list get_namespace set_next show_when_off show add_action actions
		namespace ensemble create

		# Metadata for every added page. Array names have the form '<page_name>,<type>', where <type> can be:
		#	'ns': Page namespace. Empty string if the page doesn't have a namespace.
		#	'load': Tcl code to run when the page is going to be shown, but before if is actually shown.
		#	'show': Tcl code to run just after the page is shown. 
		#	'hide': Tcl code to run just after the page is hidden.
		variable pages_data 
		array set pages_data {}
#		variable actions
#		array set actions {}
#		
#		variable pages_ns
#		array set pages_ns {}
		
		#variable nextpage
		#array set nextpage {}
		#variable exit_app_on_sleep 0
		
		# 'page add' accommodates both simple-style skin/plugin pages using the same background image or colored rectangle 
		#	for all pages (which can be defined in the theme), or Insight-style customized with a background image per-page,
		#	by defining -bg_img
		#
		# Named options:
		#  -style to apply the default aspects of the provided style
		#  -bg_img background image file to use
		#  -bg_color background color to use, in case no background image is defined
		#  -skin passed to ::add_de1_page if necessary
		#  -namespace either a value that can be a boolean, or a list of namespaces names.
		#		If the option is not specified, uses ::dui::create_page_namespaces as default. Then:
		#		If 'true' or equivalent, uses namespace ::dui::pages::<page_name> for each page, creating it if necessary.
		#		If 'false' or equivalent, uses no page namespace.
		#		Otherwise, uses the passed namespaces for each page. A namespace can be provided for each page, or
		#			a common namespace can be used for all of them. If the namespace does not exist yet, it is created,
		#			and the data array variable is defined. 
		proc add { pages args } {
			variable pages_data
			array set opts $args
			set can [dui canvas]
			
			foreach page $pages {
				if { ![string is wordchar $page] } {
					error "Page names can only have letters, numbers and underscores. '$page' is not valid."
				} elseif { [info exists pages_data($page,ns)] } {
					error "Page names must be unique. '$page' is duplicated."
				}
			}
			
			set style [dui::args::get_option -style "" 1]
			set bg_img [dui::args::get_option -bg_img [dui aspect get page.bg_img -style $style]]
			if { $bg_img ne "" } {
				::add_de1_page $pages $bg_img [dui::args::get_option -skin ""] 
				#add_de1_image $page 0 0 $bg_img
			} else {
				set bg_color [dui::args::get_option -bg_color [dui aspect get page.bg_color -style $style]]
				if { $bg_color ne "" } {
					foreach c $pages {
						#set tag "${c}.background"
						$can create rect 0 0 [rescale_x_skin 2560] [rescale_y_skin 1600] -fill $bg_color -width 0 \
							-tags  [list pages $c] -state "hidden"
						#dui item add_to_pages $c $tag
					}
				}
			}
							
			set ns [dui::args::get_option -namespace $::dui::create_page_namespaces 0]
			if { [string is true -strict $ns] } {
				set ns {}
				foreach page $pages {
					lappend ns ::dui::pages::${page}
				}				
			} elseif { [string is false -strict $ns] } {
				set ns ""
			} 
			
			if { $ns eq "" } {
				foreach page $pages {
					set pages_data($page,ns) {}
				}
			} else {
				# If the page namespace does not exist, create it. Also ensure it has the needed variables.
				foreach page $pages page_ns $ns {
					if { $page_ns eq "" } {
						set page_ns [lindex $ns 0]
					}
					set pages_data($page,ns) $page_ns
					
					if { $page_ns ne "" } {
						if { [namespace exists $page_ns] } {
							if { ![info exists ${page_ns}::data] } {
								namespace eval $page_ns {
									variable data
									array set $data {}
								}
							}
							if { ![info exists ${page_ns}::widgets] } {
								namespace eval $page_ns {
									variable widgets
									array set widgets {}
								}
							}
						} else {
							namespace eval $page_ns {
								namespace export *
								namespace ensemble create
								
								variable data
								array set data {}
								
								variable widgets
								array set widgets {}
							}
						}
					}
				}
			}
		}
		
		proc current {} {
			# Later on dui will keep the current page. At the moment, just use the global variable 
			return $::de1(current_context)
		}
		
		proc exists { page } {
			variable pages_data
			return [info exists pages_data($page,ns)]
		}
		
		proc list {} {
			variable pages_data
			set pages {}
			foreach arrname [array names pages_data "*,ns"] {
				lappend pages [string range $arrname 0 end-3]
			}
			return $pages
		}
		
		# If several pages are passed, only uses the first one. Checks that the namespace actually exists, if it
		#	doesn't returns an empty string.
		proc get_namespace { page } {
			variable pages_data
			set page [lindex $page 0]
			set ns [ifexists pages_data($page,ns)]
			if { $ns ne "" && ![namespace exists $ns] } {
				msg -WARN [namespace current] "page namespace '$ns' not found"
				set ns ""
			} 
			return $ns
		}
			
		proc set_next { machinepage guipage } {
			#variable nextpage
			#msg "set_next_page $machinepage $guipage"
			set key "machine:$machinepage"
			set ::nextpage($key) $guipage
		}

		proc show_when_off { page_to_show args } {
			set_next off $page_to_show
			show $page_to_show {*}$args
		}
				
		proc show { page_to_show args } {
			display_change [current] $page_to_show {*}$args
		}
		
		proc display_change { page_to_hide page_to_show args } {
			set can [dui canvas]
			delay_screen_saver
			
			# EB
			set hide_ns [get_namespace $page_to_hide]
			set show_ns [get_namespace $page_to_show]
			set key "machine:$page_to_show"
			if {[ifexists ::nextpage($key)] != ""} {
				# there are different possible tabs to display for different states (such as preheat-cup vs hot water)
				set page_to_show $::nextpage($key)
			}
		
			if {[current] eq $page_to_show} {
				#msg "page_display_change returning because ::de1(current_context) == $page_to_show"
				return 
			}
		
			msg [namespace current] display_change "$page_to_hide->$page_to_show"
				
			# EB: This should be handled by the main app adding actions to the sleep/off/saver pages
			if {$page_to_hide == "sleep" && $page_to_show == "off"} {
				msg [namespace current] "discarding intermediate sleep/off state msg"
				return 
			} elseif {$page_to_show == "saver"} {
				if {[ifexists ::exit_app_on_sleep] == 1} {
					get_set_tablet_brightness 0
					close_all_ble_and_exit
				}
			}
		
			# signal the page change with a sound
			say "" $::settings(sound_button_out)
			#msg "page_display_change $page_to_show"
			#set start [clock milliseconds]
		
			# EB: This should be added on the main app as a load action on the "saver" page
			# set the brightness in one place
			if {$page_to_show == "saver" } {
				if {$::settings(screen_saver_change_interval) == 0} {
					# black screen saver
					display_brightness 0
				} else {
					display_brightness $::settings(saver_brightness)
				}
				borg systemui $::android_full_screen_flags  
			} else {
				display_brightness $::settings(app_brightness)
			}
		
			
			if {$::settings(stress_test) == 1 && $::de1_num_state($::de1(state)) == "Idle" && [info exists ::idle_next_step] == 1} {		
				msg "Doing next stress test step: '$::idle_next_step '"
				set todo $::idle_next_step 
				unset -nocomplain ::idle_next_step 
				eval $todo
			}
			
			# EB

			foreach action [actions $page_to_show load] {
				eval $action
			}
			if { $show_ns ne "" && [info procs ${show_ns}::load] ne "" } {
				set page_loaded [${show_ns}::load $page_to_hide $page_to_show {*}$args]
				if { ![string is true $page_loaded] } {
					# Interrupt the loading: don't show the new page
					return
				}
			}

			foreach action [actions $page_to_hide hide] {
				eval $action
			}			
			if { $hide_ns ne "" && [info procs ${hide_ns}::hide] ne "" } {
				${hide_ns}::hide $page_to_hide $page_to_show
			}

			#global current_context
			set ::de1(current_context) $page_to_show
		
			#puts "page_display_change hide:$page_to_hide show:$page_to_show"
			try {
				$can itemconfigure $page_to_hide -state hidden
			} on error err {
				msg -ERROR [namespace current] display_change "error hiding $page_to_hide: $err"
			}
			#$can itemconfigure [list "pages" "splash" "saver"] -state hidden
		
			if {[info exists ::delayed_image_load($page_to_show)] == 1} {
				set pngfilename	$::delayed_image_load($page_to_show)
				msg "Loading skin image from disk: $pngfilename"
				
				set errcode [catch {
					# this can happen if the image file has been moved/deleted underneath the app
					#fallback is to at least not crash
					msg "page_display_change image create photo $page_to_show -file $pngfilename" 
					image create photo $page_to_show -file $pngfilename
					#msg "image create photo $page_to_show -file $pngfilename"
				}]
		
				if {$errcode != 0} {
					catch {
						msg "image create photo error: $::errorInfo"
					}
				}
		
				foreach {page img} [array get ::delayed_image_load] {
					if {$img == $pngfilename} {
						
						# Matching delayed image load to every page that references it
						# this avoids loading the same iamge over and over, for each page referencing it
		
						set errcode [catch {
							# this error can happen if the image file has been moved/deleted underneath the app, fallback is to at least not crash
							$can itemconfigure $page -image $page_to_show -state hidden					
						}]
		
						if {$errcode != 0} {
							catch {
								msg "$can itemconfigure page_to_show ($page/$page_to_show) error: $::errorInfo"
							}
						}
		
						unset -nocomplain ::delayed_image_load($page)
					}
				}
		
			}
		
#			try {
#				$can itemconfigure $page_to_show -state normal
#			} on error err {
#				msg -ERROR [namespace current ] display_change "showing page $page_to_show: $err"
#			}
		
			set these_labels [ifexists ::existing_labels($page_to_show)]
#			#msg "these_labels: $these_labels"
#					
#			if {[info exists ::all_labels] != 1} {
#				set ::all_labels {}
#				foreach {page labels} [array get ::existing_labels]  {
#					set ::all_labels [concat $::all_labels $labels]
#				}
#				set ::all_labels [lsort -unique $::all_labels]
#			}
		
			#msg "Hiding [llength $::all_labels] labels"
#			foreach label $::all_labels {
#				if {[$can itemcget $label -state] != "hidden"} {
#					$can itemconfigure $label -state hidden
#					#msg "hiding: '$label'"
#				}
#			}

			# EB NO NEED TO USE ::all_labels like commented code above, can do with canvas tags ??
			foreach item [$can find withtag all] {
				if { [$can itemcget $item -state] ne "hidden" } {
					$can itemconfigure $item -state hidden
				}
			}

			try {
				$can itemconfigure $page_to_show -state normal
			} on error err {
				msg -ERROR [namespace current ] display_change "showing page $page_to_show: $err"
			}
			
			#msg "Showing [llength $these_labels] labels"

			# Backward-compatible for pages that are not created using the new tags system.
			foreach label $these_labels {
				$can itemconfigure $label -state normal
				#msg "showing: '$label'"
			}

			# New dui system, no need to use ::existing_labels, can do with canvas tags, provided p:<page_name> tags 
			#	were used.
			set items_to_show [$can find withtag p:$page_to_show]
			if { [llength $items_to_show] > 0 } {
				foreach item $items_to_show {
					$can itemconfigure $item -state normal
				}
			} 
			
			foreach action [actions $page_to_show show] {
				eval $action
			}
			
			if { $show_ns ne "" && [info procs ${show_ns}::show] ne "" } {
				${show_ns}::show $page_to_hide $page_to_show
				#set ::dui::pages::${page_to_show}::page_drawn 1
			}
			
			#set end [clock milliseconds]
			#puts "elapsed: [expr {$end - $start}]"
		
			# The old actions system, equivalent to the new page "show" event action. 
			# Left temporarilly for compatibility.
			global actions
			if {[info exists actions($page_to_show)] == 1} {
				foreach action $actions($page_to_show) {
					eval $action
					msg "action: '$action"
				}
			}

			update
						
			#msg "Switched to page: $page_to_show [stacktrace]"
			msg "Switched to page: $page_to_show"
		
			update_onscreen_variables
			dui hide_android_keyboard
		}
		
		proc add_action { pages event tclcode } {
			variable pages_data
			if { $event ni {load show hide} } {
				error "'$event' is not a valid event for 'dui page add_action'"
			}
			foreach page $pages {
				lappend pages_data($page,$event) $tclcode
			}
		}
		
		proc actions { page event } {
			variable pages_data
			if { $event ni {load show hide} } {
				error "'$event' is not a valid event for 'dui page add_action'"
			}
			return [ifexists pages_data($page,$event)]
		}
	}

	### PAGES SUB-ENSEMBLE ###
	# Just a container namespace for client code to create UI pages as children namespaces.
	namespace eval pages {
		namespace export *
		namespace ensemble create
	}
	
	### ITEMS SUB-ENSEMBLE ###
	# Items are visual items added to the canvas, either canvas items (text, arcs, lines...) or Tk widgets.
	namespace eval item {
		namespace export *
		namespace ensemble create
	
		variable sliders
		array set sliders {}
		
		# A list of paths where to look for image files. Within each, it will look in the
		#	<resolution_width>x<resolution_height> subfolder.
		variable img_dirs {}
		
		# Keep track of what labels are displayed in what pages. Warns if a label already exists.
		# In the future this shouldn't be needed, as dui manages what to show using canvas tags. But it's needed
		#	while the old and new systems coexist.
		proc add_to_pages { pages tags } {
			global existing_labels
			foreach page $pages {
				set page_tags [ifexists existing_labels($page)]
				foreach tag $tags {					
					if { $tag in $page_tags } {
						#msg -WARN [namespace current] "tag/label '$tag' already exists in page '$page'"
						error "label '$tag' already exists in page '$page'"
					} else {
						msg [namespace current] "adding tag '$tag' to page '$page'"
						lappend page_tags $tag
					}
				}
				set existing_labels($page) $page_tags
			}
		}

		# Just a wrapper for the add_* commands, for consistency of the API
		proc add { type args } {
			if { [info proc ::dui::add::$type] ne "" } {
				::dui::add::$type {*}$args
			} else {
				msg -ERROR [namespace current] "no 'dui add $type' command available"
			}
		}
		
		# Canvas items selector using tags. Returns unique item IDs. Use trailing * as in "<tag>*" to return all  
		#	related tags (e.g. a listbox with its label and scrollbar)
		# Use the empty string, "*", or "all" to return all tags in the page. Leave the page empty to not filter
		#	to a specific page.
		# Allows specifiying items/widgets in 3 ways:
		#	1) As a page + a list of canvas tags
		#	2) As a list of canvas item IDs (integer numbers) if only one argument is specified. They are then
		#		returned without changes.
		#	3) As a canvas widget pathname. Then it is returned without changes.
		# The second form is there to allow passing the contents of data(widgets) directly to this function. 
		proc get { page_or_ids_or_widgets {tags {}} } {
			set can [dui canvas]
			if { $tags eq "" } {
				if { $page_or_ids_or_widgets eq "" } {
					return ""
				}
				
				set result {}
				if { [string is integer [lindex $page_or_ids_or_widgets 0]] } {
					foreach id $page_or_ids_or_widgets {						
						if { [$can find withtag $id] eq $id } {
							lappend result $id
						}
					}
				} else {
					foreach w $page_or_ids_or_widgets {
						if { [winfo exists $w] } {
							lappend result $w
						}
					}
				}
				return [unique_list $result]
			}
			
			set ids {}
			set page [lindex $page_or_ids_or_widgets 0] 
			foreach tag $tags {
				if {  $page eq "" } {
					set found [$can find withtag $tag]
				} elseif { $tag eq "*" || $tag eq "" || $tag eq "all"} {
					set found [$can find withtag "p:$page"]
				} else {
					set found [$can find withtag "p:$page&&$tag"]
					
				}
				if { $found eq "" } {
					msg -NOTICE [namespace current] get: "no canvas tag matches '$tag' in page '$page'"
				} else {
					lappend ids {*}$found
				}
			}

			return [unique_list $ids]
		}
		
		# If page is empty, 'tag_or_widget' should be a widget pathname, and returns it if it exists, or an empty
		#	string if not.
		# If page is non-empty, searches the widget in the dui canvas by tag and returns its pathanme if it's a 
		#	widget/window, or and empty string if it's not found or not a window.
		# This is used by all 'dui item' subcommands that use Tk widgets, so that client code can refer to them
		#	by any of canvas ID, page/canvas tag, or by widget pathname.
		# proc get_widget { page {tag_or_widget {}} }
		proc get_widget { page_or_ids_or_widget {tag {}} } {			
			set widget [lindex [get $page_or_ids_or_widget $tag] 0]
			if { [winfo exists $widget] } {
				return $widget
			} else {
				set can [dui canvas]
				if { [$can type $widget] eq "window" } {
					return [$can itemcget $widget -window]
				}
			}
			return ""
			
#			if { $page eq "" } {
#				set widget [lindex $tag_or_widget 0]
#				if { winfo exists $widget } {
#					return $widget
#				}
#			} else {
#				set can [dui canvas]
#				set item [get [lindex $page 0] [lindex $tag_or_widget 0]]
#				if { [$can type $item] eq "window" } {
#					return [$can itemcget $item -window]
#				}
#			}
#			return ""
		}
		
		# Provides a single interface to configure options for both canvas items (text, arcs...) and canvas widgets 
		#	(window entries, listboxes, etc.)
		# Allows specifiying items/widgets in 3 ways:
		#	1) As a list of widgets pathnames (.can.my_entry, etc.)
		#	2) As a list of canvas item IDs (integer numbers)
		#	3) As a page name as first argument, and a list of tag names as second argument
		proc config { page_or_ids_or_widgets args } {
			set can [dui canvas]
			if { [string range [lindex $args 0] 0 0] eq "-" || [lindex $args 0] eq "" } {
				set items [get $page_or_ids_or_widgets]
			} else {
				set items [get $page_or_ids_or_widgets [lindex $args 0]]
				set args [lrange $args 1 end]
			}
				
			# Passing '$tags' directly to itemconfigure when it contains multiple tags not always works, iterating
			#	is often needed.
			foreach item $items {
				#msg [namespace current] "config:" "item '$item' of type '[$can type $tag]' with '$args'"
				if { [winfo exists $item] } {
					$item configure {*}$args
				} elseif { [$can type $item] eq "window" } {
					[$can itemcget $item -window] configure {*}$args
				} else {
					$can itemconfigure $item {*}$args
				}
			}
		}
		
#		proc config { page tags args } {
#			set can [dui canvas]
#			# Passing '$tags' directly to itemconfigure when it contains multiple tags not always works, iterating
#			#	is often needed.
#			foreach item [get $page $tags] {
#				#msg [namespace current] "config:" "tag '$tag' of type '[$can type $tag]' with '$args'"
#				if { [$can type $item] eq "window" } {
#					[$can itemcget $item -window] configure {*}$args
#				} else {
#					$can itemconfigure $item {*}$args
#				}
#			}
#		}

		proc cget { page_or_ids_or_widgets args } {
			set can [dui canvas]
			if { [string range [lindex $args 0] 0 0] eq "-" || [lindex $args 0] eq "" } {
				set items [get $page_or_ids_or_widgets]
			} else {
				set items [get $page_or_ids_or_widgets [lindex $args 0]]
				set args [lrange $args 1 end]
			}
				
			# Passing '$tags' directly to itemconfigure when it contains multiple tags not always works, iterating
			#	is often needed.
			set result {}
			foreach item $items {
				#msg [namespace current] "config:" "item '$item' of type '[$can type $tag]' with '$args'"
				if { [winfo exists $item] } {
					lappend result [$item cget {*}$args]
				} elseif { [$can type $item] eq "window" } {
					lappend result [[$can itemcget $item -window] cget {*}$args]
				} else {
					lappend result [$can itemcget $item {*}$args]
				}
			}
			return $result
		}
		
		# "Smart" widgets enabler or disabler. 'enabled' can take any value equivalent to boolean (1, true, yes, etc.) 
		# For text, changes its fill color to the default or provided font or disabled color.
		# For other widgets like rectangle "clickable" button areas, enables or disables them.
		# Does nothing if the widget is hidden.
		proc enable_or_disable { enabled page_or_ids_or_widgets {tags {}} } {
			#set can [dui canvas]
#			if { $page eq "" } {
#				set page [dui page current]
#			}
			
			if { [string is true $enabled] || $enabled eq "enable" } {
				set state normal
			} else {
				set state disabled
			}
			
			config $page_or_ids_or_widgets $tags -state $state
		} 
		
		# "Smart" widgets disabler. 
		# For text, changes its fill color to the default or provided disabled color.
		# For other widgets like rectangle "clickable" button areas, disables them.
		# Does nothing if the widget is hidden. 
		proc disable { page_or_ids_or_widgets {tags {}} } {
			enable_or_disable 0 $page_or_ids_or_widgets $tags
		}
		
		proc enable { page_or_ids_or_widgets {tags {}} } {
			enable_or_disable 1 $page_or_ids_or_widgets $tags
		}
		
		# "Smart" widgets shower or hider. 'show' can take any value equivalent to boolean (1, true, yes, etc.)
		# If check_context=1, only hides or shows if the items page is the currently active page. This is useful,
		#	for example, if you're showing after a delay, as the page/page may have been changed in between.
		proc show_or_hide { show page_or_ids_or_widgets {tags {}} { check_context 1 } } {
			if { $tags eq "" && [llength $page_or_ids_or_widgets] == 1 && [dui page exists $page_or_ids_or_widgets] && $check_context } {
				if { $page_or_ids_or_widgets ne [dui page current] } {
					return
				}
			}
#			if { $page eq "" } {
#				set page [dui page current]
#			} elseif { $check_context && $page ne [dui page current] } {
#				return
#			}
			
			if { [string is true $show] || $show eq "show" } {
				set state normal
			} else {
				set state hidden
			}
			
			config $page_or_ids_or_widgets $tags -state $state
		}
		
		proc show { page tags { check_context 1} } {
			show_or_hide 1 $page $tags $check_context
		}
		
		proc hide { page tags { check_context 1} } {
			show_or_hide 0 $page $tags $check_context
		}

		proc add_image_dirs { args } {
			variable img_dirs
			if { [llength $args] == 1 } {
				set args [lindex $args 0]
			}
			
			foreach dir $args {
				if { [file isdirectory $dir] } {
					if { $dir in $img_dirs } {
						msg -NOTICE [namespace current] "images directory '$dir' was already in the list"
					} else {
						lappend img_dirs $dir
						msg [namespace current] "adding image directory '$dir'"
					}
				} else {
					msg -ERROR [namespace current] "images directory '$dir' not found"
				}
			}
		}
		
		proc image_dirs {} {
			variable img_dirs
			return $img_dirs
		}
		
		# Moves a text canvas item with respect to another item or widget, i.e. to a position relative to another one.
		# pos can be any of "n", "nw", "ne", "s", "sw", "se", "w", "wn", "ws", "e", "en", "es".
		# xoffset and yoffset define a fixed offset with respect to the coordinates obtained from processing 'pos'. 
		#	Can be positive or negative.
		# anchor is how to position the text widget relative to the point obtained after processing pos & offsets. 
		#	Takes the same values as the standard -anchor option. If not defined, keeps the existing widget -anchor.
		# move_too is a list of other widgets that will be repositioned together with widget, maintaining the same relative
		#	distances to the 'wrt' widget as they had originally. Typically used for the rectangle "button" areas 
		#	around text labels.
		proc relocate_text_wrt { page tag wrt { pos w } { xoffset 0 } { yoffset 0 } { anchor {} } { move_too {} } } {
			set can [dui canvas]
			set page [lindex $page 0]
			set tag [get $page [lindex $tag 0]]
			set wrt [get $page [lindex $wrt 0]]
			lassign [$can bbox $wrt] x0 y0 x1 y1 
			lassign [$can bbox $tag] wx0 wy0 wx1 wy1
			set xoffset [rescale_x_skin $xoffset]
			set yoffset [rescale_y_skin $yoffset]
			
			if { $pos eq "center" } {
				set newx [expr {$x0+int(($x1-$x0)/2)+$xoffset}]
				set newy [expr {$y0+int(($y1-$y0)/2)+$yoffset}]
			} else {
				set pos1 [string range $pos 0 0]
				set pos2 [string range $pos 1 1]
				
				if { $pos1 eq "w" || $pos1 eq ""} {
					set newx [expr {$x0+$xoffset}]
					
					if { $pos2 eq "n" } {
						set newy [expr {$y0+$yoffset}]
					} elseif { $pos2 eq "s" } {
						set newy [expr {$y1+$yoffset}]
					} else {
						set newy [expr {$y0+int(($y1-$y0)/2)+$yoffset}]
					}
				} elseif { $pos1 eq "e" } {
					set newx [expr {$x1+$xoffset}]
					
					if { $pos2 eq "n" } {
						set newy [expr {$y0+$yoffset}]
					} elseif { $pos2 eq "s" } {
						set newy [expr {$y1+$yoffset}]
					} else {
						set newy [expr {$y0+int(($y1-$y0)/2)+$yoffset}]
					}			
				} elseif { $pos1 eq "n" } {
					set newy [expr {$y0+$yoffset}]
					
					if { $pos2 eq "w" } {
						set newx [expr {$x0+$xoffset}]
					} elseif { $pos2 eq "e" } {
						set newx [expr {$x1+$xoffset}]
					} else {
						set newx [expr {$x0+int(($x1-$x0)/2)+$xoffset}]
					}
				} elseif { $pos1 eq "s" } {
					set newy [expr {$y1+$yoffset}]
					
					if { $pos2 eq "w" } {
						set newx [expr {$x0+$xoffset}]
					} elseif { $pos2 eq "e" } {
						set newx [expr {$x1+$xoffset}]
					} else {
						set newx [expr {$x0+int(($x1-$x0)/2)+$xoffset}]
					}
				} else return 
			}
			
			if { $anchor ne "" } {
				# Embedded in catch as widgets like rectangles don't support -anchor
				catch { $can itemconfigure $tag -anchor $anchor }
			}
			# Don't use command 'moveto' as then -anchor is not acknowledged
			$can coords $tag "$newx $newy"
			
			if { $move_too ne "" } {
				lassign [$can bbox $tag] newx newy
				
				foreach w $move_too {			
					set mtcoords [$can coords $w]
					set mtxoffset [expr {[lindex $mtcoords 0]-$wx0}]
					set mtyoffset [expr {[lindex $mtcoords 1]-$wy0}]
					
					if { [llength $mtcoords] == 2 } {
						$can coords $w "[expr {$newx+$mtxoffset}] [expr {$newy+$mtyoffset}]"
					} elseif { [llength $mtcoords] == 4 } {
						$can coords $w "[expr {$newx+$mtxoffset}] [expr {$newy+$mtyoffset}] \
							[expr {$newx+$mtxoffset+[lindex $mtcoords 2]-[lindex $mtcoords 0]}] \
							[expr {$newy+$mtyoffset+[lindex $mtcoords 3]-[lindex $mtcoords 1]}]"
					}
				}
			}
					
			return "$newx $newy"
		}
		
		# Ensures a minimum or maximum size of a widget in pixels. This is normally useful for text base entries like 
		#	entry or listbox whose width & height on creation have to be defined in number of characters, so may be too
		#	small or too big depending on the actual font in use.
		# OBSOLETE, use -canvas_width and -canvas_height options to set sizes in pixels of text-based widgets. 
		proc ensure_size { widgets args } {
			array set opts $args
			set can [dui canvas]
			foreach w $widgets {
				lassign [$can bbox $w ] x0 y0 x1 y1
				set width [rescale_x_skin [expr {$x1-$x0}]]
				set height [rescale_y_skin [expr {$y1-$y0}]]
				
				set target_width 0
				if { [info exists opts(-width)] } {
					set target_width [rescale_x_skin $opts(-width)]
				} elseif { [info exists opts(-max_width)] && $width > [rescale_x_skin $opts(-max_width)]} {
					set target_width [rescale_x_skin $opts(-max_width)] 
				} elseif { [info exists opts(-min_width)] && $width < [rescale_x_skin $opts(-min_width)]} {
					set target_width [rescale_x_skin $opts(-min_width)]
				}
				if { $target_width > 0 } {
					$can itemconfigure $w -width $target_width
				}
				
				set target_height 0
				if { [info exists opts(-height)] } {
					set target_height [rescale_y_skin $opts(-height)]
				} elseif { [info exists opts(-max_height)] && $height > [rescale_y_skin $opts(-max_height)]} {
					set target_height [rescale_y_skin $opts(-max_width)] 
				} elseif { [info exists opts(-min_height)] && $height < [rescale_y_skin $opts(-min_height)]} {
					set target_height [rescale_y_skin $opts(-min_height)]
				}
				if { $target_height > 0 } {
					$can itemconfigure $w -height $target_height
				}
			}
		}
		
		# Configures a page listbox yscrollbar locations and sizes. Run once the page is shown for then to be dynamically 
		# positioned.
		proc set_yscrollbar_dim { page widget_tag {scrollbar_tag {}} } {
			set can [dui canvas]
			if { $scrollbar_tag eq "" } {
				set scrollbar_tag ${main_tag}-ysb
			}
			
			lassign [$can bbox $widget_tag] x0 y0 x1 y1
			[$can itemcget $scrollbar_tag -window] configure -length [expr {$y1-$y0}]
			$can coords $scrollbar_tag "$x1 $y0"
		}
		
		# convenience function to link a "scale" widget with a "listbox" so that the scale becomes a scrollbar to the 
		#	listbox, rather than using the ugly Tk native scrollbar
		proc listbox_moveto { listbox_tag dest1 dest2 } {
			set lb [[dui canvas] itemcget $listbox_tag -window]
			# get number of items visible in list box
			set visible_items [lindex [split [$lb configure -height] " "] 4]
			# get total items in listbox
			set total_items [$lb size]
			# if all the items fit on screen then there is nothing to do
			if {$visible_items >= $total_items} {return}
			# determine which item would be at the top if the last items is at the bottom
			set last_top_item [expr $total_items - $visible_items]
			# determine which item should be at the top for the requested value
			set top_item [expr int(round($last_top_item * $dest2))]
		
			$lb yview $top_item
		}
		
		# convenience function to link a "scale" widget with a "listbox" so that the scale becomes a scrollbar to the 
		#	listbox, rather than using the ugly Tk native scrollbar
		proc scale_scroll { listbox_tag slider_varname dest1 dest2} {
			set lb [[dui canvas] itemcget $listbox_tag -window]
			# get number of items visible in list box
			set visible_items [lindex [split [$lb configure -height] " "] 4]
			# get total items in listbox
			set total_items [$lb size]
			# if all the items fit on screen then there is nothing to do
			if {$visible_items >= $total_items} {return}
			# determine which item would be at the top if the last items is at the bottom
			set last_top_item [expr $total_items - $visible_items]
			# determine what percentage of the way down the current top item is
			set rescaled_value [expr $dest1 * $total_items / $last_top_item]
		
			upvar $slider_varname fieldname
			set fieldname $rescaled_value
		}
		
		# Returns the values of the selected items in a listbox. If a 'values' list is provided, returns the matching
		# items in that list instead of matching to listbox entries, unless 'values' is shorter than the listbox,
		# in which case indexes not reachable from 'values' are taken from the listbox values.
		proc listbox_get_selection { page_or_id_or_widget tag {values {}} } {
			set widget [get_widget $page_or_id_or_widget $tag]
			set cursel [$widget curselection]
			if { $cursel eq "" } return {}
		
			set result {}	
			set n [llength $values]
			foreach idx [$widget curselection] {
				if { $values ne "" && $idx < $n } {
					lappend result [lindex $values $idx]
				} else {
					lappend result [$widget get $idx]
				}
			}	
			
		#	if { [llength $result] == 1 } {
		#		return [lindex $result 0]
		#	} else {
		#		return $result
		#	}
			return $result	
		}
		
		# Sets the selected items in a listbox, matching the string values.
		# If a 'values' list is provided, 'selected' is matched against that list instead of the actual values shown in the listbox.
		# If 'reset_current' is 1, clears the previous selection first.
		proc listbox_set_selection { page_or_id_or_widget tag selected { values {} } { reset_current 1 } } {
			set widget [get_widget $page_or_id_or_widget $tag]
			if { $selected eq "" } return
			if { $values eq "" } { 
				set values [$widget get 0 end]
			} else {
				# Ensure values has the same length as the listbox items, otherwises trim it or add the listbox items
				set ln [$widget size]
				set vn [llength $values]
				if { $ln < $vn } {
					set values [lreplace $values $ln end]
				} elseif { $ln > $vn } {
					lappend values [$widget get $vn end]
				}
			}
			
			if { $reset_current == 1 } { $widget selection clear 0 end }	
			if { [$widget cget -selectmode] eq "single" && [llength $selected] > 1 } {
				set selected [lindex $selected end]
			}
			
			
			foreach sel $selected {
				set sel_idx [lsearch -exact $values $sel]
				if { $sel_idx > -1 } { 
					$widget selection set $sel_idx 
					$widget see $sel_idx
				}
			}
		}
		
		# Adapted from Johanna's MimojaCafe skin code, attributed to Barney.
		# Return the canvas IDs of all created items.
		proc rounded_rectangle { x0 y0 x1 y1 radius colour disabled tags } {
			set can [dui canvas]
			set ids {}
			set x0 [rescale_x_skin $x0] 
			set y0 [rescale_y_skin $y0] 
			set x1 [rescale_x_skin $x1] 
			set y1 [rescale_y_skin $y1]
			
			lappend ids [$can create oval $x0 $y0 [expr $x0 + $radius] [expr $y0 + $radius] -fill $colour -disabledfill $disabled \
				-outline $colour -disabledoutline $disabled -width 0 -tags $tags -state "hidden"]
			lappend ids [$can create oval [expr $x1-$radius] $y0 $x1 [expr $y0 + $radius] -fill $colour -disabledfill $disabled \
				-outline $colour -disabledoutline $disabled -width 0 -tags $tags -state "hidden"]
			lappend ids [$can create oval $x0 [expr $y1-$radius] [expr $x0+$radius] $y1 -fill $colour -disabledfill $disabled \
				-outline $colour -disabledoutline $disabled -width 0 -tags $tags -state "hidden"]
			lappend ids [$can create oval [expr $x1-$radius] [expr $y1-$radius] $x1 $y1 -fill $colour -disabledfill $disabled \
				-outline $colour -disabledoutline $disabled -width 0 -tags $tags -state "hidden"]
			lappend ids [$can create rectangle [expr $x0 + ($radius/2.0)] $y0 [expr $x1-($radius/2.0)] $y1 -fill $colour \
				-disabledfill $disabled -disabledoutline $disabled -outline $colour -width 0 -tags $tags -state "hidden"]
			lappend ids [$can create rectangle $x0 [expr $y0 + ($radius/2.0)] $x1 [expr $y1-($radius/2.0)] -fill $colour \
				-disabledfill $disabled -disabledoutline $disabled -outline $colour -width 0 -tags $tags -state "hidden"]
			return $ids
		}
		
		# Inspired on Barney's rounded_rectangle, mimic DSx buttons showing a button outline without a fill.
		# Return the canvas IDs of all created items.
		proc rounded_rectangle_outline { x0 y0 x1 y1 arc_offset colour disabled width tags } {
			set can [dui canvas]
			set ids {}
			set x0 [rescale_x_skin $x0] 
			set y0 [rescale_y_skin $y0] 
			set x1 [rescale_x_skin $x1] 
			set y1 [rescale_y_skin $y1]
		
			lappends ids [$can create arc [expr $x0] [expr $y0+$arc_offset] [expr $x0+$arc_offset] [expr $y0] -style arc -outline $colour \
				-width [expr $width-1] -tags $tags -start 90 -disabledoutline $disabled -state "hidden"]
			lappend ids [$can create arc [expr $x0] [expr $y1-$arc_offset] [expr $x0+$arc_offset] [expr $y1] -style arc -outline $colour \
				-width [expr $width-1] -tags $tags -start 180 -disabledoutline $disabled -state "hidden"]
			lappend ids [$can create arc [expr $x1-$arc_offset] [expr $y0] [expr $x1] [expr $y0+$arc_offset] -style arc -outline $colour \
				-width [expr $width-1] -tags $tags -start 0 -disabledoutline $disabled -state "hidden"]
			lappend ids [$can create arc [expr $x1-$arc_offset] [expr $y1] [expr $x1] [expr $y1-$arc_offset] -style arc -outline $colour \
				-width [expr $width-1] -tags $tags -start -90 -disabledoutline $disabled -state "hidden"]
			
			lappend ids [$can create line [expr $x0+$arc_offset/2] [expr $y0] [expr $x1-$arc_offset/2] [expr $y0] -fill $colour \
				-width $width -tags $tags -disabledfill $disabled -state "hidden"]
			lappend ids[$can create line [expr $x1] [expr $y0+$arc_offset/2] [expr $x1] [expr $y1-$arc_offset/2] -fill $colour \
				-width $width -tags $tags -disabledfill $disabled -state "hidden"]
			lappend ids[$can create line [expr $x0+$arc_offset/2] [expr $y1] [expr $x1-$arc_offset/2] [expr $y1] -fill $colour \
				-width $width -tags $tags -disabledfill $disabled -state "hidden"]
			lappend ids[$can create line [expr $x0] [expr $y0+$arc_offset/2] [expr $x0] [expr $y1-$arc_offset/2] -fill $colour \
				-width $width -tags $tags -disabledfill $disabled -state "hidden"]
			return $ids
		}
		
		# Moves the slider in the dscale to the provided position. This has 2 modes:
		#	1) If slider_coord is specified, changes the value of variable $varname according to the relative
		#		position of the slider within the scale, given by slider_coord.
		#	2) If slider_coord is not specified, uses the value of $varname and moves the slider to match the value.
		# Needs 'args' at the end because this is called from a 'trace add variable'.
		proc dscale_moveto { page dscale_tag varname from to {digits 0} {slider_coord {}} args } {			
			set can [dui canvas]
			set slider [dui item get $page "${dscale_tag}-crc"]
			if { $slider eq "" } return
			lassign [$can bbox $slider] sx0 sy0 sx1 sy1
			# Return if the page is not currently visible
			if {$sx0 eq "" } return		
			
			set back [dui item get $page "${dscale_tag}-bck"]
			set front [dui item get $page "${dscale_tag}-frn"]
			if { $slider eq "" || $back eq "" || $front eq "" } {
				return
			}
			
			lassign [$can coords $back] bx0 by0 bx1 by1
			lassign [$can coords $front] fx0 fy0 fx1 fy1
				
			set swidth [expr {$sx1-$sx0}]
			set sheight [expr {$sy1-$sy0}]
			if { ($bx1 - $bx0) >= ($by1 -$by0) } {
				set orient h
			} else {
				set orient v
			}
			
			set varvalue ""
			if { $slider_coord eq "" && $varname ne "" } {
				if { [info exists $varname] } {
					set varvalue [subst \$$varname] 
				} else {
					set varvalue $from
					set $varname $varvalue
				}
				if { [string is double -strict $varvalue] } {
					if { $varvalue <= $from } {
						switch $orient h {set slider_coord $bx0} v {set slider_coord $by0}
					} elseif { $varvalue >= $to } {
						switch $orient h {set slider_coord [expr {$bx1-$swidth/2}]} v {set slider_coord $by1}
					} elseif { $orient eq "h" } {
						set slider_coord [expr {($bx0+$swidth/2)+(($bx1-$swidth/2)-($bx0+$swidth/2))*$varvalue/($to-$from)}]
					} else {
						set slider_coord [expr {$by0+($by1-$by0)*$varvalue/($to-$from)}]
					}
				} else {
					return
				}
			}
			
			if { $orient eq "h" } {
				# Horizontal
				if { ($slider_coord-$swidth/2) <= $bx0 } {
					$can coords $front $bx0 $by0 [expr {$bx0+$swidth/2}] $by1
					$can coords $slider $bx0 $sy0 [expr {$bx0+$swidth}] $sy1
					if { $varvalue eq "" } { set $varname $from }
					#set dx [expr {$bx0-$sx0}] 
				} elseif { $slider_coord >= ($bx1-$swidth/2) } {
					$can coords $front $bx0 $by0 [expr {$bx1-$swidth/2}] $by1
					$can coords $slider [expr {$bx1-$swidth}] $sy0 $bx1 $sy1
					if { $varvalue eq "" } { set $varname $to }
					#set dx [expr {$sx1-$bx1}]
				} else {
					$can coords $front $bx0 $by0 $slider_coord $by1
					$can move $slider [expr {$slider_coord-($swidth/2)-$sx0}] 0
					if { $varvalue eq "" } {
						set $varname [format "%.${digits}f" [expr {$from+\
							($to-$from)*(($slider_coord-$swidth/2-$bx0)/($bx1-$swidth-$bx0))}]]
					}
				} 
			} else {
				if { $slider_coord <= $bx0 } {
					$can coords $front $bx0 $by0 [expr {$bx0+1}] $by1
					$can coords $slider $bx0 $sy0 [expr {$bx0+$swidth}] $sy1
					if { $varvalue eq "" } { set $varname $from }
					#set dx [expr {$bx0-$sx0}] 
				} elseif { $slider_coord >= [expr {$bx1-$swidth}]} {
					$can coords $front $bx0 $by0 $bx1 $by1
					$can coords $slider [expr {$bx1-$swidth}] $sy0 $bx1 $sy1
					if { $varvalue eq "" } { set $varname $to }
					#set dx [expr {$sx1-$bx1}]
				} else {
					$can coords $front $bx0 $by0 [expr {$slider_coord+$swidth/2}] $by1
					$can move $slider [expr {$slider_coord-$sx0}] 0
					if { $varvalue eq "" } { 
						set $varname [format "%.${digits}f" [expr {($to-$from)*($slider_coord-$bx0)/($bx1-$swidth-$bx0}]]					
					}
				} 
			}
		}
		
		proc change_var_in_range { var change min max {n_decimals {}} } {
			set newvalue [expr {[ifexists $var 0]+$change}]
			if { $newvalue < $min } {
				set newvalue $min
			} elseif { $newvalue > $max } {
				set newvalue $max
			} 
			if { $n_decimals ne "" } {
				set newvalue [format "%.${n_decimals}f" $newvalue]
			}
			set $var $newvalue
		}
		
		# Computes the anchor point coordinates with respect to the provided bounding box coordinates, returns a list 
		#	with 2 elements. 
		# Has more valid values than usual anchor: n, ne, nw, e, en, ew, s, sw, se, w, wn, ws.
		proc anchor_inside_box { anchor x0 y0 x1 y1 {xoffset 0} {yoffset 0} } {
			if { $anchor eq "center" } {
				set x [expr {$x0+int(($x1-$x0)/2)+$xoffset}]
				set y [expr {$y0+int(($y1-$y0)/2)+$yoffset}]
				return [list $x $y]
			}
			
			set anchor1 [string range $anchor 0 0]
			set anchor2 [string range $anchor 1 1]
			
			if { $anchor1 eq "w" || $anchor1 eq ""} {
				set x [expr {$x0+$xoffset}]
				
				if { $anchor2 eq "n" } {
					set y [expr {$y0+$yoffset}]
				} elseif { $anchor2 eq "s" } {
					set y [expr {$y1+$yoffset}]
				} else {
					set y [expr {$y0+int(($y1-$y0)/2)+$yoffset}]
				}
			} elseif { $anchor1 eq "e" } {
				set x [expr {$x1+$xoffset}]
				
				if { $anchor2 eq "n" } {
					set y [expr {$y0+$yoffset}]
				} elseif { $anchor2 eq "s" } {
					set y [expr {$y1+$yoffset}]
				} else {
					set y [expr {$y0+int(($y1-$y0)/2)+$yoffset}]
				}			
			} elseif { $anchor1 eq "n" } {
				set y [expr {$y0+$yoffset}]
				
				if { $anchor2 eq "w" } {
					set x [expr {$x0+$xoffset}]
				} elseif { $anchor2 eq "e" } {
					set x [expr {$x1+$xoffset}]
				} else {
					set x [expr {$x0+int(($x1-$x0)/2)+$xoffset}]
				}
			} elseif { $anchor1 eq "s" } {
				set y [expr {$y1+$yoffset}]
				
				if { $anchor2 eq "w" } {
					set x [expr {$x0+$xoffset}]
				} elseif { $anchor2 eq "e" } {
					set x [expr {$x1+$xoffset}]
				} else {
					set x [expr {$x0+int(($x1-$x0)/2)+$xoffset}]
				}
			} else {
				return [list "" ""]
			}
			
			return [list $x $y]
		}
	
		# Given a box reference coordinates {x0 y0} and dimensions {width height}, returns a 4-element list with the new 
		#	"nw" and "se" coordinates corresponding to anchoring the box to {x0 y0} with the 'anchor' specification.
		# This works like setting canvas text coordinates and an anchor point, but for boxes like buttons.
		# Optional x and y-offsets can be defined to move the targets once they have been computed.
		# Anchor valid values are center, n, ne, nw, s, se, sw, w, e
		proc anchor_coords { anchor x y width height {xoffset 0} {yoffset 0} } {
			if { $anchor eq "center" } {
				set x0 [expr {$x-$width/2+$xoffset}]
				set y0 [expr {$y-$height/2+$yoffset}]
				set x1 [expr {$x+$width/2+$xoffset}]
				set y1 [expr {$y+$height/2+$yoffset}]
				return [list $x0 $y0 $x1 $y1]
			}
			
			set anchor1 [string range $anchor 0 0]
			set anchor2 [string range $anchor 1 1]
			
			if { $anchor1 eq "w" && $anchor2 eq ""} {
				set x0 [expr {$x+$xoffset}]
				set y0 [expr {$y-$height/2+$yoffset}]
			} elseif { $anchor1 eq "e" && $anchor2 eq "" } {
				set x0 [expr {$x-$width+$xoffset}]
				set y0 [expr {$y-$height/2+$yoffset}]
			} elseif { $anchor1 eq "n" } {
				set y0 [expr {$y+$yoffset}]
				
				if { $anchor2 eq "w" } {
					set x0 [expr {$x+$xoffset}]
				} elseif { $anchor2 eq "e" } {
					set x0 [expr {$x-$width+$xoffset}]
				} elseif { $anchor2 eq "" }  {
					set x0 [expr {$x-$width/2+$xoffset}]
				}
			} elseif { $anchor1 eq "s" } {
				set y0 [expr {$y-$height+$yoffset}]
				
				if { $anchor2 eq "w" } {
					set x0 [expr {$x+$xoffset}]
				} elseif { $anchor2 eq "e" } {
					set x0 [expr {$x-$width+$xoffset}]
				} elseif { $anchor2 eq "" }  {
					set x0 [expr {$x-$width/2+$xoffset}]
				}
			} else {
				return [list "" "" "" ""]
			}

			set x1 [expr {$x0+$width+$xoffset}]
			set y1 [expr {$y0+$height+$yoffset}]
			return [list $x0 $y0 $x1 $y1]
		}
	}

	### ADD SUBENSEMBLE: COMMANDS TO CREATE CANVAS ITEMS AND WIDGETS AND ADD THEM TO THE CANVAS ###
	namespace eval add {
		namespace export *
		namespace ensemble create
		
		# Not needed at the moment. For basic operation we don't need to keep the dscale state anywhere. The
		# 	calls in the bind events are enough, as they include all the info in their arguments.
		# This may be needed in the future if we want client code to invoke methods on dscales easilyt.
#		::variable dscales
#		array set dscales {}
		
		proc theme { args } {
			dui theme add {*}$args
		}
		
		proc aspect { args } {
			dui aspect set {*}$args
		}
		
		proc symbol { args } {
			dui symbol set {*}$args
		}
		
		proc page { args } {
			dui page add {*}$args
		}

		proc font { args } {
			dui font load {*}$args
		}
		
		proc font_dirs { args } {
			dui font add_dirs {*}$args
		}
		
		proc image_dirs { args } {
			dui item add_image_dirs {*}$args 
		}
		
		# Add text items to the canvas. Returns the list of all added tags (one per page).
		#
		# Named options:
		#	-tags a label that allows to access the created canvas items
		#	-style to apply the default aspects of the provided style
		#	-aspect_type to query default aspects for type different than "text"
		#	All others passed through to the 'canvas create text' command
		proc text { pages x y args } {
			global text_cnt
			set x [rescale_x_skin $x]
			set y [rescale_y_skin $y]
			
			set tags [dui::args::process_tags_and_var $pages text ""]
			set main_tag [lindex $tags 0]
	
			set style [dui::args::get_option -style "" 1]		
			dui::args::process_aspects text $style "" "pos"		
			dui::args::process_font text $style
					
			set width [dui::args::get_option -width {} 1]
			if { $width ne "" } {
				set width [rescale_x_skin $width]
				dui::args::add_option_if_not_exists -width $width
			}
			
			try {
				set id [[dui canvas] create text $x $y -state hidden {*}$args]
			} on error err {
				set msg "can't add text '$main_tag' in page(s) '$pages' to canvas: $err"
				msg -ERROR [namespace current] $msg
				error $msg
				return
			}
			
			set ns [dui page get_namespace $pages]
			if { $ns ne "" } {
				set ${ns}::widgets($main_tag) $id
			}
			dui item add_to_pages $pages $main_tag
			msg -INFO [namespace current] text "'$main_tag' to page(s) '$pages' with args '$args'"
			return $id
		}
		
		# Adds text to a page that is the result of evaluating some code. The text shown is updated automatically whenever
		#	the underlying code evaluates to a different text.
		# Named options:
		#  -textvariable Tcl code. Not the name of a variable, but code to be evaluated. So, to refer to global variable 'x' 
		#		you must use '{$::x}', not '::x'.
		# 		If -textvariable gives a plain name instead of code to be evaluted (no brackets, parenthesis, ::, etc.) 
		#		and the first page in 'pages' is a namespace, uses {$::dui::pages::<page>::data(<textvariable>)}. 
		#		Also in this case, if -tags is not specified, uses the textvariable name as tag.
		# All others passed through to the 'dui add text' command
		proc variable { pages x y args } {
			global variable_labels
			
			set tags [dui::args::process_tags_and_var $pages "variable" -textvariable]
			set main_tag [lindex $tags 0]
			set varcmd [dui::args::get_option -textvariable "" 1]
	
			set id [dui add text $pages $x $y {*}$args]
			
			if { $varcmd ne "" } {
				foreach page $pages {
					msg [namespace current] variable "with tag '$main_tag' to page(s) '$page'"
					lappend variable_labels($page) [list $main_tag $varcmd]
				}
			}
			
			return $id
		}
		
		
		proc symbol { pages x y args } {
			set symbol [dui::args::get_option -symbol "" 1]
			if { $symbol eq "" } {
				set symbol [dui::args::get_option -text "" 1]
			}
			if { $symbol eq "" } {
				return
			}
			
			set symbol [dui symbol get $symbol]
			dui::args::add_option_if_not_exists -font_family $dui::symbol::font_filename
			
			dui::args::add_option_if_not_exists -aspect_type symbol
			
			return [dui add text $pages $x $y -text $symbol {*}$args]
		}
		
		# Add button items to the canvas. Returns the list of all added tags (one per page).
		#
		# Defaults to an "invisible" button, i.e. a rectangular "clickable" area. Specify the -style or -shape argument
		#	to generate a visible button instead.
		# Invisible buttons can show their clickable area while debugging, by setting namespace variable debug_buttons=1.
		#	In that case, the outline color is given by aspect 'button.debug_outline' (or black if undefined).
		# Generates up to 3 canvas items/tags per page. Default one is named upon the provided -tags and corresponds to 
		#	the invisible "clickable" area. If a visible button is generated, it its assigned tag "<tag>.button".
		#	If a label is specified, it gets tag "<tag>.label". Returns the list of all added tags.
		#
		# Named options:  
		#	If the first two arguments are integer numbers, they are interpreted as the absolute bottom-right coordinates
		#		of the button. If not provided, arguments -bwidth and -bheight are used.
		#	-tags a label that allows to access the created canvas items
		#	-bwidth to set the width of the button. If this is provided, x1 is ignored and width is added to x0 instead.
		#	-bheight to set the height of the button. If this is provided, y1 is ignored and height is added to y0 instead.
		#		Normally bwidth and bheight are used when defining a button style in the theme aspects, so that buttons
		#		using a given style always have the same size.
		#	-shape any of 'rect', 'rounded' (Barney/MimojaCafe style) or 'outline' (DSx style)
		#	-style to apply the default aspects of the provided style
		#	-command tcl code to be run when the button is clicked
		#	-label label text, in case a label is to be shown inside the button
		#	-labelvariable, to use a variable as label text
		#	-label_pos a list with 2 elements between 0 and 1 that specify the x and y percentages where to position
		#		the label inside the button
		#	-label_* (-label_fill -label_outline etc.) are passed through to 'dui add text' or 'dui add variable'
		#	-symbol to add a Fontawesome symbol/icon to the button, on position -symbol_pos, and using option values
		#		given in -symbol_* that are passed through to 'dui add symbol'
		#	-radius for rounded rectangles, and -arc_offset for rounded outline rectangles
		#	All others passed through to the respective visible button creation command.
		proc button { pages x y args } {
			set debug_buttons $::dui::debug_buttons
			set can [dui canvas]
			set ns [dui page get_namespace $pages]
			
			set cmd [dui::args::get_option -command {} 1]
			set style [dui::args::get_option -style "" 1]
			dui::args::process_aspects button $style
	
			set x1 0
			set y1 0
			set bwidth [dui::args::get_option -bwidth "" 1]
			if { $bwidth ne "" } {
				set x1 [expr {$x+$bwidth}]
			}
			set bheight [dui::args::get_option -bheight "" 1]
			if { $bheight ne "" } {
				set y1 [expr {$y+$bheight}]
			}		 
			
			if { [llength $args] > 0 && [string is entier [lindex $args 0]] } {
				if { $x1 <= 0 } {
					set x1 [lindex $args 0]
				}
				set args [lrange $args 1 end]
			}
			if { [llength $args] > 0 && [string is entier [lindex $args 0]] } {
				if { $y1 <= 0 } {
					set y1 [lindex $args 0]
				}
				set args [lrange $args 1 end]
			}
			if { $x1 <= 0 } {
				set x1 [expr {$x+100}]
			}
			if { $y1 <= 0 } {
				set y1 [expr {$y+100}]
			}
			
			set anchor [dui::args::get_option -anchor nw 1]
			if { $anchor ne "nw" } {
				lassign [dui::item::anchor_coords $anchor $x $y [expr {$x1-$x}] [expr {$y1-$y}]] x y x1 y1
			}
			
			set rx [rescale_x_skin $x]
			set rx1 [rescale_x_skin $x1]
			set ry [rescale_y_skin $y]
			set ry1 [rescale_y_skin $y1]
					
			set tags [dui::args::process_tags_and_var $pages button {} 1]
			set main_tag [lindex $tags 0]
			set button_tags [list ${main_tag}-btn {*}[lrange $tags 1 end]]
			
			# Note this cannot be processed by 'dui item process_label' as this one processes the positioning of the
			#	label differently (inside), also we need to extract label options from the args before painting the 
			#	background button (as $args is passed to the painting proc) but not create the label until after that
			#	button has been painted.
			set label [dui::args::get_option -label "" 1]
			set labelvar [dui::args::get_option -labelvariable "" 1]
			if { $label ne "" || $labelvar ne "" } {
				set label_tags [list ${main_tag}-lbl {*}[lrange $tags 1 end]]	
				set label_args [dui::args::extract_prefixed -label_]
				
				foreach aspect [dui aspect list -type [list button_label text] -style $style] {
					dui::args::add_option_if_not_exists -$aspect [dui aspect get button_label $aspect -style $style \
						-default {} -default_type text] label_args
				}
				
				set label_pos [dui::args::get_option -pos {0.5 0.5} 1 label_args]
				set xlabel [expr {$x+int($x1-$x)*[lindex $label_pos 0]}]
				set ylabel [expr {$y+int($y1-$y)*[lindex $label_pos 1]}]
			}
			
			# Process symbol
			set symbol [dui::args::get_option -symbol "" 1]
			if { $symbol ne "" } {
				set symbol_tags [list ${main_tag}-sym {*}[lrange $tags 1 end]]	
				set symbol_args [dui::args::extract_prefixed -symbol_]
				set symbol_pos [dui::args::get_option -pos [dui aspect get button_symbol pos -style $style -default {0.5 0.5} \
					-default_type symbol] 1 symbol_args]
				set xsymbol [expr {$x+int($x1-$x)*[lindex $symbol_pos 0]}]
				set ysymbol [expr {$y+int($y1-$y)*[lindex $symbol_pos 1]}]
			}
					
			# As soon as the rect has a non-zero width (or maybe an outline or fill?), its "clickable" area becomes only
			#	the border, so if a visible rectangular button is needed, we have to add an invisible clickable rect on 
			#	top of it.
			set ids {}
			if { $style eq "" && ![dui::args::has_option -shape]} {
				if { $debug_buttons == 1 } {
					set width 1
					set outline [dui aspect get button debug_outline -style $style -default "black"]
				} else {
					set width 0
				}
	
				if { $width > 0 } {
					set ids [$can create rect $rx $ry $rx1 $ry1 -outline $outline -width $width -tags $button_tags \
						-state hidden]
				}
			} else {		
				dui::args::remove_option -debug_outline
				set shape [dui::args::get_option -shape [dui aspect get button shape -style $style -default rect] 1]
				
				if { $shape eq "round" } {
					set fill [dui::args::get_option -fill [dui aspect get button fill -style $style]]
					set disabledfill [dui::args::get_option -disabledfill [dui aspect get button disabledfill -style $style]]
					set radius [dui::args::get_option -radius [dui aspect get button radius -style $style -default 40]]
					
					set ids [dui item rounded_rectangle $x $y $x1 $y1 $radius $fill $disabledfill $button_tags]
				} elseif { $shape eq "outline" } {
					set outline [dui::args::get_option -outline [dui aspect get button outline -style $style]]
					set disabledoutline [dui::args::get_option -disabledoutline [dui aspect get button disabledoutline -style $style]]
					set arc_offset [dui::args::get_option -arc_offset [dui aspect get button arc_offset -style $style -default 50]]
					set width [dui::args::get_option -width [dui aspect get button width -style $style -default 3]]
					
					set ids [dui item rounded_rectangle_outline $x $y $x1 $y1 $arc_offset $outline $disabledoutline \
						$width $button_tags]
				} else {
					set ids [$can create rect $rx $ry $rx1 $ry1 -tags $button_tags -state hidden {*}$args]
				}
			}
			if { $ids ne "" && $ns ne "" } {
				set ${ns}::widgets([lindex $button_tags 0]) $ids
				dui item add_to_pages $pages [lindex $button_tags 0]
			}					
			
			if { $label ne "" } {
				dui add text $pages $xlabel $ylabel -text $label -tags $label_tags -aspect_type button_label \
					-style $style {*}$label_args
			} elseif { $labelvar ne "" } {
				dui add variable $pages $xlabel $ylabel -textvariable $labelvar -tags $label_tags \
					-aspect_type button_label -style $style {*}$label_args 
			}
			
			if { $symbol ne "" } {
				dui add symbol $pages $xsymbol $ysymbol -text $symbol -tags $symbol_tags -aspect_type button_symbol \
					-style $style {*}$symbol_args
			}
			
			# Clickable rect
			set id [$can create rect $rx $ry $rx1 $ry1 -fill {} -outline black -width 0 -tags $tags -state hidden]
			if { $cmd eq "" } {
				msg -WARN [namespace current] button "button '$main_tag' does not have a command"
			} else {
				set ns [dui page get_namespace [lindex $pages 0]] 
				#set first_page [lindex $pages 0]
				if { $ns ne "" } { 
					if { [string is wordchar $cmd] && [info proc ${ns}::$cmd] ne "" } {
						set cmd ${ns}::$cmd
					}				
					regsub -all {%NS} $cmd $ns cmd
				}
				regsub {%x0} $cmd $rx cmd
				regsub {%x1} $cmd $rx1 cmd
				regsub {%y0} $cmd $ry cmd
				regsub {%y1} $cmd $ry1 cmd
			}
			$can bind $main_tag [platform_button_press] $cmd
			
			msg -INFO [namespace current] button "'$main_tag' to page(s) '$pages' with args '$args'"
			if { $ns ne "" } {
				set ${ns}::widgets($main_tag) $id
			}								
			dui item add_to_pages $pages $main_tag
			return $id
		}

		# Adds canvas items (arcs, ovals, lines, etc.) to pages
		proc canvas_item { type pages args } {
			set can [dui canvas]
			
			set coords {}
			set i 0
			while { [llength $args] > 0 && [string is entier [lindex $args 0]] } {
				if { $i % 2 == 0 } {
					set coord [rescale_x_skin [lindex $args 0]]
				} else {
					set coord [rescale_y_skin [lindex $args 0]]
				}
				lappend coords $coord 
				set args [lrange $args 1 end]
				incr i
			}
					
			set tags [dui::args::process_tags_and_var $pages $type ""]
			set main_tag [lindex $tags 0]
	
			set style [dui::args::get_option -style "" 1]
			dui::args::process_aspects $type $style "" "pos"
					
			try {
				set w [[dui canvas] create $type {*}$coords -state hidden {*}$args]
			} on error err {
				set msg "can't add $type '$main_tag' in page(s) '$pages' to canvas: $err"
				msg -ERROR [namespace current] $msg
				error $msg
				return
			}

			set ns [dui page get_namespace $pages]
			if { $ns ne "" } {
				set ${ns}::widgets($main_tag) $w
			}
			dui item add_to_pages $pages $main_tag
			
			msg -INFO [namespace current] canvas_item "$type '$main_tag' to page(s) '$pages' with args '$args'"
			return $main_tag
		}

		# Extra named options:
		#	-type The type of image, defaults to 'photo'
		#	-canvas_* Options to be passed through to the canvas create command
		proc image { pages x y filename args } {
			set can [dui canvas]

			if { $filename eq "" } {
				set msg "An image filename is required"
				msg -ERROR [namespace current] image $msg
				error $msg
				return
			} 
			if { [file dirname $filename] eq "." } {
				foreach dir [dui item image_dirs] {
					set full_fn "$dir/${::screen_size_width}x${::screen_size_height}/$filename"
					if { [file exists $full_fn] } {
						set filename $full_fn
						break
					}
				}
			}
			if { ![file exists $filename] } {
				# TBD: Do resizing if the 2560x1600 image file exists, as in background images?
				set msg "Image filename '$filename' not found"
				msg -ERROR [namespace current] image $msg
				error $msg
				return	
			}

			set x [rescale_x_skin $x]
			set y [rescale_y_skin $y]
			set tags [dui::args::process_tags_and_var $pages image ""]
			set main_tag [lindex $tags 0]
			set style [dui::args::get_option -style "" 1]
			dui::args::process_aspects image $style ""
			set type [dui::args::get_option -type photo 1]
			
			# Options that are to be passed to the 'canvas create' command instead of the image creation command.
			# Using this we can modify the canvas image anchor or other options.
			set canvas_args [dui::args::extract_prefixed -canvas_]
			dui::args::add_option_if_not_exists -anchor nw canvas_args
			
			dui::args::remove_option -tags
			try {
				set w [::image create $type $main_tag -file "$filename" {*}$args]
			} on error err {
				set msg "can't create image '$main_tag' in page(s) '$pages': $err"
				msg -ERROR [namespace current] $msg
				error $msg
				return	
			}
			
			try {
				[dui canvas] create image $x $y -image $main_tag -tags $tags -state hidden {*}$canvas_args
			} on error err {
				set msg "can't add image '$main_tag' in page(s) '$pages' to canvas: $err"
				msg -ERROR [namespace current] $msg
				error $msg
				return
			}
	
			 
			set ns [dui page get_namespace $pages]
			if { $ns ne "" } {
				set ${ns}::widgets($main_tag) $w
			}			
			dui item add_to_pages $pages $main_tag
			
			msg -INFO [namespace current] image "add '$main_tag' to page(s) '$pages' with args '$args'"			
			return $main_tag
		}
				
		# Named options:
		#	-tags
		#	-canvas_anchor, canvas_width, canvas_height are passed to the canvas create command.
		#   -label or -labelvariable
		#	-label_pos can be a pair of absolute coordinates; a pair of relative coordinates with respect to the widget
		#		top-left coordinates {x y}, if they start by "-" or "+"; or a position marker and optional positive or
		#		negative x and y offsets. The marker and offsets are used in a relocate_text_wrt call on the page show 
		#		event, so that it is repositioned dynamically for widgets whose size is defined in characters instead
		#		of pixels.
		#	-label_* passed through to 'add text'
		#	-tclcode code to be evaluated after the widget is created, to allow configuring the widget. It is evaluated
		#		in a global context, and performs the following substitutions:
		#			%W the widget pathname
		#			%NS the page namespace, if it has one, o/w an empty string
		proc widget { type pages x y args } {
			set can [dui canvas]
			set rx [rescale_x_skin $x]
			set ry [rescale_y_skin $y]
			
			set ns [dui page get_namespace $pages]
			set tags [dui::args::process_tags_and_var $pages $type "" 0 args 0]
			set main_tag [lindex $tags 0]
			
			set widget $can.[lindex $pages 0]-$main_tag
			if { [info exists ::$widget] } {
				set msg "$type widget with name '$widget' already exists"
				msg -ERROR [namespace current] $msg
				error $msg
				return
			}
			
			set style [dui::args::get_option -style "" 1]
			foreach a [dui aspect list -type $type -style $style] {
				#msg [namespace current] widget "type=$type, style=$style, a=$a"
				dui::args::add_option_if_not_exists -$a [dui aspect get $type $a -style $style]
			}
	
			dui::args::process_font $type $style
	
			# Options that are to be passed to the 'canvas create' command instead of the widget creation command.
			# Using this we can modify the canvas item anchor, or use pixel widths & heights for text widgets like
			#	entries or listboxes.
			set canvas_args [dui::args::extract_prefixed -canvas_]
			dui::args::add_option_if_not_exists -anchor nw canvas_args
			if { [dui::args::has_option -width canvas_args] } {
				dui::args::add_option_if_not_exists -width [rescale_x_skin [dui::args::get_option -width 0 1 canvas_args]] canvas_args 
			}
			if { [dui::args::has_option -height canvas_args] } {
				dui::args::add_option_if_not_exists -height [rescale_y_skin [dui::args::get_option -height 0 1 canvas_args]] canvas_args 
			}				
			if { $type eq "scrollbar" } {
				# From the original add_de1_widget, but WHY this?
				dui::args::add_option_if_not_exists -height 245 canvas_args
			}
			
			dui::args::process_label $pages $x $y $type $style
			
			dui::args::remove_option -tags
			set tclcode [dui::args::get_option -tclcode "" 1]
			try {
				::$type $widget {*}$args
			} on error err {
				set msg "can't create $type widget '$widget' on page(s) '$pages': $err"
				msg -ERROR [namespace current] $msg
				error $msg
				return			
			}
			
			# BLT on android has non standard defaults, so we overrride them here, sending them back to documented defaults
			if {$type eq "graph" && ($::android == 1 || $::undroid == 1)} {
				$widget grid configure -dashes "" -color #DDDDDD -hide 0 -minor 1 
				$widget configure -borderwidth 0
				#$widget grid configure -hide 0
			}
		
			# Additional code to run when creating this widget, such as chart configuration instructions
			if { $tclcode ne "" } {
				regsub -all {%W} $tclcode $widget tclcode
				regsub -all {%NS} $tclcode $ns tclcode
				try {  
					# It should be safer to run 'uplevel #0 $tclcode', but inherited code would break, so at the moment
					# 	we eval in the current context (but it's unsafe, may redefine local variables like $x, $pages, etc.)
					#uplevel #0 $tclcode
					eval $tclcode
				} on error err {
					set msg "error evaluating tclcode for $type widget '$widget' \{ $tclcode \}: $err"
					msg -ERROR [namespace current] $msg 
					error $msg
					return
				}
			}
			
			try {
				set windowname [$can create window  $rx $ry -window $widget -tags $tags -state hidden {*}$canvas_args]
			} on error err {
				set msg "can't add $type widget '$widget' in page(s) '$pages' to canvas: $err"
				msg -ERROR [namespace current] $msg
				error $msg
				return
			}
				
			# EB: Maintain this? I don't find any use of this array in the app code
			#set ::tclwindows($widget) [list $x $y]
			msg -INFO [namespace current] widget "$type '$main_tag' to page(s) '$pages' with args '$args'"

			if { $ns ne "" } {
				set "${ns}::widgets($main_tag)" $widget
			}			
			dui item add_to_pages $pages $main_tag
			return $widget
		}
		
		# Add a text entry box. Adds validation and full page editor call on top of add_widget.
		#
		# Named options:
		#  -data_type if 'numeric' and -vcmd is undefined, adds validation based on the following parameters:
		#  -n_decimals number of decimals allowed. Defaults to 0 if undefined.
		#  -min minimum value accepted
		#  -max maximum value accepted
		#  -small_increment small increment used on clicker controls. Not used by default, but is passed to page editors
		#		if the -editor_page option is specified 
		#  -big_increment big increment used on clicker controls. Not used by default, but is passed to page editors
		#		if the -editor_page option is specified
		#  -default Default value passed to the page editor if the -editor_page option is specified
		#  -trim if 1, trims leading and trailing whitespace after editing the value. Defaults to the value of 
		#		$dui::trim_entries.
		#  -editor_page A page name that serves as a full page editor for the value, or "1" to use the default page
		#		editor if it defined for the -data_type. The first argument of that page must be the fully qualified name 
		#		of the variable that holds the value.
		proc entry { pages x y args } {
			set tags [dui::args::process_tags_and_var $pages entry -textvariable 1]
			set main_tag [lindex $tags 0]
			
	#		set style [dui::args::get_option -style "" 0]
			
			# Data type and validation
			set data_type [dui::args::get_option -data_type "text" 1]
			set n_decimals [dui::args::get_option -n_decimals 0 1]
			set trim  [dui::args::get_option -trim $::dui::trim_entries 1]
			set editor_page [dui::args::get_option -editor_page $::dui::use_editor_pages 1]
			set editor_page_title [dui::args::get_option -editor_page_title "" 1]
			foreach fn {min max default small_increment big_increment} {
				set $fn [dui::args::get_option -$fn "" 1]
			}
			
			set width [dui::args::get_option -width "" 1]
			if { $width ne "" } {
				dui::args::add_option_if_not_exists -width [expr {int($width * $::globals(entry_length_multiplier))}]
			}
			
			if { ![dui::args::has_option -vcmd] } {
				set vcmd ""
				if { $data_type eq "numeric" } {
					set vcmd [list ::dui::validate_numeric %P $n_decimals $min $max]
				}
				
				if { $vcmd ne "" } {
					dui::args::add_option_if_not_exists -vcmd $vcmd
					dui::args::add_option_if_not_exists -validate key
				}
			}
					
			set widget [dui add widget entry $pages $x $y {*}$args]
		
			# Default actions on leaving a text entry: Trim text, format if needed, and hide_android_keyboard
			bind $widget <Return> { dui hide_android_keyboard ; focus [tk_focusNext %W] }
			
			set textvariable [dui::args::get_option -textvariable]
			if { $textvariable ne "" } {
				set leave_cmd ""
				if { $data_type in "text long_text category" } {
					if { [string is true $trim] } {
						append leave_cmd "set $textvariable \[string trim \$$textvariable\];"
					}
				} elseif { $data_type eq "numeric" } {
					append leave_cmd "if \{\$$textvariable ne \{\} \} \{ 
						set $textvariable \[format \"%%.${n_decimals}f\" \$$textvariable\] 
					\};"
				} 
				append leave_cmd "dui hide_android_keyboard;"
				bind $widget <Leave> $leave_cmd
			}
			
			# Invoke editor page on double tap (maybe other editors in the future, e.g. a date editor)
			if { $editor_page ne "" && ![string is false $editor_page] && $textvariable ne ""} {
				if { [string is true $editor_page] && $data_type eq "numeric" } {
					set editor_page "dui_number_editor" 
				} 
	
				set editor_cmd [list dui page show_when_off $editor_page $textvariable -n_decimals $n_decimals -min $min \
					-max $max -default $default -small_increment $small_increment -big_increment $big_increment \
					-page_title $editor_page_title]
				set editor_cmd "if \{ \[$widget cget -state\] eq \"normal\" \} \{ $editor_cmd \}" 
				
				bind $widget <Double-Button-1> $editor_cmd
			}
				
			return $widget
		}
		
		#  Adds a checkbox using Fontawesome symbols (which can be resized to any font size) instead of the tiny Tk 
		#	checkbutton.
		# Named options:
		#	-textvariable the name of the boolean variable to map the checkbox to.
		#	-command optional tcl code to run when the checkbox is clicked. 
		proc checkbox { pages x y args } {
			set tags [dui::args::process_tags_and_var $pages checkbox -textvariable 1]
			set main_tag [lindex $tags 0]
			
			set style [dui::args::get_option -style "" 0]
			dui::args::process_font checkbox $style
			set checkvar [dui::args::get_option -textvariable "" 1]
			dui::args::process_label $pages $x $y checkbox $style
			set cmd [dui::args::get_option -command "" 1]
			
			#set first_page [lindex $pages 0]
			set ns [dui::page::get_namespace [lindex $pages 0]]
			if { $ns ne "" } { 
				if { [string is wordchar $cmd] && [info proc ${ns}::$cmd] ne "" } {
					set cmd ${ns}::$cmd
				}		
				regsub -all {%NS} $cmd $ns cmd
			}
			if { $checkvar ne "" } {
				set cmd "if { \[string is true \$$checkvar\] } { set $checkvar 0 } else { set $checkvar 1 }; $cmd"
			}
			
			dui add variable $pages $x $y -textvariable \
				"\[lindex \$::dui::symbol::checkbox_symbols_map \[string is true \$$checkvar\]\]" -aspect_type checkbox {*}$args
	
			set button_tags [list ${main_tag}-btn {*}[lrange $tags 1 end]]		
			dui add button $pages [expr {$x-5}] [expr {$y-5}] [expr {$x+60}] [expr {$y+60}] ] -tags $button_tags -command $cmd
			
			return $main_tag
		}
		
		proc listbox { pages x y args } {
			set tags [dui::args::process_tags_and_var $pages listbox -listvariable 1]
			set main_tag [lindex $tags 0]
			set ids {}
			
			set style [dui::args::get_option -style "" 0]
			set width [dui::args::get_option -width "" 1]
			if { $width ne "" } {
				dui::args::add_option_if_not_exists -width [expr {int($width * $::globals(entry_length_multiplier))}]
			}
			set height [dui::args::get_option -height "" 1]
			if { $height ne "" } {
				dui::args::add_option_if_not_exists -height [expr {int($height * $::globals(listbox_length_multiplier))}]
			}
	
			set ysb [dui::args::process_yscrollbar $pages $x $y listbox $style]
			if { $ysb != 0 && ![dui::args::has_option -yscrollcommand] } {
				dui::args::add_option_if_not_exists -yscrollcommand \
					"::dui::item::scale_scroll $main_tag ::dui::item::sliders($main_tag)"
			}
			
			return [dui add widget listbox $pages $x $y {*}$args]
		}
		
		# Options name to match those in Tk slider widget.
		# -orient
		# -length line length (vertical or horizontal total distance)
		# -width line width 
		# -sliderlength
		# -from
		# -to
		# -variable
		# -foreground (main color for left part and circle)
		# -disabledforeground
		# -background (color for right part)
		# -disabledbackground
		# -small_increment
		# -big_increment
		# -plus_minus
		# -default ?
		proc dscale { pages x y args } {
			set can [dui canvas]			
			set tags [dui::args::process_tags_and_var $pages dscale -variable 1]
			set main_tag [lindex $tags 0]
			set ns [dui page get_namespace $pages]
												
			set style [dui::args::get_option -style "" 0]
			dui::args::process_aspects dscale $style ""
			set label_id [dui::args::process_label $pages $x $y dscale $style ${main_tag}-bck]
			set var [dui::args::get_option -variable "" 1]
			set orient [string range [dui::args::get_option -orient horizontal] 0 0]
			set from [dui::args::get_option -from 0]
			set to [dui::args::get_option -max [expr {$from+100}]]
			set digits [dui::args::get_option -digits 0]
			set default [dui::args::get_option -default [expr {($from-$to)/2}]]
			set width [dui::args::get_option -width 8]
			set length [dui::args::get_option -length 300]
			set sliderlength [dui::args::get_option -sliderlength 25]
			set foreground [dui::args::get_option -foreground blue]
			set disabledforeground [dui::args::get_option -disabledforeground grey]
			set background [dui::args::get_option -background grey]
			set disabledbackground [dui::args::get_option -disabledforeground grey]
			set smallinc [dui::args::get_option -smallincrement 1]
			set biginc [dui::args::get_option -bigincrement 10]
			set plus_minus [string is true [dui::args::get_option -plus_minus 1]]
			set pm_width 0
			if { $plus_minus } {
				set pm_width 20
			}
			
			set x [rescale_x_skin $x]
			set y [rescale_y_skin $y]
			if { $orient eq "v" } {
				set length [rescale_y_skin $length]
				set sliderlength [rescale_y_skin $sliderlength]
				set width [rescale_x_skin $width]
				set y [expr {$y+$pm_width}]
				set x1 $x
				set x1f $x
				set y1 [expr {$y+$length-$pm_width}]
				set y1f [expr {$y+($y1-$y)/2}]
				set moveto_cmd [list dui::item::dscale_moveto [lindex $pages 0] $main_tag $var $from $to $digits %y]
			} else {
				set length [rescale_x_skin $length]
				set sliderlength [rescale_x_skin $sliderlength]
				set width [rescale_y_skin $width]
				set x [expr {$x+$pm_width}]
				set x1 [expr {$x+$length-$pm_width}]
				set x1f [expr {$x+$sliderlength/2}]
				set y1 $y
				set y1f $y
				set moveto_cmd [list dui::item::dscale_moveto [lindex $pages 0] $main_tag $var $from $to $digits %x]
				
				if { $plus_minus } {
					# -font [dui font get notosansuiregular 12]
					set id [$can create text [expr {$x-$pm_width}] [expr {$y-3}] -text "-" -anchor w -justify left  \
						-font [dui font get notosansuiregular 18] -fill $foreground -disabledfill $disabledforeground \
						-tags [list ${main_tag}-dec {*}$tags] -state hidden]
					lappend ids $id
					if { $ns ne "" } {
						set "${ns}::widgets(${main_tag}-dec)" $id
					}							
					set id [$can create rect [expr {$x-$pm_width-20}] [expr {$y-$sliderlength/2}] $x [expr {$y+$sliderlength/2}] \
						-fill {} -width 0 -tags [list ${main_tag}-tdec {*}$tags] -state hidden]					
					$can bind ${main_tag}-tdec [platform_button_press] [list dui item change_var_in_range $var \
						-$smallinc $from $to $digits]
					$can bind ${main_tag}-tdec <Triple-ButtonPress-1> [list dui item change_var_in_range $var \
						-$biginc $from $to $digits]
					lappend ids $id
					if { $ns ne "" } {
						set "${ns}::widgets(${main_tag}-tdec)" $id
					}							
					
					set id [$can create text [expr {$x1+$pm_width}] [expr {$y-1}] -text "+" -anchor e -justify right -font [dui font get notosansuiregular 16] \
						-fill $foreground -disabledfill $disabledforeground -tags [list ${main_tag}-inc {*}$tags] \
						-state hidden]
					lappend ids $id
					if { $ns ne "" } {
						set "${ns}::widgets(${main_tag}-inc)" $id
					}											
					set id [$can create rect $x1 [expr {$y-$sliderlength/2}] [expr {$x1+$pm_width+20}] [expr {$y+$sliderlength/2}] \
						-fill {} -width 0 -tags [list ${main_tag}-tinc {*}$tags] -state hidden]
					$can bind ${main_tag}-tinc [platform_button_press] [list dui item change_var_in_range $var \
						$smallinc $from $to $digits]
					$can bind ${main_tag}-tinc <Triple-ButtonPress-1> [list dui item change_var_in_range $var \
						$biginc $from $to $digits]
					lappend ids $id
					if { $ns ne "" } {
						set "${ns}::widgets(${main_tag}-tinc)" $id
					}
				}
				
			}
			
			set id [$can create line $x $y $x1 $y1 -width $width -fill $background -disabledfill $disabledbackground \
				-capstyle round -tags [list ${main_tag}-bck {*}$tags] -state hidden]
			lappend ids $id
			if { $ns ne "" } {
				set "${ns}::widgets(${main_tag}-bck)" $id
			}
			set id [$can create line $x $y $x1f $y1f -width $width -fill $foreground -disabledfill $disabledforeground \
				-capstyle round -tags [list ${main_tag}-frn {*}$tags] -state hidden]
			lappend ids $id
			if { $ns ne "" } {
				set "${ns}::widgets(${main_tag}-frn)" $id
			}			
			set id [$can create rect  $x [expr {$y-$sliderlength/2}] $x1 [expr {$y1+$sliderlength/2}] -fill {} -width 0 \
				-tags [list ${main_tag}-tap {*}$tags] -state hidden]			
			$can bind ${main_tag}-tap [platform_button_press] $moveto_cmd
			lappend ids $id
			if { $ns ne "" } {
				set "${ns}::widgets(${main_tag}-tap)" $id
			}
									
			set id [$can create oval [expr {$x1f-($sliderlength/2)}] [expr {$y1f-($sliderlength/2)}] \
				[expr {$x1f+($sliderlength/2)}] [expr {$y1f+($sliderlength/2)}] -fill $foreground \
				-disabledfill $disabledforeground -width 0 -tags [list {*}$tags ${main_tag}-crc] -state hidden] 
			$can bind ${main_tag}-crc <B1-Motion> $moveto_cmd
			lappend ids $id			
			if { $ns ne "" } {
				set "${ns}::widgets(${main_tag}-crc)" $id
				set "${ns}::widgets($main_tag)" $ids
			}
			
			set update_cmd [list ::dui::item::dscale_moveto [lindex $pages 0] $main_tag $var $from $to $digits ""]
			trace add variable $var write $update_cmd
			# Force initializing the slider position
			dui page add_action $pages show $update_cmd
			
			# Invoke number editor page on tap of the label
			set editor_page [dui::args::get_option -editor_page $::dui::use_editor_pages]
			if { $editor_page ne "" && ![string is false $editor_page] && $var ne "" && $label_id ne "" } {
				# TO BE CHANGED
				set n_decimals $digits
				
				if { [string is true $editor_page] } {
					set editor_page "dui_number_editor" 
				}
				set editor_page_title [dui::args::get_option -editor_page_title]
				set editor_cmd [list dui page show_when_off $editor_page $var -n_decimals $n_decimals -min $from \
					-max $to -default $default -small_increment $smallinc -big_increment $biginc \
					-page_title $editor_page_title]
				set editor_cmd "if \{ \[$can itemcget $label_id -state\] eq \"normal\" \} \{ $editor_cmd \}"
				$can bind $label_id [platform_button_press] $editor_cmd
			}
			
			dui item add_to_pages $pages $main_tag
			return $ids
		}
	}
	
	### INITIALIZE ###
	proc init {} {
	}
	
	proc canvas {} {
		return ".can"
	}
	
	proc setup_ui {} {
		# Launch setup methods of pages created with 'dui add page'
		set applied_ns {}
		foreach page [page list] {
			set ns [page get_namespace $page]
			if { $ns ne "" && $ns ni $applied_ns } {
				if { [info proc ${ns}::setup] eq "" } {
					msg [namespace current] -NOTICE "page namespace '${ns}' does not have a setup method"
				} else {
					#msg [namespace current] setup_ui "running ${ns}::setup"
					${ns}::setup
				}
				lappend applied_ns $ns
			}
		}
		
		# Launch setup methods of pages created as sub-namespaces of ::dui::pages (which do not require 'dui add page')
		foreach ns [namespace children ::dui::pages] {
			if { $ns ni $applied_ns } {
				if { [info proc ${ns}::setup] eq "" } {
					msg [namespace current] -NOTICE "page namespace '${ns}' does not have a setup method"
				} else {
					#msg [namespace current] setup_ui "running ${ns}::setup"
					${ns}::setup
				}
				lappend applied_ns $ns
			}
		}
	}
	
	

		
	### GENERAL TOOLS ###
	
	# Command to invoke from the -vcmd option to validate numeric entries, with -validate key.
	# Returns 1 if empty or a valid numeric value in the requested range, 0 otherwise.
	# Trims leading zeros to avoid octal arithmetic.
	proc validate_numeric { value {n_decimals 0} {min_value {}} {max_value {}} } {
		set value [string trimleft $value 0]
		if { $value eq {} } {
			return 1
		}
		if { $value eq "." && $n_decimals > 0 } {
			return 1
		}
		if { $value eq "-" } {
			return [expr {($min_value eq "" || ([string is double $min_value] && $min_value < 0))}]
		}
		
		if { $n_decimals eq "" || $n_decimals == 0 } {
			if { ![string is entier $value] } {
				return 0
			}			
		} elseif { ![string is double $value] } {
			return 0
		} else {
			set parts [split $value .]
			set dec_part ""
			if { [llength $parts] > 1 } {
				set dec_part [lindex $parts 1]
			} 
			if { $dec_part ne "" && [string length $dec_part] > $n_decimals } {
				return 0
			}
		}
		
		if { $min_value ne "" && [string is double $min_value] && $value < $min_value } {
			return 0
		}
		if { $max_value ne "" && [string is double $max_value] && $value > $max_value } {
			return 0
		}
		return 1
	}
	
	proc hide_android_keyboard {} {
		# make sure on-screen keyboard doesn't auto-pop up, and if
		# physical keyboard is connected, make sure navbar stays hidden
		sdltk textinput off
		focus .can
	}
		
}


# General utilities
# Returns the list with duplicates removed, keeping the original list sorting of elements, unlike 'lsort -unique'.
# See discussion in https://wiki.tcl-lang.org/page/Unique+Element+List
proc unique_list {list} {
	set new {}
	foreach item $list {
		if { $item ni $new } {
			lappend new $item
		}
	}
	return $new
}

### FULL-PAGE EDITORS ################################################################################################

namespace eval ::dui::pages::dui_number_editor {
	variable widgets
	array set widgets {}
		
	variable data
	array set data {		
		previous_page {}
		callback_cmd {}
		page_title {}
		num_variable {}
		value {}
		min {}
		max {}
		default {}
		n_decimals {}
		small_increment {}
		big_increment {}
		previous_values {}
	}

	proc setup {} {
		variable data 
		variable widgets
		set page [namespace tail [namespace current]]
#		set incs_font_size 6
		
		# Page and title
		dui page add $page -namespace [namespace current]
		dui add variable $page 1280 100 -tags dui_ne_page_title -textvariable page_title -style page_title
		
		# Insight-style background shapes
		dui add canvas_item rect $page 10 190 2550 1430 -style insight_back_box
		dui add canvas_item line $page 14 188 2552 189 -style insight_back_box_shadow
		dui add canvas_item line $page 2551 188 2552 1426 -style insight_back_box_shadow

		dui add canvas_item rect $page 22 210 1270 600 -style insight_front_box
		dui add canvas_item rect $page 22 620 1270 1410 -style insight_front_box
		dui add canvas_item rect $page 1290 210 2536 1410 -style insight_front_box
		
		# Value being edited. Use the center coordinates of the text entry as reference for the whole row.
		set x 625; set y 390
		dui add entry $page $x $y -tags value -width 6 -data_type numeric -font_size +6 -canvas_anchor center \
			-justify center
				
		# Increment/decrement clicker buttons style
		dui aspect set -style dne_clicker {button.shape round button.bwidth 120 button.bheight 140 
			button.radius 20 button.anchor center
			button_symbol.pos {0.5 0.4} button_symbol.anchor center button_symbol.font_size 20
			button_label.pos {0.5 0.8} button_label.font_size 10 button_label.anchor center}
		
		# Decrement value arrows		
		set hoffset 45; set bspace 140
		dui add button $page [expr {$x-$hoffset-$bspace}] $y -tags small_decr -style dne_clicker \
			-symbol chevron_left -labelvariable {-[format [%NS::value_format] $%NS::data(small_increment)]} \
			-command { %NS::incr_value -$%NS::data(small_increment) }
		
		dui add button $page [expr {$x-$hoffset-$bspace*2}] $y -tags big_decr -style dne_clicker \
			-symbol chevron_double_left -labelvariable {-[format [%NS::value_format] $%NS::data(big_increment)]} \
			-command { %NS::incr_value -$%NS::data(big_increment) } 

		dui add button $page [expr {$x-$hoffset-$bspace*3}] $y -tags to_min -style dne_clicker \
			-symbol arrow_to_left -labelvariable {[format [%NS::value_format] $%NS::data(min)]} \
			-command { %NS::set_value -$%NS::data(min) } 

		# Increment value arrows
		dui add button $page [expr {$x+$hoffset+$bspace}] $y -tags small_incr -style dne_clicker \
			-symbol chevron_right -labelvariable {+[format [%NS::value_format] $%NS::data(small_increment)]} \
			-command { %NS::incr_value $%NS::data(small_increment) }
			
		dui add button $page [expr {$x+$hoffset+$bspace*2}] $y -tags big_incr -style dne_clicker \
			-symbol chevron_double_right -labelvariable {+[format [%NS::value_format] $%NS::data(big_increment)]} \
			-command { %NS::incr_value $%NS::data(big_increment) } 
	
		dui add button $page [expr {$x+$hoffset+$bspace*3}] $y -tags to_max -style dne_clicker \
			-symbol arrow_to_right -labelvariable {[format [%NS::value_format] $%NS::data(max)]} \
			-command { %NS::set_value $%NS::data(max) } 
		
		# Erase button
		#		dui add symbol $page $x_left_center [expr {$y+140}] eraser -size medium -has_button 1 \
		#			-button_cmd { set ::dui::pages::dui_number_editor::data(value) "" }
		
#		# Previous values listbox
		dui add listbox $page 450 780 -tags previous_values -canvas_width 350 -canvas_height 550 -yscrollbar 1 \
			-label [translate "Previous values"] -label_style section_font_size -label_pos {450 700} -label_anchor nw 
		bind $widgets(previous_values) <<ListboxSelect>> ::dui::pages::dui_number_editor::previous_values_select
		
#		# Numeric type pad
		dui aspect set -style dne_pad_button {button.shape round button.bwidth 280 button.bheight 220 
			button.radius 20 button.anchor nw
			button_label.pos {0.5 0.5} button_label.font_family notosansuibold 
			button_label.font_size 24 button_label.anchor center}
		
		set x_base 1425; set y_base 290
		set width 280; set height 220; set hspace 80; set vspace 60
		set row 0; set col 0
		
		foreach line { {7 8 9} {4 5 6} {1 2 3} {"Del" 0 "."} } {
			foreach num $line {
				set x [expr {$x_base+$col*($width+$hspace)}]
				set y [expr {$y_base+$row*($height+$vspace)}]
				if { $num eq "." } {
					set tag "num_dot"
				} else {
					set tag "num$num"
				}
				
				dui add button $page $x $y [expr {$x+$width}] [expr {$y+$height}] -tags $tag -style dne_pad_button \
					-label "$num" -command [list %NS::enter_character $num] 
				
				incr col
			}
			set col 0
			incr row
		}
		
		dui add button $page 1035 1460 -tags dne_settings_ok -style insight_ok -command page_done -label [translate Ok]
	}
	
	# Accepts any of the named options -page_title, -callback_cmd, -min, -max, -n_decimals, -default, -small_increment  
	#	and -big_increment. If any from -min on is not defined or an empty string, the page does not load.
	proc load { page_to_hide page_to_show num_variable args } {
		variable data
		array set opts $args
		set page [namespace tail [namespace current]]
			
		set data(num_variable) $num_variable 
		if { $data(num_variable) eq "" } {
			msg -WARN [namespace current] load: "num_variable is required"
			return 0
		}
		if { ![info exists $num_variable] } {
			set $num_variable ""
		}
		
		set data(previous_page) $page_to_hide
		
		set fields {page_title callback_cmd previous_values default min max n_decimals small_increment big_increment}
		foreach fn $fields {
			set data($fn) [ifexists opts(-$fn)]
		}
		foreach fn [lrange $fields 4 end] {
			if { $data($fn) eq "" } {
				msg -WARN [namespace current] load: "-$fn is required"
				return 0
			}
		}
		if { $data(max) <= $data(min) } {
			msg -WARN [namespace current] load: "max ($data(max)) must be bigger than min ($data(min))"
			return 0			
		}
		
		if { $data(page_title) eq "" } {
			set data(page_title) [translate "Edit number"]
		}
		if { $data(default) eq "" } {
			set data(default) $data(min)
		}
		
		return 1
	}
	
	proc show { page_to_hide page_to_show } {
		variable data
		set page [namespace tail [namespace current]]
		dui item enable_or_disable [expr {$data(n_decimals)>0}] $page "num_dot*"
		dui item enable_or_disable [expr {[llength $data(previous_values)]>0}] $page "previous_values*"
	
		if { $data(num_variable) ne "" && [subst \$$data(num_variable)] ne "" } {
			# Without the delay, the value is not selected. Tcl misteries...
			after 10 ::dui::pages::dui_number_editor::set_value [subst \$$data(num_variable)]
		}	
	}
	
	proc value_format {} {
		variable data
		return "%.$data(n_decimals)f"
	}
	
	proc set_value { new_value } {
		variable data
		if { $new_value ne "" } {
			if { $new_value != 0 } { set new_value [string trimleft $new_value 0] } 
			set new_value [format [value_format] $new_value]
		}
		set data(value) $new_value
		value_change
		select_value
	}
	
	proc select_value {} {
		variable widgets
		focus $widgets(value)
		$widgets(value) selection range 0 end 
	}
	
	proc value_change {} {
		variable data 
		variable widgets
		set widget $widgets(value)
		
		if { $data(value) ne "" } {
			if { $data(min) ne "" && $data(value) < $data(min) } {
				$widget configure -foreground [dui aspect get text fill -style error]
			} elseif { $data(max) ne "" && $data(value) > $data(max) } {
				$widget configure -foreground [dui aspect get text fill -style error]
			} else {
				$widget configure -foreground [dui aspect get text fill]
			}
		}
	}
	
	proc enter_character { char } {
		variable data
		variable widgets
		set widget $widgets(value)
		
		set max_len [string length [expr round($data(max))]]
		if { $data(n_decimals) > 0 } { 
			incr max_len [expr {$data(n_decimals)+1}] 
		}
	
		set idx -1
		catch { set idx [$widget index sel.first] }
		#[selection own] eq $widget
		if { $idx > -1 } {
			set idx_last [$widget index sel.last]
			if { $char eq "Del" } {
				set data(value) "[string range $data(value) 0 [expr {$idx-1}]][string range $data(value) $idx_last end]"
			} else {
				set data(value) "[string range $data(value) 0 [expr {$idx-1}]]$char[string range $data(value) $idx_last end]"
			}
			selection own $widget
			$widget selection clear
			$widget icursor [expr {$idx+1}]
		} else {	
			set idx [$widget index insert]
			if { $char eq "Del" } {
				set data(value) "[string range $data(value) 0 [expr {$idx-2}]][string range $data(value) $idx end]"
				if { $idx > 0 } { $widget icursor [expr {$idx-1}] }
			} elseif { [string length $data(value)] < $max_len } {
				$widget insert $idx $char
			}
		}
		
		set data(value) [string trimleft $data(value) 0]
		value_change
	}
	
	proc incr_value { incr } {
		variable data	
		
		if { $data(value) eq "" } {
			if { $data(default) ne "" } {
				set value $data(default)
			} elseif { $data(min) ne "" && $data(max) ne "" } {
				set value [expr {($data(max)-$data(min))/2}]
			} else {
				set value 0
			}
		} else {
			set value $data(value)
		}
	
		set new_value [expr {$value + $incr}]
		if { $data(min) ne "" && $new_value < $data(min) } {
			set new_value $data(min)
		} 
		if { $data(max) ne "" && $new_value > $data(max) } {
			set new_value $data(max)
		}
		
		set new_value [format [value_format] $new_value]
		if { $new_value != $data(value) } {
			set_value $new_value
		}
	}
	
	proc previous_values_select {} {
		variable widgets		
		set new_value [dui item listbox_get_selection $widgets(previous_values)]
		if { $new_value ne "" } { 
			set_value $new_value 
		}
	}
	
	proc page_cancel {} {
		variable data
		if { $data(callback_cmd) ne "" } {
			$data(callback_cmd) {}
		} else {
			dui page show_when_off $data(previous_page)
		}
	}
	
	proc page_done {} {
		variable data
		set fmt [value_format]
		
		if { $data(value) ne "" } {
			if { $data(value) < $data(min) } {
				set data(value) [format $fmt $data(min)]
			} elseif { $data(value) > $data(max) } {
				set data(value) [format $fmt $data(max)]
			} else {
				if { $data(value) > 0 } { set data(value) [string trimleft $data(value) 0] }
				set data(value) [format $fmt $data(value)]
			}
		}
		
		if { $data(callback_cmd) ne "" } {
			$data(callback_cmd) $data(value)
		} else {		
			set $data(num_variable) $data(value)
			dui page show_when_off $data(previous_page)
		}
	}
}

### JUST FOR TESTING

dui init
#dui font add_dirs "[skin_directory]/fonts" "[homedir]/fonts"
dui font add_dirs "[homedir]/fonts"
# dui item add_image_dirs "[homedir]/skins/$::settings(skin)" "[homedir]/skins/default"
dui item add_image_dirs "[homedir]/skins/Insight" "[homedir]/skins/default"
set ::settings(enabled_plugins) {}
# dui_demo SDB github