#!/bin/sh
# This is an example of using Cvs::Brancher to do a scheduled build
# of the OSDL website.  This is intended only for development purposes.
# It's useful for scheduling a release for five minutes in the future.
# This isn't appropriate for production use though.

# What time is it?
Y=`date +%y`
M=`date +%m`
D=`date +%d`
h=`date +%H`
m=`date +%M`
s=`date +%S`
echo Current date/time is $M/$D/$Y $h:$m:$s

# Schedule release for future
# Note - this doesn't account for wrapping of the hour
let m=$m
let m=$m+5

date="$M/$D/$Y"
time=`printf "%s:%02d" $h $m`
echo Release date/time is $date $time

if [ -e /tmp/testing.log ]; then
    rm /tmp/testing.log
fi

# Establish the branch
branch.pl osdl_extranet_test $date $time \
    --debug=0 \
    --quiet \
    --smtp=smtp \
    --cvs_root_dir=':pserver:bryce@cvs.pdx.osdl.net:/var/cvs' \
    --working_area='/tmp' \
    --build_script='webbuild_dev.sh' \
    --notify_from='www@osdl.org' \
    --notify_to='bryce@osdl.org' \
    --logfile=/tmp/testing.log

# Optionally can also give the following options:
#
#   If can't to a merge, then just fail without a rollout
#   --die_on_fail   



