#
# Dockerfile for liquid-feedback
#

FROM debian:buster

ENV LF_CORE_VERSION 4.2.2
ENV LF_FRONTEND_VERSION 4.0.0
ENV LF_WEBMCP_VERSION 2.2.1
ENV LF_MOONBRIDGE_VERSION 1.1.3
ENV LUA_VERSION 5.3

#
# install dependencies
#

RUN apt-get update && apt-get -y install \
        build-essential \
        exim4 \
        imagemagick \
        liblua${LUA_VERSION}-dev \
        libpq-dev \
        lua${LUA_VERSION} \
        liblua${LUA_VERSION}-0 \
        postgresql \
        postgresql-server-dev-11 \
        pmake \
        libbsd-dev \
        curl \
        discount

#
# prepare file tree
#


RUN mkdir -p /opt/lf/sources/patches \
             /opt/lf/sources/scripts \
             /opt/lf/bin

WORKDIR /opt/lf/sources

#
# Download sources
#

RUN curl https://www.public-software-group.org/pub/projects/liquid_feedback/backend/v${LF_CORE_VERSION}/liquid_feedback_core-v${LF_CORE_VERSION}.tar.gz | tar -xvzf - \
 && curl https://www.public-software-group.org/pub/projects/liquid_feedback/frontend/v${LF_FRONTEND_VERSION}/liquid_feedback_frontend-v${LF_FRONTEND_VERSION}.tar.gz | tar -xvzf - \
 && curl https://www.public-software-group.org/pub/projects/webmcp/v${LF_WEBMCP_VERSION}/webmcp-v${LF_WEBMCP_VERSION}.tar.gz | tar -xvzf - \
 && curl https://www.public-software-group.org/pub/projects/moonbridge/v${LF_MOONBRIDGE_VERSION}/moonbridge-v${LF_MOONBRIDGE_VERSION}.tar.gz | tar -xvzf -

#
# Build moonbridge
#

RUN cd /opt/lf/sources/moonbridge-v${LF_MOONBRIDGE_VERSION} \
    && pmake MOONBR_LUA_PATH=/opt/lf/moonbridge/?.lua \
    && mkdir /opt/lf/moonbridge \
    && cp moonbridge /opt/lf/moonbridge/ \
    && cp moonbridge_http.lua /opt/lf/moonbridge/

#
# build core
#

WORKDIR /opt/lf/sources/liquid_feedback_core-v${LF_CORE_VERSION}

RUN make \
    && cp lf_update lf_update_issue_order lf_update_suggestion_order /opt/lf/bin

#
# build WebMCP
#

WORKDIR /opt/lf/sources/webmcp-v${LF_WEBMCP_VERSION}

RUN make \
    && mkdir /opt/lf/webmcp \
    && cp -RL framework/* /opt/lf/webmcp

WORKDIR /opt/lf/

RUN cd /opt/lf/sources/liquid_feedback_frontend-v${LF_FRONTEND_VERSION} \
    && cp -R . /opt/lf/frontend \
    && cd /opt/lf/frontend/fastpath \
    && make \
    && chown www-data /opt/lf/frontend/tmp

#
# setup db
#

COPY ./scripts/setup_db.sql /opt/lf/sources/scripts/
COPY ./scripts/config_db.sql /opt/lf/sources/scripts/

RUN addgroup --system lf \
    && adduser --system --ingroup lf --no-create-home --disabled-password lf \
    && service postgresql start \
    && (su -l postgres -c "psql -f /opt/lf/sources/scripts/setup_db.sql") \
    && (su -l postgres -c "PGPASSWORD=liquid psql -U liquid_feedback -h 127.0.0.1 -f /opt/lf/sources/liquid_feedback_core-v${LF_CORE_VERSION}/core.sql liquid_feedback") \
    && (su -l postgres -c "PGPASSWORD=liquid psql -U liquid_feedback -h 127.0.0.1 -f /opt/lf/sources/scripts/config_db.sql liquid_feedback") \
    && service postgresql stop

#
# cleanup
#

RUN rm -rf /opt/lf/sources \
    && apt-get -y purge \
        build-essential \
        liblua${LUA_VERSION}-dev \
        libpq-dev \
        postgresql-server-dev-11 \
    && apt-get -y autoremove \
    && apt-get clean

#
# configure everything
#

# TODO: configure mail system

# app config
COPY ./scripts/lfconfig.lua /opt/lf/frontend/config/

# update script
COPY ./scripts/lf_updated /opt/lf/bin/

# startup script
COPY ./scripts/start.sh /opt/lf/bin/

#
# ready to go
#

EXPOSE 8080

WORKDIR /opt/lf/frontend

ENTRYPOINT ["/opt/lf/bin/start.sh"]
