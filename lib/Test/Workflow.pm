package Test::Workflow;
use strict;
use warnings;

use Scalar::Util qw/reftype/;

use Test::Stream;

use Test::Workflow::Group;
use Test::Workflow::Block;

use Test::Stream::Util qw/try/;
use Test::Stream::Carp qw/croak confess/;

use Test::Stream::Exporter;
exports qw{
    define_components

    generate_adder
    build_workflow
    run_workflow
    root_workflow

    spec

    auto_run
};
Test::Stream::Exporter->cleanup();

my %STACKS;
my %COMPONENTS;
my %TYPES;

define_components( tests => {type => 'action', state_layer => 1} );

my %AUTO_RUN;
sub auto_run {
    my $package = shift;
    my ($params) = @_;

    require Test::Workflow::Scheduler;

    my $ran = 0;
    Test::Stream->shared->follow_up(
        sub {
            return if $ran++;
            my ($wf) = @{$STACKS{$package} || []};

            croak "No workflow for package '$package' which was set to auto-run!"
                unless $wf;

            $params->{workflow} = $wf;

            my $scheduler = delete $params->{scheduler} || 'Test::Workflow::Scheduler';
            $scheduler->run(%$params);
        }
    );
}

sub root_workflow {
    my $pkg = shift || caller;
    return $STACKS{$pkg};
}

sub spec {
    my $name = pop;
    my $spec = $COMPONENTS{$name} || croak "No component named $name!";
    return { %$spec };
}

sub define_components {
    my $caller = caller;

    while (my $name = shift) {
        my $spec = shift;
        confess "$name was already defined by $COMPONENTS{$name}->{_defined}"
            if $COMPONENTS{$name};

        $spec = { type => "", %$spec, _defined => $caller, name => $name };

        croak "Invalid type ($spec->{type}) in '$spec->{name}'"             if $spec->{type} !~ m/^(modifier|action|init|multiplier)$/;
        croak "Modifiers must have a value for 'alter' ($spec->{name})"     if $spec->{type} eq 'modifier' && !$spec->{alter};
        croak "Only modifiers may have a value for 'alter' ($spec->{name})" if $spec->{alter} && $spec->{type} ne 'modifier';

        $COMPONENTS{$name} = $spec;
    }
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

    return ($block, [$pkg, $file, $line, $sub], $name, \%params );
}

sub generate_adder {
    my ($type) = @_;
    my ($pkg, $file, $line) = caller();

    # Lexicalize these for use in the string eval.
    my $stacks = \%STACKS;
    my $parse = \&_parse_params;

    # Use an eval to ensure the sub is named instead of __ANON__ in any traces.
    # Also spoof the line + file so that people know where they generated it.
    eval <<"    EOT" || die $@;
package $pkg;
#line $line "$file"
sub $type { my (\$block, \$caller) = \$parse->('$type', \\\@_); \$stacks->{\$caller->[0]}->[-1]->add(type => '$type', item => \$block) }
1;
    EOT
}

sub build_workflow {
    my ($block, $caller, $name, $params) = _parse_params('workflow', \@_);
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

    require Test::Workflow::Scheduler;
    my $scheduler = delete $params{scheduler} || 'Test::Workflow::Scheduler';
    $scheduler->run(%params);
}

1;
