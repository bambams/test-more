use strict;
use warnings;
use Test::More;

use Test::Suite;

describe foo => {todo => "I am a teapot"}, sub {
    ok(0, "In Describe");

    case yyy => sub { ok(0, "In case") };
    case zzz => sub { ok(0, "In case") };

    #before_each xxx => sub { ok(0, "In before_each") };

    tests bar => sub {
        ok(0, "in tests");
    };
};

done_testing;
