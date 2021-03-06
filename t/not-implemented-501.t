use Mojo::Base -strict;
use Test::Mojo;
use Test::More;
use File::Spec::Functions;
use Mojolicious::Lite;
use t::Api;

plugin Swagger2 => {url => 't/data/not-implemented.json'};

my $t = Test::Mojo->new;

ok $t->app->routes->lookup('not_implemented'), 'add route not_implemented';
$t->get_ok('/not-implemented')->status_is(501)->json_is('/valid', 0)
  ->json_is('/errors/0/message', 'Controller not implemented.')->json_is('/errors/0/path', '/');

eval 'package t::NotImplemented; use Mojo::Base "Mojolicious::Controller"; $INC{"t/NotImplemented.pm"}=1;';
$t->get_ok('/not-implemented')->status_is(501)->json_is('/errors/0/message', 'Method not implemented.');

*t::NotImplemented::not_implemented = sub { my ($c, $args, $cb) = @_; $c->$cb({}); };
$t->get_ok('/not-implemented')->status_is(200)->content_is('{}');

done_testing;
