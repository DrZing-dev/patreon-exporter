FROM perl:5.26

WORKDIR /mojo

ADD . .

ENV PERL_CARTON_PATH=/mojo/local
ENV PERL5LIB=${PERL_CARTON_PATH}/lib/perl5
ENV PATH=${PERL_CARTON_PATH}/bin:${PERL_HOME}/bin:${PATH}

RUN cpanm --notest --no-man-page Carton

RUN carton install --cpanfile /mojo/cpanfile

ENV LIBEV_FLAGS=7

# SSL mode requires cert/key to be in ssl/fullchain.pem and ssl/privkey.key
# See https://certbot.eff.org/instructions for instructions
ENV ENABLE_SSL=1

EXPOSE 8080 8443

CMD hypnotoad -f /mojo/patreon.pl
