#!/usr/bin/perl -w
#========================================================================
#
# scheduled_build.pl
#
# DESCRIPTION
#
# Merges a branched cvswebsite repository & rebuilds it
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
# TODO
#
#------------------------------------------------------------------------
#
# Last Modified:  $Date: 2003/12/15 20:55:15 $
#
# $Id: scheduled_build.pl,v 1.14 2003/12/15 20:55:15 hobar Exp $
#
# $Log: scheduled_build.pl,v $
# Revision 1.14  2003/12/15 20:55:15  hobar
# cvs_root wasn't being initialized with arguments.
#
# Revision 1.13  2003/10/09 19:17:04  bryce
# Updating versions to 1.00, except for Mail::Template, which I'm giving
# its own numbering scheme, since I want to break it out separately and
# since it's not really featureful enough to call it 1.00.
#
# Revision 1.12  2003/10/09 18:17:01  bryce
# Fixing $opt_branch_name -> $branch_name
#
# Revision 1.11  2003/10/06 18:16:03  bryce
# Adding 'premerge' and 'merged' tags to scheduled_build.pl
#
# Revision 1.10  2003/10/03 22:05:26  bryce
# Making scheduled build script clean up after itself.
#
# Revision 1.9  2003/10/02 22:51:08  bryce
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
# Revision 1.8  2003/10/02 01:44:43  bryce
# Updating to Version = 0.20
#
# Revision 1.7  2003/10/02 01:40:19  bryce
# Adding a chdir to ensure script's running in the right place.
# Also, documenting the general usage process.
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
# Revision 1.5  2003/10/01 00:47:10  bryce
# Testing...  Found bug in how errors are detected from the webbuild script
#
# Revision 1.4  2003/09/30 20:11:59  bryce
# Updating to version 0.10
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
# Revision 1.1  2003/07/02 20:26:28  bryce
# Moving templates into templates directory
#
# Revision 1.1.1.1  2003/05/28 18:04:52  bryce
# Initial commit
#
#========================================================================

use strict;            # Forces variable decl's
use Carp;              # Improved error/warning prints
use Pod::Usage;        # To report program usage
use Getopt::Long;      # Basic cmdline arg handling
use File::Basename;    # fileparse(), basename(), dirname()
use File::Copy;        # copy(), move()
use File::Find;        # find(), finddepth()
use File::Path;        # mkpath(), rmtree()
use File::Spec::Functions qw(:ALL);
use Mail::Sender;
use Template;          # For template processing

use Cvs::Brancher;
use Mail::Template;

#------------------------------------------------------------------------
# Global variables
#------------------------------------------------------------------------

use vars qw($VERSION $NAME);
$VERSION = '1.00';
my $NAME = 'scheduled_build.pl';

#------------------------------------------------------------------------
# User config area
#------------------------------------------------------------------------
our $opt_build_script = 'webbuild.sh';    # Script to run at scheduled time
our $opt_cvs_module   = '';               # CVS module name
our $opt_cvs_root_dir = '';               # CVS ext/pserver string
our $opt_debug        = 5;                # Prints debug messages
our $opt_die_on_fail = 0;      # If can't merge, give up rather than roll out
our $opt_help        = "0";    # Prints a brief help message
our $opt_helplong    = "0";    # Prints a long help message
our $opt_logfile     = '';     # Logfile to attach to email notices
our $opt_man         = "0";    # Prints a manual page (detailed help)
our $opt_notify_from = 'webmaster@osdl.org';
our $opt_notify_to   = '';
our $opt_quiet       = '';                     # Keep cvs output somewhat quiet
our $opt_smtp        = 'smtp';                 # Name of the SMTP server to sue
our $opt_version     = "0";                    # Prints the version and exits
our $opt_very_quiet  = '';                     # Keep cvs output very quiet
our $opt_working_area = '';    # Temporary dir for doing checkout work



#------------------------------------------------------------------------
# Commandline option processing
#------------------------------------------------------------------------

Getopt::Long::Configure("bundling");
GetOptions(
	"build_script=s",      # Script to run at scheduled time
	"cvs_module|m=s",      # CVS module name
	"cvs_root_dir|d=s",    # CVS ext/pserver string
	"debug|D=i",           # Prints debug messages
	"die_on_fail",         # If can't merge, give up rather than roll out
	"help|h",              # Prints a brief help message
	"helplong|H",          # Prints a long help message
	"logfile=s",           # Logfile to attach to notice emails
	"man",                 # Prints a manual page (detailed help)
	"notify_from=s",       # Address of who is sending the email
	"notify_to=s",         # Address to send status notifications to
	"quiet|q",             # Keep cvs output somewhat quiet
	"smtp=s",              # SMTP host for sending mail
	"version|V",           # Prints the version and exits
	"very_quiet|Q",        # Keep cvs output very quiet
	"working_area|w=s",    # Temporary dir for doing checkout work
) || pod2usage(1);

if ($opt_version) {
	print "$VERSION\n";
	exit 0;
}

my $cvs_options = '';
if ($opt_very_quiet) {
	$cvs_options = '-q';
}
elsif ($opt_quiet) {
	$cvs_options = '-Q';
}
if ($opt_cvs_root_dir) {
	$cvs_options .= " -d $opt_cvs_root_dir";
}

my $branch_name = shift @ARGV || warn "No branch name specified\n";

pod2usage( -verbose => 0, -exitstatus => 0 ) if $opt_help;
pod2usage( -verbose => 1, -exitstatus => 0 ) if $opt_helplong;
pod2usage( -verbose => 2, -exitstatus => 0 ) if $opt_man;

#========================================================================
# Subroutines
#------------------------------------------------------------------------

my $ErrorLog = '';

sub msg {
	my $text  = shift || return;
	my $level = shift || 0;

	if ( $opt_debug > $level ) {
		warn $text if $opt_debug > $level;
		$ErrorLog .= $text;
	}
}

sub main {
	my $cvs = new Cvs::Brancher( ( cvs_options => $cvs_options ) );

	msg( `date`,     0 );
	msg( `hostname`, 0 );

	msg( "[sb] Creating working area\n", 0 );
	$cvs->create_working_area($opt_working_area)
	  or die "[sb] Could not create working area '$opt_working_area'\n";

	msg( "[sb] Changing to working area '$opt_working_area'\n", 0 );
	chdir($opt_working_area)
	  or die "[sb] Could not cd to '$opt_working_area'\n";

	my $checkout_path = catdir( $opt_working_area, $branch_name );
	msg( "[sb] Checkout path is '$checkout_path'\n", 0 );

	msg( "[sb] Checking out branch '$branch_name' of '$opt_cvs_module'\n", 0 );
	$cvs->checkout_branch( $opt_cvs_module, $branch_name, $branch_name )
	  or die
	  "[sb] Could not checkout branch '$branch_name' to '$opt_working_area'\n";

	if ( !-d $checkout_path ) {
		die "[sb] CVS checkout failed - $checkout_path doesn't exist\n";
	}
	msg( "[sb] $checkout_path exists.  Beginning merge.\n", 1 );

	msg( "[sb] Marking premerge point in branch '$branch_name-premerge'\n", 0 );
	$cvs->create_tag("$branch_name-premerge")
	  or die "[sb] Could not create tag $branch_name-premerge\n";

	if ( !$cvs->merge_branch( $checkout_path, $branch_name ) ) {

		# Ack!  The merge failed.  At this point we've got a problem.
		# It requires a human to figure out how to merge this, and
		# we're not human (yet).

		# If user wants us to just fail, then just fail.
		if ($opt_die_on_fail) {
			die
"[sb] Failed to merge branch.  Terminating and skipping deployment.\n";
		}

		# Otherwise, carry on.  Roll out the change without doing the merge.

		msg("[sb] MERGE FAILED.  Trying again, and skipping the merge.\n");

		msg(
			qq|
The merge of the branch to HEAD failed.
You must manually merge this release as follows:

   0.  ssh to host $ENV{HOSTNAME}
   1.  cd $checkout_path-TODO
   2.  cvs update -A
   3.  edit conflicting files to fix merge issue
       webbuild_test.sh  # Optional
   4.  cvs commit
   5.  webbuild_production.sh
|
		);
		msg( "Moving $checkout_path to $checkout_path-TODO\n", 0 );
		rmtree( ["$checkout_path-TODO"], 0, 1 );
		move( $checkout_path, "$checkout_path-TODO" );

		msg( "[sb] Changing to working area '$opt_working_area'\n", 0 );
		chdir($opt_working_area)
		  or die "[sb] Could not cd to '$opt_working_area'\n";

		msg( "[sb] Checking out branch '$branch_name' of '$opt_cvs_module'\n",
			0 );
		$cvs->checkout_branch( $opt_cvs_module, $branch_name, $branch_name )
		  or die
"Could not do a second checkout of $branch_name to '$opt_working_area'\n";

		if ( !-d $checkout_path ) {
			die
"[sb] Second CVS checkout failed - $checkout_path doesn't exist\n";
		}
	}
	else {
		msg( "[sb] Marking merged point '$branch_name-merged'\n", 0 );
		$cvs->create_tag("$branch_name-merged")
		  or die "[sb] Could not create tag $branch_name-merged\n";
	}

	# Validate build script
	if ( $opt_build_script !~ m|^[\w/\.\-]+$| ) {
		die "[sb] Invalid characters in build script filename.  "
		  . "Only ones allowed:  a-zA-z0-9._-/\n";
	}
	elsif ( !-e catfile( $checkout_path, $opt_build_script ) ) {
		die
"[sb] Build script '$checkout_path/$opt_build_script' does not exist\n";
	}
	elsif ( !-x catfile( $checkout_path, $opt_build_script ) ) {
		die
"[sb] Build script '$checkout_path/$opt_build_script' cannot be executed\n";
	}

	msg( "[sb] Changing to checkout area '$checkout_path'\n", 0 );
	chdir($checkout_path)
	  or die "[sb] Could not cd to '$checkout_path\n";

	msg( "[sb] Running web build script '$opt_build_script'\n", 0 );
	`$opt_build_script`;

	if ( $? != 0 ) {
		my $errcode = $?;
		die "[sb] There was a problem running the build script.\n"
		  . "[sb] $opt_build_script returned code '$errcode'\n"
		  . "[sb] Leaving the checkout in '$checkout_path' for you.\n";
	}

	# Clean up after self
	msg( "All done.  Removing $checkout_path\n", 1 );
	rmtree( ["$checkout_path"], 0, 1 );
}

#========================================================================
# Main program
#------------------------------------------------------------------------

my $recipient = { email => $opt_notify_to };
msg( "[sb] Starting main program\n", 1 );
msg("[sb] Sending notifications to '$opt_notify_to'\n");
eval { main(); };

my $message;
if ($@) {
	msg( $@, 0 );
	$message->{subject} =
	  "Problem deploying scheduled web change - $branch_name";
	$message->{body} = qq|
CVS Module:           $opt_cvs_module
Branch:               $branch_name

$@\n|;
}
else {
	$message->{subject} = "Successful deployment of web change - $branch_name";
	$message->{body}    = qq|
CVS Module:           $opt_cvs_module
Branch:               $branch_name

The website change has been successfully performed and deployed into
production according to schedule.\n|;
}
if ( $opt_logfile && $opt_logfile ne '/dev/null' ) {
	$message->{body} .= "\n\nLogfile attached.\n\n";
	$message->{file} = $opt_logfile;
}

msg( "[sb] Sending message about results\n", 2 );
my $mailer = new Mail::Template( ( notify_from => $opt_notify_from ) );
$mailer->send_template_email( $recipient, $message )
  or die "[sb] Could not send mail to recipient: $?\n";

msg( "[sb] Ending main program\n\n", 1 );

exit(1);

#########################################################################

__END__


=head1 NAME

scheduled_build.pl - Merges a branched cvs module and runs a script to
do a build on it.


=head1 SYNOPSIS

scheduled_build.pl branchname [options]

 Options:
       --build_script=string     Build script to run at scheduled time
   -d, --cvs_root_dir=string     CVS ext/pserver string
   -m, --cvs_module=string       CVS module name
   -D, --debug=integer           Prints debug messages
       --die_on_fail=boolean     If can't merge, give up rather than roll out
   -h, --help=boolean            Prints a brief help message
   -H, --helplong=boolean        Prints a long help message
       --logfile=string          Logfile to attach to notification message
       --man=boolean             Prints a manual page (detailed help)
       --notify_from=string      Email address for the From field in notices
       --notify_to=string        Email address for the To field in notices
   -q, --quiet=boolean           Keep cvs output somewhat quiet
       --smtp=string             SMTP host for sending email
   -V, --version=boolean         Prints the version and exits
   -Q, --very_quiet=boolean      Keep cvs output very quiet
   -w, --working_area=string     Temporary dir for doing checkout work

=head1 DESCRIPTION

B<scheduled_build.pl> is used to perform a checkout of a branched cvs
module, merge the branch back into the HEAD, and run a script on it.
This script could, for example, perform a rebuild and deployment of a
website.

This script is designed to be invoked via 'at' by branch.pl.  The
commandline options for this script are passed through this interface by
branch.pl, so look to it for control of these parameters.

=head1 OPTIONS

=over 8

=item B<--build_script>

The name (and path if necessary) to the script to be run at the
scheduled time.  It is expected that this script will attempt to rebuild
the website and return an error code if there is a problem.  

=item B<-m, --cvs_module>

The name of the CVS module that has the branch for building.  

=item B<-d, --cvs_root_dir>

This option allows specification of the pserver or ext string to use for
CVS checkouts.  This is the same as the contents of the CVS/Root
variable in your checked out CVS module.  It is passed to the cvs
commands as `cvs -d $cvs_root_dir command ...`

If this is not set, the value of the $CVSROOT environment variable will
be used.

=item B<-D, --debug>

Prints debug messages.  Specify a number from 0 (none) to 5 (all) to
indicate the verbosity of debug messaging.  Also note that verbosity of
the invoked cvs commands can be controlled via the --quiet and
--very_quiet options.

=item B<-h, --help>

Prints a brief help message

=item B<-H, --helplong>

Prints a long help message

=item B<--man>

Prints a manual page (detailed help)

=item B<-q, --quiet>

This passes the '-q' option to cvs, which causes cvs to be 'somewhat
quiet'.  From the cvs manpage: "informational messages, such as reports
of recursion through subdirectories, are suppressed."

=item B<--notify_from>

The email address to use in the From field of email notices sent about the
scheduled build's success or failure.

=item B<--notify_to>

The email address to use in the To field of email notices sent about the
scheduled build's success or failure.

=item B<--smtp>

The SMTP host to use for sending out emails.  This parameter is used by
Mail::Sender.

=item B<-V, --version>

Prints the version and exits

=item B<-Q, --very_quiet>

This passes the '-Q' option to cvs, which causes cvs to be 'very quiet'.
From the cvs manpage: " the command will generate output only for
serious problems."

=item B<-w, --working_area>

This is the directory that the system should use for placing checkouts
of the CVS modules.  Note that in cases of merge failures, branches will
be left in this directory, so give thought to sizing the file system
this is on to permit multiple copies of the cvs module to exist here.

=back

See B<scheduled_build.pl> -h for a summary of options.


=head1 PREREQUISITES

This script requires the C<strict> module.  It also requires
C<foobar 1.00>.

=head1 COREQUISITES

CGI

=head1 SCRIPT CATEGORIES

CPAN/Administrative

=head1 BUGS

None known.

=head1 VERSION

1..00

Distributed as part of Cvs-Builder.

=head1 SEE ALSO

L<perl(1)>,
L< tgen | http://freshmeat.net/projects/tgen/ >, 
L<cvswebsite>

=head1 AUTHOR

Bryce Harrington E<lt>brycehar@bryceharrington.comE<gt>

L<http://www.osdl.org/|http://www.osdl.org/>

=head1 COPYRIGHT

Copyright (C) 2003 Bryce Harrington.
All Rights Reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 REVISION

Revision: $Revision: 1.14 $

=cut



