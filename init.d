#!/bin/sh
#
# Based on sample LSB init script,
# copyright (c) 2007 Javier Fernandez-Sanguino <jfs@debian.org>
#
# This is free software; you may redistribute it and/or modify
# it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2,
# or (at your option) any later version.
#
# This is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License with
# the Debian operating system, in /usr/share/common-licenses/GPL;  if
# not, write to the Free Software Foundation, Inc., 59 Temple Place,
# Suite 330, Boston, MA 02111-1307 USA
#
### BEGIN INIT INFO
# Provides:          2ping
# Required-Start:    $remote_fs $network $time
# Required-Stop:     $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: starts/stops the 2ping listener
### END INIT INFO

PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

DAEMON=/usr/bin/2ping
NAME=2ping
DESC="2ping listener"
PIDFILE=/var/run/$NAME.pid

test -x $DAEMON || exit 0

. /lib/lsb/init-functions

# Default options, these can be overriden by the information
# at /etc/default/$NAME
TWOPINGD_OPTS=""
TWOPINGD_USER=nobody
TWOPINGD_DIETIME=2
#TWOPINGD_STARTTIME=2

# Include defaults if available
if [ -f /etc/default/$NAME ] ; then
	. /etc/default/$NAME
fi

# Silently ignore requests to start if not explicitly enabled
if [ "x$TWOPINGD_RUN" != "xyes" ] ; then
    exit 0
fi

# Check that the user exists (if we set a user)
# Does the user exist?
if [ -n "$TWOPINGD_USER" ] ; then
    if getent passwd | grep -q "^$TWOPINGD_USER:"; then
        # Obtain the uid and gid
        DAEMONUID=`getent passwd |grep "^$TWOPINGD_USER:" | awk -F : '{print $3}'`
        DAEMONGID=`getent passwd |grep "^$TWOPINGD_USER:" | awk -F : '{print $4}'`
    else
        log_failure_msg "The user $TWOPINGD_USER, required to run $NAME does not exist."
        exit 1
    fi
fi


set -e

running_pid() {
# Check if a given process pid's cmdline matches a given name
    pid=$1
    name=$2
    [ -z "$pid" ] && return 1
    [ ! -d /proc/$pid ] &&  return 1
    #cmd=`cat /proc/$pid/cmdline | tr "\000" "\n"|head -n 1 |cut -d : -f 1`
    ## Is this the expected server
    #[ "$cmd" != "$name" ] &&  return 1
    ### 2ping specific (since $0 is usually "/usr/bin/perl"):
    cmd=`cat /proc/$pid/cmdline | tr "\000" "\n"|grep "$name"`
    [ -z "$cmd" ] && return 1
    return 0
}

running() {
# Check if the process is running looking at /proc
# (works for all users)

    # No pidfile, probably no daemon present
    [ ! -f "$PIDFILE" ] && return 1
    pid=`cat $PIDFILE`
    running_pid $pid $DAEMON || return 1
    return 0
}

start_server() {
# Start the process using the wrapper
        if [ -z "$TWOPINGD_USER" ] ; then
            start-stop-daemon --start --quiet \
                        --background \
                        --make-pidfile --pidfile $PIDFILE \
                        --exec $DAEMON -- \
                        --listen -q $TWOPINGD_OPTS \
                        >/dev/null
            errcode=$?
        else
# if we are using a daemonuser then change the user id
            start-stop-daemon --start --quiet \
                        --chuid $TWOPINGD_USER \
                        --background \
                        --make-pidfile --pidfile $PIDFILE \
                        --exec $DAEMON -- \
                        --listen -q $TWOPINGD_OPTS \
                        >/dev/null
            errcode=$?
        fi
	return $errcode
}

stop_server() {
# Stop the process using the wrapper
        start-stop-daemon --stop --quiet --pidfile $PIDFILE
        errcode=$?
	return $errcode
}

force_stop() {
# Force the process to die killing it manually
	[ ! -e "$PIDFILE" ] && return
	if running ; then
		kill -15 $pid
	# Is it really dead?
		sleep "$TWOPINGD_DIETIME"s
		if running ; then
			kill -9 $pid
			sleep "$TWOPINGD_DIETIME"s
			if running ; then
				echo "Cannot kill $NAME (pid=$pid)!"
				exit 1
			fi
		fi
	fi
	rm -f $PIDFILE
}


case "$1" in
  start)
	log_daemon_msg "Starting $DESC " "$NAME"
        # Check if it's running first
        if running ;  then
            log_progress_msg "apparently already running"
            log_end_msg 0
            exit 0
        fi
        if start_server ; then
            # NOTE: Some servers might die some time after they start,
            # this code will detect this issue if TWOPINGD_STARTTIME is set
            # to a reasonable value
            [ -n "$TWOPINGD_STARTTIME" ] && sleep $TWOPINGD_STARTTIME # Wait some time 
            if  running ;  then
                # It's ok, the server started and is running
                log_end_msg 0
            else
                # It is not running after we did start
                log_end_msg 1
            fi
        else
            # Either we could not start it
            log_end_msg 1
        fi
	;;
  stop)
        log_daemon_msg "Stopping $DESC" "$NAME"
        if running ; then
            # Only stop the server if we see it running
			errcode=0
            stop_server || errcode=$?
            log_end_msg $errcode
        else
            # If it's not running don't do anything
            log_progress_msg "apparently not running"
            log_end_msg 0
            exit 0
        fi
        ;;
  force-stop)
        # First try to stop gracefully the program
        $0 stop
        if running; then
            # If it's still running try to kill it more forcefully
            log_daemon_msg "Stopping (force) $DESC" "$NAME"
			errcode=0
            force_stop || errcode=$?
            log_end_msg $errcode
        fi
	;;
  restart|force-reload)
        log_daemon_msg "Restarting $DESC" "$NAME"
		errcode=0
        stop_server || errcode=$?
        # Wait some sensible amount, some server need this
        [ -n "$TWOPINGD_DIETIME" ] && sleep $TWOPINGD_DIETIME
        start_server || errcode=$?
        [ -n "$TWOPINGD_STARTTIME" ] && sleep $TWOPINGD_STARTTIME
        running || errcode=$?
        log_end_msg $errcode
	;;
  status)

        log_daemon_msg "Checking status of $DESC" "$NAME"
        if running ;  then
            log_progress_msg "running"
            log_end_msg 0
        else
            log_progress_msg "apparently not running"
            log_end_msg 1
            exit 1
        fi
        ;;
  # Use this if the daemon cannot reload
  reload)
        log_warning_msg "Reloading $NAME daemon: not implemented, as the daemon"
        log_warning_msg "cannot re-read the config file (use restart)."
        ;;
  *)
	N=/etc/init.d/$NAME
	echo "Usage: $N {start|stop|force-stop|restart|force-reload|status}" >&2
	exit 1
	;;
esac

exit 0
