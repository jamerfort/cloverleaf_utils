# parse the command line

set num_args [llength $argv]

set GROUP_BY trxid
set SOURCE {}
set DEST {}
set TRXID {}
set XLATE {}
set PROC {}
set NETCONFIG ""
set OUTPUT_FORMAT {
	source
	dest
	trxid
	type
	xlate
	preprocs
	procs
	postprocs
	ibprocs
	obprocs
}

set LEVEL 0
set LEADER ""

set i 0
while { $i < $num_args } {
	switch -exact -- [lindex $argv $i] {
		-by {
			#@usage -by [dest|trxid]
			#@description group by destination or trxid
			
			# set the grouping order
			incr i
			set GROUP_BY [string tolower [lindex $argv $i]]
		}

		-s {
			#@usage -s THREAD_NAME
			#@usage -s 're:THREAD_REGEX'
			#@description Show only routes that have source threads matching the given thread or regular expression
			
			# set the source thread
			incr i
			lappend SOURCE [lindex $argv $i]
		}

		-d {
			#@usage -d THREAD_NAME
			#@usage -d 're:THREAD_REGEX'
			#@description Show only routes that have destination threads matching the given thread or regular expression

			# set the destination thread
			incr i
			lappend DEST [lindex $argv $i]
		}

		-t {
			#@usage -t TRXID
			#@usage -t 're:TRXID_REGEX'
			#@description Show only routes that have trxids matching the given thread or regular expression

			# set the trxid
			incr i
			lappend TRXID [lindex $argv $i]
		}

		-x {
			#@usage -x XLATE
			#@usage -x 're:XLATE_REGEX'
			#@description Show only routes that have xlates matching the given xlate or regular expression
			
			# set the Xlate
			incr i
			lappend XLATE [lindex $argv $i]
		}

		-p {
			#@usage -p PROC_SPEC
			#@usage -p 're:PROC_REGEX'
			#@description Show only routes that use the procs matching the given proc spec or regular expression
			#@description The PROC_SPEC is a string made up of the proc name, followed by the TPS args.  This is the same method used to output the procs.
			
			# set the proc
			incr i
			lappend PROC [lindex $argv $i]
		}

		-f {
			#@usage -f NETCONFIG_PATH
			#@description Set the NetConfig file to load
			
			# set the NetConfig file
			incr i
			set NETCONFIG [lindex $argv $i]
		}

		-o {
			#@usage -o FLAG
			#@usage -o -FLAG
			#@usage -o -*
			#@description Set the output format.  A preceding "-" means to remove the indicated data from the output.  Otherwise, add it back.
			#@description The list of flags are: type xlate preprocs postprocs ibprocs obprocs
			#@description The flags can be globbed, thus to remove all, use '-o -*'.

			# set the output format
			incr i

			set fmt_flag [string tolower [lindex $argv $i]]

			if { [string index $fmt_flag 0] == "-" } {
				# remove the flag
				foreach index [lsort -integer -decreasing [lsearch -all -glob $OUTPUT_FORMAT [string range $fmt_flag 1 end]]] {
					set OUTPUT_FORMAT [lreplace $OUTPUT_FORMAT $index $index]
				}
			} else {
				if { [string index $fmt_flag 0] == "+" } {
					set fmt_flag [string range $fmt_flag 1 end]
				}

				lappend OUTPUT_FORMAT $fmt_flag
			}
		}

		default {
			#do nothing
		}
	}

	incr i
}

if { $NETCONFIG != "" } {
	netconfig load $NETCONFIG
}

proc output { output_type output_string } {
	global OUTPUT_FORMAT LEVEL LEADER

	if { [lsearch $OUTPUT_FORMAT $output_type] != -1} {
		for { set i 0 } { $i < $LEVEL } { incr i } {
			puts -nonewline "\t"
		}
		puts "${LEADER}${output_string}"
		return 1
	}

	return 0
}

proc filter_route {_source route_data} {
	set dest [lindex $route_data 0]
	set trxid [lindex $route_data 1]
	set type [lindex $route_data 2]
	set extra_data [lindex $route_data 3]
	set ibprocs [lindex $route_data 4]
	set obprocs [lindex $route_data 5]

	set preprocs {}
	set procs {}
	set postprocs {}

	set xlate {}

	# pull out extra information
	if { $type == "xlate" } {
		set xlate [lindex $extra_data 0]
		set preprocs [lindex $extra_data 1]
		set postprocs [lindex $extra_data 2]
	} elseif { $type == "raw" } {
		set procs $extra_data
	}

	foreach pair {
		{SOURCE _source}
		{DEST dest}
		{TRXID trxid}
		{XLATE xlate}
	} {
		global [lindex $pair 0]

		set desired_list [set [lindex $pair 0]]
		set actual [set [lindex $pair 1]]

		set meets_desire 0

		foreach desired $desired_list {
			if { $desired != "" } {
				if { [regexp {^re:} $desired] } {
					if { [regexp [string range $desired 3 end] $actual]} {
						set meets_desire 1
					}
				} else {
					if { $desired == $actual } {
						set meets_desire 1
					}
				}
			}
		}

		if { [llength $desired_list] > 0 && ! $meets_desire } {
			# block this route
			return 0
		}
	}

	# filter by procs
		global PROC

		# do we even care about the procs?
		if { [llength $PROC] > 0 } {
			# yes

			set meets_desire 0

			# loop through each type of proc
			foreach proc_set {ibprocs preprocs procs postprocs obprocs} {
				foreach proc_data [set $proc_set] {
					set proc_string [proc_to_string $proc_data]

					foreach desired $PROC {
						if { $desired != "" } {
							if { [regexp {^re:} $desired] } {
								if { [regexp [string range $desired 3 end] $proc_string]} {
									set meets_desire 1
								}
							} else {
								if { $desired == $proc_string } {
									set meets_desire 1
								}
							}
						}
					}
				}
			}

			if { ! $meets_desire } {
				return 0
			}
		}

	# allow through
	return 1
}


proc process_proc_list {data} {
	set args [keylget data ARGS]
	set procs [keylget data PROCS]

	set proc_list {}

	set num_procs [llength $procs]

	for {set i 0} {$i < $num_procs} {incr i} {
		set proc_name [lindex $procs $i]
		set proc_args [lindex $args $i]

		lappend proc_list [list $proc_name $proc_args]
	}

	return $proc_list
}

proc proc_to_string {proc_data} {
	set proc_name [lindex $proc_data 0]
	set proc_args [regsub -all {\n} [lindex $proc_data 1] {\\n}]

	return "$proc_name $proc_args"
}

proc print_route_data {route_data} {
	global LEVEL LEADER

	set old_LEVEL $LEVEL
	set LEVEL 3

	set old_LEADER $LEADER
	set LEADER "  "
	
	set is_first 1

	proc p {output_type s} {
		upvar is_first is_first
		global LEADER

		if { $is_first } {
			set LEADER "- "
		} else {
			set LEADER "  "
		}
		
		if { [output $output_type $s] } {
			set is_first 0
		}
	}

	set dest [lindex $route_data 0]
	set trxid [lindex $route_data 1]
	set type [lindex $route_data 2]
	set extra_data [lindex $route_data 3]
	set ibprocs [lindex $route_data 4]
	set obprocs [lindex $route_data 5]
	
	p type "TYPE: $type"

	foreach ibproc $ibprocs {
		p ibprocs "IBPROC: [proc_to_string $ibproc]"
	}
	
	if { $type == "xlate" } {
		set xlate [lindex $extra_data 0]
		set preprocs [lindex $extra_data 1]
		set postprocs [lindex $extra_data 2]

		foreach preproc $preprocs {
			p preprocs "PREPROC: [proc_to_string $preproc]"
		}

		p xlate "XLATE: $xlate"

		foreach postproc $postprocs {
			p postprocs "POSTPROC: [proc_to_string $postproc]"
		}
	} elseif { $type == "raw" } {
		set procs $extra_data

		foreach _proc $procs {
			p procs "PROC: [proc_to_string $_proc]"
		}
	}

	foreach obproc $obprocs {
		p obprocs "OBPROC: [proc_to_string $obproc]"
	}

	set LEVEL $old_LEVEL
	set LEADER $old_LEADER
}

proc print_routes {thread routes} {
	if { [llength [keylkeys routes]] == 0 } {
		return
	}

	puts "$thread"

	foreach level1 [lsort [keylkeys routes]] {
		puts "\t$level1"	

		foreach level2 [lsort [keylkeys routes $level1]] {
			puts "\t\t$level2"

			foreach route_data [keylget routes "$level1.$level2"] {
				#puts "\t\t
				print_route_data $route_data
			}
		}
	}
}

foreach thread [netconfig get connection list] {
	set data [netconfig get connection data $thread]

	# get the route data
	set routes_by_dest {}
	set routes_by_trxid {}

	set ibprocs [process_proc_list [keylget data SMS.IN_DATA]]

	foreach route_data [keylget data DATAXLATE] {
		set trxid [keylget route_data TRXID]
		
		foreach dest_data [keylget route_data ROUTE_DETAILS] {
			set type [keylget dest_data TYPE]

			set extra_data {}

			if { $type == "xlate" } {
				set xlate [keylget dest_data XLATE]

				# preprocs/postprocs
				set preprocs [process_proc_list [keylget dest_data PREPROCS]]
				set postprocs [process_proc_list [keylget dest_data POSTPROCS]]

				set extra_data [list $xlate $preprocs $postprocs]
			} elseif { $type == "raw" } {
				set procs [process_proc_list [keylget dest_data PROCS]]
				set extra_data $procs
			}

			foreach dest [keylget dest_data DEST] {
				# get the outbound procs
				set dest_thread_data [netconfig get connection data $dest]
				set obprocs [process_proc_list [keylget dest_thread_data SMS.OUT_DATA]]

				set route_data [list $dest $trxid $type $extra_data $ibprocs $obprocs]

				if { [filter_route $thread $route_data] } {
					if { [lsearch [keylkeys routes_by_dest] $dest] == -1 || [lsearch [keylkeys routes_by_dest $dest] $trxid] == -1} {
						keylset routes_by_dest "$dest.$trxid" {}
					}

					if { [lsearch [keylkeys routes_by_trxid] $trxid] == -1 || [lsearch [keylkeys routes_by_trxid $trxid] $dest] == -1} {
						keylset routes_by_trxid "$trxid.$dest" {}
					}

					set by_dest [keylget routes_by_dest "$dest.$trxid"]
					lappend by_dest $route_data
					keylset routes_by_dest "$dest.$trxid" $by_dest

					set by_trxid [keylget routes_by_trxid "$trxid.$dest"]
					lappend by_trxid $route_data
					keylset routes_by_trxid "$trxid.$dest" $by_trxid
				}
			}
		}
	}

	if { $GROUP_BY == "dest" } {
		print_routes $thread $routes_by_dest
	} else {
		print_routes $thread $routes_by_trxid
	}

}
