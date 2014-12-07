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
        define_types

        generate_adder
        build_workflow

        root_workflow

        auto_run
    };

    Test::Stream::Exporter->cleanup();

    my %STACKS;

    my %COMPONENTS = (
        tests    => {type => 'action',  require_name => 1, require_code => 1, state_layer => 1},
        workflow => {type => 'builtin', require_name => 1, require_code => 1, state_layer => 1},
    );


    my @TYPE_ORDER;
    my %TYPES = (
        modifier   => { run => 'builtin', defined => __PACKAGE__ },
        action     => { run => 'builtin', defined => __PACKAGE__ },
        init       => { run => 'builtin', defined => __PACKAGE__ },
        multiplier => { run => 'builtin', defined => __PACKAGE__ },
        builtin    => { run => 'builtin', defined => __PACKAGE__ },
    );

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

    sub comp {
        my $name = pop;
        my $spec = $COMPONENTS{$name} || croak "No component named $name!";
        return {%$spec}; # Shallow Copy
    }

    sub type {
        my $name = pop;
        my $type = $TYPES{$name} || croak "No type named $name!";
        return {%$type}; # Shallow Copy
    }

    sub types { @TYPE_ORDER }

    sub define_types {
        my $caller = caller;

        while (my $name = shift) {
            my $sub = shift;

            confess "Type '$name' requires a coderef, got '$sub'"
                unless $sub && ref $sub && reftype $sub eq 'CODE';

            confess "Type '$name' already defined by $TYPES{$name}->{defined}"
                if $TYPES{$name};

            push @TYPE_ORDER => $name;
            $TYPES{$name} = {run => $sub, defined => $caller};
        }
    }

    sub define_components {
        my $caller = caller;

        while (my $name = shift) {
            my $spec = shift;
            confess "$name was already defined by $COMPONENTS{$name}->{_defined}"
                if $COMPONENTS{$name};

            $spec = {type => "", %$spec, _defined => $caller, name => $name};

            croak "Invalid type ($spec->{type}) in '$spec->{name}'"             unless $TYPES{$spec->{type}};
            croak "Modifiers must have a value for 'alter' ($spec->{name})"     if $spec->{type} eq 'modifier' && !$spec->{alter};
            croak "Only modifiers may have a value for 'alter' ($spec->{name})" if $spec->{alter} && $spec->{type} ne 'modifier';

            $COMPONENTS{$name} = $spec;
        }
    }

    sub _parse_params {
        my ($comp, $args) = @_;

        my ($pkg, $file, $line, $sub) = caller(1);

        my $arg_count = scalar @$args;

        die "Not enough arguments to '$comp' ($arg_count) at $file line $line."
            if $arg_count == 0;

        die "Too many arguments to '$comp' ($arg_count) at $file line $line"
            if $arg_count > 3;

        my ($code, $name, $params);
        if ($arg_count == 1) {
            die "'$comp' requires a coderef, got '$comp'" unless ref $args->[0];
            my $rt = reftype($args->[0]);

            if ($rt eq 'CODE') {
                $params = {};
                $code = $args->[0];
            }
            elsif ($rt eq 'HASH') {
                $params = $args->[0];
                $code = delete $params->{code} || delete $params->{method} || delete $params->{sub};
                $name = delete $params->{name} || "";
            }
        }
        elsif ($arg_count == 2) {
            my $refa = reftype $args->[0] || "";
            my $refb = reftype $args->[1] || "";

            if ($refa eq 'HASH') {
                ($params, $code) = @$args;
                $name = delete $params->{name} || "";
            }
            elsif(!$refa) {
                $name = $args->[0];

                if ($refb eq 'CODE') {
                    $code = $args->[1];
                    $params = {};
                }
                elsif ($refb eq 'HASH') {
                    $params = $args->[1];
                    $code = delete $params->{code};
                }
            }
        }
        else {
            ($name, $params, $code) = @$args;
        }

        die "name given to '$comp' may not be a reference, got: $name at $file line $line.\n"
            if $name && ref $name;

        die "Invalid coderef given to '$comp', got: $code at $file line $line.\n"
            if $code && !(ref($code) && reftype($code) eq 'CODE');

        my $spec = comp($comp) || confess "No such component: '$comp'";
        die "'$comp' requires a name at $file line $line.\n"
            if $spec->{require_name} && !$name;

        die "'$comp' requires a coderef at $file line $line.\n"
            if $spec->{require_code} && !$code;

        my $block = Test::Workflow::Block->new_from_pairs(
            coderef => $code,
            name    => $name,
            caller  => [$pkg, $file, $line, $sub],
            params  => $params,
        );

        $STACKS{$pkg} ||= [
            Test::Workflow->new_from_pairs(
                name    => "$pkg (root)",
                defined => [$pkg, $file, 0, undef],
                root    => $pkg
            )
        ];

        return ($block, [$pkg, $file, $line, $sub], $name, $params);
    }

    sub generate_adder {
        my ($comp) = @_;
        my ($pkg, $file, $line) = caller();

        # Lexicalize these for use in the string eval.
        my $stacks = \%STACKS;
        my $parse  = \&_parse_params;

        # Use an eval to ensure the sub is named instead of __ANON__ in any traces.
        # Also spoof the line + file so that people know where they generated it.
        eval <<"    EOT" || die $@;
package $pkg;
#line $line "$file"
sub $comp { my (\$block, \$caller) = \$parse->('$comp', \\\@_); \$stacks->{\$caller->[0]}->[-1]->add(comp => '$comp', item => \$block) }
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

        my $comp = $params{comp} || confess "the 'comp' field is mandatory";
        my $item = $params{item} || confess "the 'item' field is mandatory";

        my $slot = comp($comp)->{'type'};

        $item->merge_params($self->params) if $item->can('merge_params');
        push @{$self->[COMPONENTS]->{$slot}} => [$comp, $item];
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

        my $all = { map { $_ => [ @{$inherit->{$_} || []}, @{$comps->{$_} || []} ] } qw/modifier multiplier/, types() };

        my $actions = {};
        my @action_order;
        for my $action (@{$comps->{action}}) {
            my ($comp, $it) = @$action;

            my $unit = Test::Workflow::Unit->new_from_pairs(
                stateful  => 1,
                comp      => $comp,
                core      => $it,
                scheduler => $scheduler,
                is_test   => $it->can('name') ? $it->name : $comp,
            );

            push @{$actions->{$comp}} => $unit;
            push @action_order => $unit;
        }

        my $multipliers = {};
        my @mul_order;
        for my $mul (@{$all->{multiplier}}) {
            my ($comp, $it) = @$mul;
            my $spec = comp($comp);

            my $unit = Test::Workflow::Unit->new_from_pairs(
                stateful  => 0,
                comp      => $comp,
                core      => $it,
                scheduler => $scheduler,
                affix     => $spec->{affix},
            );

            push @{$multipliers->{$comp}} => $unit;
            push @mul_order => $unit;
        }

        my $to_modify = { %$multipliers, %$actions };

        # Apply modifiers
        for my $mod (@{$all->{modifier}}) {
            my ($comp, $it) = @$mod;
            my $spec = comp($comp);

            my $alter = $spec->{alter};
            next unless $to_modify->{$alter};
            for my $unit (@{$to_modify->{$alter}}) {
                $unit->alter($it, $spec->{affix});
            }
        }

        warn "Multipliers are wrong, should be: outer x inner x deeper x test";
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

        for my $type (types()) {
            my $set = $all->{$type} || next;
            my $tspec = &type($type);
            for my $cus (@$set) {
                my ($comp, $it) = @$cus;
                @units = $tspec->{run}->($it, $comp, @units);
            }
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

