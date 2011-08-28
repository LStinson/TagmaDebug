#!/usr/bin/env tclsh
# tagma.tcl --
# Last Modified: 2011-08-27
#
# Implements simple debugging for TCL.
# By Lorance Stinson AT Gmail.....
# The name was selected to, hopefully, not clash with anything existing.
# Based on "TclDebugger by S.Arnold. v0.1 2007-09-09" - http://wiki.tcl.tk/19872

namespace eval ::TagmaDebug:: {
    variable argv $::argv
    variable argv0 $::argv0
    variable break ""
    variable log ""
    variable enter ""
    variable leave ""
    variable step ""
    variable prompt "Tagma> "
    variable description "TagmaDebug by Lorance Stinson AT Gmail..."
    variable verbose 0
    variable entercontinues 1
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
#   Re-enables tracing on __TagmaDebugMain if it should be on.
proc ::TagmaDebug::Break {name1 name2 op} {
    switch -- $op {
        read - write {
            eputs "$op [var $name1 $name2] = [uplevel 1 set [var $name1 $name2]]"
        }
        unset {
            eputs "unset [var $name1 $name2]"
            # Stop tracing this variable if it is unset.
            if {[Unbreak [var $name1 $name2]] < 0} {
                Unbreak $name1
            }
        }
        default {
            error "Break: Unknown OP '$op' for '$name1' - '$name2'."
        }
    }
    uplevel 1 ::TagmaDebug::debug

    # Turn tracing back on for __TagmaDebugMain, if it previously was.
    variable step
    if {[lsearch -exact $step "__TagmaDebugMain"] >= 0} {
        trace add execution __TagmaDebugMain enterstep ::TagmaDebug::Step
    }
}

# ::TagmaDebug::Unbreak --
#   Removes the break trace from a variable.
#
# Arguments:
#   name        The name of the variable.
#
# Result:
#   -1 if the variable is not found break list.
#
# Side effect:
#   Tracing is disabled on the variable.
#   The variable name is removed from the break list.
proc ::TagmaDebug::Unbreak {name} {
    variable break
    set i [lsearch -exact $break $name]
    if {$i < 0} {return -1}
    set break [lreplace $break $i $i]
    catch {
        trace remove variable $name {read write unset} ::TagmaDebug::Break
    }
    return 0
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
#   Re-enables tracing on __TagmaDebugMain if it should be on.
proc ::TagmaDebug::Log {name1 name2 op} {
    switch -- $op {
        read - write {
            eputs "$op [var $name1 $name2] = [uplevel 1 set [var $name1 $name2]]"
        }
        unset {
            eputs "unset [var $name1 $name2]"
            # Stop tracing this variable if it is unset.
            if {[Unlog [var $name1 $name2]] < 0} {
                Unlog $name1
            }
        }
        default {
            error "Log: Unknown OP '$op' for '$name1' - '$name2'."
        }
    }

    # Turn tracing back on for __TagmaDebugMain, if it previously was.
    variable step
    if {[lsearch -exact $step "__TagmaDebugMain"] >= 0} {
        trace add execution __TagmaDebugMain enterstep ::TagmaDebug::Step
    }
}

# ::TagmaDebug::Unlog --
#   Removes the logging trace from a variable.
#
# Arguments:
#   name        The name of the variable.
#
# Result:
#   -1 if the variable is not found in the log list.
#
# Side effect:
#   Tracing is disabled on the variable.
#   The variable name is removed from the log list.
proc ::TagmaDebug::Unlog {name} {
    variable log
    set i [lsearch -exact $log $name]
    if {$i < 0} {return -1}
    set log [lreplace $log $i $i]
    catch {
        trace remove variable $name {read write unset} ::TagmaDebug::Log
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
    lappend list $elt
    return $list
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
proc ::TagmaDebug::Enter {cmdstring op} {
    switch -- $op {
        enter {
            eputs "Entering: [lindex $cmdstring 0]"
            variable verbose
            if {$verbose} {
                eputs "Args: [list [lrange $cmdstring 1 end]]"
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
proc ::TagmaDebug::Leave {cmdstring code result op} {
    switch -- $op {
        leave {
            eputs "Leaving: [lindex $cmdstring 0]"
            variable verbose
            if {$verbose} {
                eputs "Result Code: $code"
                eputs "Result: [list $result]"
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
#
# Arguments:
#   From the trace command.
#
# Result:
#   None
#
# Side effect:
#   Disables the step trace on __TagmaDebugMain if entering Log or Break.
#   (This is to not step into the debugger.)
#   Prints the command that is about to be executed
#   Enters the debugger prompt.
proc ::TagmaDebug::Step {cmdstring op} {
    if {[string range $cmdstring 0 16] eq "::TagmaDebug::Log" ||
        [string range $cmdstring 0 18] eq "::TagmaDebug::Break"} {
        # Disable tracing on __TagmaDebugMain.
        # Don't want to trace variable breakpoints...
        trace remove execution __TagmaDebugMain enterstep ::TagmaDebug::Step
        return
    }

    switch -- $op {
        enterstep {
            eputs $cmdstring
        }
        default {
            error "Step: Unknown OP '$op' for '$cmdstring'."
        }
    }
    uplevel 1 ::TagmaDebug::debug [list $cmdstring]
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

# ::TagmaDebug::eputs --
#   Prints a string to STDERR
#
# Arguments:
#   string      The string to print
#
# Result:
#   None
#
# Side effect:
#   The string is printed to STDERR.
proc ::TagmaDebug::eputs {string} {
    puts stderr $string
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
        eputs "$varname = [uplevel 1 set $varname]"
    } else {
        eputs "variable $varname does not exist"
    }
}

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

# ::TagmaDebug::PrintHelp --
#   Prints the help text.
#
# Arguments:
#   ARG         ARG Description
#
# Result:
#   None
#
# Side effect:
#   Prints the help text.
proc ::TagmaDebug::PrintHelp {} {
    variable description
    eputs description
    eputs [join {
        "Commands are:"
        "    h or ?      Prints this message."
        "    a or >      Prints the command being executed."
        "    p           Prints the current level & procedure."
        "    e or \[..\]   Evaluates a command."
        "    !           Execute a shell command."
        "    =           Prints the content of each variable name."
        "    var         Watchs the modifications of some variables."
        "        log     Logs all modifications to stderr."
        "        break   Adds breakpoint for writes."
        "        info    Prints all variables being watched for."
        "        clear   Clears logging and breaks."
        "    cmd"
        "        enter   Set a break point for the entering of a command."
        "        leave   Set a break point for the leaving of a command."
        "        info    Prints all commands being watched.."
        "        step    Steps through the command."
        "        clear   Clear break points (using glob patterns)."
        "    c or Enter  Continue execution."
        "    r           Restarts the program."
        "    v           Toggle verbosity. (Print extra info, when available.)"
        "    x or q      Exit the debugger."
        "Based on TclDebugger by S.Arnold. v0.1 2007-09-09 http://wiki.tcl.tk/19872"
        } "\n"]
}

# ::TagmaDebug::debug --
#   The interactive part of the debugger.
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
    while 1 {
        variable entercontinues
        variable prompt
        variable verbose

        # Prompt and wait for input.
        set flag [expr {$verbose ? "{V}" : ""}]
        puts -nonewline stderr "$flag$prompt"
        flush stderr

        if {[gets stdin line] < 0} {
            puts ""
            exit
        } elseif {$line eq ""} {
            if {$entercontinues} {
                return
            } else {
                continue
            }
        }

        # Special case, execute anything embedded in '[...]'.
        if {[string index $line 0] eq "\["} {
            if {[catch {eputs [uplevel 1 [string range $line 1 end-1]]} msg]} {
                eputs "Error: $msg"
            }
            continue
        }

        set command [lindex $line 0]
        switch -- $command {
            h - ?   {
                PrintHelp
            }
            e       {
                if {[catch {eputs [uplevel 1 [lrange $line 1 end]]} msg]} {
                    eputs "Error: $msg"
                }
            }
            ! {
                if {[catch {eputs [exec -ignorestderr -- [lrange $line 1 end]]} msg]} {
                    eputs "Error: $msg"
                }
            }
            a - >   {
                eputs $cmdstring
            }
            p       {
                set command "::"
                set level [uplevel 1 info level]
                if {$level > 0} {
                    set command [uplevel 1 info level 0]
                }
                eputs "($level) $command"
            }
            =       {
                foreach var [lrange $line 1 end] {uplevel 1 ::TagmaDebug::PrintVariable $var}
            }
            var     {
                if {[llength $line] < 2 || [llength $line] > 3} {
                    eputs "Bad Syntax! $command requires 1 or 2 arguments."
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
                            eputs "=== $t: ==="
                            eputs [set $n]
                            eputs "----"
                        }
                    }
                    clear   {
                        foreach {v t cmd} {log Logged Unlog break "Breaks at" Unbreak} {
                            eputs "clearing $t..."
                            variable $v
                            foreach i [set $v] {
                                if {[string match $value $i]]} {
                                    eputs $i
                                    # unlogs or unbreaks the variable
                                    ::TagmaDebug::$cmd $i
                                }
                            }
                        }
                    }
                    default { eputs "no such subcommand: $subcmd" }
                }
            }
            cmd     {
                if {[llength $line] < 2 || [llength $line] > 3} {
                    eputs "Bad Syntax! $command requires 1 or 2 arguments."
                    continue
                }
                foreach {subcmd value} [lrange $line 1 end] {break}
                switch -- $subcmd {
                    enter   {
                        if {![CheckCommand $value]} {
                            eputs "The command '$value' does not currently exist."
                            eputs "Can not set a break point for a non-existant command."
                            continue
                        }
                        variable enter
                        set enter [Store $enter $value]
                        trace add execution $value enter ::TagmaDebug::Enter
                    }
                    leave   {
                        if {![CheckCommand $value]} {
                            eputs "The command '$value' does not currently exist."
                            eputs "Can not set a break point for a non-existant command."
                            continue
                        }
                        variable leave
                        set leave [Store $leave $value]
                        trace add execution $value leave ::TagmaDebug::Leave
                    }
                    step    {
                        if {![CheckCommand $value]} {
                            eputs "The command '$value' does not currently exist."
                            eputs "Can not set a break point for a non-existant command."
                            continue
                        }
                        variable step
                        set step [Store $step $value]
                        trace add execution $value enterstep ::TagmaDebug::Step
                    }
                    info    {
                        foreach {n t} {enter Enters leave Leaves step Stepping} {
                            variable $n
                            eputs "=== $t: ==="
                            eputs [set $n]
                            eputs "----"
                        }
                    }
                    clear   {
                        foreach {v t cmd} {enter Enters Unenter leave Leaves Unleave step Stepping Unstep} {
                            eputs "clearing $t..."
                            variable $v
                            foreach i [set $v] {
                                if {[string match $value $i]} {
                                    eputs $i
                                    # 'unenters', 'unleaves' or 'unstep' the command
                                    ::TagmaDebug::$cmd $i
                                }
                            }
                        }
                    }
                    default { eputs "no such subcommand: $subcmd" }
                }
            }
            c       {
                return
            }
            r       {
                variable argv0
                variable argv
                eval exec [list [info nameofexecutable] $argv0] $argv
                exit
            }
            v       {
                set verbose [expr {!$verbose}] }
            x - q   {
                exit
            }
            default {
                eputs "no such command: $command"
            }
        }
    }
}

# ::TagmaDebug::prepare --
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
proc ::TagmaDebug::prepare {} {
    global argv argv0
    variable description

    # Make sure there is something to debug.
    if {[llength $argv] == 0} {
        puts "Usage: $argv0 Script.tcl ..."
        puts ""
        puts "A script to debug is required."
        puts "All command line options are passed to the script."
        exit
    }

    # Start the program!
    set argv0 [lindex $argv 0]
    set argv [lrange $argv 1 end]

    # Prompts
    eputs $description
    eputs "Type h to the prompt to get help."
    if {![file exists $argv0]} {
        set argv0 [auto_execok $argv0]
    }

    # steps toplevel execution
    variable step
    set step [Store $step __TagmaDebugMain]
    trace add execution __TagmaDebugMain enterstep ::TagmaDebug::Step

    # Always catch at the end of the program.
    trace add execution __TagmaDebugComplete enter ::TagmaDebug::Enter

    eputs ""
    eputs "Debugging starts here:"
}

# __TagmaDebugMain --
#   The main entry point for debugging.
#   All activity from this procedure on is stepped over.
#   Calling the script from here insures it is debugged.
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

# Prepare and go!
::TagmaDebug::prepare
__TagmaDebugMain
__TagmaDebugComplete
