package Test::Workflow::Scheduler;
use strict;
use warnings;

use Scalar::Util qw/blessed reftype/;
use Test::Stream::Util qw/try/;
use Test::Stream::Carp qw/confess croak/;

use Test::Workflow qw/spec/;
use Test::Workflow::Unit;

sub new {
    my $class = shift;
    my %params = @_;
    return bless {
        state => [],
        args  => [],
        %params,
    }, $class;
}

sub args { $_[0]->{args} }

sub state {
    my $self = shift;
    return unless @{$self->{state}};
    return $self->{state}->[-1];
}

sub push_state { push @{$_[0]->{state}} => {} }

sub pop_state { pop @{$_[0]->{state}} }

sub run {
    my $proto = shift;
    my %params = @_;

    my $self = blessed $proto ? $proto : $proto->new(%params);

    my $workflow = delete $params{workflow} || confess "No workflow";

    my @units = map { $self->_compile($_, {}) } $workflow, @{$workflow->includes};

    $self->run_unit($_, 0) for @units;
}

sub run_unit {
    my $self = shift;
    my ($unit, $nested, @prefix_args) = @_;

    confess "Invalid unit ($unit)!"
        unless $unit && blessed $unit && $unit->isa('Test::Workflow::Unit');

    $unit->run(@prefix_args, @{$self->args});
}

sub _compile {
    my $self = shift;
    my ($group, $inherit) = @_;
    my $comps = $group->components;

    my $all = { map { $_ => [ @{$inherit->{$_} || []}, @{$comps->{$_} || []} ] } qw/modifier multiplier/ };

    my $actions = {};
    my @action_order;
    for my $action (@{$comps->{action}}) {
        my ($type, $it) = @$action;

        my $unit = Test::Workflow::Unit->new_from_pairs(
            stateful  => 1,
            type      => $type,
            core      => $it,
            scheduler => $self,
        );

        push @{$actions->{$type}} => $unit;
        push @action_order => $unit;
    }

    my $multipliers = {};
    my @mul_order;
    for my $mul (@{$all->{multiplier}}) {
        my ($type, $it) = @$mul;
        my $spec = spec($type);

        my $unit = Test::Workflow::Unit->new_from_pairs(
            stateful  => 0,
            type      => $type,
            core      => $it,
            scheduler => $self,
            affix     => $spec->{affix},
        );

        push @{$multipliers->{$type}} => $unit;
        push @mul_order => $unit;
    }

    my $to_modify = { %$multipliers, %$actions };

    # Apply modifiers
    for my $mod (@{$all->{modifier}}) {
        my ($type, $it) = @$mod;
        my $spec = spec($type);

        my $alter = $spec->{alter};
        next unless $to_modify->{$alter};
        for my $unit (@{$to_modify->{$alter}}) {
            $unit->alter($it, $spec->{affix});
        }
    }

    my @units;
    # apply multipliers to actions
    if (@mul_order) {
        for my $mul (@mul_order) {
            for my $action (@action_order) {
                push @units => $action->multiply($mul);
            }
        }
    }
    else {
        @units = @action_order;
    }

    push @units => map { $self->_compile($_, $all) } @{$group->subgroups};

    

    return @units unless $comps->{init} && @{$comps->{init}};

    my $unit = Test::Workflow::Unit->new_from_pairs(
        stateful => 1,
        core     => \@units,
        scheduler => $self,
    );

    $unit->alter($_) for @{$comps->{init}};

    return ($unit);
}

1;

__END__
