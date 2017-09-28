#!/bin/sh
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

set -ex

# This file will be launched with the command:
# 
#	docker-entrypoint.sh ensure-postgresql-upgrade.sh postgres
#
# It will perform a postgresql upgrade if needed, then launch postgres as
# usual.

#
# See if cluster needs upgrade
#

if [ -e "$PGDATA/PG_VERSION" ]; then
	orig_cluster_version="$(head -1 "$PGDATA/PG_VERSION")"
else
	orig_cluster_version=
fi

if [ ! "$orig_cluster_version" ] || \
	[ "${PG_VERSION#$orig_cluster_version}" != "${PG_VERSION}" ]
then
	# Cluster version is the same as container version; no upgrade needed.
	exec docker-entrypoint.sh "$@"
fi

echo >&2 "PostgreSQL version in this container is $PG_VERSION"
echo >&2 "PostgreSQL data was written by version $orig_cluster_version"
echo >&2 "Cluster upgrade will be performed..."


#
# Move old cluster
#

# Since we typically mount a volume at $PGDATA, and we want to avoid crossing
# filesystems, we move the old data to a directory within itself. We take
# advantage here of the fact that there should be no preexisting dot-directores
# and '*' skips them.
mkdir "$PGDATA/.old"
mv "$PGDATA"/* "$PGDATA/.old/"
mv "$PGDATA/.old" "$PGDATA/old"
# If a different container created the old cluster, then their postgres might
# have a different uid than ours. Just in case, recursively chown all the
# postgres data.
chown -Rc postgres.postgres "$PGDATA"
chmod =,u=rwX "$PGDATA/old"

#
# Initialize new cluster
#

# We can't just launch 'docker-entrypoint.sh postgres' here because that will
# stand up more than an empty cluster, which causes problems for pg_upgrade.

PGDATA="$PGDATA/new" gosu postgres initdb

#
# Adjust authentication
#

# The new cluster's auth will be trust by default.
# We don't necessarily know what the old one was.
# Make the old one "peer" then later migrate the old one's original settings to
# the new.
mv "$PGDATA/old/pg_hba.conf" "$PGDATA/old/pg_hba.conf.bak"
echo "local all all peer" > "$PGDATA/old/pg_hba.conf"
chown postgres "$PGDATA/new/pg_hba.conf"

#
# Run pg_upgrade
#

cd /tmp # so it can write its log

gosu postgres pg_upgrade \
	--old-datadir "$PGDATA/old" \
	--old-bindir "/usr/lib/postgresql/$orig_cluster_version/bin/" \
	--new-datadir "$PGDATA/new" \
	--new-bindir "/usr/lib/postgresql/$PG_MAJOR/bin/"

#
# Restore pg_hba.conf
#
mv "$PGDATA/old/pg_hba.conf.bak" "$PGDATA/new/pg_hba.conf"

#
# Apply old configuration to new
#
cp -d "$PGDATA/old/postgresql.conf" "$PGDATA/new/"

#
# Delete old cluster; move new into place.
#

rm -rf "$PGDATA/old"
mv "$PGDATA/new"/* "$PGDATA"
rmdir "$PGDATA/new"

#
# Start new cluster
#

echo >&2 "Database upgrade complete; launching 'docker-entrypoint.sh ""$@""'"
exec docker-entrypoint.sh "$@"
