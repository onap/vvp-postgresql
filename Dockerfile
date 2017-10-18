# ============LICENSE_START========================================== 
# org.onap.vvp/postgresql
# ===================================================================
# Copyright © 2017 AT&T Intellectual Property. All rights reserved.
# ===================================================================
#
# Unless otherwise specified, all software contained herein is licensed
# under the Apache License, Version 2.0 (the “License”);
# you may not use this software except in compliance with the License.
# You may obtain a copy of the License at
#
#             http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#
#
# Unless otherwise specified, all documentation contained herein is licensed
# under the Creative Commons License, Attribution 4.0 Intl. (the “License”);
# you may not use this documentation except in compliance with the License.
# You may obtain a copy of the License at
#
#             https://creativecommons.org/licenses/by/4.0/
#
# Unless required by applicable law or agreed to in writing, documentation
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# ============LICENSE_END============================================
#
# ECOMP is a trademark and service mark of AT&T Intellectual Property.
FROM postgres:9.6

# Postgres upgrader container
#
# Prior to this container, we ran an Alpine Linux container with Alpine's
# packaged PostgreSQL 9.4
#
# PostgreSQL 9.5 and above will not read data files written by PostgreSQL 9.4;
# a migration must be performed.
#
# We found it difficult to update to a more recent version of Alpine Linux,
# because doing so would bring along a major-version update of PostgreSQL.
#
# One way to migrate a PostgreSQL database is to use pg_dump, transferring
# files, and pg_restore, maybe while juggling containers.
#
# We want to use pg_upgrade with link mode to migrate from 9.4 to 9.6, because
# - it is "much faster and will use less disk space."
# - we don't at present have replication or zero-downtime deploys so a small
#   maintenance window is acceptable and expected
# - the deploy process should be as simple as updating the container twice
# https://www.postgresql.org/docs/9.6/static/pgupgrade.html
#
# pg_upgrade requires the postgresql binaries be installed for both the new
# version and the old version of the cluster.
#
# PostgreSQL9.6 is not available as package for the Alpine version we're using.
#
# Upstream's -alpine docker containers compile postgres during the docker
# build, but their standard containers just apt-get install from a Debian
# repository. The repository contains packages for many postgresql versions,
# which will co-exist happily in the same system (container).
#
# So, during the upgrade, we use the debian-based container. After the
# migration is successful, we will switch to the Alpine-based container running
# the same version of PostgreSQL.
#

# Install the old version of postgres
RUN apt-get update \
    && apt-get install -y postgresql-9.4 postgresql-contrib-9.4 \
    && rm -rf /var/lib/apt/lists/*

# Docker will call docker-entrypoint.sh with these arguments.
# docker-entrypoint.sh only performs database initialization when its first
# argument is 'postgres', then it execs its arguments. So, our upgrade script
# will perform the upgrade if necessary, then exec docker-entrypoint.sh with
# its argument, 'postgres', and startup should continue as normal. This also
# means that if the container is launched with a different "command" it will
# replace our custom stuff, as a user might expect.
COPY ensure-postgresql-upgrade.sh /usr/local/bin
CMD ["ensure-postgresql-upgrade.sh", "postgres"]
