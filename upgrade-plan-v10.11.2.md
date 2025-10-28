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
# Update Mattermost version in test environment
cd ~/mattermost-docker
# Edit .env.test
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
# ./holo/restore_mattermost_db.sh ../.env.test mattermost_backup_2024-08-28_0200.sql.gz
```

### 2.4 Upgrade Test Instance
```bash
# Start full test environment with new version
docker compose --env-file .env.test -f docker-compose.harden.yml up -d

# Monitor logs for any issues
docker compose --env-file .env.test -f docker-compose.harden.yml logs -f mattermost
```

### 2.5 Test Environment Validation
- [ ] Verify version shows 10.11.2 in System Console
- [ ] Test basic functionality (login, posting, file uploads)
- [ ] Test integrations and plugins
- [ ] Check for any safety limit warnings
- [ ] Verify search functionality
- [ ] Test team/channel creation
- [ ] Validate user management features

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
# Update production configuration
cd ~/mattermost-docker
# Edit .env
# Set: MATTERMOST_IMAGE_TAG=10.11.2

# Pull new images
docker compose -f docker-compose.harden.yml pull

# Restart services with new version
docker compose -f docker-compose.harden.yml up -d

# Monitor upgrade process
docker compose -f docker-compose.harden.yml logs -f mattermost
```

### 3.3 Post-Upgrade Verification
- [ ] Check Mattermost version in System Console
- [ ] Verify all services are running
- [ ] Test critical functionality
- [ ] Check system performance
- [ ] Monitor logs for errors
- [ ] Verify backup functionality

## Phase 4: Rollback Plan

### 4.1 Immediate Rollback (if issues detected)
```bash
# Stop services
docker compose -f docker-compose.harden.yml down

# Restore from backup using restore script
./holo/restore_mattermost_db.sh ../.env backup_pre_10.11.2.sql.gz
# Revert MATTERMOST_IMAGE_TAG in .env
docker compose -f docker-compose.harden.yml up -d
```

### 4.2 Rollback Validation
- [ ] Verify system is running previous version
- [ ] Test critical functionality
- [ ] Check data integrity

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