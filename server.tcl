#!/usr/bin/env tclsh
# tagmaserver.tcl --
# Last Modified: 2011-09-03
#
# A control server to the Tagma Debugger.
# The debugger connects to the server allowing remote control
# of the debuggger.

namespace eval ::TagmaServer:: {
    namespace export tagma
    variable defaultPort 5444
    variable clients
    array set clients {}
    variable settings
    array set settings {
        channel     ""
        current     ""
        descr       "Tagma Debug Server by Lorance Stinson AT Gmail..."
        prefix      "Tagma:"
        prompt      "Tagma> "
        shell       0
        verbose     1
    }
    variable endshell 0
}
# ::TagmaDebug::print --
#   Prints string(s).
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
#   The strings are printed.
proc ::TagmaServer::print {args} {
    variable settings
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
        eval "$cmd \"\$prefix\$arg\""
    }
    flush stdout
}


# ::TagmaServer::Server --
#   Start the server process.
#
# Arguments:
#   port        Optional port to listen on.
#
# Result:
#   None
#
# Side effect:
#   The server process is started.
#   The settings are updated.
proc ::TagmaServer::Server {{port ""}} {
    variable settings
    if {$port eq ""} {
        variable defaultPort
        set port $defaultPort
    }
    if {$settings(verbose)} {
        print -prefix "Starting the server on port $port."
    }
    set settings(channel) [socket -server ::TagmaServer::Accept $port]
}

# ::TagmaServer::Accept --
#   Sets up a client connection.
#
# Arguments:
#   socket      Client Socket.
#   addr        Client IP Address.
#   port        Client Port.
#
# Result:
#   None
#
# Side effect:
#   Configures events for the client.
#   Adds the client to the clients list.
proc ::TagmaServer::Accept {socket addr port} {
    variable clients
    variable settings
    set clientID $addr:$port
    print ""
    print -prefix "Tagma Server connection from $clientID"
    fconfigure $socket -buffering line -blocking 0
    fileevent $socket readable [list ::TagmaServer::Read $socket $clientID]
    set clients($clientID) $socket
    if {[array size clients] == 1} {
        set settings(current) $clientID
    }
}

# ::TagmaServer::Read --
#   Read data from the debugger (client).
#
# Arguments:
#   socket      The socket connection.
#   clientID    The client ID. (IP Addr:Port)
#
# Result:
#   Prints data recieved from the client.
#
# Side effect:
#   Closes the connection if the socket goes EOF.
proc ::TagmaServer::Read {socket clientID} {
    variable clients
    variable settings
    set socket $clients($clientID)
    if {[eof $socket] || [gets $socket input] < 0} {
        CloseConnection $clientID
        return
    }
    if {$settings(shell)} {
        if {[string match "*$settings(prompt)" $input] > 0} {
            print -nonewline "$input"
        } else {
            print "$input"
        }
    } else {
        print "$clientID: $input"
    }
}

# ::TagmaServer::Write --
#   Write data to the debugger (client).
#
# Arguments:
#   clientID    The client ID. (IP Addr:Port)
#   args        The data to send to the client.
#
# Result:
#   None
#
# Side effect:
#   Closes the connection if the socket goes EOF.
proc ::TagmaServer::Write {clientID args} {
    variable clients
    if {[array get clients $clientID] eq ""} {
        return
    }
    set socket $clients($clientID)
    if {[eof $socket]} {
        CloseConnection $clientID
        return
    }
    
    puts $socket $args
    if {[catch {flush $socket}]} {
        CloseConnection $clientID
    }
}

# ::TagmaServer::CloseConnection --
#   Closes a client socket.
#
# Arguments:
#   clientID        The client connection to close.
#
# Result:
#   None
#
# Side effect:
#   The socket is closed and the client is removed from the list.
proc ::TagmaServer::CloseConnection {clientID} {
    variable clients
    variable settings
    print ""
    print -prefix "Closing the connection to $clientID..."
    set socket $clients($clientID)
    array unset clients $clientID
    if {$settings(current) eq $clientID} {
            set settings(current) ""
    }
    close $socket
}

# ::TagmaServer::PrintHelp --
#   Prints the help text.
#
# Arguments:
#
# Result:
#   None
#
# Side effect:
#   Prints the help text.
proc ::TagmaServer::PrintHelp {} {
    variable settings
    print $settings(descr)
    print -list -- {
        "Remotely controlls a Tagma Debugger."
        "The debugger connects to the server and waits for input."
        "Arguments are passed as strings to the debugger."
        "Normal debugger output is then printed."
        ""
        "Options:"
        "    -help       Print help."
        "    -select     Select from connected debuggers."
        "    -shell      Enter an interactive shell."
        "                Simualtes working directly with the debugger."
        "                Waits for a connection if there is none."
        "    -start      Start the Tagma server process. (Optional port)"
        "    -verbose    Control/Display verbose mode. (on/off)"
        "    --          End option processing."
    }
}

# ::TagmaServer::Shell --
#   Shell that mimics using the debuger directly.
#
# Arguments:
#   None
#
# Result:
#   None
#
# Side effect:
#   Interacts with the user and the remote debugger.
proc ::TagmaServer::Shell {} {
    variable settings
    set settings(shell) 1

    # Enter the interactive shell.
    fileevent stdin readable [list ::TagmaServer::ShellRead]
    vwait ::TagmaServer::endshell
    set ::TagmaServer::endshell 0
}

# ::TagmaServer::ShellRead --
#   The read function for the interactive shell.
#
# Arguments:
#   None
#
# Result:
#   None
#
# Side effect:
#   Reads user input and sends it to the remote debugger.
proc ::TagmaServer::ShellRead {} {
    variable settings
    if {[gets stdin input] < 0} {
        puts "DIE!!"
        set ::TagmaServer::endshell 1
        return
    }
    if {$settings(current) eq ""} {
        print "There is no active connection."
    } else {
        Write $settings(current) $input
    }
}

# ::TagmaServer::tagma --
#   User interface to TagmaServer.
#   With no options send its args to the remoge debugger.
#   Controls the server and the remote debugger.
#   By default the first debugger to connect is selected.
#
# Options:
#   -help       Print help for the command.
#   -select     Select from connected debuggers.
#   -shell      Enter an interactive shell.
#               Simualtes working directly with the debugger.
#   -start      Start the Tagma server process. (Optional port)
#   -verbose    Control verbose mode. (on/off)
#   --          End option processing.
#
# Arguments:
#   args        What the user supplies...
#
# Result:
#   None
#
# Side effect:
#   Controls the server and client.
proc ::TagmaServer::tagma {args} {
    variable settings
    variable clients

    # Process the options.
    set count 0
    set arg_count [llength $args]
    foreach arg $args {
        switch -nocase -- $arg {
            -- {
                incr count
                break
            }
            -help {
                PrintHelp
                return
            }
            -select {
                incr count
                if {$count < $arg_count} {
                    set new_client [lindex $args $count]
                    if {[array get clients $new_client] eq ""} {
                        print -prefix "Unknown client: $new_client"
                        return
                    }
                    set settings(current) $new_client
                }
                set cur_client "N/A"
                if {$settings(current) ne ""} {
                        set cur_client $settings(current)
                }
                print "Current client $cur_client"
                print "Clients:"
                foreach client [array names clients] {
                    print "    $client"
                }
                return
            }
            -shell {
                Shell
                return
            }
            -start {
                if {$settings(channel) ne ""} {
                    print "The server is already running."
                    return
                }
                set port ""
                incr count
                if {$count < $arg_count} {
                    set port [lindex $args $count]
                }
                Shell $port
            }
            -verbose {
                incr count
                if {$count < $arg_count} {
                    set settings(verbose) [lindex $args $count]
                }
                set state [expr {$settings(verbose) ? "Enabled" : "Disabled"}]
                print -prefix "Verbose is currently $state."
                return
            }
            default { break }
        }
    }
    if {$count} {
        set args [lrange $args $count end]
    }

    if {$settings(current) eq ""} {
        print "No active connection."
        return
    }
    
    Write $settings(current) $args
}

namespace import ::TagmaServer::tagma

# Processing if called as a script.
if {[string match "server*" [file tail $argv0]]} {
    ::TagmaServer::print -prefix "Starting TagmaServer and interactive shell."
    ::TagmaServer::Server
    ::TagmaServer::Shell
}
