## OpenCA::Log::Message.pm 
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

## this simple class has only to manage the message itself
## it is used to create correct transformations

package OpenCA::Log::Message;

use XML::Twig;
use POSIX qw(strftime);

use FileHandle;
our ($STDERR, $STDOUT);
$STDOUT = \*STDOUT;
$STDERR = \*STDERR;

our ($errno, $errval);

($OpenCA::Log::Message::VERSION = '$Revision: 1.3 $' )=~ s/(?:^.*: (\d+))|(?:\s+\$$)/defined $1?"0\.9":""/eg;

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
                debug_fd  => $STDOUT,
                ## debug_msg => ()
               };

    bless $self, $class;

    my $keys = { @_ };

    $self->{HASH} = $self->_parseHash ($keys->{HASHREF})
        if ($keys->{HASHREF});
    $self->_parseXML ($keys->{XML}) if ($keys->{XML});

    ## prepare class and level
    foreach my $key (keys %{$keys}) {
        $self->{HASH}->{CLASS} = $keys->{$key}  if ($key =~ /^CLASS$/i);
        $self->{HASH}->{LEVEL} = $keys->{$key} if ($key =~ /^LEVEL$/i);
    }

    ## prepare timestamp
    if (not $self->{HASH}->{TIMESTAMP})
    {
        ## we use UTC timestamps because they are unique for all systems
        my $time = time;
        $self->{HASH}->{TIMESTAMP}     = strftime ("%Y-%b-%d %H:%M:%S", gmtime ($time));
        $self->{HASH}->{ISO_TIMESTAMP} = strftime ("%Y-%m-%d %H:%M:%S", gmtime ($time));
        $self->{TIMESTAMP} = $time;
    }

    ## prepare ID
    if (not $self->{HASH}->{ID})
    {
        ## timestamp + 32-digit random
        $self->{HASH}->{ID} = $self->{TIMESTAMP};
        for (my $h=0; $h<32; $h++)
        {
            $self->{HASH}->{ID} .= int (int (rand (10) + 0.5) % 10);
        }
    }

    return $self;
}

sub _parseHash {
    my $self = shift;
    my $hash = shift;

    my $result = undef;
    foreach my $key (keys %{$hash})
    {
        if (ref $key)
        {
            $result->{uc $key} = $self->_parseHash ($hash->{$key});
        } else {
            $result->{uc $key} = $hash->{$key};
        }
    }
    return $result;
}

sub _parseXML {
    my $self = shift;

    ## create XML object
    $self->{twig} = new XML::Twig;
    if (not $self->{twig})
    {
        $self->debug ("XML::Twig cannot be created.");
        $self->setError (6431010, "XML::Twig cannot be created");
        return undef;
    }

    ## parse XML
    if (not $self->{twig}->safe_parse($_[0]))
    {
        my $msg = $@;
        $self->debug ("XML::Twig cannot parse configuration");
        $self->setError (6431020, "XML::Twig cannot parse XML data.".
                           "XML::Parser returned errormessage: $msg");
        return undef;
    }

    ## build hash by recursion
    $self->{HASH} = $self->_parseXMLlevel($self->{twig}->root);

    return 1;
}

sub _parseXMLlevel {

    my $self   = shift;
    my $entity = $_[0];
    my $result = undef;
    return $result if (not $entity);

    ## return the content if there are no children
    return $entity->field if ($entity->is_field);

    ## load all childrens of the entity
    my @list = $entity->children;

    foreach my $child (@list)
    {
        $result->{uc ($child->tag)} = $self->_parseXMLlevel ($child);
    }
    return $result;
}

sub getXML {
    my $self = shift;
    return "<log_message>".$self->_buildXML ($self->{HASH}, "    ")."\n</log_message>";
}

sub _buildXML {
    my $self = shift;
    my $ref  = $_[0];
    my $tab  = $_[1];
    my $space = "    ";
    my $xml   = "";

    my @list = keys %{$ref};
    @list = sort @list;

    foreach my $item (@list)
    {
        if (ref $ref->{$item})
        {
            $xml .= "\n".$tab."<".lc $item.">".
                    $self->_buildXML ($ref->{$item}, $tab.$space).
                    "\n".$tab."</".lc $item.">";
        } else {
            $xml .= "\n".$tab."<".lc $item.">".
                    $ref->{$item}.
                    "</".lc $item.">";
        }
    }
    return $xml;
}

sub getHash {
    my $self = shift;
    return $self->{HASH};
}

sub setSignature {
    my $self = shift;
    $self->{HASH}->{SIGNATURE} = $_[0];
    return 1;
}

sub getClass {
    my $self = shift;
    return $self->{HASH}->{CLASS};
}

sub getLevel {
    my $self = shift;
    return $self->{HASH}->{LEVEL};
}

sub getID {
    my $self = shift;
    return $self->{HASH}->{ID};
}

sub getTimestamp {
    my $self = shift;
    return $self->{HASH}->{TIMESTAMP};
}

sub getISOTimestamp {
    my $self = shift;
    return $self->{HASH}->{ISO_TIMESTAMP};
}

sub getSignature {
    my $self = shift;
    return $self->{HASH}->{SIGNATURE};
}

sub getSessionID {
    my $self = shift;
    return $self->{HASH}->{SESSION_ID};
}

1;
__END__
