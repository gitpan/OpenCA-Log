## OpenCA::Logger::Syslog.pm 
##
## Copyright (C) 2003 Michael Bell <michael.bell@web.de>
## All rights reserved.
##
##    This library is free software; you can redistribute it and/or
##    modify it under the terms of the GNU Lesser General Public
##    License as published by the Free Software Foundation; either
##    version 2.1 of the License, or (at your option) any later version.
##
##    This library is distributed in the hope that it will be useful,
##    but WITHOUT ANY WARRANTY; without even the implied warranty of
##    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
##    Lesser General Public License for more details.
##
##    You should have received a copy of the GNU Lesser General Public
##    License along with this library; if not, write to the Free Software
##    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
##

use strict;

package OpenCA::Logger::Syslog;

use FileHandle;
our ($STDERR, $STDOUT);
$STDOUT = \*STDOUT;
$STDERR = \*STDERR;

our ($errno, $errval);
our $AUTOLOAD;

($OpenCA::Logger::Syslog::VERSION = '$Revision: 1.2 $' )=~ s/(?:^.*: (\d+))|(?:\s+\$$)/defined $1?"0\.9":""/eg;

# Preloaded methods go here.

## Create an instance of the Class
sub new {
    my $that = shift;
    my $class = ref($that) || $that;

    my $self = {
                DEBUG     => 0,
                debug_fd  => $STDOUT,
                ## debug_msg => ()
               };

    bless $self, $class;

    my $keys = { @_ };

    ## load config
    $self->{name}        = $keys->{name};
    $self->{host}        = $keys->{host};
    $self->{port}        = $keys->{port};
    $self->{facility}    = $keys->{facility};
    $self->{socket_type} = $keys->{socket_type};
    $self->{prefix}      = $keys->{prefix};
    $self->{prefix}      = "OpenCA PKI Logging" if (not $self->{prefix});
    $self->{name}        = $self->{prefix}      if (not $self->{name});
    $self->{host}        = "127.0.0.1"          if (not $self->{host});
    $self->{port}        = "154"                if (not $self->{port});
    $self->{facility}    = "local7"             if (not $self->{facility});

    ## we support Net, Sys, Unix
    return $self->setError (6511010, "Type of Syslog was not specified.")
        if (not $keys->{type});
    return $self->setError (6511010, "Type of Syslog is not supported.")
        if ($keys->{type} !~ /^(Net|Unix|Sys)$/i);
    $self->{type} = "Net"  if ($keys->{type} =~ /Net/i);
    $self->{type} = "Unix" if ($keys->{type} =~ /Unix/i);
    $self->{type} = "Sys"  if ($keys->{type} =~ /Sys/i);

    ## try to load requested syslog module
    ## get the token class    
    my $syslog_class = "OpenCA::Logger::Syslog::".$self->{type};
    eval "require $syslog_class";
    return $self->setError ($@, "Cannot load class OpenCA::Logger::Syslog::".$self->{type}.". ".$@) if ($@);

    $self->{syslog} = eval {$syslog_class->new (
                                 prefix      => $self->{prefix},
                                 host        => $self->{host},
                                 port        => $self->{port},
                                 facility    => $self->{facility},
                                 socket_type => $self->{socket_type},
                                )};

    return $self->setError ($@, "Cannot initialize new syslog object. ".$@) if ($@);
    return $self->setError (6511005, "The new syslog object of class ".
                                     "OpenCA::Logger::Syslog::".$self->{type}.
                                     " cannot be created.")
        if (not $self->{syslog});

    return $self;
}

sub setError {
    my $self = shift;

    if (scalar (@_) == 4) {
        my $keys = { @_ };
        $self->{errno}  = $keys->{ERRNO};
        $self->{errval} = $keys->{ERRVAL};
    } else {
        $self->{errno}  = $_[0];
        $self->{errval} = $_[1];
    }
    $errno  = $self->{errno};
    $errval = $self->{errval};

    return undef;
}

sub errno {
    my $self = shift;
    return $self->{errno};
}

sub errval {
    my $self = shift;
    return $self->{errval};
}

sub supportLogSignature {
    return undef;
}

sub supportLogDigest {
    return undef;
}

sub supportGetMessage {
    return undef;
}

sub supportSearch {
    return undef;
}

sub addMessage {
    my $self = shift;
    my $msg  = $_[0];

    return $self->setError (6511070, "Cannot write to syslogdevice.")
        if (not $self->{syslog}->addMessage ($msg));

    return 1;
}

sub flush {
    return 1;
}

1;

__END__
