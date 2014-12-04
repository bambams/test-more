package Test::Workflow::Scheduler;
use strict;
use warnings;

use Test::Stream::Carp qw/confess/;

my %COMPONENTS;

sub define {
    my $class = shift;

    my $caller = caller;

    while (my $name = shift) {
        my $spec = shift;
        confess "$name was already defined by $COMPONENTS{$name}->{defined}"
            if $COMPONENTS{$name};

        $COMPONENTS{$name} = { %$spec, defined => $caller };
    }
}

sub run {
    my $proto = shift;
    my %params = @_;

    my $inst = $proto->new(%params);

    my $workflow = delete $params{workflow} || confess "No workflow";

    my @items = map { $inst->compile($_) } $workflow, @{$workflow->include};

    for my $item (@items) {
        if ($item->isa('Test::Workflow::Unit')) {
            $inst->run_unit($item);
        }
        elsif($item->isa('Test::Workflow::Set')) {
            $inst->run_set($item);
        }
    }
}

sub run_unit {
    my $self = shift;
}

sub run_set {
    my $self = shift;
}

1;
