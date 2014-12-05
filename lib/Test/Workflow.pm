package Test::Workflow;
use strict;
use warnings;

use Test::Stream;

use Test::Workflow::Group;
use Test::Workflow::Block;
use Test::Workflow::Scheduler;

use Test::Stream::Util qw/try/;
use Test::Stream::Carp qw/croak/;

use Test::Stream::Exporter;

use Scalar::Util qw/reftype/;

our %STACKS;

Test::Workflow::Scheduler->define(
    tests => {type => 'action',     state_layer => 1},
    case  => {type => 'multiplier', affix       => -1},

    before_all => {type => 'init', affix => -1},
    around_all => {type => 'init', affix => 0},
    after_all  => {type => 'init', affix => 1},

    before_each => {type => 'modifier', affix => -1, alter => 'tests'},
    around_each => {type => 'modifier', affix => 0,  alter => 'tests'},
    after_each  => {type => 'modifier', affix => 1,  alter => 'tests'},

    before_case => {type => 'modifier', affix => -1, alter => 'case'},
    around_case => {type => 'modifier', affix => 0,  alter => 'case'},
    after_case  => {type => 'modifier', affix => 1,  alter => 'case'},
);

for my $prefix (qw/before after around/) {
    for my $component (qw/case each all/) {
        _generate_adder("${prefix}_${component}");
    }
}

_generate_adder('case');
_generate_adder('tests');

{
    no warnings 'once';
    *it       = \&tests;
    *cases    = \&workflow;
    *describe = \&workflow;
}

default_exports qw{
    before_each after_each around_each
    before_all  after_all  around_all
    before_case after_case around_case

    case

    workflow cases describe

    tests it

    run_workflow
    root_workflow
};

sub before_import {
    my $class = shift;
    my ($caller, $args) = @_;
    my @new_args;
    my %run_params;

    while(my $arg = shift @$args) {
        if ($arg =~ m/^-(.+)$/) {
            $run_params{$arg} = shift @$args;
            next;
        }
        push @new_args => $arg;
    }
    @$args = @new_args;

    return if $run_params{no_auto};

    my $ran = 0;
    Test::Stream->shared->follow_up(
        sub {
            return if $ran++;
            my ($wf) = @{$STACKS{$caller} || []};
            return unless $wf;
            run_workflow(%run_params, workflow => $wf);
        }
    );
}

sub _parse_params {
    my ($tool, $args) = @_;

    my $name   = shift @$args;
    my $code   = pop @$args;
    my %params = @$args;

    my ($pkg, $file, $line, $sub) = caller(1);

    die "The first argument to '$tool' must be a name at $file line $line.\n"
        unless $name && !ref $name;

    die "The last argument to '$tool' must be a coderef at $file line $line.\n"
        unless $code && ref($code) && reftype($code) eq 'CODE';

    my $block = Test::Workflow::Block->new_from_pairs(
        coderef => $code,
        name    => $name,
        caller  => [$pkg, $file, $line, $sub],
        params  => \%params
    );

    $STACKS{$pkg} ||= [Test::Workflow::Group->new_from_pairs(
        name   => "$pkg (root)",
        caller => [$pkg, $file, 0, undef],
        root   => $pkg
    )];

    return ($name, $block, \%params, [$pkg, $file, $line, $sub]);
}

sub _generate_adder {
    my ($type) = @_;

    # Use an eval to ensure the sub is named instead of __ANON__ in any traces.
    eval <<"    EOT" || die $@;
        sub $type {
            my (\$name, \$block, \$params, \$caller) = _parse_params('$type', \\\@_);
            \$STACKS{\$caller->[0]}->[-1]->add(type => '$type', item => \$block);
        }

        1;
    EOT
}

sub workflow {
    my ($name, $block, $params, $caller) = _parse_params('workflow', \@_);
    my $pkg = $caller->[0];

    my $workflow = Test::Workflow::Group->new_from_pairs(
        params => $params,
        name   => $name,
        caller => $caller,
        block  => $block,
    );

    push @{$STACKS{$pkg}} => $workflow;
    my ($ok, $err) = try { $block->run };
    pop @{$STACKS{$pkg}};

    if ($ok) {
        $STACKS{$pkg}->[-1]->add_group($workflow);
    }
    else {
        die $err;
    }

    return $workflow;
}

sub run_workflow {
    my %params = @_;
    my $caller = caller;

    unless ($params{workflow}) {
        my ($wf) = @{$STACKS{$caller} || []};

        croak "No workflow for package '$caller', and no workflow provided."
            unless $wf;

        $params{workflow} = $wf;
    }

    my $scheduler = delete $params{scheduler} || 'Test::Workflow::Scheduler';
    $scheduler->run(%params);
}

sub root_workflow {
    my $pkg = shift || caller;
    return $STACKS{$pkg};
}

1;
