package Web::Response;
BEGIN {
  $Web::Response::AUTHORITY = 'cpan:DOY';
}
{
  $Web::Response::VERSION = '0.03';
}
use Moose;
# ABSTRACT: common response class for web frameworks

use HTTP::Headers ();
use Plack::Util ();
use URI::Escape ();

use Web::Request::Types ();


has status => (
    is      => 'rw',
    isa     => 'Web::Request::Types::HTTPStatus',
    lazy    => 1,
    default => sub { confess "Status was not supplied" },
);

has headers => (
    is      => 'rw',
    isa     => 'Web::Request::Types::HTTP::Headers',
    lazy    => 1,
    coerce  => 1,
    default => sub { HTTP::Headers->new },
    handles => {
        header           => 'header',
        content_length   => 'content_length',
        content_type     => 'content_type',
        content_encoding => 'content_encoding',
        location         => [ header => 'Location' ],
    },
);

has content => (
    is      => 'rw',
    isa     => 'Web::Request::Types::PSGIBody',
    lazy    => 1,
    coerce  => 1,
    default => sub { [] },
);

has cookies => (
    is      => 'rw',
    isa     => 'HashRef[Str|HashRef[Str]]',
    lazy    => 1,
    default => sub { +{} },
);

has _encoding_obj => (
    is        => 'rw',
    isa       => 'Object',
    predicate => 'has_encoding',
    handles   => {
        encoding => 'name',
    },
);

sub BUILDARGS {
    my $class = shift;

    if (@_ == 1 && ref($_[0]) eq 'ARRAY') {
        return {
            status => $_[0][0],
            (@{ $_[0] } > 1
                ? (headers => $_[0][1])
                : ()),
            (@{ $_[0] } > 2
                ? (content => $_[0][2])
                : ()),
        };
    }
    else {
        return $class->SUPER::BUILDARGS(@_);
    }
}

sub redirect {
    my $self = shift;
    my ($url, $status) = @_;

    $self->status($status || 302);
    $self->location($url);
}

sub finalize {
    my $self = shift;

    $self->_finalize_cookies;

    my $res = [
        $self->status,
        [
            map {
                my $k = $_;
                map {
                    my $v = $_;
                    # replace LWS with a single SP
                    $v =~ s/\015\012[\040|\011]+/chr(32)/ge;
                    # remove CR and LF since the char is invalid here
                    $v =~ s/\015|\012//g;
                    ( $k => $v )
                } $self->header($k);
            } $self->headers->header_field_names
        ],
        $self->content
    ];

    return $res unless $self->has_encoding;

    return Plack::Util::response_cb($res, sub {
        return sub {
            my $chunk = shift;
            return unless defined $chunk;
            return $self->_encode($chunk);
        };
    });
}

sub _encode {
    my $self = shift;
    my ($content) = @_;
    return $content unless $self->has_encoding;
    return $self->_encoding_obj->encode($content);
}

sub _finalize_cookies {
    my $self = shift;

    my $cookies = $self->cookies;
    for my $name (keys %$cookies) {
        $self->headers->push_header(
            'Set-Cookie' => $self->_bake_cookie($name, $cookies->{$name}),
        );
    }

    $self->cookies({});
}

sub _bake_cookie {
    my $self = shift;
    my ($name, $val) = @_;

    return '' unless defined $val;
    $val = { value => $val }
        unless ref($val) eq 'HASH';

    my @cookie = (
        URI::Escape::uri_escape($name)
      . '='
      . URI::Escape::uri_escape($val->{value})
    );

    push @cookie, 'domain='  . $val->{domain}
        if defined($val->{domain});
    push @cookie, 'path='    . $val->{path}
        if defined($val->{path});
    push @cookie, 'expires=' . $self->_date($val->{expires})
        if defined($val->{expires});
    push @cookie, 'max-age=' . $val->{'max-age'}
        if defined($val->{'max-age'});
    push @cookie, 'secure'
        if $val->{secure};
    push @cookie, 'HttpOnly'
        if $val->{httponly};

    return join '; ', @cookie;
}

# XXX DateTime?
my @MON  = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
my @WDAY = qw( Sun Mon Tue Wed Thu Fri Sat );

sub _date {
    my $self = shift;
    my ($expires) = @_;

    return $expires unless $expires =~ /^\d+$/;

    my ($sec, $min, $hour, $mday, $mon, $year, $wday) = gmtime($expires);
    $year += 1900;

    return sprintf("%s, %02d-%s-%04d %02d:%02d:%02d GMT",
                   $WDAY[$wday], $mday, $MON[$mon], $year, $hour, $min, $sec);
}

__PACKAGE__->meta->make_immutable;
no Moose;



1;

__END__
=pod

=head1 NAME

Web::Response - common response class for web frameworks

=head1 VERSION

version 0.03

=head1 SYNOPSIS

  use Web::Request;

  my $app = sub {
      my ($env) = @_;
      my $req = Web::Request->new_from_env($env);
      # ...
      return $req->new_response(status => 404)->finalize;
  };

=head1 DESCRIPTION

Web::Response is a response class for L<PSGI> applications. Generally, you will
want to create instances of this class via C<new_response> on the request
object, since that allows a framework which subclasses L<Web::Request> to also
return an appropriate subclass of Web::Response.

All attributes on Web::Response objects are writable, and the final state of
them will be used to generate a real L<PSGI> response when C<finalize> is
called.

=head1 METHODS

=head2 status($status)

Sets (and returns) the status attribute, as described above.

=head2 headers($headers)

Sets (and returns) the headers attribute, as described above.

=head2 header($name, $val)

Shortcut for C<< $ret->headers->header($name, $val) >>.

=head2 content_length($length)

Shortcut for C<< $ret->headers->content_length($length) >>.

=head2 content_type($type)

Shortcut for C<< $ret->headers->content_type($type) >>.

=head2 content_encoding($encoding)

Shortcut for C<< $ret->headers->content_encoding($encoding) >>.

=head2 location($location)

Shortcut for C<< $ret->headers->header('Location', $location) >>.

=head2 content($content)

Sets (and returns) the C<content> attribute, as described above.

=head2 cookies($cookies)

Sets (and returns) the C<cookies> attribute, as described above.

=head2 redirect($location, $status)

Sets the C<Location> header to $location, and sets the status code to $status
(defaulting to 302 if not given).

=head2 finalize

Returns a valid L<PSGI> response, based on the values given.

=head1 CONSTRUCTOR

=head2 new(%params)

Returns a new Web::Response object. Valid parameters are:

=over 4

=item status

The HTTP status code for the response.

=item headers

The headers to return with the response. Can be provided as an arrayref, a
hashref, or an L<HTTP::Headers> object. Defaults to an L<HTTP::Headers> object
with no contents.

=item content

The content of the request. Can be provided as a string, an object which
overloads C<"">, an arrayref containing a list of either of those, a
filehandle, or an object that implements the C<getline> and C<close> methods.
Defaults to C<[]>.

=item cookies

A hashref of cookies to return with the response. The values in the hashref can
either be the string values of the cookies, or a hashref whose keys can be any
of C<value>, C<domain>, C<path>, C<expires>, C<max-age>, C<secure>,
C<httponly>. In addition to the date format that C<expires> normally uses,
C<expires> can also be provided as a UNIX timestamp (an epoch time, as returned
from C<time>). Defaults to C<{}>.

=back

=head1 AUTHOR

Jesse Luehrs <doy at cpan dot org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by Jesse Luehrs.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

