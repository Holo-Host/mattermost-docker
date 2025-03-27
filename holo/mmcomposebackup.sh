
#!/bin/sh
# Set default connection parameters for pg_dump
PGHOST=${PROD}
PGUSER=${PGUSER:-mmuser}
PGDATABASE=${PGDATABASE:-mattermost}
S3_BUCKET=${S3_BUCKET:-db.dr1.chat.holo.host}

DATE=$(date "+%Y-%m-%d-%H%M")
TARGET=s3://${S3_BUCKET}/${PGDATABASE}-${DATE}.sql.gz

echo Backing up ${PGHOST}/${PGDATABASE} to ${TARGET}

# export PGPASSWORD=${DATABASE_PASSWORD}
pg_dump --clean -Z 9 -v -h ${PGHOST} -U ${PGUSER} -d ${PGDATABASE} | aws s3 cp --storage-class STANDARD_IA --sse aws:kms - ${TARGET}

docker-compose exec db pg_dump -U postgres postgres --no-owner | gzip -9  > db-backup-$(date +%d-%m-%y).sql.gz
