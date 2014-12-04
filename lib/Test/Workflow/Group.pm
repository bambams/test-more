package Test::Workflow::Group;
use strict;
use warnings;

use Test::Stream::Carp qw/confess/;

use Test::Stream::ArrayBase(
    accessors => [qw/name block components params caller root include/],
);

sub init {
    my $self = shift;
    $self->[COMPONENTS] ||= {};
    $self->[INCLUDE]    ||= [];
}

sub add {
    my $self = shift;
    my %params = @_;

    my $type = $params{type} || confess "the 'type' field is mandatory";
    my $item = $params{item} || confess "the 'item' field is mandatory";

    push @{$self->[COMPONENTS]->{$type}} => $item;
}

sub include {
    my $self = shift;
    for my $wf (@_) {
        confess "$wf is not a Test::Workflow::Group object" unless $wf->isa('Test::Workflow::Group');
        push @{$self->[INCLUDE]} => $wf;
    }
}

1;
