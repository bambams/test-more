package Test::Suite;
use strict;
use warnings;

use Test::Workflow qw{
    define_components
    generate_adder
    auto_run
    build_workflow
};

use Test::Stream::Exporter;

define_components(
    case => {type => 'multiplier', affix => -1, require_name => 1, require_code => 1},

    before_all => {type => 'init', affix => -1, require_code => 1},
    around_all => {type => 'init', affix => 0 , require_code => 1},
    after_all  => {type => 'init', affix => 1 , require_code => 1},

    before_each => {type => 'modifier', affix => -1, require_code => 1, alter => 'tests'},
    around_each => {type => 'modifier', affix => 0,  require_code => 1, alter => 'tests'},
    after_each  => {type => 'modifier', affix => 1,  require_code => 1, alter => 'tests'},

    before_case => {type => 'modifier', affix => -1, require_code => 1, alter => 'case'},
    around_case => {type => 'modifier', affix => 0,  require_code => 1, alter => 'case'},
    after_case  => {type => 'modifier', affix => 1,  require_code => 1, alter => 'case'},
);

for my $prefix (qw/before after around/) {
    for my $component (qw/case each all/) {
        generate_adder("${prefix}_${component}");
    }
}

generate_adder('case');
generate_adder('tests');

{
    no warnings 'once';
    *it       = \&tests;
    *workflow = \&build_workflow;
    *cases    = \&build_workflow;
    *describe = \&build_workflow;
}

default_exports qw{
    before_each after_each around_each
    before_all  after_all  around_all
    before_case after_case around_case

    case

    workflow cases describe

    tests it
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

    auto_run($caller, \%run_params);
}

1;
