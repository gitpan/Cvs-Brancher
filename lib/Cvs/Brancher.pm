package Cvs::Brancher;
#========================================================================
#
# Cvs::Brancher.pm
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
# Last Modified:  $Date: 2003/10/09 19:16:55 $
#
# $Id: Brancher.pm,v 1.11 2003/10/09 19:16:55 bryce Exp $
#
# $Log: Brancher.pm,v $
# Revision 1.11  2003/10/09 19:16:55  bryce
# Updating versions to 1.00, except for Mail::Template, which I'm giving
# its own numbering scheme, since I want to break it out separately and
# since it's not really featureful enough to call it 1.00.
#
# Revision 1.10  2003/10/06 18:16:03  bryce
# Adding 'premerge' and 'merged' tags to scheduled_build.pl
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
# Revision 1.7  2003/10/01 23:47:10  bryce
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
# Revision 1.6  2003/10/01 00:47:10  bryce
# Testing...  Found bug in how errors are detected from the webbuild script
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
=head1 NAME 

B<Cvs::Brancher> - Handles branching and merging of CVS trees.

=head1 SYNOPSYS

    use Cvs::Brancher;
    my $cvs = new Cvs::Brancher((cvs_options=>$cvs_options));
    $cvs->create_working_area($work_area);
    chdir($work_area);
    $cvs->checkout_branch($cvs_module, $branch_name, "$work_area/$branch_name-branch");
    $cvs->create_tag($branch_name);
    $cvs->merge_branch("$work_area/$branch_name-merge", $branch_name));
    

=head1 DESCRIPTION

B<Cvs::Brancher> provides a set of wrapper routines around CVS commands
for doing branching and merging of CVS trees.  This is designed for the
Cvswebsite system to enable semi-automated merges to be done when one is
editing the website and wishes to do a merge before a build.  It may be
general enough for other sorts of uses.

=head1 METHODS

=cut


use strict;
use Carp;
use File::Path;
use File::Find;

require Exporter;
require DynaLoader;

use vars qw($VERSION @ISA);
@ISA = qw( Exporter DynaLoader );
$VERSION = '1.00';
@Cvs::Brancher::EXPORT =    qw(
			       );
@Cvs::Brancher::EXPORT_OK = qw( );
@Cvs::Brancher::EXPORT_TAGS = qw( 'all' => [ qw( ) ] );

use fields qw(
	      _cvs_options
	      );
use vars qw( %FIELDS );

my $NAME = __PACKAGE__;

use constant DEBUGGING => 0;

#========================================================================
# Subroutines
#------------------------------------------------------------------------

=head3 new()

Creates a new object.  The %args is used to set the default
operational parameters:

cvs_options  (optional) Specifies options to be passed to CVS

=cut

sub new {
    my ($this, %args) = @_;
    my $class = ref($this) || $this;
    my $self = bless [\%FIELDS], $class;

    # Bring in the args
    while (my ($field, $value) = each %args) {
        confess "Invalid parameter to $NAME '$field'"
            unless (exists $FIELDS{"_$field"});
        $self->{"_$field"} = $value;
    }

    # Specify defaults
    $self->{_cvs_options}   ||= '';

    return $self;
}


=head3 create_working_area($dir, $permissions)

Creates the working directory for doing CVS checkouts and manipulations.

Returns true if the directory exists.

=cut

sub create_working_area {
    my $self = shift;
    my $dir = shift || die "No dir specified to create_working_area()\n";
    my $permissions = shift || 0711;

    return 1==1 if (-e $dir);

    warn " [cb] mkpath $dir $permissions\n" if DEBUGGING>0;
    eval { mkpath($dir, 0, $permissions) };
    warn ("Couldn't create path $dir: $@\n") if ($@);

    return (-e $dir);
}


=head3 create_tag($tag_name)

Makes a tag in the current working directory.  

The current directory must be a valid checked out CVS module with write
capabilities so that the tag can be established.

=cut

sub create_tag {
    my $self = shift;
    my $tag_name = shift;

    if (!$tag_name) {
        warn "[cb] No tag specified to create_tag()\n";
        return undef;
    }

    warn " [cb] Creating tag '$tag_name' in current working directory\n"
	if DEBUGGING>0;
    `cvs $self->{_cvs_options} tag $tag_name`;
    return ($?==0);
}


=head3 create_branch($branch_name)

Establishes a branch in the current working directory.  The current
working directory must be a valid CVS module that has write permission,
so that the branch can be established.

=cut

sub create_branch {
    my $self = shift;
    my $branch_name = shift || die "[cb] No branch name specified to create_branch()\n";

    warn " [cb] Marking branch '$branch_name'\n"
        if DEBUGGING>0;
    `cvs $self->{_cvs_options} tag -b $branch_name`;
    return ($?==0);
}


=head3 checkout_branch($module_name, $branch, $co_dir)

Performs a cvs checkout of a particular branch of the given
$module_name, naming the checkout directory $co_dir.  If $branch is not
specified, 'HEAD' will be used.  If $co_dir is not given, it will
default to the same as $module_name.

=cut

sub checkout_branch {
    my $self = shift;
    my $module_name = shift || die "[cb] No module specified to checkout_branch()\n";
    my $branch = shift || 'HEAD';
    my $co_dir = shift || $module_name;

    if (-d $co_dir) {
        warn " [cb] Removing existing '$co_dir'\n"
            if DEBUGGING>1;
        my $num = rmtree([$co_dir], 0, 1);
        warn " [cb] $num files successfully deleted\n" if DEBUGGING>2;
    }

    warn " [cb] `cvs $self->{_cvs_options} checkout -d $co_dir -r $branch $module_name`\n"
        if DEBUGGING>2;
    `cvs $self->{_cvs_options} checkout -d $co_dir -r $branch $module_name`;
    return ($?==0);
}



=head3 merge_branch($co_dir, $branch_name)

Does a merge of a cvs branch to the HEAD.  Returns count of number of
collisions found.

This routine performs a chdir into $co_dir and leaves the cwd in that
state.  It expects to find HEAD checked out in $co_dir.

=cut

sub merge_branch {
    my $self = shift;
    my $co_dir = shift || die "[cb] No checkout dir specified to merge_branch()\n";
    my $branch_name = shift || die "[cb] No branch name specified to merge_branch()\n";

    warn " [cb] Chdir to module '$co_dir'\n" if DEBUGGING>0;
    if (!chdir($co_dir)) {
        warn "[cb] Could not cd to '$co_dir'\n";
        return undef;
    }

    warn " [cb] Removing sticky tags\n" if DEBUGGING>0;
    `cvs $self->{_cvs_options} update -A`;
    if ($?!=0) {
        warn " [cb] cvs update failed when removing sticky tags\n" 
            if DEBUGGING>0;
#       This cvs command appears to return fail codes when things
#       are otherwise okay.  Thus we will treat errors from it as
#       non-fatal.
#        return undef;
#       TODO:  Test 'if ($?==0)' instead
    }

    warn " [cb] Marking premerge point in main tree '$branch_name-premerge'\n"
        if DEBUGGING>0;
    if (!$self->create_tag("$branch_name-premerge")) {
        warn "[cb] Could not create premerge tag '$branch_name-premerge'\n";
        return undef;
    }

    warn " [cb] Merging branch '$branch_name'\n" if DEBUGGING>0;
    `cvs $self->{_cvs_options} update -Pd -j $branch_name`;
    if ($?!=0) {
        warn " [cb] cvs update failed\n" if DEBUGGING>0;
        return undef;
    }

    my @collision = ();
    # Search for '.#*' files & collect a list of them, via File::Find()
    find({ wanted => sub {  /\.\#/ && push(@collision, $File::Find::name) }, 
	   no_chdir => 1 },  '.');
    warn " [cb] Searching for collisions in $branch_name\n" if DEBUGGING>0;
    foreach my $file (@collision) {
        warn " [cb] Collision:  '$file'\n";
    }

    return (@collision==0);
}

=head1 EXAMPLES

Basic example of establishing a branch, doing something, and merging it
back in.

    use Cvs::Brancher;
    my $cvs = new Cvs::Brancher((cvs_options=>$cvs_options));

    my $cvs_module  = 'test_module';
    my $cvs_options = '-Q -d :pserver:me@cvs.mydomain.org:/var/cvs';
    my $branch_name = 'Scheduled_release_010203_0500';
    my $work_area = '/tmp/cvs_checkouts';

    my $cvs = new Cvs::Brancher((cvs_options=>$cvs_options));

    $cvs->create_working_area($work_area)
        or die "Could not mkdir $work_area\n";
    $cvs->checkout_branch($cvs_module, 'HEAD', "$work_area/$cvs_module")
        or die "Could not check out $cvs_module to $work_area\n";
    chdir($work_area)
        or die "Could not cd to $work_area\n";
    $cvs->create_tag("$branch_name-branchroot")
        or die "Could not create tag $branch_name-branchroot\n";
    $cvs->create_branch("$branch_name-branch")
        or die "Could not create branch $branch_name-branch\n";

    # Do stuff with the branch...

    $cvs->checkout_branch($cvs_module, $branch_name, $branch_name)
        or die "[sb] Could not checkout branch '$branch_name' to '$work_area'\n";

    if (! $cvs->merge_branch("$work_area/$branch_name", $branch_name)) {
        # CVS merge failed.  
        # Handle merge problems here...
    } else {
        # CVS merge succeeded.
    }


=head1 PREREQUISITES

C<Carp>
C<File::Path>
C<File::Find>
C<Exporter>
C<DynaLoader>


=head1 BUGS

Having to chdir() in order for cvs to work properly is cumbersome and
could probably be done better.

Operating CVS by shelling out the commands is undesireable, inefficient,
and poor from a security standpoint.  It would be highly preferable to
call a proper CVS library API, and we would if a good one existed.
There are several developments in this direction, so hopefully it will
be addressed in time, and the exec's can be replaced.  Ideally, a good
CVS Perl interface would possibly replace this module entirely.

Since this wrappers cvs, there are probably a multiplicity of strange
error conditions that this module doesn't take into account.  These can
be considered bugs.  Patches to address any such cases found are quite
welcome.


=head1 VERSION

1.00

=head1 SEE ALSO

L<perl(1)>,
L<tgen | http://freshmeat.net/projects/tgen/>,
L<cvswebsite>

=head1 AUTHOR

Bryce W. Harrington E<lt>bryce@osdl.orgE<gt>

L<http://www.osdl.org/|http://www.osdl.org/>

=head1 COPYRIGHT

Copyright (C) 2003 Bryce Harrington.
All Rights Reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 REVISION

Revision: $Revision: 1.11 $

=cut
1;
