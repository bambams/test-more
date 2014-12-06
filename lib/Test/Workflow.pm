package Test::Workflow;
use strict;
use warnings;

use Test::Stream;

use Scalar::Util qw/blessed reftype/;

use Test::Stream::Util qw/try/;
use Test::Stream::Carp qw/croak confess/;

# {{{ Exports, meta-data, etc.
{
    use Test::Workflow::Block;

    use Test::Stream::Exporter;
    exports qw{
        define_components

        generate_adder
        build_workflow
        root_workflow

        spec

        auto_run
    };

    Test::Stream::Exporter->cleanup();

    my %STACKS;
    my %COMPONENTS;
    my %TYPES;

    define_components(tests => {type => 'action', state_layer => 1});

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

                $wf->run(%$params);
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
        return {%$spec};
    }

    sub define_components {
        my $caller = caller;

        while (my $name = shift) {
            my $spec = shift;
            confess "$name was already defined by $COMPONENTS{$name}->{_defined}"
                if $COMPONENTS{$name};

            $spec = {type => "", %$spec, _defined => $caller, name => $name};

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

        $STACKS{$pkg} ||= [
            Test::Workflow->new_from_pairs(
                name    => "$pkg (root)",
                defined => [$pkg, $file, 0, undef],
                root    => $pkg
            )
        ];

        return ($block, [$pkg, $file, $line, $sub], $name, \%params);
    }

    sub generate_adder {
        my ($type) = @_;
        my ($pkg, $file, $line) = caller();

        # Lexicalize these for use in the string eval.
        my $stacks = \%STACKS;
        my $parse  = \&_parse_params;

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

        my $workflow = Test::Workflow->new_from_pairs(
            params  => $params,
            name    => $name,
            defined => $caller,
            block   => $block,
        );

        push @{$STACKS{$pkg}} => $workflow;
        my ($ok, $err) = try { $block->run };
        pop @{$STACKS{$pkg}};

        if ($ok) {
            $STACKS{$pkg}->[-1]->add_wf($workflow);
        }
        else {
            die $err;
        }

        return $workflow;
    }
}
# }}}

# {{{ Object related code
{
    use Test::Stream::ArrayBase(
        accessors => [qw/name block components nested params defined root includes/],
    );

    sub init {
        my $self = shift;

        $self->[COMPONENTS] ||= {};
        $self->[INCLUDES]   ||= [];
        $self->[PARAMS]     ||= {};
        $self->[NESTED]  ||= [];
    }

    sub add {
        my $self   = shift;
        my %params = @_;

        my $type = $params{type} || confess "the 'type' field is mandatory";
        my $item = $params{item} || confess "the 'item' field is mandatory";

        my $slot = Test::Workflow::spec($type)->{'type'};

        $item->merge_params($self->params) if $item->can('merge_params');
        push @{$self->[COMPONENTS]->{$slot}} => [$type, $item];
    }

    sub add_wf {
        my $self = shift;
        my ($wf) = @_;

        confess "$wf is not a Test::Workflow instance"
            unless blessed($wf) && $wf->isa('Test::Workflow');

        push @{$self->[NESTED]} => $wf;
    }

    sub include {
        my $self = shift;
        for my $wf (@_) {
            confess "$wf is not a Test::Workflow::Group object" unless $wf->isa('Test::Workflow::Group');
            push @{$self->[INCLUDES]} => $wf;
        }
    }

    sub run {
        my $self = shift;
        my %params = @_;

        require Test::Workflow::Scheduler;
        my $scheduler = delete $params{scheduler} || Test::Workflow::Scheduler->new(%params);

        my @units = map { $_->_compile($scheduler, {}) } $self, @{$self->includes};

        $scheduler->run_unit($_) for @units;
    }

    sub _compile {
        my $self = shift;
        my ($scheduler, $inherit) = @_;
        my $comps = $self->components;

        my $all = { map { $_ => [ @{$inherit->{$_} || []}, @{$comps->{$_} || []} ] } qw/modifier multiplier/ };

        my $actions = {};
        my @action_order;
        for my $action (@{$comps->{action}}) {
            my ($type, $it) = @$action;

            my $unit = Test::Workflow::Unit->new_from_pairs(
                stateful  => 1,
                type      => $type,
                core      => $it,
                scheduler => $scheduler,
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
                scheduler => $scheduler,
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

        push @units => map { $_->_compile($scheduler, $all) } @{$self->nested};



        return @units unless $comps->{init} && @{$comps->{init}};

        my $unit = Test::Workflow::Unit->new_from_pairs(
            stateful => 1,
            core     => \@units,
            scheduler => $scheduler,
        );

        $unit->alter($_) for @{$comps->{init}};

        return ($unit);
    }
}

# }}}

1;

