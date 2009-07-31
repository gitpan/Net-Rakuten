# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl Net-Rakuten.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 6;
BEGIN { use_ok('Net::Rakuten') };

#########################

my $r = Net::Rakuten->new(
    developer_id => 'mock developer id',
    output_type  => 'perl',
);

for my $method ( qw( 
    search
    item_search
    genre_search
    item_code_search
    catalog_search
) ) {

    can_ok( $r, $method );
}

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

