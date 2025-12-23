-- Mattermost Database Maintenance Script
-- Recommended for execution during a scheduled outage.
-- This script performs VACUUM FULL on critical tables to reclaim space and rebuild indexes,
-- followed by a full schema reindex and database-wide analyze.

\echo 'Starting Mattermost database maintenance...'

-- Targeted VACUUM FULL on tables with high churn or large volume
\echo 'Vacuuming and analyzing critical tables (this may take some time)...'

\echo 'Processing: posts'
VACUUM FULL ANALYZE posts;

\echo 'Processing: threads'
VACUUM FULL ANALYZE threads;

\echo 'Processing: threadmemberships'
VACUUM FULL ANALYZE threadmemberships;

\echo 'Processing: status'
VACUUM FULL ANALYZE status;

\echo 'Processing: sessions'
VACUUM FULL ANALYZE sessions;

\echo 'Processing: audits'
VACUUM FULL ANALYZE audits;

\echo 'Processing: preferences'
VACUUM FULL ANALYZE preferences;

\echo 'Processing: channelmemberhistory'
VACUUM FULL ANALYZE channelmemberhistory;

\echo 'Processing: channelmembers'
VACUUM FULL ANALYZE channelmembers;

\echo 'Processing: fileinfo'
VACUUM FULL ANALYZE fileinfo;

\echo 'Processing: reactions'
VACUUM FULL ANALYZE reactions;

-- Rebuild all indexes in the public schema for optimal performance
\echo 'Reindexing the entire public schema...'
REINDEX SCHEMA public;

-- Final database-wide analyze to ensure the query planner has the best statistics
\echo 'Performing final database-wide ANALYZE...'
ANALYZE;

\echo 'Maintenance complete.'
