## OpenCA::Log.pm 
##
## Copyright (C) 2000-2003 Michael Bell <michael.bell@web.de>
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

package OpenCA::Log;

use OpenCA::Tools;

use FileHandle;
our ($STDERR, $STDOUT);
$STDOUT = \*STDOUT;
$STDERR = \*STDERR;

our ($errno, $errval);

($OpenCA::Log::VERSION = '$Revision: 1.4 $' )=~ s/(?:^.*: (\d+))|(?:\s+\$$)/defined $1?"0\.9":""/eg;

sub setError {
    my $self = shift;

    if (scalar (@_) == 4) {
        my $keys = { @_ };
        $errval = $keys->{ERRVAL};
        $errno  = $keys->{ERRNO};
    } else {
        $errno  = $_[0];
        $errval = $_[1];
    }

    print $STDERR "PKI Master Alert: Access control error\n";
    print $STDERR "PKI Master Alert: Aborting all operations\n";
    print $STDERR "PKI Master Alert: Error:   $errno\n";
    print $STDERR "PKI Master Alert: Message: $errval\n";
    print $STDERR "PKI Master Alert: debugging messages of access control follow\n";
    $self->{debug_fd} = $STDERR;
    $self->debug ();
    $self->{debug_fd} = $STDOUT;

    ## support for: return $self->setError (1234, "Something fails.") if (not $xyz);
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

sub debug {

    my $self = shift;
    if ($_[0]) {
        $self->{debug_msg}[scalar @{$self->{debug_msg}}] = $_[0];
        $self->debug () if ($self->{DEBUG});
    } else {
        my $msg;
        foreach $msg (@{$self->{debug_msg}}) {
            $msg =~ s/ /&nbsp;/g;
            my $oldfh = select $self->{debug_fd};
            print $msg."<br>\n";
            select $oldfh;
        }
        $self->{debug_msg} = ();
    }

}

sub new {
    my $that = shift;
    my $class = ref($that) || $that;

    my $self = {
                DEBUG     => 0,
                debug_fd  => $STDERR,
                ## debug_msg => ()
               };

    bless $self, $class;

    my $keys = { @_ };

    ## get crypto backend
    $self->{TOKEN} = $keys->{CRYPTO};
    $self->debug ("token loaded");

    ## load config
    $self->{configfile} = $keys->{CONFIG};
    $self->{cache}      = $keys->{CACHE};
    $self->debug ("config ready");

    ## determine slots
    my $slot_count = $self->{cache}->get_xpath_count (
                         FILENAME => $self->{configfile},
                         XPATH    => 'log/slots/slot');
    for (my $i=0; $i<$slot_count; $i++)
    {
        $self->debug ("loading slot ...");
        my $name  = $self->{cache}->get_xpath (
                        FILENAME => $self->{configfile},
                        XPATH    => [ 'log/slots/slot', 'name' ],
                        COUNTER  => [ $i, 0 ]);
        my $class = $self->{cache}->get_xpath (
                        FILENAME => $self->{configfile},
                        XPATH    => [ 'log/slots/slot', 'class' ],
                        COUNTER  => [ $i, 0 ]);
        my $level = $self->{cache}->get_xpath (
                        FILENAME => $self->{configfile},
                        XPATH    => [ 'log/slots/slot', 'level' ],
                        COUNTER  => [ $i, 0 ]);
        $self->{CLASS}->{$class}[scalar @{$self->{CLASS}->{$class}}] = $name;
        $self->{LEVEL}->{$level}[scalar @{$self->{LEVEL}->{$level}}] = $name;
        $self->{SLOT}->{$name}->{logger} = $self->{cache}->get_xpath (
                        FILENAME => $self->{configfile},
                        XPATH    => [ 'log/slots/slot', 'logger' ],
                        COUNTER  => [ $i, 0 ]);
        if (not defined $self->{SLOT}->{$name}->{logger})
        {
            print STDERR "OpenCA LOG: There is a log slot without a logger!";
            return undef;
        }
        my @list = ();
        my @known_para = ( "name", "class", "level", "logger",
                           "type", "prefix", "facility", "socket_type",
                           "dir");
        foreach my $h (@known_para) {
            my $value = $self->{cache}->get_xpath (
                        FILENAME => $self->{configfile},
                        XPATH    => [ 'log/slots/slot', $h ],
                        COUNTER  => [ $i, 0 ]);
            push @list, $h, $value if (defined $value);
        }
        $self->debug ("    name=".$name);
        $self->debug ("    class=".$class);
        $self->debug ("    level=".$level);

        ## try to load requested syslog module
        my $syslog_class = "OpenCA::Logger::".$self->{SLOT}->{$name}->{logger};
        eval "require $syslog_class";
        return $self->setError (64310025, $@) if ($@);
        $self->debug ("    loaded class");

        $self->{SLOT}->{$name} = eval {$syslog_class->new (@list)};
        $self->debug ("    object result: ".$@);
        $self->debug ("    object errno: ".eval {$syslog_class::errno});
        return $self->setError ($@, $@) if ($@);
        return $self->setError (64310030, $@."(".$syslog_class::errno.")".$syslog_class::errval)
            if (not $self->{SLOT}->{$name} or not ref $self->{SLOT}->{$name});
        $self->debug ("    loaded object");
    }
    $self->debug ("slots loaded");
    foreach my $class (keys %{$self->{CLASS}}) {
        @{$self->{CLASS}->{$class}} = sort @{$self->{CLASS}->{$class}};
    }
    foreach my $level (keys %{$self->{LEVEL}}) {
        @{$self->{LEVEL}->{$level}} = sort @{$self->{LEVEL}->{$level}};
    }
    $self->debug ("slots sorted");

    return $self;
}

sub addMessage {
    my $self = shift;
    my $msg  = $_[0];

    ## determine used slots

    ## build class list
    my @class_list = ();

    push @class_list, @{$self->{CLASS}->{$msg->getClass}}
        if (exists $self->{CLASS}->{$msg->getClass});
    push @class_list, @{$self->{CLASS}->{'*'}}
        if (exists $self->{CLASS}->{'*'});
    @class_list = sort @class_list;

    ## build level list
    my @level_list = ();
    push @level_list, @{$self->{LEVEL}->{$msg->getLevel}}
        if (exists $self->{LEVEL}->{$msg->getLevel});
    push @level_list, @{$self->{LEVEL}->{'*'}}
        if (exists $self->{LEVEL}->{'*'});
    @level_list = sort @level_list;

    ## merge lists
    my @slot_list = ();
    my $class_slot = pop @class_list;
    my $level_slot = pop @level_list;
    while (defined $class_slot and defined $level_slot)
    {
        if ($class_slot > $level_slot) {
            $level_slot = pop @level_list;
        } elsif ($class_slot < $level_slot) {
            $class_slot = pop @class_list;
        } else {
            push @slot_list, $class_slot;
            $level_slot = pop @level_list;
            $class_slot = pop @class_list;
        }
    }
    return $self->setError (64510020, "There is no appropriate logger.") if (not scalar @slot_list);

    ## sign message if supported
    if ($self->{TOKEN}->keyOnline)
    {
        $msg->setSignature($self->{TOKEN}->sign(DATA => $msg->getXML));
    }

    ## store message in slots
    foreach my $slot (@slot_list) {
        ## add message
        return $self->setError (64510030, "addMessage failed for log slot $slot.")
            if (not $self->{SLOT}->{$slot}->addMessage ($msg));

        ## get digest from log if supported and
        ## sign digest from log if supported
        if ($self->{SLOT}->{$slot}->supportLogDigest and $self->{SLOT}->{$slot}->supportLogSignature)
        {
            my $digest    = $$self->{SLOT}->{slot}->getLogDigest;
            my $signature = $self->{TOKEN}->sign(DATA => $digest);
            $self->{SLOT}->{$slot}->addLogSignature($signature);
        }
        
        ## flush log
        $self->{SLOT}->{$slot}->flush;
    }
    return 1;
}

## should be implemented later
sub search {
    my $self = shift;
    my $keys = { @_ };
    my @list = ();
    my @slots = ();

    ## extract parameters
    my $class = $keys->{CLASS};
    my $level = $keys->{LEVEL};
    my $id    = $keys->{SESSION_ID};

    ## find slots which support searching
    foreach my $slot (keys %{$self->{SLOT}})
    {
        push @slots, $slot if ($self->{SLOT}->{$slot}->supportSearch);
    }

    ## search in every slot
    foreach my $slot (@slots) {
        my @res = ();
        push @res, "CLASS",      $class if (defined $class);
        push @res, "LEVEL",      $level if (defined $level);
        push @res, "SESSION_ID", $id    if (defined $id);
        @res = $self->{SLOT}->{$slot}->search (@res);
        push @list, @res if @res;
    }

    ## order results
    @list = sort @list;

    ## remove duplicates
    my @h_list = @list;
    @list = ();
    foreach my $item (@h_list)
    {
        push @list, $item if ($list[scalar @list -1] ne $item);
    }

    ## return
    return @list;
}

sub getMessage {
    my $self = shift;
    my $id   = shift;
    my @slots = ();

    ## find slots which support getMessage
    foreach my $slot (keys %{$self->{SLOT}})
    {
        push @slots, $slot if ($self->{SLOT}->{$slot}->supportGetMessage);
    }

    ## try to get slot
    foreach my $slot (@slots) {
        my $msg = $self->{SLOT}->{$slot}->getMessage ($id);
        return $msg if $msg;
    }

    ## cannot get message
    return undef;
}

1;
__END__
