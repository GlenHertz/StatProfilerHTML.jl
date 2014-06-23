#!/usr/bin/env perl

use t::lib::Test;
use t::lib::Slowops;

use Devel::StatProfiler::Report;
use Time::HiRes qw(time);

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }

use Devel::StatProfiler -file => $profile_file, -interval => 1000;
my ($l1);

for (my $count = 10000; ; $count *= 2) {
    my $start = time;
    note("Trying with $count iterations");
    t::lib::Slowops::foo($count);
    -d '.' for 1..$count;   BEGIN { $l1 = __LINE__ + 0 }
    last if time - $start >= 0.5;
}

Devel::StatProfiler::stop_profile();

my $slowops_foo_line = 7;
my $r = Devel::StatProfiler::Report->new(
    slowops => [qw(ftdir unstack)],
);
my $a = $r->{aggregate};
$r->add_trace_file($profile_file);
$r->finalize;

# sanity checking
ok($a->{subs}{__FILE__ . ':CORE::ftdir'});
ok($a->{subs}{__FILE__ . ':CORE::unstack'});
ok($a->{subs}{'t/lib/Slowops.pm:CORE::ftdir'});
ok($a->{subs}{'t/lib/Slowops.pm:CORE::unstack'});
ok(!exists $a->{file_map}{CORE});

### start checking we have one ftdir instance per file

my ($ftdir_main) = grep $_->{name} eq 'CORE::ftdir',
                        @{$a->{files}{'t/301_report_slowops.t'}{subs}{-2}};
my ($ftdir_so)   = grep $_->{name} eq 'CORE::ftdir',
                        @{$a->{files}{'t/lib/Slowops.pm'}{subs}{-2}};

is($ftdir_main, $a->{subs}{__FILE__ . ':CORE::ftdir'});
is($ftdir_so,   $a->{subs}{'t/lib/Slowops.pm:CORE::ftdir'});
is($ftdir_main->{kind}, 2);
is($ftdir_so->{kind}, 2);
isnt($ftdir_main, $ftdir_so);

### end checking we have one ftdir instance per file
### start checking op-sub call sites

{
    my $cs = $ftdir_so->{call_sites}{"t/lib/Slowops.pm:$slowops_foo_line"};

    is($cs->{caller}, $a->{subs}{'t/lib/Slowops.pm:t::lib::Slowops::foo'});
    is($cs->{file}, 't/lib/Slowops.pm');
    is($cs->{line}, $slowops_foo_line);
    is($cs->{inclusive}, $cs->{exclusive});
}

### end  checking op-sub call sites
### start checking op-sub is in callees

my $slowops_pm = $a->{files}{'t/lib/Slowops.pm'};
{
    my @callees = sort { our ($a, $b); $a->{callee}{name} cmp $b->{callee}{name} }
                       @{$slowops_pm->{lines}{callees}{$slowops_foo_line}};

    is($callees[0]{callee}, $ftdir_so);
    is($callees[1]{callee}{name}, 'CORE::unstack');
}

### start checking op-sub is in callees

done_testing();
