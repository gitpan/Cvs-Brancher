package Mail::Template;
#========================================================================
#
# Mail::Template
#
# DESCRIPTION
#                                                                       
# Manages templatified emails for sending through Mail::Sender
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
# Last Modified:  $Date: 2003/10/09 19:17:03 $
#
# $Id: Template.pm,v 1.6 2003/10/09 19:17:03 bryce Exp $
#
# $Log: Template.pm,v $
# Revision 1.6  2003/10/09 19:17:03  bryce
# Updating versions to 1.00, except for Mail::Template, which I'm giving
# its own numbering scheme, since I want to break it out separately and
# since it's not really featureful enough to call it 1.00.
#
# Revision 1.5  2003/10/06 18:16:03  bryce
# Adding 'premerge' and 'merged' tags to scheduled_build.pl
#
# Revision 1.4  2003/10/02 22:51:08  bryce
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
# Revision 1.3  2003/10/02 01:44:43  bryce
# Updating to Version = 0.20
#
# Revision 1.2  2003/09/30 20:11:59  bryce
# Updating to version 0.10
#
# Revision 1.1  2003/09/18 16:41:14  bryce
# Adding Mail::Template perl module
#
#
#
#========================================================================
=head1 NAME 

B<Mail::Template> - Manages templatified emails for sending through
Mail::Sender

=head1 SYNOPSYS

    use Mail::Template;

    my $mailer = new Mail::Template((notify_from=>'me\@domain.org'));

    $mailer->send_template_email($recipient, $message)
        or die "Could not send mail to recipient: $?\n";


=head1 DESCRIPTION

B<Mail::Template> provides an interface for generating emails from
templates using Template-Toolkit and sending them through Mail::Sender.

=head1 METHODS

=cut

use strict;
use Carp;
use Mail::Sender;

require Exporter;
require DynaLoader;

use vars qw($VERSION @ISA);
@ISA = qw( Exporter DynaLoader );
$VERSION = '0.31';
@Mail::Template::EXPORT =    qw(
                                Error
			       );
@Mail::Template::EXPORT_OK = qw( );
@Mail::Template::EXPORT_TAGS = qw( 'all' => [ qw( ) ] );

use fields qw(
	      _smtp
              _notify_from
	      );
use vars qw( %FIELDS );

my $NAME = __PACKAGE__;

use constant DEBUGGING => 0;

#========================================================================
# Subroutines
#------------------------------------------------------------------------

=head2 new()

Creates a new object.  The %args is used to set the default
operational parameters:

smtp - The name of the smtp mail server to send mail notices to. 
       Defaults to 'smtp'.

notify_from - The email address that messages sent by this instance of
       Mail::Template should be addressed as From.  Defaults to 
       the environment variables USER@HOST

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
    $self->{_smtp}          ||= 'smtp';
    $self->{_notify_from}   ||= $ENV{USER}.'@'.$ENV{HOST};    

    undef $Mail::Template::Error;

    return $self;
}


=head2 send_template_email(\%recipient, \%message, \%vars)

  Provides a wrapperized interface around Mail::Sender and
  Template::Toolkit so you can manage and send templatified
  emails flexibly and easily.  Its routines use hashes for
  the data objects to make it simpler for interfacing with
  other application objects and subsystems.

  recipient has the following fields:
     email - required
     name - optional

  message has the following fields:
     subject - required
     file - pathname of a file to include as an attachment in email
    Any one of the following is required:
     body - optional
     body_template - optional
     body_template_filename - optional

  vars is a user-definable set of variables sent directly to 
    template toolkit when processing the body_template

=cut

sub send_template_email {
    my $self = shift;
    my $recipient = shift || die "No recipient to send_template_email()\n";
    my $message = shift || die "No msg_template to send_template_email()\n";
    my $vars = shift || undef;
    my $to = $recipient->{email} || die "No recipient email specified\n";
    my $subject = $message->{subject} || 'no subject';

    # Assemble the body of the email
    my $msg = $message->{body};
    if (! $msg) {
        # Get the mail message template if necessary
        my $input = $message->{body_template} ||
            $message->{body_template_filename};
        if (! $input) {
            $Mail::Template::Error = 
                "No body_template nor body_template_filename given for message\n";
            return undef;
        }

        # Run message through Template Toolkit
        my $tt2_config = {
            INCLUDE_PATH => '/var/tmailer/lib',
        };

        my $template = Template->new($tt2_config);
        if (! $template->process($input, \$msg)) {
            $Mail::Template::Error = "Could not process template\n";
            return undef;
        }
    }

    my $sender = Mail::Sender->new({
        smtp => $self->{_smtp},
        from => $self->{_notify_from},
    });
    if (! $sender) {
        $Mail::Template::Error = "Can't create the Mail::Sender object:  "
            . "$Mail::Sender::Error\n";
        return undef;
    }

    if ($message->{file}) {
        # Need to send a file
        if (! ref ($sender->MailFile({ 
            to => $to, subject => $subject, msg => $msg, 
            file => $message->{file}
            }))
         and warn "Mail sent OK.\n"
         ) {
             $Mail::Template::Error =
                 "Can't send the message:  $Mail::Sender::Error\n";
             return undef;
         }
    } else {
        # No file to be sent, so just send a regular email
        if (ref ($sender->MailMsg({
            to => $to, subject => $subject, msg => $msg,
        }))) {
            warn "Mail sent OK.\n";
        } else {
            $Mail::Template::Error =
                "Can't send the message:  $Mail::Sender::Error\n";
            return undef;
        }
    }
    return (1==1);
}



=head1 PREREQUISITES

Template-Toolkit

Mail::Sender

=head1 BUGS

None known.

=head1 VERSION

0.31

=head1 SEE ALSO

L<perl(1)>,
L<Template-Toolkit | http://www.template-toolkit.org/>,
L<Mail::Sender>

=head1 AUTHOR

Bryce Harrington E<lt>brycehar@bryceharrington.comE<gt>

L<http://www.osdl.org/|http://www.osdl.org/>

=head1 COPYRIGHT

Copyright (C) 2003 Bryce Harrington.
All Rights Reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 REVISION

Revision: $Revision: 1.6 $

=cut
1;
