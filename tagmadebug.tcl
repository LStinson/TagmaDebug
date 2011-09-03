#!/usr/bin/env tclsh
# tagma.tcl --
# Last Modified: 2011-09-02
#
# Implements simple debugging for TCL.
# By Lorance Stinson AT Gmail.....
# The name was selected to, hopefully, not clash with anything existing.
# Based on "TclDebugger by S.Arnold. v0.1 2007-09-09" - http://wiki.tcl.tk/19872

namespace eval ::TagmaDebug:: {
    variable argv $::argv
    variable argv0 $::argv0
    variable break  {}
    variable enter  {}
    variable leave  {}
    variable log    {}
    variable procs  {}
    variable step   {}
    variable debugDisabled 0
    variable debugDisabledCmd ""
    variable settings
    array set settings {
        body        1
        descr       "TagmaDebug by Lorance Stinson AT Gmail..."
        enter       1
        packages    0
        prefix      ">>"
        prompt      "Tagma> "
        server      0
        socket      ""
        verbose     0
    }
}

# XXX Utilities XXX

# ::TagmaDebug::CheckCommand --
#   Checks if a command exists.
#
# Arguments:
#   command     The name of the command to check.
#
# Result:
#   0 if the command does not exist.
#   1 if the command is a procedure, command or function.
#
# Side effect:
#   None
proc ::TagmaDebug::CheckCommand {command} {
    if {[uplevel 1 info procs $command] ne "" ||
        [uplevel 1 info commands $command] ne "" ||
        [uplevel 1 info functions $command] ne ""} {
        return 1
    }
    return 0
}

# ::TagmaDebug::CloseConnection --
#   Close a connection to a server.
#
# Arguments:
#   None
#
# Result:
#   None
#
# Side effect:
#   The connection is closed and the settings are updated.
proc ::TagmaDebug::CloseConnection {} {
    variable settings
    close $settings(socket)
    set settings(socket) ""
    set settings(server) 0
    puts stderr "$settings(prefix) Lost connection with the server..."
}

# ::TagmaDebug::EPuts --
#   Prints strings to STDERR.
#   Each string is printed on a separate line.
#
# Options
#   -list       Treat the first argument as a list and pring each element.
#   -nonewline  Do not print an ending newline.
#   -prefix     Prefix each string with the prefix from settings.
#   --          End processing of options.
#
# Arguments:
#   args        Strings to print.
#
# Result:
#   None
#
# Side effect:
#   The strings are printed to STDERR.
proc ::TagmaDebug::Eputs {args} {
    variable settings
    set channel [expr {$settings(server) ? $settings(socket) : "stderr"}]
    set cmd "puts"
    set count 0
    set list 0
    set prefix ""
    foreach arg $args {
        switch -nocase -- $arg {
            -- {
                incr count
                break
            }
            -list {
                incr count
                set list 1
            }
            -nonewline {
                incr count
                append cmd " -nonewline"
            }
            -prefix {
                incr count
                append prefix "$settings(prefix) "
            }
            default { break }
        }
    }

    foreach arg [expr {$list ? [lindex $args $count] :
                               [lrange $args $count end]}] {
        eval "$cmd \$channel \"\$prefix\$arg\""
    }
    if {[catch {flush $channel}]} {
        CloseConnection
    }
}

# ::TagmaDebug::PrintVariable --
#   Prints a variable and its value.
#
# Arguments:
#   varname     The name of the variable to print.
#
# Result:
#   None
#
# Side effect:
#   The variable and value are printed.
proc ::TagmaDebug::PrintVariable {varname} {
    if {[uplevel 1 array exists $varname]} {
        uplevel 1 parray $varname
        return
    }
    if {[uplevel 1 info exists $varname]} {
        Eputs -prefix "$varname = [uplevel 1 set $varname]"
    } else {
        Eputs -prefix "Variable '$varname' does not exist."
    }
}

# ::TagmaDebug::RemoveVarTrace --
#   Remove a trace from a variable.
#
# Arguments:
#   name        The name of the variable.
#   list        The list to remove the variable from.
#   callBack    The callback command to remove.
#
# Result:
#   -1 if the variable is not found in the log list.
#
# Side effect:
#   Tracing is disabled on the variable.
#   The variable name is removed from the list.
proc ::TagmaDebug::RemoveVarTrace {name list callBack} {
    variable $list
    set i [lsearch -exact [set $list] $name]
    if {$i < 0} {return -1}
    set $list [lreplace [set $list] $i $i]
    catch {
        trace remove variable $name {read write unset} $callBack
    }
    return 0
}

# ::TagmaDebug::Store --
#   Stores a value in a list if it is not already present.
#
# Arguments:
#   list        The list to modify.
#   elt         The value to store.
#
# Result:
#   The modified, or original, list.
#
# Side effect:
#   None
proc ::TagmaDebug::Store {list elt} {
    if {[lsearch -exact $list $elt] >= 0} {return $list}
    return [lappend list $elt]
}

# ::TagmaDebug::var --
#   Returns a variable or an index into a hash.
#
# Arguments:
#   name        Variable or hash.
#   key         Optional key in the hasn.
#
# Result:
#   The appropriate value.
#
# Side effect:
#   None
proc ::TagmaDebug::var {name key} {
    if {$key eq ""} {return $name}
    return $name\($key\)
}

# XXX Tracing Callbacks XXX

# ::TagmaDebug::Break --
#   Callback for breaking on variables.
#
# Arguments:
#   From the trace command.
#
# Result:
#   None
#
# Side effect:
#   Prints the information for the variable.
#   Enters the debugger prompt.
#   Disables logging if the variable was unset.
#   Re-enables debuggin.
proc ::TagmaDebug::Break {name1 name2 op} {
    switch -- $op {
        read - write {
            Eputs -prefix "$op [var $name1 $name2] = [uplevel 1 set [var $name1 $name2]]"
        }
        unset {
            Eputs -prefix "unset [var $name1 $name2]"
            # Stop tracing this variable if it is unset.
            if {[RemoveVarTrace [var $name1 $name2] break ::TagmaDebug::Break] < 0} {
                RemoveVarTrace $name1 break ::TagmaDebug::Break
            }
        }
        default {
            error "Break: Unknown OP '$op' for '$name1' - '$name2'."
        }
    }
    uplevel 1 ::TagmaDebug::debug

    # Re-enable debugging.
    variable debugDisabled
    if {$debugDisabled > 0} {set debugDisabled 0}
}

# ::TagmaDebug::Log --
#   Callback for logging variables.
#
# Arguments:
#   From the trace command.
#
# Result:
#
# Side effect:
#   Prints the information for the variable.
#   Disables logging if the variable was unset.
#   Re-enables debugging.
proc ::TagmaDebug::Log {name1 name2 op} {
    switch -- $op {
        read - write {
            Eputs -prefix "$op [var $name1 $name2] = [uplevel 1 set [var $name1 $name2]]"
        }
        unset {
            Eputs -prefix "unset [var $name1 $name2]"
            # Stop tracing this variable if it is unset.
            if {[RemoveVarTrace [var $name1 $name2] log ::TagmaDebug::Log] < 0} {
                RemoveVarTrace $name1 log ::TagmaDebug::Log
            }
        }
        default {
            error "Log: Unknown OP '$op' for '$name1' - '$name2'."
        }
    }

    # Re-enable debugging.
    variable debugDisabled
    if {$debugDisabled > 0} {set debugDisabled 0}
}

# ::TagmaDebug::Enter --
#   Callback for command entry.
#
# Arguments:
#   From the trace command.
#
# Result:
#   None
#
# Side effect:
#   prints when the command is entered.
#   Enters the debugger prompt.
#   Disables debugging upon entering TagmaDebug.
proc ::TagmaDebug::Enter {cmdstring op} {
    variable debugDisabled
    if {$debugDisabled} { return }

    if {[string range $cmdstring 0 13] eq "::TagmaDebug::"} {
        # Disable debuggin.
        set debugDisabled 1
        return
    }

    switch -- $op {
        enter {
            Eputs -prefix "Entering: [lindex $cmdstring 0]"
            variable settings
            if {$settings(verbose)} {
                Eputs -prefix "Args: [list [lrange $cmdstring 1 end]]"
            }
        }
        default {
            error "Enter: Unknown OP '$op' for '$cmdstring'."
        }
    }
    uplevel 1 ::TagmaDebug::debug [list $cmdstring]
}

# ::TagmaDebug::Unenter --
#   Removes the enter trace from a command.
#
# Arguments:
#   name        The command name.
#
# Result:
#   -1 if the command is not found in the enter list.
#
# Side effect:
#   Tracing is disabled on the command.
#   The variable name is removed from the enter list.
proc ::TagmaDebug::Unenter {name} {
    variable enter
    set i [lsearch -exact $enter $name]
    if {$i < 0} {return -1}
    set enter [lreplace $enter $i $i]
    catch {
        trace remove execution $name enter ::TagmaDebug::Enter
    }
    return 0
}

# ::TagmaDebug::Leave --
#   Callback for command leave.
#
# Arguments:
#   From the trace command.
#
# Result:
#   None
#
# Side effect:
#   prints when the command is left.
#   Enters the debugger prompt.
#   Disables debugging upon entering TagmaDebug.
proc ::TagmaDebug::Leave {cmdstring code result op} {
    variable debugDisabled
    if {$debugDisabled} { return }

    if {[string range $cmdstring 0 13] eq "::TagmaDebug::"} {
        # Disable debugging
        set debugDisabled 1
        return
    }

    switch -- $op {
        leave {
            Eputs -prefix "Leaving: [lindex $cmdstring 0]"
            variable settings
            if {$settings(verbose)} {
                Eputs -prefix "Result Code: $code"
                Eputs -prefix "Result: [list $result]"
            }
        }
        default {
            error "Leave: Unknown OP '$op' for '$cmdstring'."
        }
    }
    uplevel 1 ::TagmaDebug::debug [list $cmdstring]
}

# ::TagmaDebug::Unleave --
#   Removes the leave trace from a command.
#
# Arguments:
#   name        The command name.
#
# Result:
#   -1 if the command is not found in the leave list.
#
# Side effect:
#   Tracing is disabled on the command.
#   The variable name is removed from the leave list.
proc ::TagmaDebug::Unleave {name} {
    variable leave
    set i [lsearch -exact $leave $name]
    if {$i < 0} {return -1}
    set leave [lreplace $leave $i $i]
    catch {
        trace remove execution $name leave ::TagmaDebug::Leave
    }
    return 0
}

# ::TagmaDebug::Step --
#   Callback for command step.
#   This is really named _Step because the first step isn't real.
#   So to skip that step a fake Step is called for the first one
#   then renames this step to Step.
#
# Arguments:
#   From the trace command.
#
# Result:
#   None
#
# Side effect:
#   Prints the command that is about to be executed
#   Disables debugging upon entering TagmaDebug.
proc ::TagmaDebug::_Step {cmdstring op} {
    variable debugDisabled
    if {$debugDisabled} { return }

    # Disable debugging for certain commands.
    switch -glob -- $cmdstring {
        ::TagmaDebug::* {
            # Disable for the debugger its self.
            set debugDisabled 1
            return
        }
        "proc *" {
            # Disable debug, but show the user it was called.
            set debugDisabled 1
            variable settings
            if {!$settings(body)} {
                set cmdstring [lrange $cmdstring 0 end-1]
            }
        }
        "::unknown *" {
            # Disable debug, but show the user it was called.
            set debugDisabled 1
        }
        "package *" {
            variable settings
            if {!$settings(packages)} {
                # Disable debug, but show the user it was called.
                # Will not be re-enabled till after the command exits.
                # See EnableDebug for more information.
                variable debugDisabledCmd
                set debugDisabled -1
                set debugDisabledCmd $cmdstring
            }
        }
    }

    switch -- $op {
        enterstep {
            Eputs -prefix -list -- [split $cmdstring "\n\r"]
        }
        default {
            error "Step: Unknown OP '$op' for '$cmdstring'."
        }
    }
    uplevel 1 ::TagmaDebug::debug [list $cmdstring]
}

# ::TagmaDebug::__Step --
#   Fake Step to hide the first step.
#   This step is really the uplevel call to start debugging.
#   There is no need to see that.
#
# Arguments:
#   From the trace command.
#
# Result:
#   None
#
# Side effect:
#   Renames Step to __Step.
#   Renames _Step to Step.
proc ::TagmaDebug::Step {cmdstring op} {
    rename ::TagmaDebug::Step ::TagmaDebug::__Step
    rename ::TagmaDebug::_Step ::TagmaDebug::Step
}

# ::TagmaDebug::Unstep --
#   Removes the enter trace from a command.
#
# Arguments:
#   name        The command name.
#
# Result:
#   -1 if the command is not found in the step list.
#
# Side effect:
#   Tracing is disabled on the command.
#   The variable name is removed from the step list.
proc ::TagmaDebug::Unstep {name} {
    variable step
    set i [lsearch -exact $step $name]
    if {$i < 0} {return -1}
    set step [lreplace $step $i $i]
    catch {
        trace remove execution $name enterstep ::TagmaDebug::Step
    }
    return 0
}

# ::TagmaDebug::EnableDebug--
#   Callback to re-enable debugging.
#   Add as a leave callback and debugging will be turned back on.
#
# Arguments:
#   From the trace command.
#
# Result:
#   None
#
# Side effect:
#   Prints the command that is about to be executed
#   Disables debugging upon entering TagmaDebug.
proc ::TagmaDebug::EnableDebug {cmdstring code result op} {
    variable debugDisabledCmd
    if {$cmdstring eq $debugDisabledCmd} {
        variable debugDisabled
        set debugDisabled 0
        set debugDisabledCmd ""
        variable settings
        if {$settings(verbose)} {
            Eputs -prefix "Leaving: $cmdstring"
        }
    }
}

# XXX Interactive XXX

# ::TagmaDebug::PrintHelp --
#   Prints the help text.
#
# Arguments:
#
# Result:
#   None
#
# Side effect:
#   Prints the help text.
proc ::TagmaDebug::PrintHelp {} {
    variable settings
    Eputs $settings(descr)
    Eputs -list -- {
        "Commands are:"
        "    !           Execute a shell command."
        "    =           Prints the content of each variable name provided."
        "    a or >      Prints the command being executed."
        "    c or Enter  Continue execution."
        "    h or ?      Prints this message."
        "    e or \[..\]   Evaluates a command."
        "    var         Watchs the modifications of some variables."
        "        log     Logs all modifications to stderr."
        "        break   Adds breakpoint for writes."
        "        info    Prints all variables being watched for."
        "        clear   Clears logging and breaks."
        "    cmd         Watches commands."
        "        enter   Set a break point for the entering of a command."
        "        leave   Set a break point for the leaving of a command."
        "        info    Prints all commands being watched.."
        "        step    Steps through the command."
        "        clear   Clear break points (using glob patterns)."
        "    procs       Print defined procedures  (using glob patterns)."
        "    p           Prints the current level & procedure."
        "    r           Restarts the program."
        "    x or q      Exit the debugger."
        "Settings: (Reflected by the flags in '{}')"
        "    B           Toggle printing the body of procedures."
        "    E           Toggle Enter acting as a shortcut to 'c Enter'."
        "    P           Toggle stepping into package."
        "    V           Toggle verbosity. (Print extra info, when available.)"
        "Based on TclDebugger by S.Arnold. v0.1 2007-09-09 http://wiki.tcl.tk/19872"
        }
}

# ::TagmaDebug::debug --
#   The interactive part of the debugger.
#   Prompts the user for input and acts on it.
#
# Arguments:
#   cmdstring   The optional command that is about to be executed.
#
# Result:
#   None
#
# Side effect:
#   Manipulates tracing and the lists.
proc ::TagmaDebug::debug {{cmdstring ""}} {
    variable settings

    while 1 {
        # Build the prompt details.
        set    flags [expr {$settings(body)     ? "B" : ""}]
        append flags [expr {$settings(enter)    ? "E" : ""}]
        append flags [expr {$settings(packages) ? "P" : ""}]
        append flags [expr {$settings(verbose)  ? "V" : ""}]
        set level [uplevel 1 info level]
        set command ""
        if {$level > 0} {
            set command " => [lindex [uplevel 1 info level 0] 0]"
        }

        # Prompt and wait for input.
        if {$settings(server)} {
            Eputs "{$flags}($level$command)$settings(prompt)"
        } else {
            Eputs -nonewline "{$flags}($level$command)$settings(prompt)"
            flush stderr
        }

        if {$settings(server)} {
            if {[gets $settings(socket) line] < 0} {
                CloseConnection
                continue
            }
            if {$line eq "{}"} {
                    set line ""
            }
        } elseif {[gets stdin line] < 0} {
            puts ""
            exit
        }
        if {$line eq ""} {
            if {$settings(enter)} {
                return
            } else {
                continue
            }
        }

        # Special case, execute anything embedded in '[...]'.
        if {[string index $line 0] eq "\["} {
            if {[catch {Eputs [uplevel 1 [string range $line 1 end-1]]} msg]} {
                Eputs "Error: $msg"
            }
            continue
        }

        set command [lindex $line 0]
        switch -- $command {
            !       {
                if {[catch {Eputs [exec -ignorestderr -- [lrange $line 1 end]]} msg]} {
                    Eputs "Error: $msg"
                }
            }
            =       {
                foreach var [lrange $line 1 end] {
                    uplevel 1 ::TagmaDebug::PrintVariable $var
                }
            }
            a - >   {
                Eputs $cmdstring
            }
            c       {
                return
            }
            e       {
                if {[catch {Eputs [uplevel 1 [lrange $line 1 end]]} msg]} {
                    Eputs "Error: $msg"
                }
            }
            h - ?   {
                PrintHelp
            }
            procs   {
                variable procs
                if {[llength $line] eq 1} {
                    Eputs -list $procs
                } else {
                    set print_list {}
                    set search [lindex $line 1]
                    foreach proc $procs {
                        if {[string match $search $proc]} {
                            lappend print_list $proc
                        }
                    }
                    Eputs -list $print_list
                }
            }
            p       {
                set command "::"
                set level [uplevel 1 info level]
                if {$level > 0} {
                    set command [uplevel 1 info level 0]
                }
                Eputs "($level) $command"
            }
            var     {
                if {[llength $line] < 2 || [llength $line] > 3} {
                    Eputs "Bad Syntax! $command requires 1 or 2 arguments."
                    continue
                }
                foreach {subcmd value} [lrange $line 1 end] {break}
                switch -- $subcmd {
                    log     {
                        variable log
                        set log [Store $log $value]
                        uplevel 1 [list trace add variable $value {read write unset} ::TagmaDebug::Log]
                    }
                    break   {
                        variable break
                        set break [Store $break $value]
                        uplevel 1 [list trace add variable $value {read write unset} ::TagmaDebug::Break]
                    }
                    info    {
                        foreach {n t} {log Logged break "Breaks at"} {
                            variable $n
                            Eputs "=== $t: ==="
                            Eputs [lsort [set $n]]
                            Eputs "----"
                        }
                    }
                    clear   {
                        foreach {v t cmd} {log Logged Unlog break "Breaks at" Unbreak} {
                            Eputs "clearing $t..."
                            variable $v
                            foreach i [set $v] {
                                if {[string match $value $i]]} {
                                    Eputs $i
                                    # unlogs or unbreaks the variable
                                    ::TagmaDebug::$cmd $i
                                }
                            }
                        }
                    }
                    default { Eputs "No such option: $subcmd" }
                }
            }
            cmd     {
                if {[llength $line] < 2 || [llength $line] > 3} {
                    Eputs "Bad Syntax! $command requires 1 or 2 arguments."
                    continue
                }
                foreach {subcmd value} [lrange $line 1 end] {break}
                switch -- $subcmd {
                    enter   {
                        if {![CheckCommand $value]} {
                            Eputs "The command '$value' does not currently exist."
                            Eputs "Can not set a break point for a non-existant command."
                            continue
                        }
                        variable enter
                        set enter [Store $enter $value]
                        trace add execution $value enter ::TagmaDebug::Enter
                    }
                    leave   {
                        if {![CheckCommand $value]} {
                            Eputs "The command '$value' does not currently exist."
                            Eputs "Can not set a break point for a non-existant command."
                            continue
                        }
                        variable leave
                        set leave [Store $leave $value]
                        trace add execution $value leave ::TagmaDebug::Leave
                    }
                    step    {
                        if {![CheckCommand $value]} {
                            Eputs "The command '$value' does not currently exist."
                            Eputs "Can not set a break point for a non-existant command."
                            continue
                        }
                        variable step
                        set step [Store $step $value]
                        trace add execution $value enterstep ::TagmaDebug::Step
                    }
                    info    {
                        foreach {n t} {enter Enters leave Leaves step Stepping} {
                            variable $n
                            Eputs "=== $t: ==="
                            Eputs [lsort [set $n]]
                            Eputs "----"
                        }
                    }
                    clear   {
                        foreach {v t cmd} {enter Enters   Unenter
                                           leave Leaves   Unleave
                                           step  Stepping Unstep} {
                            Eputs "clearing $t..."
                            variable $v
                            foreach i [set $v] {
                                if {[string match $value $i]} {
                                    Eputs $i
                                    # 'unenters', 'unleaves' or 'unstep' the command
                                    ::TagmaDebug::$cmd $i
                                }
                            }
                        }
                    }
                    default { Eputs "No such option: $subcmd" }
                }
            }
            con {
                    set host "localhost"
                    set port "5444"
                    if {[llength $line] > 1} {
                            set host [lindex $line 1]
                    }
                    if {[llength $line] > 2} {
                            set port [lindex $line 2]
                    }
                    Eputs "Connecting to the server $host:$port..."
                    if {[catch {set socket [socket localhost 5444]} res]} {
                        Eputs "Unable to connect to the server $host$port."
                        Eputs "Error: $res"
                        continue
                    }
                    set settings(server) 1
                    set settings(socket) $socket
            }
            r       {
                variable argv0
                variable argv
                eval exec [list [info nameofexecutable] $argv0] $argv
                exit
            }
            x - q   {
                exit
            }
            B       {
                set settings(body) [expr {!$settings(body)}]
            }
            E       {
                set settings(enter) [expr {!$settings(enter)}]
            }
            P       {
                set settings(packages) [expr {!$settings(packages)}]
            }
            V       {
                set settings(verbose) [expr {!$settings(verbose)}]
            }
            default {
                Eputs "no such command: $command"
            }
        }
    }
}

# XXX Setup & Entry XXX

# ::TagmaDebug::Prepare --
#   Prepares for debugging.
#
# Arguments:
#   None
#
# Result:
#   None
#
# Side effect:
#   Enables tracing on __TagmaDebugMain.
#   Enables tracing on __TagmaDebugComplete, but does not store it in a list.
#   Informs the user debugging is starting.
proc ::TagmaDebug::Prepare {} {
    global argv argv0
    variable settings

    # Make sure there is something to debug.
    if {[llength $argv] == 0} {
        puts "Usage: $argv0 Script.tcl ..."
        puts ""
        puts "A script to debug is required."
        puts "All command line options are passed to the script."
        exit
    }

    # Set argv for the script.
    set argv0 [lindex $argv 0]
    set argv [lrange $argv 1 end]
    if {![file exists $argv0]} {
        set argv0 [auto_execok $argv0]
    }

    # Set the trace on the top level procedure.
    variable step
    set step [Store $step __TagmaDebugMain]
    trace add execution __TagmaDebugMain enterstep ::TagmaDebug::Step

    # Always catch at the end of the program.
    trace add execution __TagmaDebugComplete enter ::TagmaDebug::Enter

    # Traces to re-enable debugging after certain commands.
    trace add execution package leave ::TagmaDebug::EnableDebug

    Eputs $settings(descr)
    Eputs "Type h to the prompt to get help."
    Eputs ""
    Eputs "Debugging starts here:"
}

# __TagmaDebugMain --
#   The main entry point for debugging.
#   All activity from this procedure on is stepped over.
#   Calling the script from here insures it is debugged.
#   The uplevel call is skipped over bu the debugger.
#
# Arguments:
#   None
#
# Result:
#   None
#
# Side effect:
#   The passed script is run.
proc __TagmaDebugMain {} {
    uplevel 1 "source $::argv0"
}

# __TagmaDebugComplete --
#   Marks the end of debugging.
#   Triggers the debugger even when all commands are cleared.
#   Gives the user a chance to further debug after their script exits.
#
# Arguments:
#   None
#
# Result:
#   None
#
# Side effect:
#   Causes the debugger to be entered.
proc __TagmaDebugComplete {} {
}

# unknown --
#   Replacement for "unknown" to catch errors so the script does not exit.
#
# Arguments:
#   args        Arguments normally passed to unknown.
#
# Result:
#   None
#
# Side effect:
#   Invokes the debugger if called and the real unknown throws an error.
#   Prints details of the error, and args if verbose.
rename unknown _tagma_unknown
proc unknown {args} {
    variable ::TagmaDebug::settings
    if {$::TagmaDebug::settings(verbose)} {
        ::TagmaDebug::Eputs "'unknown' has been invoked with: $args"
    }

    if {[catch {uplevel 1 [list _tagma_unknown {*}$args]} msg]} {
        ::TagmaDebug::Eputs "Error from 'unknown': $msg"
        if {$::TagmaDebug::settings(verbose)} {
            ::TagmaDebug::Eputs "Args passed to 'unknown': $args"
        }
        ::TagmaDebug::debug
    }

    # Re-enable debugging.
    variable ::TagmaDebug::debugDisabled
    if {$debugDisabled > 0} {set debugDisabled 0}
}

# proc --
#   Replacement for "proc" to record procedures as they are created.
#
# Arguments:
#   name        Name of the procedure,
#   args        Argument list for the procedure.
#   body        Procedure body.
#
# Result:
#   None
#
# Side effect:
#   Records the procedure in the list procs
#   Creates the procedure as normal.
rename proc _tagma_proc
_tagma_proc proc {name args body} {
    variable ::TagmaDebug::settings
    variable ::TagmaDebug::procs

    if {$::TagmaDebug::settings(verbose)} {
        ::TagmaDebug::Eputs "Creating procedure '$name' {$args}."
    }

    # Add the procedure to the procs list.
    set ::TagmaDebug::procs [::TagmaDebug::Store $::TagmaDebug::procs $name]

    # Create the procedure.
    _tagma_proc $name $args $body

    # Re-enable debugging.
    variable ::TagmaDebug::debugDisabled
    if {$debugDisabled > 0} {set debugDisabled 0}
}

# Prepare and go!
::TagmaDebug::Prepare
__TagmaDebugMain
__TagmaDebugComplete
