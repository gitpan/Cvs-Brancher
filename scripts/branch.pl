#!/usr/bin/perl -w
#========================================================================
#
# branch.pl
#
# DESCRIPTION
#
# Branches a cvswebsite repository & schedules release                  
#
# AUTHOR
#   Bryce Harrington <brycehar@bryceharrington.com>
#
# COPYRIGHT
#   Copyright (C) 2003 Bryce Harrington  
#   All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#------------------------------------------------------------------------
#
# Last Modified:  $Date: 2003/12/26 17:44:30 $
#
# $Id: branch.pl,v 1.12 2003/12/26 17:44:30 bryce Exp $
#
# $Log: branch.pl,v $
# Revision 1.12  2003/12/26 17:44:30  bryce
# Correcting details in email message text
#
# Revision 1.11  2003/10/10 23:07:06  bryce
# Clarifying email regarding what happens on merge problem
#
# Revision 1.10  2003/10/09 19:17:03  bryce
# Updating versions to 1.00, except for Mail::Template, which I'm giving
# its own numbering scheme, since I want to break it out separately and
# since it's not really featureful enough to call it 1.00.
#
# Revision 1.9  2003/10/03 01:27:05  bryce
# Adding idea of using this for cfengine scheduled rollouts
#
# Revision 1.8  2003/10/02 22:51:08  bryce
# Changes for the 0.30 release
#
# - Add mention of which hostname the at jobs run on
# - Change subject line for errors to not say 'Fatal'
# - Add mention of rollout / date / time to error/success emails
# - Ensure we can detect the webbuild.sh fail indicator
# - Elaborate on error/success messages in scheduled_build.pl
# - Review/revise email handling
# - Make sure die messages show up in testing log
# - Update versions to 0.30
#
# Revision 1.7  2003/10/02 01:44:43  bryce
# Updating to Version = 0.20
#
# Revision 1.6  2003/10/01 23:47:10  bryce
# * Fix mkpath of '$HOME' directory
# * Find why it did not check out after merge collision
# * Find why it got a merge collision when it shouldn't have
# * Change $! to $? in Cvs::Brancher
# * "rm: cannot lstat `/tmp/testing.log': No such file or directory"
# * Do 3 scheduled dry runs of the tool to webtest
# * Document scheduled_build.pl and branch.pl
# * Alphabetize application cmdline options
# * Verify enough options are getting passed to scheduled_build
# * Document chdir for merge
# * Ensure testing.log gets appended to error email msgs
# * branch.pl:  need to test for $opt_helplong and $opt_man
# * Fix the branch-branch substitutions
#
# Revision 1.5  2003/09/30 20:11:59  bryce
# Updating to version 0.10
#
# Revision 1.4  2003/09/30 19:30:58  bryce
# Applying patch from Kees (see ChangeLog for Sep 30)
#
# Revision 1.3  2003/09/18 18:13:53  bryce
# Tweaking to make toolset actually function
#
# Revision 1.2  2003/09/18 16:40:42  bryce
# Implementing lots of base functionality
#
# Revision 1.1.1.1  2003/09/09 18:16:38  bryce
# Initial import
#
#
#========================================================================

use strict;                             # Forces variable decl's
use Carp;                               # Improved error/warning prints
use Pod::Usage;                         # To report program usage
use Getopt::Long;                       # Basic cmdline arg handling
use File::Basename;                     # fileparse(), basename(), dirname()
use File::Copy;                         # copy(), move()
use File::Find;                         # find(), finddepth()
use File::Path;                         # mkpath(), rmtree()
use File::Spec::Functions qw| :ALL |;

use Cvs::Brancher;
use Mail::Template;

#------------------------------------------------------------------------
# Global variables
#------------------------------------------------------------------------

use vars qw($VERSION $NAME);
$VERSION             = '1.00';
my $NAME             = 'branch.pl';

#------------------------------------------------------------------------
# User config area
#------------------------------------------------------------------------

our $opt_branch_name  = '';  # Name of branch
our $opt_build_script = '';
our $opt_co_dir       = '';  # Name of checkout directory to use
our $opt_cvs_root_dir = '';  # CVS ext/pserver string
our $opt_debug        = 5;   # Prints debug messages
our $opt_die_on_fail  = 0;
our $opt_help         = "0"; # Prints a brief help message
our $opt_helplong     = "0"; # Prints a long help message
our $opt_logfile      = '/dev/null';
our $opt_man          = "0"; # Prints a manual page (detailed help)
our $opt_notify_from  = '';
our $opt_notify_to    = '';
our $opt_quiet        = "0"; # Keep cvs output somewhat quiet
our $opt_smtp         = '';
our $opt_version      = "0"; # Prints the version and exits
our $opt_very_quiet   = "0"; # Keep cvs output very quiet
our $opt_working_area = '';  # Temporary dir for doing checkout work

#------------------------------------------------------------------------
# Commandline option processing
#------------------------------------------------------------------------

Getopt::Long::Configure ("bundling");  
GetOptions(
           "branch_name|b=s",  # Name of branch
	   "build_script=s",
           "co_dir|c=s",       # Name of checkout directory to use
           "cvs_root_dir|d=s", # CVS ext/pserver string
           "debug|D=i",        # Prints debug messages
	   "die_on_fail",
           "help|h",           # Prints a brief help message
           "helplong|H",       # Prints a long help message
           "logfile=s",
           "man",              # Prints a manual page (detailed help)
	   "notify_from=s",
	   "notify_to=s",
           "quiet|q",          # Keep cvs output somewhat quiet
	   "smtp=s",
           "version|V",        # Prints the version and exits
           "very_quiet|Q",     # Keep cvs output very quiet
           "working_area|w=s", # Temporary dir for doing checkout work
            ) || pod2usage(-verbose => 0, -exitstatus => 1);

my $modulename = shift @ARGV;
my $date = shift @ARGV;
my $time = shift @ARGV;

if ($opt_version) {
    print "$VERSION\n";
    exit 0;
}

pod2usage(-verbose => 0, -exitstatus => 0) if $opt_help;
pod2usage(-verbose => 1, -exitstatus => 0) if $opt_helplong;
pod2usage(-verbose => 2, -exitstatus => 0) if $opt_man;

die "[br] Error:  modulename not specified\n" 
    unless $modulename;
die "[br] Error:  date not specified correctly\n"
    unless ($date =~ m|^\d\d/\d\d/\d\d$|);
die "[br] Error:  time not specified correctly\n"
    unless ($time =~ m|^\d\d\:\d\d$|);

msg("[br] Creating branch of '$modulename' to release at $date $time\n",2);

# Set defaults
$opt_working_area   ||=  '/tmp';
$opt_co_dir         ||= "$modulename\_$date\_$time-branch";
$opt_branch_name    ||= "Scheduled_release_$date\_$time";

$opt_co_dir           =~ s|[/:]||g;
$opt_branch_name      =~ s|[/:]||g;

my $cvs_options = '';
if ($opt_very_quiet) {
    $cvs_options = '-q';
} elsif ($opt_quiet) {
    $cvs_options = '-Q';
}
if ($opt_cvs_root_dir) {
    $cvs_options .= " -d $opt_cvs_root_dir";
}

# This sets up the args that will be passed to scheduled_build.pl
my $sb_args = qq($opt_branch_name-branch
		 --build_script=$opt_build_script 
		 --cvs_module=$modulename 
		 --cvs_root_dir=$opt_cvs_root_dir 
		 --logfile=$opt_logfile
		 --notify_from=$opt_notify_from 
		 --notify_to=$opt_notify_to 
		 --smtp=$opt_smtp 
		 --working_area=$opt_working_area 
		 );
if ($opt_very_quiet) {
    $sb_args .= " --very_quiet";
} elsif ($opt_quiet) {
    $sb_args .= " --quiet";
}
if ($opt_die_on_fail) {
    $sb_args .= " --die_on_fail";
}
$sb_args =~ s/\s+/ /g;

#========================================================================
# Subroutines
#------------------------------------------------------------------------

my $ErrorLog = '';
sub msg {
    my $text = shift || return;
    my $level = shift || 0;

    if ($opt_debug>$level) {
        warn $text if $opt_debug>$level;
        $ErrorLog .= $text;
    }
}

sub main() {
    my $cvs = new Cvs::Brancher((cvs_options=>$cvs_options));

    msg("[br] Creating working area\n", 2);
    $cvs->create_working_area($opt_working_area) 
	or die "[br] Could not mkdir $opt_working_area\n";

    msg("[br] Chdir to working area '$opt_working_area'\n", 3);
    chdir($opt_working_area) 
	or die "[br] Could not cd to $opt_working_area\n";

    msg("[br] Checking out a working copy of '$modulename' as $opt_co_dir\n", 0);
    $cvs->checkout_branch($modulename, 'HEAD', $opt_co_dir)
        or die "[br] Could not check out $modulename to $opt_co_dir\n";
        
    msg("[br] Chdir to module $opt_co_dir", 3);
    chdir($opt_co_dir)
	or die "[br] Could not cd to $opt_co_dir in $opt_working_area\n";

    msg("[br] Marking root of branch in main tree '$opt_branch_name-branchroot'\n", 0);
    $cvs->create_tag("$opt_branch_name-branchroot")
	or die "[br] Could not create tag $opt_branch_name-branchroot\n";

    msg("[br] Marking branch '$opt_branch_name-branch'\n", 0);
    $cvs->create_branch("$opt_branch_name-branch")
	or die "[br] Could not create branch $opt_branch_name-branch\n";

    msg("[br] Removing working area file '$opt_co_dir'\n", 0);
    chdir($opt_working_area);
    my $num = rmtree([$opt_co_dir], 0, 1);
    msg("[br] $num files successfully deleted\n", 2);

    if (-e $opt_logfile) {
	msg("[br] removing existing logfile '$opt_logfile'\n", 2);
        unlink $opt_logfile;
    }

    msg("[br] Executing 'scheduled_build.pl $sb_args &> $opt_logfile' | at -m $time $date\n", 2);
    `echo "scheduled_build.pl $sb_args >& $opt_logfile" | at -m $time $date`;

}

#========================================================================
# Main program
#------------------------------------------------------------------------

my $recipient = {
    email => $opt_notify_to
    };

msg("[br] Starting main program on '$ENV{HOSTNAME}'\n", 1);
eval {
    main();
};

my $message;
if ($@) {
    msg($@, 0);
    msg("*** Fatal error ***\n", 0);
    $message = {
        subject => "Error creating the web change branch/schedule.\n",
        body => "\n\nError Log:\n----------\n\n$ErrorLog\n" ,
    };
} else {
    my $cvs_command = "cvs ";
    if ($opt_cvs_root_dir) {
        $cvs_command .= "-d $opt_cvs_root_dir ";
    }
    $cvs_command .= "co -d $opt_branch_name ";
    $cvs_command .= "-r $opt_branch_name-branch $modulename"

    my ($on_problem_text, $on_problem_text_short);
    if ($opt_die_on_fail) {
	$on_problem_text_short = qq|on successful merge|;
        $on_problem_text = qq|If there is an error merging, we will abort and notify|;
    } else {
	$on_problem_text_short = qq|no matter what|;
        $on_problem_text = qq|If there is an error merging, we will deploy the branch without merging|;
    }

    my $success_msg = qq(
----------------------------------------------------
A branch is now established for the scheduled change
----------------------------------------------------
CVS Module Name:               $modulename
Branch Name:                   $opt_branch_name-branch
Scheduled release:             $date  $time  ($on_problem_text_short)
Notification Will Be Sent To:  $opt_notify_to

Check out the branch using the following command (all one line!):

 $cvs_command

Make any changes required for this scheduled release.
Commit your changes and they will be rolled out according to schedule.


Cancelling a Change
===================
If you need to cancel this schedule, use 'atq' to view the pending jobs
and 'atrm' to remove the cancelled one.  This will need to be run on the
machine '$ENV{HOSTNAME}'.


Manually Rescheduling a Change
==============================
If you need to reschedule the deployment, cancel the current job and add
a new one via the command:

 echo "scheduled_build.pl $sb_args >& $opt_logfile" | at -m HH:MM MM/DD/YY

Specify the new time and date for "hh:mm MM/DD/YY".


Fault Handling
==============
$on_problem_text\n);

    msg("Successful scheduling of change\n$success_msg", 0);
    $message = {
        subject => "Branch established for scheduled change\n",
        body => $success_msg
        };
}

my $mailer = new Mail::Template((notify_from=>$opt_notify_from));
$mailer->send_template_email($recipient, $message) 
    or die "[br] Could not send mail to recipient\n";

msg("[br] Ending main program\n\n", 1);
exit(1);

#########################################################################

__END__


=head1 NAME

branch.pl - Branches a cvs modules & schedules a build operation via 'at'


=head1 SYNOPSIS

branch.pl modulename MM/DD/YY HH:MM [ options ]

 Options:
   -b, --branch_name=string      Name of branch
       --build_script=string     Name of script in module to invoke
   -c, --co_dir=string           Name of checkout directory to use
   -d, --cvs_root_dir=string     CVS ext/pserver string
   -D, --debug=integer           Prints debug messages
       --die_on_fail             Abort on merge error or deploy anyway
   -h, --help                    Prints a brief help message
   -H, --helplong                Prints a long help message
       --logfile=string          File to direct stdout/stderr of at-job
       --man                     Prints a manual page (detailed help)
       --notify_to=string        Address to send notifications to
       --notify_from=string      Address to send notifications from
   -q, --quiet                   Keep cvs output somewhat quiet
       --smtp=string             Name of the SMTP server to send to
   -V, --version                 Prints the version and exits
   -Q, --very_quiet              Keep cvs output very quiet
   -w, --working_area=string     Temporary dir for doing checkout work

=head1 DESCRIPTION

B<branch.pl> establishes a tagged branch in a CVS module and schedules a
merge and build to occur at a later date.  It is intended to be used in
conjunction with scheduled_build.pl for doing scheduled automated merge,
build and deployments.  You might use it to roll out website changes at
odd hours, such as posting a press release in time for the start of the
business day on the east coast, or to roll out cfengine changes to a
data center during the night, to minimize the impact of downtime.

Once run, you can check out the branch and make any changes required.
Check the changes back in to assure they'll be deployed correctly.

You can review the queued jobs via 'atq' or 'at -l'.  Jobs can
be removed via 'atrm' or 'at -rm'.  See your 'at' documentation for more
details.

If you need to reschedule a deployment, take note of the branch name and
other options, remove the queued job, and then add a new job at the new
time.  Note that the branch name will continue to have the _original_
release date/time in its name, but that's okay; it's only there for
informational purposes.


=head1 OPTIONS

=over 8

=item B<-b, --branch_name>

This option allows overriding of the name to use when tagging the
branch.  The default is to name it 'Scheduled_release_MMDDYY_HHMM'.  If
you choose to override it, note that the ':' and '/' characters should
not be used and will be stripped out.

The branch_name is used both for the tagging of the cvs module and for
naming checked out directories, so if you choose to override it, do so
with care.  You may want to override this if you wish to use a different
tag naming scheme.

This is used as the argument to scheduled_build.pl.

=item B<--build_script>

The name (and path if necessary) to the script to be run at the
scheduled time.  For example, this script would attempt to rebuild
the website and return an error code if there is a problem.

This parameter is passed to scheduled_build.pl.

=item B<-c, --co_dir>

This allows overriding the checkout directory name.  By default this
will be set to 'modulename_MMDDYY_HHMM-branch'.  If you choose to
override it, note that the ':' and '/' characters should not be used
will be stripped out.

This directory is used temporarily to checkout the HEAD in order to
create the branch.  You probably will never need to override this.

=item B<-d, --cvs_root_dir>

This option allows specification of the pserver or ext string to use for
CVS checkouts.  This is the same as the contents of the CVS/Root
variable in your checked out CVS module.  It is passed to the cvs
commands as `cvs -d $cvs_root_dir command ...`

If this is not set, the value of the $CVSROOT environment variable will
be used.

The value of this option is also passed to scheduled_build.pl.

=item B<-D, --debug>

Prints debug messages.  Specify a number from 0 (none) to 5 (all) to
indicate the verbosity of debug messaging.  Also note that verbosity of
the invoked cvs commands can be controlled via the --quiet and
--very_quiet options.

=item B<--die_on_fail>

Normally, scheduled_build.pl will detect when a merge has failed and
re-try without doing a merge.  This option suppresses this behavior so 
that the program simply terminates on a merge problem.  

This parameter is passed to scheduled_build.pl.

=item B<-h, --help>

Prints a brief help message

=item B<-H, --helplong>

Prints a long help message

=item B<--logfile>

Filename for putting the at-job's stdout and stderr streams.  This will
be in addition to any emails sent.  By default it is set to /dev/null.
Setting this can be useful for debugging purposes.

=item B<--man>

Prints a manual page (detailed help)

=item B<--notify_from>

This is the email address that messages should be marked as being from.
This controls what appears in the From field of the email messages.

=item B<--notify_to>

This allows specifying where email notifications should be sent.  For
example, this can be set to send messages to a mailing list that
interested watchers can subscribe to as they wish.

=item B<-q, --quiet>

This passes the '-q' option to cvs, which causes cvs to be 'somewhat
quiet'.  From the cvs manpage: "informational messages, such as reports
of recursion through subdirectories, are suppressed."

This parameter is also passed to scheduled_build.pl.

=item B<--smtp>

Name of the SMTP server to send email notices.  This is required by
Mail::Sender; see its manpage for more details.

This parameter is also passed to scheduled_build.pl.

=item B<-V, --version>

Prints the version and exits

=item B<-Q, --very_quiet>

This passes the '-Q' option to cvs, which causes cvs to be 'very quiet'.
From the cvs manpage: " the command will generate output only for
serious problems."

This parameter is also passed to scheduled_build.pl.

=item B<-w, --working_area>

This is the directory that the system should use for placing checkouts
of the CVS modules.  Note that in cases of merge failures, branches will
be left in this directory, so give thought to sizing the file system
this is on to permit multiple copies of the cvs module to exist here.

The value of this option is also passed to scheduled_build.pl.

=back

See B<branch.pl> -h for a summary of options.


=head1 PREREQUISITES

This script requires the following Perl modules:

C<Carp>,
C<Pod::Usage>,
C<Getopt::Long>,
C<File::Basename>,
C<File::Copy>,
C<File::Find>,
C<File::Path>,
C<File::Spec>,
C<Cvs::Brancher>

=head1 SCRIPT CATEGORIES

CPAN/Administrative

=head1 BUGS

The system has a granularity of 1 minute since 'at' has a 1-minute
granularity.  It's not expected that this will pose a problem in
practice, although note that if you run this script a couple times in
quick succession, it won't behave properly.

The date syntax MM/DD/YY is used, although YYMMDD would be preferred.
This limit is due to the way 'at' works on the developer's machine.

=head1 VERSION

1.00

Distributed as part of Cvs-Brancher.

=head1 SEE ALSO

L<perl(1)>,
L<tgen | http://freshmeat.net/projects/tgen/>, 
L<cvswebsite>

=head1 AUTHOR

Bryce Harrington E<lt>bryce@osdl.orgE<gt>

L<http://www.osdl.org/|http://www.osdl.org/>

=head1 COPYRIGHT

Copyright (C) 2003 Bryce Harrington.
All Rights Reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 REVISION

Revision: $Revision: 1.12 $

=cut



