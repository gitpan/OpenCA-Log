## OpenCA::Logger::XML.pm 
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

package OpenCA::Logger::XML;

use DB_File;
use OpenCA::Log::Message;

## use FileHandle;
## our ($STDERR, $STDOUT);
## $STDOUT = \*STDOUT;
## $STDERR = \*STDERR;

our ($errno, $errval);

($OpenCA::Logger::XML::VERSION = '$Revision: 1.3 $' )=~ s/(?:^.*: (\d+))|(?:\s+\$$)/defined $1?"0\.9":""/eg;

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
    foreach my $key (keys %{$keys}) {
        $self->{DIR} = $keys->{$key} if ($key =~ /DIR/i);
    }

    return $self->setError (6512010, "You must specify the used directory.")
        if (not $self->{DIR});
    return $self->setError (6512011, "The specified file must be a directory.")
        if (not -d $self->{DIR});

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
    return 1;
}

sub supportSearch {
    return 1;
}

sub addMessage {
    my $self = shift;
    my $msg  = $_[0];

    ## load timestamp
    my $iso = $msg->getISOTimestamp;

    ## parse iso timestamp
    my @time = ($iso =~ /(\d\d\d\d)-(\d\d)-(\d\d)\s*(\d\d):(\d\d):(\d\d)/);

    ## check log-directory
    return $self->setError (6512030, "The logging directory doesn't exist.")
        if (not -d $self->{DIR});

    ## build log path
    my $path = $self->{DIR}."/time";
    foreach my $item (@time)
    {
        $path .= "/".$item;
        return $self->setError (6512032, "Cannot create directory $path.")
            if (not -d $path and not mkdir $path, 0755);
    }

    ## filename now complete
    my $filename = $path."/".$msg->getID.".xml";

    ## write file
    return $self->setError (6512034, "Cannot open file $filename for writing.")
        if (not open FD, ">$filename");
    return $self->setError (6512035, "Cannot write to file $filename.")
        if (not print FD $msg->getXML);
    return $self->setError (6512036, "Cannot close file $filename.")
        if (not close FD);

    ## create symbolic links
    for (my $h=0; $h < 5; $h++)
    {
        ## remove last directory or filename
        $path     =~ s/\/[^\/]*$//;

        ## create all directory if not present
        return $self->setError (6512038, "Cannot create directory $path.")
            if (not -d $path."/all" and not mkdir $path."/all", 0755);
        
        ## create dynamic link
        return $self->setError (6512039, "Cannot create directory $path.")
            if (not -e $path."/all/".$msg->getID.".xml" and
                not symlink $filename, $path."/all/".$msg->getID.".xml");
    }

    ## add message to class db
    return undef if (not $self->_updateIndex (TYPE => "class",
                                              NAME => $msg->getClass,
                                              ID   => $msg->getID,
                                              REF  => $msg->getISOTimestamp));

    ## add message to level db
    return undef if (not $self->_updateIndex (TYPE => "level",
                                              NAME => $msg->getLevel,
                                              ID   => $msg->getID,
                                              REF  => $msg->getISOTimestamp));

    ## create start session entry if necessary
    return undef if (not $self->_updateIndex (TYPE => "session",
                                              NAME => "start",
                                              ID   => $msg->getID,
                                              REF  => $msg->getISOTimestamp));

    ## update stop session entry if necessary
    return undef if (not $self->_updateIndex (TYPE => "session",
                                              NAME => "stop",
                                              MODE => "force",
                                              ID   => $msg->getID,
                                              REF  => $msg->getISOTimestamp));

    ## create time reference
    return undef if (not $self->_updateIndex (TYPE => "time",
                                              NAME => "id2time",
                                              ID   => $msg->getID,
                                              REF  => $msg->getISOTimestamp));

    return 1;
}

sub flush {
    return 1;
}

sub getMessage {
    my $self = shift;
    my $id   = shift;
print STDERR "getMEssage: id:$id\n";

    my $handle = $self->_openDB (TYPE => "time", NAME => "id2time");
    return undef if (not $handle);

    my $iso = $self->_getDBItem (HANDLE => $handle, ID => $id);
    return undef if (not $iso);

    ## parse iso timestamp
    my @time = ($iso =~ /(\d\d\d\d)-(\d\d)-(\d\d)\s*(\d\d):(\d\d):(\d\d)/);

    ## build log path
    my $filename = $self->{DIR}."/time";
    foreach my $item (@time)
    {
        $filename .= "/".$item;
    }
    $filename .= "/".$id.".xml";
    return $self->setError (6512052, "The requested item is not present.")
        if (not -e $filename);

    ## read file
print STDERR "getMEssage: filename:$filename\n";
    my $file = "";
    return $self->setError (6512054, "Cannot open file $filename for writing.")
        if (not open FD, "$filename");
    while ( <FD> ) {
        $file .= $_;
    };
    return $self->setError (6512056, "Cannot close file $filename.")
        if (not close FD);

    ## build message
    my $msg = OpenCA::Log::Message->new (XML => $file);
    return $self->setError (OpenCA::Log::Message::errno, OpenCA::Log::Message::errval)
        if (not $msg);
print STDERR "getMEssage: timestamp:".$msg->getISOTimestamp."\n";

    return $msg;
}

sub search {
    my $self = shift;
    my $keys = { @_ };
    my @class_list   = undef;
    my @level_list   = undef;
    my @session_list = undef;

    ## build class list
    if ($keys->{CLASS})
    {
        my $handle = $self->_openDB (TYPE => "CLASS", NAME => $keys->{CLASS});
        return undef if (not $handle);
        @class_list = sort $self->_loadDB ($handle);
    }

    ## build level list
    if ($keys->{LEVEL})
    {
        my $handle = $self->_openDB (TYPE => "LEVEL", NAME => $keys->{LEVEL});
        return undef if (not $handle);
        @level_list = sort $self->_loadDB ($handle);
    }

    ## session filter
        ## get start time
        ## get stop time
        ## search all messages for the session_id

    ## load all items if no class is specified
    if (not $keys->{LEVEL} and not $keys->{CLASS})
    {
        my $handle = $self->_openDB (TYPE => "TIME", NAME => "id2time");
        return undef if (not $handle);
        @class_list = sort $self->_loadDB ($handle);
    }

    ## merge lists
    my @list = ();
    if (not $keys->{LEVEL})
    {
        push @list, @class_list;
    } elsif (not $keys->{CLASS}) {
        push @list, @level_list;
    }else {
        my $class = pop @class_list;
        my $level = pop @level_list;
        while (defined $class and defined $level)
        {
            if ($class > $level) {
                $level = pop @level_list;
            } elsif ($class < $level) {
                $class = pop @class_list;
            } else {
                push @list, $class;
                $level = pop @level_list;
                $class = pop @class_list;
            }
        }
    }

    ## return result
    return @list;
}

sub _updateIndex {

    my $self = shift;
    my $keys = { @_ };
    my $type = $keys->{TYPE};
    my $name = $keys->{NAME};
    my $id   = $keys->{ID};
    my $ref  = $keys->{REF};
    my $mode = $keys->{MODE};

    ## open and perhaps create index
    my $db_h = $self->_openDB (TYPE => $type, NAME => $name);
    return undef if (not $db_h);

    ## check for already present item
    if (not $mode or $mode !~ /force/i)
    {
        my $item = $self->_getDBItem (HANDLE => $db_h, ID => $id);
        return 1 if ($item);
    }

    ## insert item id + iso_timestamp
    return undef if (not $self->_insertDBItem (HANDLE => $db_h, ID => $id, REF => $ref));

    return 1;
}

sub _openDB {
    my $self = shift;
    my $keys = { @_ };
    my $type = $keys->{TYPE};
    my $name = $keys->{NAME};

    my $filename = $self->{DIR}."/".lc $type."/".lc $name.".dbm";

    return $self->{HANDLE_CACHE}->{$filename}
        if (exists $self->{HANDLE_CACHE} and
            exists $self->{HANDLE_CACHE}->{$filename});

    my %h;
    my $handle = tie %h, "DB_File", $filename, O_CREAT|O_RDWR, 0644, $DB_BTREE ;

    return $self->setError (6512042, "Cannot open database.")
        if (not $handle);

    ## cashing handles
    $self->{HANDLE_CACHE}->{$filename} = $handle;

    return $handle;
}

sub _getDBItem {
    my $self = shift;
    my $keys = { @_ };
    my $handle = $keys->{HANDLE};
    my $id     = $keys->{ID};

    my $item;
    return $item if (not $handle->get ($id, $item));
    return undef;  ## item not present in DB
}

sub _loadDB {
    my $self   = shift;
    my $handle = shift;
    my @list = ();

    my ($key, $value) = (0, 0);
    for (my $status = $handle->seq($key, $value, R_FIRST) ;
            $status == 0 ;
            $status = $handle->seq($key, $value, R_NEXT) )
    {
        push @list, $key;
    }

    return @list;
}

sub _insertDBItem {
    my $self = shift;
    my $keys = { @_ };
    my $handle = $keys->{HANDLE};
    my $id     = $keys->{ID};
    my $ref    = $keys->{REF};

    $handle->put ($id, $ref, R_NOOVERWRITE);
    return $self->setError (6512044, "Cannot insert $id to database.")
        if (not $self->_getDBItem (HANDLE => $handle, ID => $id));

    return 1;
}

sub _closeDB {
    my $self   = shift;
    my $handle = shift;

    undef $handle;

    return 1;
}

sub DESTROY
{
    my $self = shift;
    foreach my $filename (keys %{$self->{HANDLE_CACHE}})
    {
        $self->_closeDB ($self->{HANDLE_CACHE}->{$filename});
    }
}

1;

__END__
