package Net::Rakuten;

our $VERSION = '0.01';

use 5.008008;
use strict;
use warnings;
{
    use Carp;
    use LWP::UserAgent;
    use JSON qw( from_json );
    use Unicode::Japanese;
}

my (
    $API_URL,
    $API_VERSION,
    $USER_AGENT_ALIAS,
    $OUTPUT_TYPE_REGEX,
    $DEFAULT_OUTPUT_TYPE,
    %RESPONSE_TYPE_FOR,
);
{
    use Readonly;

    Readonly $API_URL             => "http://api.rakuten.co.jp/rws";
    Readonly $API_VERSION         => '2.0';
    Readonly $USER_AGENT_ALIAS    => __PACKAGE__ . "/$VERSION";
    Readonly $OUTPUT_TYPE_REGEX   => qr{\A (?: xml|perl|json ) \z}xms;
    Readonly $DEFAULT_OUTPUT_TYPE => 'perl';

    Readonly %RESPONSE_TYPE_FOR => (
        json => 'json',
        perl => 'json',
        xml  => 'rest',
    );
}

sub new {
    my $class = shift @_;

    my %params;

    if ( @_ == 1 && ref $_[0] eq 'HASH' ) {

        %params = %{ $_[0] };
    }
    elsif ( @_ % 2 == 0 ) {

        %params = @_;
    }

    croak "couldn't make sense of the parameters\n"
        if !keys %params;

    croak "developer_id is required\n"
        if !defined $params{developer_id} || !$params{developer_id};

    $params{output_type} ||= $DEFAULT_OUTPUT_TYPE;

    if ( $params{output_type} !~ $OUTPUT_TYPE_REGEX ) {

        carp "unrecognized output type requested ",
            "defaulting to $DEFAULT_OUTPUT_TYPE\n";

        $params{output_type} = $DEFAULT_OUTPUT_TYPE;
    }

    my $self = bless {
        output_type  => delete $params{output_type},
        developer_id => delete $params{developer_id},
        ua           => LWP::UserAgent->new(),
    }, $class;

    $self->{ua}->default_header( 'User-Agent', $USER_AGENT_ALIAS );

    for my $unexpected (keys %params) {
        carp "unrecognized parameter: $unexpected\n";
    }

    return $self;
}

sub search {
    my ($self,$keyword,$page) = @_;
    return $self->item_search($keyword,$page);
}

sub item_search {
    my ($self,$keyword,$page) = @_;

    $page ||= 1;

    return
        if !$keyword;

    my $url = $self->_build_url(
        'keyword'   => $keyword,
        'page'      => $page,
        'operation' => 'ItemSearch',
        'version'   => '2009-04-15',
        'sort'      => '+itemPrice',
    );

    return $self->_get_results( $url );
}

sub genre_search {
    my ($self,$genre_id) = @_;

    $genre_id ||= 0;

    my $url = $self->_build_url(
        operation => 'GenreSearch',
        version   => '2007-04-11',
        genreId   => $genre_id,
    );

    return $self->_get_results( $url );
}

sub item_code_search {
    my ($self,$item_code) = @_;

    return
        if !$item_code;

    my $url = $self->_build_url(
        operation => 'ItemCodeSearch',
        version   => '2007-04-11',
        itemCode  => $item_code,
    );

    return $self->_get_results( $url );
}

sub catalog_search {
    my ($self,$keyword) = @_;

    return
        if !$keyword;

    my $url = $self->_build_url(
        'operation' => 'CatalogSearch',
        'version'   => '2009-04-15',
        'keyword'   => $keyword,
        'sort'      => '-reviewCount',
    );

    return $self->_get_results( $url );
}

## Internal Support ##

sub _get_results {
    my ($self,$url) = @_;

    my $results;
    {
        my $request = HTTP::Request->new(GET => $url);
        my $response = $self->{ua}->request($request);
        $results = $response->is_success ? $response->content : undef;
    }

    utf8::decode( $results );

    return $results
        if $self->{output_type} =~ m/(?: xml|json )/xms;

    return from_json( $results );
}

sub _build_url {
    my $self = shift @_;
    die "unbalanced args" if @_ % 2;
    my %params = @_;

    my $type = $RESPONSE_TYPE_FOR{ $self->{output_type} };
    my $did  = $self->{developer_id};
    my $aid  = $self->{affiliate_id};

    my $url = "$API_URL/$API_VERSION/$type?developerId=$did";

    while ( my ($name,$value) = each %params ) {
        $url .= "&$name=" . _url_encode( $value, 'utf8', 'utf8' );
    }

    return $url;
}

# Content text from Rakuten is woefully littered with CSS & HTML markup
sub _tidy_up_text {
    my ($text) = @_;

    # html strip
    $text =~ s{<[^>]*>}{ }msxg;

    # css strip (fingers crossed)
    $text =~ s{[\w\{:;,.\-\#/* ()"']+[\}]}{ }msxg;

    # remove ridiculously huge dotted lines
    $text =~ s{[・][・]+[・]}{ ・・・ }msxg;

    # no adjacent whitespace chars
    $text =~ s{ \s{2,} }{ }msxg;

    # HTML entitize key chars
    $text =~ s{ ( ['"()\[\]] ) }{ '&#' . ord( $1 ) . ';' }msxeg;

    return $text;
}

sub _url_encode {
    my ( $value, $from_encoding, $to_encoding ) = @_;

    # Defaults to utf8 -> euc if encoding is not specified
    $from_encoding ||= 'utf8';
    $to_encoding   ||= 'euc';

    # the easy cases: value is empty or is a number
    return $value
        if !$value || $value =~ m/\A \d+ \z/msx;

    my $encoded_value = $value;

    eval {
        $encoded_value = Unicode::Japanese->new( $value, $from_encoding )->$to_encoding();
    };
    if ( $@ ) {
        warn "$@\n";
        return $value;
    }

    $encoded_value =~ s/([^\w\/ ])/"%" . uc( unpack("H2", $1) )/eg;
    $encoded_value =~ s/ /%20/g;
    $encoded_value =~ s/[+]/%2B/g;

    return $encoded_value;
}

sub _url_unencode {
    my ( $value ) = @_;

    # the easy cases: value is empty or has no %
    return $value
        if !$value || $value !~ m/ [%] /msx;

    my $unencoded_value = $value;

    $unencoded_value =~ s/%([A-F0-9]{2})/pack("H2", $1)/eg;

    return $unencoded_value;
}

1;

__END__

=head1 NAME

Net::Rakuten - Object interface to Rakuten webservice

=head1 SYNOPSIS

  use Net::Rakuten;

  my $r = Dox::Net::Rakuten->new(
      output_type  => 'perl',
      developer_id => '0123456789abcdef',
  );

  my $keyword = 'Hello Kitty';
  my $page    = 1;

  my $result_rh = $r->search($keyword,$page);

=head1 DESCRIPTION

This fills an empty niche for interfacing with the Rakuten
webservice detailed here.

  http://webservice.rakuten.co.jp/

=head1 METHODS

=over

=item search

an alias for the item_search method

=item item_search

http://webservice.rakuten.co.jp/api/itemsearch/

=item genre_search

http://webservice.rakuten.co.jp/api/genresearch/

=item item_code_search

http://webservice.rakuten.co.jp/api/itemcodesearch/

=item catalog_search

http://webservice.rakuten.co.jp/api/catalogsearch/

=back

Numerous methods not yet implemented

=head1 AUTHOR

Dylan Doxey, E<lt>dylan.doxey@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2009 by Dylan Doxey

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
