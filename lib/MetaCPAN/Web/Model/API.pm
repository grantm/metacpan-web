package MetaCPAN::Web::Model::API;

use Moose;
extends 'Catalyst::Model';

has [qw(api api_secure)] => ( is => 'ro' );

use Encode ();
use JSON;
use AnyEvent::HTTP qw(http_request);
use Try::Tiny 0.09;
use namespace::autoclean;

{
    no warnings 'once';
    $AnyEvent::HTTP::PERSISTENT_TIMEOUT = 0;
    $AnyEvent::HTTP::USERAGENT
        = 'Mozilla/5.0 (compatible; U; MetaCPAN-Web/1.0; '
        . '+https://github.com/CPAN-API/metacpan-web)';
}

sub cv {
    AE::cv;
}

=head2 COMPONENT

Set C<api> and C<api_secure> config parameters from the app config object.

=cut

sub COMPONENT {
    my $self = shift;
    my ( $app, $config ) = @_;
    $config = $self->merge_config_hashes(
        {   api        => $app->config->{api},
            api_secure => $app->config->{api_secure} || $app->config->{api}
        },
        $config
    );
    return $self->SUPER::COMPONENT( $app, $config );
}

sub model {
    my ( $self, $model ) = @_;
    return MetaCPAN::Web->model('API') unless $model;
    return MetaCPAN::Web->model("API::$model");
}

sub request {
    my ( $self, $path, $search, $params ) = @_;
    my ( $token, $method ) = @$params{qw(token method)};
    $path .= "?access_token=$token" if ($token);
    my $req = $self->cv;
    http_request $method ? $method
        : $search        ? 'post'
        : 'get' => ( $token ? $self->api_secure : $self->api ) . $path,
        body => $search ? encode_json($search) : undef,
        headers    => { 'Content-type' => 'application/json' },
        persistent => 1,
        sub {
        my ( $data, $headers ) = @_;
        my $content_type = $headers->{'content-type'} || '';

        if ( $content_type =~ /^application\/json/ ) {
            my $json = eval { decode_json($data) };
            $req->send( $@ ? $self->raw_api_response($data) : $json );
        }
        else {

            # Response is raw data, e.g. text/plain
            $req->send( $self->raw_api_response($data) );
        }
        };
    return $req;
}

my $encoding = Encode::find_encoding('utf-8-strict')
  or warn 'UTF-8 Encoding object not found';
my $encode_check = ( Encode::FB_CROAK | Encode::LEAVE_SRC );

sub raw_api_response {
    my ($self, $data) = @_;

    # will http_response ever return undef or a blessed object?
    $data  = '' if ! defined $data; # define
    $data .= '' if       ref $data; # stringify

    # we have to assume an encoding; doing nothing is like assuming latin1
    # we'll probably have the least number of issues if we assume utf8
    try {
      # decode so the template doesn't double-encode and return mojibake
      $data &&= $encoding->decode( $data, $encode_check );
    }
    catch {
      warn $_[0];
    };

    return +{ raw => $data };
}

1;
