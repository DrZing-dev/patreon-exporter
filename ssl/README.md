To enable SSL support, do the following:

1. Obtain a cert/key pair from LetsEncrypt by following the instructions at https://certbot.eff.org/instructions
2. Put the fullchain.pem and privkey.pem files in this directory.
3. Ensure ENABLE_SSL=1 is set in the Dockerfile.
4. ./docker.sh
5. Route traffic to port 8443 instead of 8080.

Note that an HTTP still listens on 8080, remove this from patreon.conf if you only want SSL.
