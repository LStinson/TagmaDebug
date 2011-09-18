#!/usr/bin/env tclsh
# tagma.tcl --
# Last Modified: 2011-09-03
# vim:ft=tcl foldmethod=marker
#
# Implements simple debugging for TCL.
# By Lorance Stinson AT Gmail.....
#
# The name was selected to, hopefully, not clash with anything existing.
# Based on "TclDebugger by S.Arnold. v0.1 2007-09-09" - http://wiki.tcl.tk/19872

# Namespace -- {{{1
namespace eval ::TagmaDebug:: {
    variable argv       $::argv
    variable argv0      $::argv0
    variable traces
    array set traces {
        varbreak        {}
        varlog          {}
        enter           {}
        enterstep       {}
        leave           {}
    }
    variable procs      {}
    variable settings
    array set settings {
        body        1
        descr       "TagmaDebug by Lorance Stinson AT Gmail..."
        disabled    0
        disablecmd  ""
        enter       1
        packages    0
        prefix      ">>"
        prompt      "Tagma> "
        server      0
        serverHost  "localhost"
        serverPort  "5444"
        socket      ""
        verbose     0
    }
}

# XXX Utilities XXX {{{1

# ::TagmaDebug::CheckCommand -- {{{2
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
    if {[uplevel 1 info procs $command]     ne "" ||
        [uplevel 1 info commands $command]  ne "" ||
        [uplevel 1 info functions $command] ne ""} {
        return 1
    }
    return 0
}

# ::TagmaDebug::CloseConnection -- {{{2
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

# ::TagmaDebug::EPuts -- {{{2
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
proc ::TagmaDebug::EPuts {args} {
    variable settings
    set channel [expr {$settings(server) ? $settings(socket) : "stderr"}]
    set cmd "puts"
    set count 0
    set list 0
    set prefix ""
    foreach arg $args {
        switch -exact -- $arg {
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
    if {$settings(server) && [catch {flush $channel}]} {
        CloseConnection
    }
}

# ::TagmaDebug::OpenConnection -- {{{2
#   Open a connection to a server.
#
# Arguments:
#   None
#
# Result:
#   None
#
# Side effect:
#   The connection is Opend and the settings are updated.
proc ::TagmaDebug::OpenConnection {} {
    variable settings
    set host $settings(serverHost)
    set port $settings(serverPort)
    EPuts "Connecting to the server $host:$port..."
    if {[catch {set socket [socket $host $port]} res]} {
        EPuts "Unable to connect to $host:$port."
        EPuts "Error: $res"
        continue
    }
    set settings(server) 1
    set settings(socket) $socket
}

# ::TagmaDebug::PrintErrorDetail -- {{{2
#   Prints details from an uncaught error
#
# Arguments:
#   errCode     The error code.
#   stackTrace  The stack trace.
#   errMsg      The error message.
#
# Result:
#   None
#
# Side effect:
#   The error details are printed.
proc ::TagmaDebug::PrintErrorDetail {errCode stackTrace errMsg} {
    EPuts -prefix "Uncaught error thrown!"
    switch -exact -- $errCode {
        1 { set codeDescr "TCL_ERROR" }
        2 { set codeDescr "TCL_RETURN" }
        3 { set codeDescr "TCL_BREAK" }
        4 { set codeDescr "TCL_CONTINUE" }
        default { set codeDescr "Unknown" }
    }
    EPuts -prefix "Error Code: $errCode ($codeDescr)"
    EPuts -prefix "Error Message: $errMsg"
    EPuts -prefix "Stack Trace:"
    EPuts -prefix -list [split $stackTrace "\r\n"]
}

# ::TagmaDebug::PrintVariable -- {{{2
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
        EPuts -prefix "$varname = [uplevel 1 set $varname]"
    } else {
        EPuts -prefix "Variable '$varname' does not exist."
    }
}

# ::TagmaDebug::Store -- {{{2
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

# ::TagmaDebug::var -- {{{2
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

# XXX Tracing Callbacks XXX {{{1

# ::TagmaDebug::CmdCallback -- {{{2
#   Callback for tracing commands.
#
# Arguments:
#   From the trace command.
#
# Result:
#   None
#
# Side effect:
#   Prints information for the command.
#   Disables logging if entering the debugger
#   Enters the debugger prompt.
proc ::TagmaDebug::_CmdCallback {args} {
    variable settings

    if {$settings(disabled)} { return }

    # Extract the parts needed from the args.
    set cmdstring [lindex $args 0]
    set op [lindex $args end]

    # Disable debugging for certain commands.
    switch -glob -- $cmdstring {
        ::TagmaDebug::* {
            # Disable for the debugger its self.
            set settings(disabled) 1
            return
        }
        "proc *" {
            # Disable debug, but show the user it was called.
            set settings(disabled) 1
            if {!$settings(body)} {
                set cmdstring [lrange $cmdstring 0 end-1]
            }
        }
        "::unknown *" {
            # Disable debug, but show the user it was called.
            set settings(disabled) 1
        }
        "package *" {
            if {!$settings(packages)} {
                # Disable debug, but show the user it was called.
                # Will not be re-enabled till after the command exits.
                # See EnableDebug for more information.
                set settings(disabled) -1
                set settings(disablecmd) $cmdstring
            }
        }
    }

    switch -- $op {
        enter {
            EPuts -prefix "Entering: [lindex $cmdstring 0]"
            if {$settings(verbose)} {
                EPuts -prefix "Args: [list [lrange $cmdstring 1 end]]"
            }
        }
        leave {
            EPuts -prefix "Leaving: [lindex $cmdstring 0]"
            if {$settings(verbose)} {
                set code [lindex $args 1]
                set result [lindex $args 2]
                EPuts -prefix "Result Code: $code"
                EPuts -prefix "Result: [list $result]"
            }
        }
        enterstep {
            EPuts -prefix -list -- [split $cmdstring "\n\r"]
        }
        default {
            error "CmdCallback: Unknown OP '$op' for '$cmdstring'."
        }
    }
    uplevel 1 ::TagmaDebug::debug [list $cmdstring]
}

# ::TagmaDebug::__CmdCallback -- {{{2
#   Fake CmdCallback to hide the first step.
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
#   Renames CmdCallback to __CmdCallback.
#   Renames _CmdCallback to CmdCallback.
proc ::TagmaDebug::CmdCallback {args} {
    rename ::TagmaDebug::CmdCallback ::TagmaDebug::__CmdCallback
    rename ::TagmaDebug::_CmdCallback ::TagmaDebug::CmdCallback
}

# ::TagmaDebug::RemoveCmdTrace -- {{{2
#   Remove a trace from a command.
#
# Arguments:
#   name        The name of the command.
#   op          The operation to remove the trace for.
#
# Result:
#   -1 if the variable is not found in the list.
#
# Side effect:
#   Tracing is disabled on the command.
#   The command name is removed from the trace list.
proc ::TagmaDebug::RemoveCmdTrace {name op} {
    variable traces
    set i [lsearch -exact $traces($op) $name]
    if {$i < 0} {return -1}
    set traces($op) [lreplace $traces($op) $i $i]

    catch { trace remove execution $name $op ::TagmaDebug::CmdCallback }
    return 0
}

# ::TagmaDebug::VarCallback -- {{{2
#   Callback for tracing variables.
#
# Arguments:
#   mode        The mode (varbreak or varlog).
#   From the trace command.
#
# Result:
#   None
#
# Side effect:
#   Prints the information for the variable.
#   Disables logging if the variable was unset.
#   Enters the debugger prompt if the mode is break.
#   Re-enables debuggin if disabled.
proc ::TagmaDebug::VarCallback {mode name1 name2 op} {
    switch -- $op {
        read - write {
            EPuts -prefix "$op [var $name1 $name2] = [uplevel 1 set [var $name1 $name2]]"
        }
        unset {
            EPuts -prefix "unset [var $name1 $name2]"
            # Stop tracing this variable if it is unset.
            if {[RemoveVarTrace [var $name1 $name2] $mode] < 0} {
                RemoveVarTrace $name1 $mode
            }
        }
        default {
            error "VarCallback: Unknown OP '$op' for '$name1' - '$name2'."
        }
    }

    if {$mode eq "varbreak"} {
        uplevel 1 ::TagmaDebug::debug
    }

    # Re-enable debugging.
    variable settings
    if {$settings(disabled) > 0} {set settings(disabled) 0}
}

# ::TagmaDebug::RemoveVarTrace -- {{{2
#   Remove a trace from a variable.
#
# Arguments:
#   name        The name of the variable.
#   list        The list to remove the variable from.
#               Also the mode passed to VarCallback.
#
# Result:
#   -1 if the variable is not found in the list.
#
# Side effect:
#   Tracing is disabled on the variable.
#   The variable name is removed from the list.
proc ::TagmaDebug::RemoveVarTrace {name list} {
    variable traces
    set i [lsearch -exact $traces($list) $name]
    if {$i < 0} {return -1}
    set traces($list) [lreplace $traces($list) $i $i]
    uplevel 2 [list trace remove variable $name {read write unset} \
                          "::TagmaDebug::VarCallback $list"]
    return 0
}

# ::TagmaDebug::EnableDebug -- {{{2
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
    variable settings
    if {$cmdstring eq $settings(disablecmd)} {
        set settings(disabled) 0
        set settings(disablecmd) ""
        variable settings
        if {$settings(verbose)} {
            EPuts -prefix "Leaving: $cmdstring"
        }
    }
}

# XXX Interactive XXX {{{1

# ::TagmaDebug::PrintHelp -- {{{2
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
    EPuts $settings(descr)
    EPuts -list -- {
        "Commands are:"
        "    !           Execute a shell command."
        "    =           Prints the content of each variable name provided."
        "    a or >      Prints the command being executed."
        "    c or Enter  Continue execution."
        "    h or ?      Prints this message."
        "    e or \[..\]   Evaluates a command."
        "    f or ff     Print the stack frame. ff also prints file information."
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
        "    con         Connect to a Tagma Debug control server."
        "                Optional Host and port. (Default: localhost and 5444)"
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

# ::TagmaDebug::debug -- {{{2
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
        set levelNum [uplevel 1 info level]
        set command ""
        if {$levelNum > 0} {
            set command " => [lindex [uplevel 1 info level 0] 0]"
        }

        # Prompt and wait for input.
        if {$settings(server)} {
            EPuts "{$flags}($levelNum$command)$settings(prompt)"
        } else {
            EPuts -nonewline "{$flags}($levelNum$command)$settings(prompt)"
            flush stderr
        }

        if {$settings(server)} {
            if {[gets $settings(socket) input] < 0} {
                CloseConnection
                continue
            }
        } elseif {[gets stdin input] < 0} {
            puts ""
            exit
        }

        if {$input eq ""} {
            if {$settings(enter)} {
                return
            } else {
                continue
            }
        }

        # Special case, execute anything embedded in '[...]'.
        if {[string index $input 0] eq "\["} {
            if {[catch {EPuts [uplevel 1 [string range $input 1 end-1]]} msg]} {
                EPuts "Error: $msg"
            }
            continue
        }

        set command [lindex $input 0]
        switch -- $command {
            !       {
                if {[catch {EPuts [exec -ignorestderr -- [lrange $input 1 end]]} msg]} {
                    EPuts "Error: $msg"
                }
            }
            =       {
                foreach var [lrange $input 1 end] {
                    uplevel 1 ::TagmaDebug::PrintVariable $var
                }
            }
            a - >   {
                EPuts $cmdstring
            }
            c       {
                return
            }
            e       {
                if {[catch {EPuts [uplevel 1 [lrange $input 1 end]]} msg]} {
                    EPuts "Error: $msg"
                }
            }
            f - ff {
                set lineFormat "%2s %2s %-6s %-30s %-30s"
                set topFrame [info frame]
                EPuts [format $lineFormat "F#" "L#" "Type" "Proc" "Cmd"]
                for {set i 1} {$i < $topFrame} {incr i} {
                    set frameInfo [info frame $i]
                    if {[string match "::TagmaDebug::*" [dict get $frameInfo cmd]]} {
                        break
                    }
                    set frameType [dict get $frameInfo type]
                    if {$frameType eq "precompiled"} {
                        set frameType "precmp"
                    }
                    set frameCmd [lindex [split [dict get $frameInfo cmd] "\r\n"] 0]
                    if {[string length $frameCmd] != [string length [dict get $frameInfo cmd]]} {
                        set frameCmd "$frameCmd ..."
                    }
                    if {[dict exists $frameInfo "level"]} {
                        set frameLevel [dict get $frameInfo level]
                    } else {
                        set frameLevel ""
                    }
                    if {[dict exists $frameInfo "proc"]} {
                        set frameProc [dict get $frameInfo proc]
                    } else {
                        set frameProc "N/A"
                    }
                    EPuts [format $lineFormat $i $frameLevel $frameType $frameProc $frameCmd]
                    if {$command eq "ff" && $frameType eq "source"} {
                        EPuts [format $lineFormat "" "@"  \
                              [dict get $frameInfo line]  \
                              [dict get $frameInfo file] ""]
                    }
                }
            }
            h - ?   {
                PrintHelp
            }
            procs   {
                variable procs
                if {[llength $input] eq 1} {
                    EPuts -list $procs
                } else {
                    set list {}
                    set search [lindex $input 1]
                    foreach proc $procs {
                        if {[string match $search $proc]} {
                            lappend list $proc
                        }
                    }
                    EPuts -list $list
                }
            }
            p       {
                set command "::"
                set level [uplevel 1 info level]
                if {$levelNum > 0} {
                    set command [uplevel 1 info level 0]
                }
                EPuts "($levelNum) $command"
            }
            var     {
                if {[llength $input] < 2 || [llength $input] > 3} {
                    EPuts "Bad Syntax! $command requires 1 or 2 arguments."
                    continue
                }
                foreach {subcmd value} [lrange $input 1 end] {break}
                variable traces
                switch -- $subcmd {
                    log     {
                        set traces(varlog) [Store $traces(varlog) $value]
                        uplevel 1 [list trace add variable $value {read write unset} \
                                              "::TagmaDebug::VarCallback varlog"]
                    }
                    break   {
                        set traces(varbreak) [Store $traces(varbreak) $value]
                        uplevel 1 [list trace add variable $value {read write unset} \
                                              "::TagmaDebug::VarCallback varbreak"]
                    }
                    info    {
                        foreach {n t} {varlog Logged varbreak "Breaks at"} {
                            EPuts "=== $t: ==="
                            EPuts [lsort $traces($n)]
                            EPuts "----"
                        }
                    }
                    clear   {
                        foreach {v t} {varlog Logged varbreak Breaks} {
                            EPuts "clearing $t..."
                            foreach i $traces($v) {
                                if {[string match $value $i]} {
                                    EPuts $i
                                    # Removes the trace from a variable.
                                    RemoveVarTrace $i $v
                                }
                            }
                        }
                    }
                    default { EPuts "No such option: $subcmd" }
                }
            }
            cmd     {
                if {[llength $input] < 2 || [llength $input] > 3} {
                    EPuts "Bad Syntax! $command requires 1 or 2 arguments."
                    continue
                }
                foreach {subcmd value} [lrange $input 1 end] {break}
                variable traces
                switch -- $subcmd {
                    enter   {
                        if {![CheckCommand $value]} {
                            EPuts "The command '$value' does not currently exist."
                            EPuts "Can not set a break point for a non-existant command."
                            continue
                        }
                        set traces(enter) [Store $traces(enter) $value]
                        trace add execution $value enter ::TagmaDebug::CmdCallback
                    }
                    leave   {
                        if {![CheckCommand $value]} {
                            EPuts "The command '$value' does not currently exist."
                            EPuts "Can not set a break point for a non-existant command."
                            continue
                        }
                        set traces(leave_ [Store $traces(leave) $value]
                        trace add execution $value leave ::TagmaDebug::CmdCallback
                    }
                    step    {
                        if {![CheckCommand $value]} {
                            EPuts "The command '$value' does not currently exist."
                            EPuts "Can not set a break point for a non-existant command."
                            continue
                        }
                        set traces(enterstep) [Store $traces(enterstep) $value]
                        trace add execution $value enterstep ::TagmaDebug::CmdCallback
                    }
                    info    {
                        foreach {n t} {enter Enters leave Leaves enterstep Stepping} {
                            EPuts "=== $t: ==="
                            EPuts [lsort $traces($n)]
                            EPuts "----"
                        }
                    }
                    clear   {
                        foreach {v t} {enter Enters leave Leaves enterstep Stepping} {
                            EPuts "clearing $t..."
                            foreach i $traces($v) {
                                if {[string match $value $i]} {
                                    EPuts $i
                                    ::TagmaDebug::RemoveCmdTrace $i $v
                                }
                            }
                        }
                    }
                    default { EPuts "No such option: $subcmd" }
                }
            }
            con {
                if {[llength $input] > 1} {
                    set settings(serverHost) [lindex $input 1]
                }
                if {[llength $input] > 2} {
                    set settings(serverPort) [lindex $input 2]
                }
                OpenConnection
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
                EPuts "no such command: $command"
            }
        }
    }
}

# XXX Setup & Entry XXX {{{1

# ::TagmaDebug::Usage -- {{{2
#   Print the command line usage.
#
# Arguments:
#   comment     An optional comment to display to the user.
#
# Result:
#   None
#
# Side effect:
#   The command line usage is printed and the program exists.
proc ::TagmaDebug::Usage {{comment ""}} {
    global argv0
    variable settings

    if {$comment ne ""} {
        EPuts $comment
        EPuts ""
    }

    EPuts "Usage: [file tail $argv0] \[Options\] \[--\] Program"
    EPuts "Debug the specified program."
    EPuts ""
    EPuts "Options:"
    EPuts "    -c        Connect to a Tagma debug control server."
    EPuts "    -H HOST   Connect to HOST instead of localhost."
    EPuts "    -h        Display this text."
    EPuts "    -P PORT   Connect to PORT instead of 5444."
    EPuts "$settings(descr)"
    exit 1
}

# ::TagmaDebug::CmdLineOpts -- {{{2
#   Process the command line options.
#
# Arguments:
#   None
#
# Result:
#   None
#
# Side effect:
#   Settings are modified.
proc ::TagmaDebug::CmdLineOpts {} {
    global argv argv0
    variable settings

    set numargs [llength $argv]
    set connect 0
    set count 0
    foreach arg $argv {
        switch -- $arg {
            -- {
                incr count
                break
            }
            -c {
                incr count
                set connect 1
            }
            -H {
                incr count
                if {$count < $numargs} {
                    set settings(serverHost) [lindex $argv $count]
                } else {
                    Usage "Host requored for '-H'."
                }
                incr count
            }
            -h {
                Usage
            }
            -P {
                incr count
                if {$count < $numargs} {
                    set settings(serverPort) [lindex $argv $count]
                } else {
                    Usage "Port requored for '-P'."
                }
                incr count
            }
            default {
                break
            }
        }
    }

    set argv [lrange $argv $count end]

    if {[llength $argv] == 0} {
        Usage "Program required for debugging."
    }

    if {$connect} {
        OpenConnection
    }
}

# ::TagmaDebug::Prepare -- {{{2
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
    global argv0 argv
    variable settings

    # Process command line options.
    CmdLineOpts

    # Set argv for the script.
    set argv0 [lindex $argv 0]
    set argv [lrange $argv 1 end]
    if {![file exists $argv0]} {
        set argv0 [auto_execok $argv0]
    }

    # Set the trace on the top level procedure.
    variable traces
    set traces(enterstep) [Store $traces(enterstep) __TagmaDebugMain]
    trace add execution __TagmaDebugMain enterstep ::TagmaDebug::CmdCallback

    # Always catch at the end of the program.
    trace add execution __TagmaDebugComplete enter ::TagmaDebug::CmdCallback

    # Traces to re-enable debugging after certain commands.
    trace add execution package leave ::TagmaDebug::EnableDebug

    EPuts $settings(descr)
    EPuts "Type h to the prompt to get help."
    EPuts ""
    EPuts "Debugging starts here:"
}

# __TagmaDebugMain -- {{{2
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

# __TagmaDebugComplete -- {{{2
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

# unknown -- {{{2
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
        ::TagmaDebug::EPuts "'unknown' has been invoked with: $args"
    }

    # Call the original "unknown" safely.
    if {[catch {uplevel 1 [list _tagma_unknown {*}$args]} msg]} {
        ::TagmaDebug::EPuts "Error from 'unknown': $msg"
        if {$::TagmaDebug::settings(verbose)} {
            ::TagmaDebug::EPuts "Args passed to 'unknown': $args"
        }
        ::TagmaDebug::debug
    }

    # Re-enable debugging.
    if {$::TagmaDebug::settings(disabled) > 0} {
        set ::TagmaDebug::settings(disabled) 0
    }
}

# proc -- {{{2
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
        ::TagmaDebug::EPuts "Creating procedure '$name' {$args}."
    }

    # Add the procedure to the procs list.
    set ::TagmaDebug::procs [::TagmaDebug::Store $::TagmaDebug::procs $name]

    # Create the procedure.
    _tagma_proc $name $args $body

    # Re-enable debugging.
    if {$::TagmaDebug::settings(disabled) > 0} {
        set ::TagmaDebug::settings(disabled) 0
    }
}

# Prepare and go! {{{2
::TagmaDebug::Prepare
if {$tcl_version == 8.5} {
    if {[set errCode [catch {__TagmaDebugMain} errMsg errOpts]]} {
        ::TagmaDebug::PrintErrorDetail $errCode [dict get $errOpts -errorinfo] $errMsg
    }
} else {
    if {[set errCode [catch {__TagmaDebugMain} errMsg]]} {
        ::TagmaDebug::PrintErrorDetail $errCode $::errorInfo $errMsg
    }
}
__TagmaDebugComplete
