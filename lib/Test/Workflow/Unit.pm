package Test::Workflow::Unit;
use strict;
use warnings;

use Scalar::Util qw/blessed/;
use Test::Stream::Carp qw/confess/;

use Test::Stream::ArrayBase(
    accessors => [qw/stateful type core before after affix/],
);

sub init {
    my $self = shift;

    confess "core must be specified"
        unless $self->[CORE];

    $self->[BEFORE] = [];
    $self->[AFTER]  = [];
}

sub multiply {
    my $self = shift;
    my ($unit) = @_;

    my $class = blessed($self);

    my $clone = $class->new(map {
        my $ref = ref($_) || ""; # Do not use reftype, we want class if it is blessed.
        # If it is an unblessed array make a shallow copy, otherwise return as-is
        $ref eq 'ARRAY' ? [@{$_}] : $_;
    } @$self);

    $clone->alter($unit, $unit->affix);
    return $clone;
}

sub alter {
    my $self = shift;
    my ($modifier, $affix) = @_;

    # -1 is before only, 0 is both, 1 is after only
    push @{$self->[BEFORE]} => [$modifier, $affix] unless $affix > 0;
    push @{$self->[AFTER]}  => $modifier           unless $affix < 0;
}

sub run {

}

1;
