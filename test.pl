use common::sense;
use Data::Dumper;
use Encode ();
use Mojo::Util qw(monkey_patch);
use Mojolicious::Lite;
use Test::Deep;
use Test::Mojo;
use Test::More;
use Test::Pretty;

my $app = app();

$app->plugin('xslate_renderer');
$app->secrets([qw( hogefuga )]);

#
# Override default exception behavior
#
$app->renderer->add_helper(
    'reply.exception' => sub {
        my ($c, $e) = @_;    # $e isa Mojo::Exception
        $c->render(
            json => {
                status  => 500,
                message => $e->message,
            },
            status => 500,
        );
    }
);

my $r = $app->routes;

$r->get('/')->to(
    cb => sub {
        my $c = shift;
        $c->render(json => { path => '/' });
    }
);

$r->get('/something')->to(
    cb => sub {
        my $c = shift;
        $c->stash->{message} = '<script>';
        $c->render('something');
    }
);

my $item_r = $r->under('/item/:item_id')->to(
    cb => sub {
        my $c       = shift;
        my $item_id = $c->stash->{item_id};

        warn "Is item ID > 0 ?: ${item_id}";

        $c->reply->not_found and return
            if not $item_id;

        1;
    }
);

#
# "bridge" is deprecated.  Just use "under"
#
my $even_item_r = $item_r->under->to(
    cb => sub {
        my $c       = shift;
        my $item_id = $c->stash->{item_id};

        warn "Is item ID even?: ${item_id}";

        die "item_id must be even!" if $item_id % 2;

        1;
    }
);

$even_item_r->get('/')->to(
    cb => sub {
        my $c       = shift;
        my $item_id = $c->stash->{item_id};

        $c->render(
            json => {
                path    => '/item/:item_id',
                item_id => $item_id,
            }
        );
    }
);

#
# Multiple "under"
#
$r->under('/under_path')->to(
    cb => sub {
        warn '1st "under" callback';
        1;
    }
    )->under->to(
    cb => sub {
        warn '2nd "under" callback';
        1;
    }
    )->under->to(
    cb => sub {
        warn '3rd "under" callback';
        1;
    }
    )->get('/')->to(
    cb => sub {
        my $c = shift;
        $c->render(json => { message => 'Dispatched after 3 nested "under" callbacks' });
    }
    );

my $t = Test::Mojo->new;

#
# Patching Test::Mojo stays the same
#
monkey_patch 'Test::Mojo', json_cmp_deeply => sub {
    my $t = shift;
    my ($p, $data) = @_ > 1 ? (shift, shift) : ('', shift);
    my $desc = Encode::encode('UTF-8', qq{cmp_deeply OK for JSON Pointer "$p"});
    return $t->success(Test::Deep->can('cmp_deeply')->($t->tx->res->json($p), $data, $desc));
};

subtest 'GET /' => sub {
    $t->get_ok('/')->status_is(200)->json_is({ path => '/', });
};

subtest 'GET /something' => sub {
    $t->get_ok('/something')->status_is(200)->content_like(qr|script|);
};

subtest 'GET /item/:item_id' => sub {

    subtest '404 if item_id => 0' => sub {
        $t->get_ok('/item/0')->status_is(404);
    };

    subtest '500 if item_id => 1' => sub {
        $t->get_ok('/item/1')->status_is(500)->json_cmp_deeply(
            {   status  => 500,
                message => re('^item_id must be even!'),
            }
        );
    };

    subtest '200 if item_id => 2' => sub {
        $t->get_ok('/item/2')->status_is(200)->json_is(
            {   path    => '/item/:item_id',
                item_id => '2',
            }
        );
    };
};

subtest 'GET /under_path' => sub {
    $t->get_ok('/under_path')->status_is(200)->json_is({ message => 'Dispatched after 3 nested "under" callbacks' });
};

done_testing;
