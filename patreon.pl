#!/usr/bin/env perl

use Mojolicious::Lite;
use Mojo::File qw(curfile);
use Mojo::JSON qw(encode_json);

my %DISCORD_USERS = ();

my $config = plugin Config => {file => "patreon.conf"};

app->secrets($config->{cookie_secrets});
app->mode($config->{runtime_mode});
push @{app->renderer->paths}, curfile->sibling("templates");

# index
get '/' => sub {
  my $c = shift;

  # existing token cookie
  if ($c->session->{access_token}) {
    return $c->redirect_to('/campaigns');
  }

  $c->render(template => 'index', auth_url => patreon_auth_url());
};

# oauth callback
get '/auth' => sub {
  my $c = shift;

  $c->render_later;

  if (my $code = $c->param('code')) {
    # verify auth code
    my $url = patreon_verify_url($code);
    $c->ua->post( patreon_verify_url($code),
      {"Content-Type" => "application/x-www-form-urlencoded"},
      sub {
        my ($ua, $tx) = @_;
        $c->log->debug("got token response");

        if ($tx->result->is_success) {
          $c->session->{access_token} = $tx->result->json->{access_token};
          $c->session(expiration => $tx->result->json->{expires_in});

          $c->log->debug("Logged in with " . $c->session->{access_token});

          return $c->redirect_to('/campaigns');
        }
        else {
          $c->log->debug($tx->result->body);
          $c->session(expires => 1); # clear session
          return $c->reply->exception($tx->result->body);
        }
      });
  }
  else {
    return $c->reply->exception("Missing oauth verify code");
  }
};

# user's campaigns
get '/campaigns' => sub {
  my $c = shift;

  my $token = $c->session->{access_token} || do {
    $c->log->debug("session expired");
    $c->session(expires => 1); # clear session
    return $c->redirect_to('/');
  };

  $c->render_later;

  $c->ua->get(
    "https://www.patreon.com/api/oauth2/v2/campaigns?fields[campaign]=created_at,creation_name,patron_count",
    {"Authorization" => "Bearer $token"},
    sub {
      my ($ua, $tx) = @_;
      $c->log->debug("got campaigns response");

      if ($tx->result->is_success) {
        _debug_dump("/campaigns", $tx->result->json);
        my $campaigns = [];
        for my $campaign ( @{$tx->result->json->{data}} ) {
          if ($campaign->{type} eq 'campaign') {
            push @{$campaigns}, {
              id           => $campaign->{id},
              name         => $campaign->{attributes}->{creation_name},
              patron_count => $campaign->{attributes}->{patron_count},
            };
          }
        }
        return $c->render(template => 'campaigns', campaigns => $campaigns);
      }
      else {
        $c->log->debug($tx->result->body);
        $c->session(expires => 1); # clear session
        _debug_dump("/campaigns error", $tx->result->body);
        return $c->reply->exception($tx->result->body);
      }
    });
};

# campaign patron list
get '/patrons', sub {
  my $c = shift;

  my $token = $c->session->{access_token} || do {
    $c->log->debug("session expired");
    $c->session(expires => 1); # clear session
    return $c->redirect_to('/');
  };

  my $id = $c->param('id') || do {
    return $c->reply->exception("Missing id param");
  };

  $c->render_later;

  # get Discord member list & Patreon patron list in parallel
  my $discord = $c->ua->get_p(
    "https://discord.com/api/v6/guilds/" . $config->{discord}->{guild_id} . "/members?limit=1000",
    {"Authorization" => "Bot " . $config->{discord}->{token}},
  );

  my $patreon = $c->ua->get_p(
      "https://www.patreon.com/api/oauth2/v2/campaigns/${id}/members?include=currently_entitled_tiers,user"
    . "&fields[member]=full_name,currently_entitled_amount_cents,patron_status"
    . "&fields[tier]=title,amount_cents,patron_count"
    . "&fields[user]=social_connections",
    {"Authorization" => "Bearer $token"},
  );

  Mojo::Promise->all($patreon, $discord)->then(sub {
    my ($patreon_tx, $discord_tx) = @_;

    # process/cache discord users
    if ($discord_tx->[0]->res->is_success) {
      $c->log->debug("got Discord members response");
      _debug_dump("discord /members", $discord_tx->[0]->result->body);
      _process_discord($discord_tx->[0]->result->json);
    }
    else {
      _debug_dump("discord members error", $discord_tx->[0]->result->body);
      return $c->reply->exception($discord_tx->[0]->result->body);
    }

    # process patrons
    my $tier_list;
    if ($patreon_tx->[0]->res->is_success) {
      $c->log->debug("got Patreon members response");
      _debug_dump("patreon /campaigns/${id}/members", $patreon_tx->[0]->result->json);
      $tier_list = _process_patrons($patreon_tx->[0]->result->json);
    }
    else {
      $c->session(expires => 1); # clear session
      _debug_dump("patreon members error", $patreon_tx->[0]->result->body);
      return $c->reply->exception($patreon_tx->[0]->result->body);
    }

    return $c->render(template => 'patrons', tiers => $tier_list);
  })->catch(sub {
    my $err = shift;
    _debug_dump("promise catch", $err);
     return $c->reply->exception($err);
  })->wait;
};

app->start;

sub _process_patrons {
  my $data = shift;

  my @tiers   = sort { $b->{attributes}->{amount_cents} <=> $a->{attributes}->{amount_cents} }
                grep { $_->{type} eq 'tier' }   @{$data->{included}};
  my @users   = grep { $_->{type} eq 'user' }   @{$data->{included}};
  my @members = grep { $_->{type} eq 'member' } @{$data->{data}};

  my $tier_list = [];
  for my $tier (@tiers) {
    my $tier_amount_cents = $tier->{attributes}->{amount_cents}; # used to match patrons in this tier

    my $entry = {
      amount       => sprintf("%.2f", $tier->{attributes}->{amount_cents} / 100),
      patron_conut => $tier->{attributes}->{patron_count},
      title        => $tier->{attributes}->{title},
    };

    my @patrons = ();
    for my $member (@members) {
      next unless $member->{attributes}->{patron_status} eq 'active_patron';
      next unless $member->{attributes}->{currently_entitled_amount_cents} == $tier_amount_cents;

      # lookup discord name
      my $member_id  = $member->{relationships}->{user}->{data}->{id};
      my ($user)     = grep { $_->{id} == $member_id } @users;

      $user->{attributes}->{social_connections}->{discord} ||= {};
      my $discord_id = $user->{attributes}->{social_connections}->{discord}->{user_id};

      if ($discord_id) {
        push @patrons, $DISCORD_USERS{$discord_id} || $member->{attributes}->{full_name} . " ($discord_id not in Discord server)";
      }
      else {
        push @patrons, $member->{attributes}->{full_name} . " (no Discord link)";
      }
    }

    $entry->{patrons} = [ sort @patrons ];
    push @{$tier_list}, $entry;
  }

  return $tier_list;
}

sub _process_discord {
  my $data = shift;

  for my $user (@{$data}) {
    $DISCORD_USERS{ $user->{user}->{id} } = $user->{nick} || $user->{user}->{username};
  }
}

sub patreon_auth_url {
    "https://www.patreon.com/oauth2/authorize"
  . "?response_type=code"
  . "&client_id="    . $config->{patreon}->{client_id}
  . "&redirect_url=" . $config->{patreon}->{redirect_uri};
}

sub patreon_verify_url {
  my $code = shift;

    "https://www.patreon.com/api/oauth2/token"
  . "?code=${code}"
  . "&grant_type=authorization_code"
  . "&client_id="     . $config->{patreon}->{client_id}
  . "&client_secret=" . $config->{patreon}->{client_secret}
  . "&redirect_uri="  . $config->{patreon}->{redirect_uri};
}

sub _debug_dump {
  my ($url, $data) = @_;

  my $file = $config->{debug_dump_file} || return;

  open my $fh, '>>', $file || die "Cannot open $file for writing: $!";
  print $fh "$url\n-----------\n";
  print $fh ref $data ? encode_json($data) : $data;
  print $fh "\n\n";
  close $fh;
}
