package Test::Workflow::Scheduler;
use strict;
use warnings;

use Scalar::Util qw/blessed reftype/;
use Test::Stream::Util qw/try/;
use Test::Stream::Carp qw/confess croak/;

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
sub pop_state  { pop  @{$_[0]->{state}}       }

sub run_unit {
    my $self = shift;
    my ($unit, $nested, @prefix_args) = @_;

    confess "Invalid unit ($unit)!"
        unless $unit && blessed $unit && $unit->isa('Test::Workflow::Unit');

    $unit->run(@prefix_args, @{$self->args});
}

1;

__END__
