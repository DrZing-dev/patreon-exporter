# Patreon + Discord patron exporter

This is a simple Mojolicious::Lite web app for exporting a list of patrons by tier. It is designed for use with patrons who have linked
their Discord accounts and Discord usernames will be exported by default, with a fallback to full name.

Only active patrons are displayed

## Config

Copy patreon.conf.example to patreon.conf and edit as needed.

patreon.conf holds config specific for the Patreon and Discord APIs. A Discord bot account must be used, do not use a user account or you may be banned from Discord. Discord guild_id is the ID of your server. To get the ID, enable Settings -> Appearance -> Developer Mode, right-click your server name and select Copy ID.

The Patreon redirect_uri must match the value registered at https://www.patreon.com/portal/registration/register-clients

Protect your secret and token values!

## Development

1. Use a recent version of Perl. This was built with 5.26.1 on macOS but should work with anything >= 5.10.1. Try Strawberry Perl for Windows support (untested).
2. Install Mojolicious from CPAN with `cpan Mojolicious`. This is the only dependency.
3. `perl patreon.pl daemon` will start a web server on localhost:3000. You will need to adjust the Patreon redirect_uri config to match.

## Running in Docker

`docker.sh` will build and run a Docker image, with the server exposed on port 8080.

## Limitations

* The Discord members API call is limited to 1000 users. If your server is larger than this, the code will need refactored to paginate this call.

## Future Ideas

* Webhook support to email yourself an auto-updated list.
