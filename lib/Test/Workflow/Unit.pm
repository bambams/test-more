package Test::Stream::Unit;
use strict;
use warnings;

sub new {
    my $class = shift;
    my $self = bless [], $class;
    return $self;
}

1;
