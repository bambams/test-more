use strict;
use warnings;
use Test::More 'no_plan';

use Test::Suite;

describe foo => sub {
    ok(1, "In Describe");

    case yyy => {todo => 'blah'}, sub { ok(0, "In case") };
    case zzz => sub { ok(1, "In case") };

    #before_each xxx => sub { ok(0, "In before_each") };

    tests bar => sub {
        ok(1, "in tests");
    };
};
