# Mattermost Upgrade Plan: v10.5.8 → v10.11.2

## Overview
**Current Version**: Mattermost v10.5.8 (ESR)
**Target Version**: Mattermost v10.11.2 (ESR)
**Upgrade Type**: Minor version upgrade within ESR line
**Instances**: mm-test (test) → mm-prod (production)

## Phase 1: Pre-Upgrade Analysis & Preparation

### 1.1 Review Upgrade Requirements
**Critical**: Mattermost v10.11.2 includes several important changes and bug fixes:
- **Security Fixes**: Multiple security patches included
- **Database Schema Updates**: Expect migrations for new features
- **Elasticsearch/OpenSearch**: If using search, verify compatibility
- **Plugin Compatibility**: Check all plugins for v10.11.2 support
- **API Changes**: Review any breaking API changes
- **Performance Improvements**: Enhanced database query optimization
- **Bug Fixes**: Critical fixes for issues found in v10.11.1

**Key v10.11.2 Changes**:
- Fixed an issue where the server would crash when processing certain malformed posts
- Improved performance for large channel member lists
- Fixed database connection pool exhaustion under high load
- Security patches for potential XSS vulnerabilities

### 1.2 Current Environment Assessment
- **Current Version**: v10.5.8 (ESR)
- **Target Version**: v10.11.2 (ESR)
- **Database**: PostgreSQL 14
  - **mm-test**: PostgreSQL 14 with pgvector extension
  - **mm-prod**: PostgreSQL 14 (pgvector extension needs installation)
- **Deployment**: Docker Compose with hardened security
- **Instances**: mm-test (test) and mm-prod (production)
- **Backup Strategy**: Nightly backups run on mm-prod via `holo/run_nightly_backup.sh`
- **Restore Method**: Use `holo/restore_mattermost_db.sh` to restore latest backup from S3

## Phase 2: Test Environment Upgrade (mm-test)

### 2.1 Pre-Upgrade Tasks
```bash
# 1. Ensure latest backup is available (nightly backups run automatically)
# Check S3 for latest backup
aws s3 ls s3://db.dr1.chat.holo.host/ | tail -5

# 2. Prepare test environment
cd ~/mattermost-docker
agebox cat .env.test.agebox > .env.test

# 3. Install pgvector extension on mm-prod (if not already installed)
# This will be needed for the production upgrade
docker compose -f docker-compose.harden.yml exec postgres psql -U mattermost -d mattermost -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

### 2.2 Update Test Environment Configuration
```bash
# Edit .env.test to set new version
nano .env.test
# Set: MATTERMOST_IMAGE_TAG=10.11.2
```

### 2.3 Restore Production Data to Test
```bash
# Start only PostgreSQL
docker compose --env-file .env.test -f docker-compose.harden.yml up -d postgres

# Restore latest production backup from S3 to test
tmux new -s mm-test-restore
./holo/restore_mattermost_db.sh ../.env.test latest_backup_from_s3.sql.gz
# Detach: Ctrl+b, d

# Note: Use actual filename from S3, e.g.:
# ./holo/restore_mattermost_db.sh ../.env.test mattermost_backup_2024-08-21_0200.sql.gz
```

### 2.4 Execute Test Upgrade
```bash
# Start full test stack (triggers migrations)
docker compose --env-file .env.test -f docker-compose.harden.yml up -d

# Monitor upgrade progress
docker compose --env-file .env.test -f docker-compose.harden.yml logs -f mattermost
```

### 2.5 Post-Upgrade Verification Checklist
- [ ] Access https://chat-ng.holochain.org
- [ ] Verify version shows 10.11.2 in System Console
- [ ] Test critical workflows:
  - User authentication
  - Channel creation/messaging
  - File uploads/downloads
  - Plugin functionality
  - Search functionality
  - API endpoints
- [ ] Check for safety limit warnings
- [ ] Verify database migrations completed successfully

## Phase 3: Production Upgrade (mm-prod)

### 3.1 Pre-Production Upgrade
```bash
# Schedule maintenance window
# Ensure pgvector extension is installed on mm-prod
docker compose -f docker-compose.harden.yml exec postgres psql -U mattermost -d mattermost -c "CREATE EXTENSION IF NOT EXISTS vector;"

# Create final production backup (or use latest nightly)
cd ~/mattermost-docker
./holo/backup_prod_db.sh

# Verify backup integrity
aws s3 ls s3://db.dr1.chat.holo.host/ | tail -3
```

### 3.2 Production Upgrade Execution
```bash
# 1. Prepare production environment
agebox cat .env.agebox > .env

# 2. Update version in production .env
nano .env
# Set: MATTERMOST_IMAGE_TAG=10.11.2

# 3. Execute upgrade
docker compose -f docker-compose.harden.yml up -d

# 4. Monitor upgrade
docker compose -f docker-compose.harden.yml logs -f mattermost
```

### 3.3 Post-Production Verification
- [ ] Verify service availability
- [ ] Check Mattermost version in System Console
- [ ] Test core functionality
- [ ] Monitor error logs for 24-48 hours
- [ ] Verify backup schedules are working

## Phase 4: Rollback Plan

### 4.1 If Issues Occur
```bash
# Quick rollback procedure
docker compose -f docker-compose.harden.yml down
# Restore from backup using restore script
./holo/restore_mattermost_db.sh ../.env backup_pre_10.11.2.sql.gz
# Revert MATTERMOST_IMAGE_TAG in .env
docker compose -f docker-compose.harden.yml up -d
```

## Phase 5: Post-Upgrade Tasks

### 5.1 Update Monitoring
- [ ] Update Diun notifications for new version
- [ ] Verify CrowdSec is monitoring correctly
- [ ] Check log rotation and retention

### 5.2 Documentation
- [ ] Document any custom changes needed
- [ ] Update runbooks with new procedures
- [ ] Record performance metrics

## Risk Mitigation

### High Priority
- **Database Backup**: Ensure multiple backups before upgrade
- **Test Environment**: Complete testing on mm-test before production
- **Maintenance Window**: Schedule during low-usage hours
- **Rollback Plan**: Have immediate rollback capability ready

### Medium Priority
- **Plugin Compatibility**: Test all critical plugins
- **Performance Impact**: Monitor resource usage post-upgrade
- **User Communication**: Notify users of maintenance window

## Timeline Estimate
- **Phase 1**: 2-3 hours (review and preparation)
- **Phase 2**: 4-6 hours (test upgrade and verification)
- **Phase 3**: 2-3 hours (production upgrade)
- **Phase 4**: 1 hour (rollback if needed)
- **Phase 5**: 1-2 hours (post-upgrade tasks)

**Total estimated time**: 8-12 hours including testing and verification

## Files to Update
- `.env.test` - Update `MATTERMOST_IMAGE_TAG=10.11.2`
- `.env` - Update `MATTERMOST_IMAGE_TAG=10.11.2` for production

## Additional Considerations
- **pgvector Extension**: Ensure pgvector is installed on mm-prod before upgrade
- **S3 Backup Access**: Latest backups are automatically available via S3
- **Restore Process**: Use `holo/restore_mattermost_db.sh` with actual S3 backup filename

## Todo Checklist
- [ ] Review Mattermost v10.11.2 release notes and breaking changes
- [ ] Check current environment configuration and backup status
- [ ] Create pre-upgrade backup of production database
- [ ] Prepare test environment with v10.11.2
- [ ] Restore production backup to test environment
- [ ] Upgrade test instance to v10.11.2
- [ ] Perform comprehensive testing on test instance
- [ ] Address any safety limit warnings if they appear
- [ ] Document any issues found during testing
- [ ] Schedule production maintenance window
- [ ] Create production backup before upgrade
- [ ] Upgrade production instance to v10.11.2
- [ ] Verify production upgrade success
- [ ] Monitor production for 24-48 hours post-upgrade