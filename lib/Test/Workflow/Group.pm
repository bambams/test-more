package Test::Workflow::Group;
use strict;
use warnings;

use Scalar::Util qw/blessed/;
use Test::Stream::Carp qw/confess/;

use Test::Stream::ArrayBase(
    accessors => [qw/name block components subgroups params caller root includes/],
);

sub init {
    my $self = shift;

    $self->[COMPONENTS] ||= {};
    $self->[INCLUDES]   ||= [];
    $self->[PARAMS]     ||= {};
    $self->[SUBGROUPS]  ||= [];
}

sub add {
    my $self = shift;
    my %params = @_;

    my $type = $params{type} || confess "the 'type' field is mandatory";
    my $item = $params{item} || confess "the 'item' field is mandatory";

    my $slot = Test::Workflow::Scheduler->spec($type, 'type');

    $item->merge_params($self->params) if $item->can('merge_params');
    push @{$self->[COMPONENTS]->{$slot}} => [$type, $item];
}

sub add_group {
    my $self = shift;
    my ($group) = @_;

    confess "$group is not a Test::Workflow::Group"
        unless blessed($group) && $group->isa('Test::Workflow::Group');

    push @{$self->[SUBGROUPS]} => $group;
}

sub include {
    my $self = shift;
    for my $wf (@_) {
        confess "$wf is not a Test::Workflow::Group object" unless $wf->isa('Test::Workflow::Group');
        push @{$self->[INCLUDES]} => $wf;
    }
}

1;
